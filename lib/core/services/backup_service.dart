/// Backup service for creating and restoring database backups
/// Supports both encrypted (.enc) and unencrypted (.db) databases seamlessly
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:uuid/uuid.dart';

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

/// Represents a backup file
class BackupInfo {
  const BackupInfo({
    required this.filePath,
    required this.fileName,
    required this.createdAt,
    required this.isEncrypted,
    required this.sizeBytes,
  });

  final String filePath;
  final String fileName;
  final DateTime createdAt;
  final bool isEncrypted;
  final int sizeBytes;

  /// Format size as human-readable string
  String get formattedSize => formatFileSize(sizeBytes);

  /// Get display name without timestamp details
  String get displayName {
    final type = isEncrypted ? 'Encrypted' : 'Unencrypted';
    return '$type backup from ${_formatDate(createdAt)}';
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
  /// the appropriate backup format.
  Future<BackupResult> createBackup() async {
    try {
      final basePath = await _getBaseDatabasePath();
      final encryptionManager = EncryptionManager(basePath);
      final isEncrypted = encryptionManager.isEncrypted;

      // Get session if encrypted (to ensure latest changes are persisted)
      final session = ref.read(encryptedDbSessionProvider);

      // Generate backup filename with timestamp and encryption state
      final timestamp = DateTime.now();
      final timestampStr =
          '${timestamp.year}'
          '${timestamp.month.toString().padLeft(2, '0')}'
          '${timestamp.day.toString().padLeft(2, '0')}_'
          '${timestamp.hour.toString().padLeft(2, '0')}'
          '${timestamp.minute.toString().padLeft(2, '0')}'
          '${timestamp.second.toString().padLeft(2, '0')}_'
          '${(timestamp.millisecond * 1000 + timestamp.microsecond).toString().padLeft(6, '0')}';

      final encryptionSuffix = isEncrypted ? '_encrypted' : '_plain';
      final extension = isEncrypted ? 'enc' : 'db';
      final fileName =
          'backup_${timestampStr}_${const Uuid().v4()}$encryptionSuffix.$extension';

      final backupsDir = await getBackupsDirectory();
      final backupPath = p.join(backupsDir.path, fileName);

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

      final backupInfo = BackupInfo(
        filePath: backupPath,
        fileName: fileName,
        createdAt: timestamp,
        isEncrypted: isEncrypted,
        sizeBytes: sizeBytes,
      );

      // Prune old backups
      await pruneOldBackups();

      return BackupResult(success: true, backupInfo: backupInfo);
    } catch (e) {
      return BackupResult(success: false, error: 'Failed to create backup: $e');
    }
  }

  /// List all existing backups, sorted by date (newest first)
  Future<List<BackupInfo>> listBackups() async {
    final backupsDir = await getBackupsDirectory();
    final backups = <BackupInfo>[];

    if (!await backupsDir.exists()) {
      return backups;
    }

    await for (final entity in backupsDir.list()) {
      if (entity is File) {
        final fileName = p.basename(entity.path);

        // Parse backup filename: backup_YYYYMMDD_HHMMSS_encrypted.enc or backup_YYYYMMDD_HHMMSS_plain.db
        if (!fileName.startsWith('backup_')) continue;

        final fileInfo = await inspectDatabaseFile(
          entity.path,
          resolveEncryptedSibling: false,
        );
        final isEncrypted = fileInfo.isEncrypted;

        // Extract timestamp from filename
        DateTime? createdAt;
        try {
          final match = RegExp(
            r'backup_(\d{8})_(\d{6})(?:_(\d{6})_)?',
          ).firstMatch(fileName);
          if (match != null) {
            final dateStr = match.group(1)!;
            final timeStr = match.group(2)!;
            createdAt = DateTime(
              int.parse(dateStr.substring(0, 4)),
              int.parse(dateStr.substring(4, 6)),
              int.parse(dateStr.substring(6, 8)),
              int.parse(timeStr.substring(0, 2)),
              int.parse(timeStr.substring(2, 4)),
              int.parse(timeStr.substring(4, 6)),
              0,
              int.parse(match.group(3) ?? '0'),
            );
          }
        } catch (_) {
          // If parsing fails, use file modification time
        }

        final stat = await entity.stat();
        createdAt ??= stat.modified;

        backups.add(
          BackupInfo(
            filePath: entity.path,
            fileName: fileName,
            createdAt: createdAt,
            isEncrypted: isEncrypted,
            sizeBytes: stat.size,
          ),
        );
      }
    }

    // Sort by date, newest first
    backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return backups;
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
        final currentBackup = await createBackup();
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
