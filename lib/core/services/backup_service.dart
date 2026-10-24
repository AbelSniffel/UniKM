/// Backup service for creating and restoring database backups
/// Supports both encrypted (.enc) and unencrypted (.db) databases seamlessly
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../shared/state/session_value.dart';
import '../../app/application/database_session_loader.dart';
import '../../providers/app_providers.dart';
import '../constants/app_constants.dart';
import '../database/database.dart';
import 'encryption_manager.dart';
import 'database_file_info.dart';
import 'legacy_db_converter.dart';
import 'logging.dart';
import '../utils/format_utils.dart';

/// Why a backup was taken. The reason is stored in the file name, so it
/// survives copies; older backups without one read as regular.
enum BackupKind {
  regular(null),
  preSync('sync'),
  preRestore('restore');

  const BackupKind(this.fileToken);
  final String? fileToken;
}

typedef _BackupName = ({
  DateTime? createdAt,
  BackupKind kind,
  String? databaseName,
  String? peerName,
  int duplicate,
});

/// Represents a backup file
class BackupInfo {
  const BackupInfo({
    required this.filePath,
    required this.fileName,
    required this.createdAt,
    required this.isEncrypted,
    required this.sizeBytes,
    this.kind = BackupKind.regular,
    this.databaseName,
    this.peerName,
  });

  final String filePath;
  final String fileName;
  final DateTime createdAt;
  final bool isEncrypted;
  final int sizeBytes;
  final BackupKind kind;

  /// Database file the backup was taken from, when recorded.
  final String? databaseName;

  /// Device a pre-sync backup was taken for, when recorded.
  final String? peerName;

  /// Format size as human-readable string
  String get formattedSize => formatFileSize(sizeBytes);

  /// Source database (when recorded) and size, for list subtitles.
  String get details => [?databaseName, formattedSize].join(' • ');

