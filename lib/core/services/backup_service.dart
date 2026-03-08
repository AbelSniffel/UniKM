/// Backup service for creating and restoring database backups
/// Supports both encrypted (.enc) and unencrypted (.db) databases seamlessly
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../providers/app_providers.dart';
import '../constants/app_constants.dart';
import '../database/database.dart';
import 'encryption_manager.dart';
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
  const BackupResult({
    required this.success,
    this.backupInfo,
    this.error,
  });

  final bool success;
  final BackupInfo? backupInfo;
  final String? error;
}

/// Result of a restore operation
class RestoreResult {
  const RestoreResult({
    required this.success,
    this.error,
    this.requiresRestart,
  });

  final bool success;
  final String? error;
  final bool? requiresRestart;
}

/// Backup service for managing database backups
class BackupService {
  BackupService({
    required this.ref,
    this.maxBackupCount = kDefaultMaxBackupCount,
  });

  final Ref ref;
  final int maxBackupCount;

  /// Timer for automatic backups
  Timer? _autoBackupTimer;

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
  Future<BackupResult> createBackup({String? label}) async {
    try {
      final basePath = await _getBaseDatabasePath();
      final encryptionManager = EncryptionManager(basePath);
      final isEncrypted = encryptionManager.isEncrypted;
      
      // Get session if encrypted (to ensure latest changes are persisted)
      final session = ref.read(encryptedDbSessionProvider);
      
      // Generate backup filename with timestamp and encryption state
      final timestamp = DateTime.now();
      final timestampStr = '${timestamp.year}'
          '${timestamp.month.toString().padLeft(2, '0')}'
          '${timestamp.day.toString().padLeft(2, '0')}_'
          '${timestamp.hour.toString().padLeft(2, '0')}'
          '${timestamp.minute.toString().padLeft(2, '0')}'
          '${timestamp.second.toString().padLeft(2, '0')}';
      
      final encryptionSuffix = isEncrypted ? '_encrypted' : '_plain';
      final extension = isEncrypted ? 'enc' : 'db';
      final fileName = 'backup_$timestampStr$encryptionSuffix.$extension';
      
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
        
        final sourceDb = sqlite3.sqlite3.open(
          sourcePath,
          mode: sqlite3.OpenMode.readOnly,
        );
        try {
          sourceDb.execute("VACUUM INTO '${_escapeSqlString(backupPath)}'");
        } finally {
          sourceDb.dispose();
        }
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
        
        final isEncrypted = fileName.contains('_encrypted') || fileName.endsWith('.enc');
        
        // Extract timestamp from filename
        DateTime? createdAt;
        try {
          final match = RegExp(r'backup_(\d{8})_(\d{6})').firstMatch(fileName);
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
            );
          }
        } catch (_) {
          // If parsing fails, use file modification time
        }
        
        createdAt ??= await entity.lastModified();
        final stat = await entity.stat();
        