  /// Readable name for lists; the encryption state is shown by an icon.
  String get displayName {
    final date = _formatDate(createdAt);
    return switch (kind) {
      BackupKind.preSync =>
        peerName == null
            ? 'Before sync on $date'
            : 'Before sync with $peerName on $date',
      BackupKind.preRestore => 'Before restore on $date',
      BackupKind.regular => 'Backup from $date',
    };
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// Result of a backup operation
class BackupResult {
  const BackupResult({required this.success, this.backupInfo, this.error});

  final bool success;
  final BackupInfo? backupInfo;
  final String? error;
}

/// Result of a restore operation
class RestoreResult {
  const RestoreResult({required this.success, this.error});

  final bool success;
  final String? error;
}

/// Backup service for managing database backups
class BackupService {
  BackupService({
    required this.ref,
    this.maxBackupCount = kDefaultMaxBackupCount,
  });

  final Ref ref;
  final int maxBackupCount;

  // Current names read "<database> 2026-10-24 13-10-02[ sync-<peer>][ (2)]".
  // The peer is base64url so any device name fits in a file name.
  static final _namePattern = RegExp(
    r'^(.+) (\d{4})-(\d{2})-(\d{2}) (\d{2})-(\d{2})-(\d{2})'
    r'(?: (sync|restore)(?:-([A-Za-z0-9_-]+))?)?(?: \((\d+)\))?\.(?:db|enc)$',
  );
  // Older names: backup_YYYYMMDD_HHMMSS[_micros_id][_<kind>-<json>]_plain.db
  static final _legacyTimestampPattern = RegExp(
    r'^backup_(\d{8})_(\d{6})(?:_(\d{6})_)?',
  );
  // Base64url may contain '_', so anchor on the encryption suffix.
  static final _legacyLabelPattern = RegExp(
    r'_(regular|presync|prerestore)(?:-([A-Za-z0-9_-]+?))?_(?:plain|encrypted)\.(?:db|enc)$',
  );
  static const _legacyKinds = {
    'regular': BackupKind.regular,
    'presync': BackupKind.preSync,
    'prerestore': BackupKind.preRestore,
  };
  static final _unsafeFileNameCharacters = RegExp(r'[<>:"/\\|?*\x00-\x1F]');
  // Windows drops trailing dots and spaces from file names.
  static final _trailingDotsOrSpaces = RegExp(r'[. ]+$');
  static const _maxPeerNameLength = 40;

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String? _decodeBase64Url(String encoded) {
    try {
      return utf8.decode(base64Url.decode(base64Url.normalize(encoded)));
    } on FormatException {
      return null; // A damaged label still identifies the backup kind.
    }
  }

  /// Readable file name for a new backup, without its extension.
  static String _backupFileStem({
    required String databasePath,
    required DateTime createdAt,
    required BackupKind kind,
    String? peerName,
  }) {
    var database = p.basename(databasePath);
    if (database.toLowerCase().endsWith('.db')) {
      database = database.substring(0, database.length - 3);
    }
    database = database
        .replaceAll(_unsafeFileNameCharacters, '-')
        .trim()
        .replaceAll(_trailingDotsOrSpaces, '');
    if (database.isEmpty) database = 'UniKM';
    final date =
        '${createdAt.year}-${_two(createdAt.month)}-${_two(createdAt.day)} '
        '${_two(createdAt.hour)}-${_two(createdAt.minute)}-${_two(createdAt.second)}';
    if (kind == BackupKind.regular) return '$database $date';
    final peer = String.fromCharCodes(
      (peerName?.trim() ?? '').runes.take(_maxPeerNameLength),
    );
    if (peer.isEmpty) return '$database $date ${kind.fileToken}';
    final encodedPeer = base64Url.encode(utf8.encode(peer)).replaceAll('=', '');
    return '$database $date ${kind.fileToken}-$encodedPeer';
  }

  /// Reads what a backup file name records, or null if it is not a backup.
  static _BackupName? _parseFileName(String fileName) {
    final current = _namePattern.firstMatch(fileName);
    if (current != null) {
      final parts = [for (var i = 2; i <= 7; i++) int.parse(current.group(i)!)];
      final encodedPeer = current.group(9);
      return (
        createdAt: DateTime(
          parts[0],
          parts[1],
          parts[2],
          parts[3],
          parts[4],
          parts[5],
        ),
        kind: switch (current.group(8)) {
          'sync' => BackupKind.preSync,
          'restore' => BackupKind.preRestore,
          _ => BackupKind.regular,
        },
        databaseName: current.group(1),
        peerName: encodedPeer == null ? null : _decodeBase64Url(encodedPeer),
        duplicate: int.tryParse(current.group(10) ?? '') ?? 1,
      );
    }
    if (!fileName.startsWith('backup_')) return null;

    DateTime? createdAt;
    final timestamp = _legacyTimestampPattern.firstMatch(fileName);
    if (timestamp != null) {
      final date = timestamp.group(1)!;
      final time = timestamp.group(2)!;
      createdAt = DateTime(
        int.parse(date.substring(0, 4)),
        int.parse(date.substring(4, 6)),
        int.parse(date.substring(6, 8)),
        int.parse(time.substring(0, 2)),
        int.parse(time.substring(2, 4)),
        int.parse(time.substring(4, 6)),
        0,
        int.parse(timestamp.group(3) ?? '0'),
      );
    }
    final label = _legacyLabelPattern.firstMatch(fileName);
    final metadataJson = label?.group(2) == null
        ? null
        : _decodeBase64Url(label!.group(2)!);
    Object? metadata;
    try {
      metadata = metadataJson == null ? null : jsonDecode(metadataJson);
    } on FormatException {
      metadata = null;
    }
    final fields = metadata is Map ? metadata : const {};
    return (
      createdAt: createdAt,
      kind: _legacyKinds[label?.group(1)] ?? BackupKind.regular,
      databaseName: fields['db'] as String?,
      peerName: fields['peer'] as String?,
      duplicate: 1,
    );
  }

  /// Get the backups directory path
  Future<Directory> getBackupsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final backupsDir = Directory(p.join(appDir.path, 'UniKM', 'backups'));
    if (!await backupsDir.exists()) {
      await backupsDir.create(recursive: true);
    }
    return backupsDir;
  }

  /// Get the current database path (configured or default)
  Future<String> _getBaseDatabasePath() async {
    final configured = ref.read(currentDatabasePathProvider);
    if (configured.isNotEmpty) {
      return configured;
    }
    return AppDatabase.getDatabasePath();
  }

  /// Create a backup of the current database
  ///
  /// Automatically detects whether the database is encrypted and creates
  /// the appropriate backup format. [kind] and [peerName] label the backup so
  /// it can be identified in the Backup Manager.
  Future<BackupResult> createBackup({
    BackupKind kind = BackupKind.regular,
    String? peerName,
  }) async {
    String? reservedPath;
    try {
      final basePath = await _getBaseDatabasePath();
      final encryptionManager = EncryptionManager(basePath);
      final isEncrypted = encryptionManager.isEncrypted;

      // Get session if encrypted (to ensure latest changes are persisted)
      final session = ref.read(encryptedDbSessionProvider);

      // The file name records the second; the extension shows encryption.
      final now = DateTime.now();
      final timestamp = DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
        now.second,
      );
      final stem = _backupFileStem(
        databasePath: basePath,
        createdAt: timestamp,
        kind: kind,
        peerName: peerName,
      );
      final extension = isEncrypted ? 'enc' : 'db';

      // Claim the name atomically so backups in the same second get " (2)".
      // SQLite's VACUUM INTO and File.copy both accept the empty file.
      final backupsDir = await getBackupsDirectory();
      late String fileName;
      late String backupPath;
      for (var duplicate = 1; ; duplicate++) {
        fileName = duplicate == 1
            ? '$stem.$extension'
            : '$stem ($duplicate).$extension';
        backupPath = p.join(backupsDir.path, fileName);
        try {
          await File(backupPath).create(exclusive: true);
          break;
        } on FileSystemException {
          if (duplicate >= 1000 || !await File(backupPath).exists()) rethrow;
        }
      }
      reservedPath = backupPath;

      if (isEncrypted) {
        // For encrypted database, persist any pending changes first
        if (session != null) {
          await session.persistFromTemp();
        }

        // Copy the encrypted file
        final encPath = '$basePath.enc';
        await File(encPath).copy(backupPath);
      } else {
        // For unencrypted database, use VACUUM INTO for a clean snapshot
        // Use the temp path if we have an encrypted session, otherwise use base path
        final sourcePath = session?.tempDbPath ?? basePath;

        _snapshotDatabase(sourcePath, backupPath);
      }

      // Get file size
      final backupFile = File(backupPath);
      final sizeBytes = await backupFile.length();

      // Read the (length-limited) names back exactly as listBackups will.
      final label = _parseFileName(fileName)!;
      final backupInfo = BackupInfo(
        filePath: backupPath,
        fileName: fileName,
        createdAt: timestamp,
        isEncrypted: isEncrypted,
        sizeBytes: sizeBytes,
        kind: label.kind,
        databaseName: label.databaseName,
        peerName: label.peerName,
      );

      reservedPath = null;

      // Prune old backups
      await pruneOldBackups();

      return BackupResult(success: true, backupInfo: backupInfo);
    } catch (e) {
      if (reservedPath != null) {
        try {
          await File(reservedPath).delete();
        } catch (_) {
          // The name reservation is empty; leaving it is harmless.
        }
      }
      return BackupResult(success: false, error: 'Failed to create backup: $e');
    }
  }

  /// List all existing backups, sorted by date (newest first)
  Future<List<BackupInfo>> listBackups() async {
    final backupsDir = await getBackupsDirectory();
    final backups = <(BackupInfo, int)>[];

    if (!await backupsDir.exists()) {
      return const [];
    }

    await for (final entity in backupsDir.list()) {
      if (entity is File) {
        final fileName = p.basename(entity.path);
        final name = _parseFileName(fileName);
        if (name == null) continue;

        final fileInfo = await inspectDatabaseFile(
          entity.path,
          resolveEncryptedSibling: false,
        );
        // Names without a readable date fall back to the modification time.
        final stat = await entity.stat();

        backups.add((
          BackupInfo(
            filePath: entity.path,
            fileName: fileName,
            createdAt: name.createdAt ?? stat.modified,
            isEncrypted: fileInfo.isEncrypted,
            sizeBytes: stat.size,
            kind: name.kind,
            databaseName: name.databaseName,
            peerName: name.peerName,
          ),
          name.duplicate,
        ));
      }
    }

    // Sort by date, newest first; " (2)" is newer within the same second.
    backups.sort((a, b) {
      final byDate = b.$1.createdAt.compareTo(a.$1.createdAt);
      return byDate != 0 ? byDate : b.$2.compareTo(a.$2);
    });

    return [for (final (backup, _) in backups) backup];
  }

  /// Prune old backups, keeping only the most recent [maxBackupCount]
  Future<int> pruneOldBackups() async {
    final backups = await listBackups();
    var deletedCount = 0;

    if (backups.length <= maxBackupCount) {
      return 0;
    }

    // Delete oldest backups
    final toDelete = backups.skip(maxBackupCount);
    for (final backup in toDelete) {
      try {
        await File(backup.filePath).delete();
        deletedCount++;
      } catch (e) {
        // Log but don't fail if we can't delete a file
        AppLog.w('Could not delete old backup ${backup.fileName}', error: e);
      }
    }

    return deletedCount;
  }