        backups.add(BackupInfo(
          filePath: entity.path,
          fileName: fileName,
          createdAt: createdAt,
          isEncrypted: isEncrypted,
          sizeBytes: stat.size,
        ));
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
  /// Note: After a successful restore, the app should be restarted to use the new database.
  Future<RestoreResult> restoreBackup({
    required String backupPath,
    String? password,
    bool createBackupFirst = true,
  }) async {
    try {
      final backupFile = File(backupPath);
      if (!await backupFile.exists()) {
        return const RestoreResult(
          success: false,
          error: 'Backup file not found',
        );
      }
      
      final basePath = await _getBaseDatabasePath();
      final isBackupEncrypted = backupPath.endsWith('.enc') || 
          p.basename(backupPath).contains('_encrypted');
      
      // Validate encrypted backup has password
      if (isBackupEncrypted && (password == null || password.isEmpty)) {
        return const RestoreResult(
          success: false,
          error: 'Password required for encrypted backup',
        );
      }
      
      // If encrypted backup, verify password first
      if (isBackupEncrypted) {
        final isValid = await _verifyBackupPassword(backupPath, password!);
        if (!isValid) {
          return const RestoreResult(
            success: false,
            error: 'Incorrect password for backup',
          );
        }
      }
      
      // Create backup of current database first if requested
      if (createBackupFirst) {
        final currentBackup = await createBackup(label: 'pre-restore');
        if (!currentBackup.success) {
          return RestoreResult(
            success: false,
            error: 'Failed to backup current database: ${currentBackup.error}',
          );
        }
      }
      
      // Close the current database connection before deleting files
      final db = ref.read(databaseProvider);
      final session = ref.read(encryptedDbSessionProvider);
      
      // Clear database from notifier so providers know it's gone
      ref.read(databaseNotifierProvider.notifier).clearDatabase();
      
      if (db != null) {
        if (session != null) {
          // For encrypted databases, persist and close properly
          await session.closeAndPersist(db);
          ref.read(encryptedDbSessionProvider.notifier).setSession(null);
        } else {
          await db.close();
        }
      }
      
      // Small delay to ensure file handles are released
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Prepare restored database in latest schema layout before writing target files.
      final restoreTempDir = await Directory.systemTemp.createTemp('UniKM_restore_');
      try {
        final preparedPlainPath = p.join(restoreTempDir.path, 'prepared_restore.db');

        if (isBackupEncrypted) {
          final sourceBasePath = p.join(restoreTempDir.path, 'restore_source');
          await backupFile.copy('$sourceBasePath.enc');
          final sourceEncryptionManager = EncryptionManager(sourceBasePath);
          final decryptedBytes = await sourceEncryptionManager.decrypt(password!);
          await File(preparedPlainPath).writeAsBytes(decryptedBytes, flush: true);
        } else {
          await backupFile.copy(preparedPlainPath);
        }

        final conversionResult = await convertLegacyDbToCurrentLayoutIfNeeded(preparedPlainPath);
        if (conversionResult.converted) {
          AppLog.i(
            'Converted restored backup to latest layout: '
            '${conversionResult.actions.join(', ')}',
          );
        }

        final targetDir = Directory(p.dirname(basePath));
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }

        if (isBackupEncrypted) {
          final convertedBasePath = p.join(restoreTempDir.path, 'converted_restore');
          await File(preparedPlainPath).copy(convertedBasePath);

          final convertedEncryptionManager = EncryptionManager(convertedBasePath);
          await convertedEncryptionManager.enable(password!);

          final encryptedBytes = await File('$convertedBasePath.enc').readAsBytes();
          await File('$basePath.enc').writeAsBytes(encryptedBytes, flush: true);
        } else {
          final restoredBytes = await File(preparedPlainPath).readAsBytes();
          await File(basePath).writeAsBytes(restoredBytes, flush: true);
        }
      } finally {
        try {
          if (await restoreTempDir.exists()) {
            await restoreTempDir.delete(recursive: true);
          }
        } catch (e) {
          AppLog.d('Failed to cleanup restore temp dir: $e');
        }
      }
      
      return const RestoreResult(
        success: true,
        requiresRestart: true,
      );
    } catch (e) {
      return RestoreResult(
        success: false,
        error: 'Failed to restore backup: $e',
      );
    }
  }

  /// Verify password for an encrypted backup
  Future<bool> _verifyBackupPassword(String backupPath, String password) async {
    try {
      // Create a temporary encryption manager for the backup
      final tempDir = Directory.systemTemp.createTempSync('UniKM_verify_');
      final tempBasePath = p.join(tempDir.path, 'verify');
      
      // Copy the backup to temp location with .enc extension
      await File(backupPath).copy('$tempBasePath.enc');
      
      final encManager = EncryptionManager(tempBasePath);
      
      try {
        // Try to decrypt - will throw if password is wrong
        await encManager.decrypt(password);
        return true;
      } catch (e) {
        return false;
      } finally {
        // Cleanup temp files
        try {
          await tempDir.delete(recursive: true);
        } catch (e) {
          // Ignore cleanup errors, but log for debugging
          AppLog.d('Failed to cleanup temp dir: $e');
        }
      }
    } catch (e) {
      return false;
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

  /// Start automatic backup timer
  void startAutoBackup(Duration interval) {
    stopAutoBackup();
    _autoBackupTimer = Timer.periodic(interval, (_) async {
      await createBackup();
    });
  }

  /// Stop automatic backup timer
  void stopAutoBackup() {
    _autoBackupTimer?.cancel();
    _autoBackupTimer = null;
  }

  /// Check if auto backup is running
  bool get isAutoBackupRunning => _autoBackupTimer?.isActive ?? false;

  /// Escape SQL string for VACUUM INTO command
  String _escapeSqlString(String value) {
    return value.replaceAll("'", "''");
  }

  /// Dispose resources
  void dispose() {
    stopAutoBackup();
  }
}

/// Provider for backup service
final backupServiceProvider = Provider<BackupService>((ref) {
  final maxBackupCount = ref.watch(backupSettingsProvider).maxCount;
  final service = BackupService(ref: ref, maxBackupCount: maxBackupCount);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for the list of backups
final backupListProvider = FutureProvider<List<BackupInfo>>((ref) async {
  final backupService = ref.watch(backupServiceProvider);
  return backupService.listBackups();
});

/// State for next auto backup time
final nextAutoBackupTimeProvider =
    NotifierProvider<NextAutoBackupTimeNotifier, DateTime?>(
      NextAutoBackupTimeNotifier.new,
    );

class NextAutoBackupTimeNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void setNextBackupTime(DateTime? value) {
    state = value;
  }
}