  /// Restore a backup file
  ///
  /// [backupPath] - Path to the backup file to restore
  /// [password] - Password for encrypted backups (required if backup is encrypted)
  /// [createBackupFirst] - Whether to create a backup of current database before restoring
  ///
  /// Returns a RestoreResult indicating success or failure.
  /// Note: After a successful restore, the active database connection should
  /// be reloaded so the restored file is used immediately.
  Future<RestoreResult> restoreBackup({
    required String backupPath,
    String? password,
    bool createBackupFirst = true,
  }) async {
    Directory? restoreDirectory;
    try {
      final info = await inspectDatabaseFile(
        backupPath,
        resolveEncryptedSibling: false,
      );
      if (!info.exists) {
        return const RestoreResult(
          success: false,
          error: 'Backup file not found',
        );
      }
      if (info.isEncrypted && (password == null || password.isEmpty)) {
        return const RestoreResult(
          success: false,
          error: 'Password required for encrypted backup',
        );
      }

      final basePath = await _getBaseDatabasePath();
      final targetDirectory = await Directory(
        p.dirname(basePath),
      ).create(recursive: true);
      // Stage beside the destination so replacement is a same-filesystem rename.
      // Prepare before pruning backups or closing the active library: either
      // action could make the selected source unavailable.
      restoreDirectory = await targetDirectory.createTemp('.unikm-restore-');
      final preparedPath = p.join(restoreDirectory.path, 'prepared.db');
      if (info.isEncrypted) {
        final sourceBase = p.join(restoreDirectory.path, 'source');
        await File(backupPath).copy('$sourceBase.enc');
        final bytes = await EncryptionManager(sourceBase).decrypt(password!);
        await File(sourceBase).writeAsBytes(bytes, flush: true);
        _snapshotDatabase(sourceBase, preparedPath);
      } else {
        _snapshotDatabase(backupPath, preparedPath);
      }
      final conversion = await convertLegacyDbToCurrentLayoutIfNeeded(
        preparedPath,
      );
      if (conversion.converted) {
        AppLog.i('Converted restored backup: ${conversion.actions.join(', ')}');
      }
      if (info.isEncrypted) {
        await EncryptionManager(preparedPath).enable(password!);
      }

      if (createBackupFirst) {
        final currentBackup = await createBackup(kind: BackupKind.preRestore);
        if (!currentBackup.success) {
          return RestoreResult(
            success: false,
            error: 'Failed to backup current database: ${currentBackup.error}',
          );
        }
      }

      final db = ref.read(databaseProvider);
      final session = ref.read(encryptedDbSessionProvider);
      ref.read(databaseNotifierProvider.notifier).clearDatabase();
      if (db != null) await const DatabaseSessionLoader().close(db, session);
      ref.read(encryptedDbSessionProvider.notifier).set(null);

      // Closed connections must not leave journals attached to a new database.
      for (final suffix in ['-wal', '-shm', '-journal']) {
        final companion = File('$basePath$suffix');
        if (await companion.exists()) await companion.delete();
      }
      final suffix = info.isEncrypted ? '.enc' : '';
      await File('$preparedPath$suffix').rename('$basePath$suffix');
      // The loader prefers .enc, so an obsolete sibling would hide a plain
      // restore. Conversely, encrypted restores must not retain plaintext.
      final obsolete = File(info.isEncrypted ? basePath : '$basePath.enc');
      if (await obsolete.exists()) await obsolete.delete();
      return const RestoreResult(success: true);
    } on InvalidPasswordException {
      return const RestoreResult(
        success: false,
        error: 'Incorrect password for backup',
      );
    } catch (e) {
      return RestoreResult(
        success: false,
        error: 'Failed to restore backup: $e',
      );
    } finally {
      try {
        await restoreDirectory?.delete(recursive: true);
      } catch (e) {
        AppLog.d('Failed to cleanup restore temp dir: $e');
      }
    }
  }

  /// Validate and snapshot SQLite, including committed data in its WAL file.
  void _snapshotDatabase(String sourcePath, String destinationPath) {
    final source = sqlite3.sqlite3.open(
      sourcePath,
      mode: sqlite3.OpenMode.readOnly,
    );
    try {
      if (source.select('PRAGMA quick_check').single.values.single != 'ok') {
        throw const FormatException('Backup is not a valid UniKM database');
      }
      source.select('SELECT id, title, game_key FROM games LIMIT 0');
      source.execute("VACUUM INTO '${destinationPath.replaceAll("'", "''")}'");
    } finally {
      source.close();
    }
  }

  /// Delete a specific backup
  Future<bool> deleteBackup(String backupPath) async {
    try {
      final file = File(backupPath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}

/// Provider for backup service
final backupServiceProvider = Provider<BackupService>((ref) {
  final maxBackupCount = ref.watch(backupSettingsProvider).maxCount;
  return BackupService(ref: ref, maxBackupCount: maxBackupCount);
});

/// State for next auto backup time
final nextAutoBackupTimeProvider = sessionValueProvider<DateTime?>(null);
