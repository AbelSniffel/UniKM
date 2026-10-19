import 'dart:io';

import '../../core/database/database.dart';
import '../../core/services/encrypted_db_session.dart';
import '../../core/services/encryption_manager.dart';
import '../../core/services/legacy_db_converter.dart';

/// An initialized connection and the persistence session that owns its file.
class OpenedDatabase {
  const OpenedDatabase({
    required this.database,
    required this.conversion,
    this.encryptedSession,
  });

  final AppDatabase database;
  final EncryptedDbSession? encryptedSession;
  final LegacyDbConversionResult conversion;
}

/// Opens and closes database files without depending on dialogs or providers.
/// Startup and database switching share migration and initialization behavior.
class DatabaseSessionLoader {
  const DatabaseSessionLoader();

  static String basePath(String selectedPath) =>
      selectedPath.toLowerCase().endsWith('.enc')
      ? selectedPath.substring(0, selectedPath.length - 4)
      : selectedPath;

  Future<AppDatabase> createPlain(String path) async {
    await File(path).parent.create(recursive: true);
    return _initialize(path);
  }

  Future<OpenedDatabase> openPlain(
    String path, {
    bool mustExist = false,
  }) async {
    final file = File(path);
    if (mustExist && !file.existsSync()) {
      throw FileSystemException('Database file not found', path);
    }
    final conversion = await convertLegacyDbToCurrentLayoutIfNeeded(path);
    return OpenedDatabase(
      database: await _initialize(path),
      conversion: conversion,
    );
  }

  Future<OpenedDatabase> openEncrypted(String path, String password) async {
    final manager = EncryptionManager(path);
    final tempPath = await manager.decryptToTemp(password);
    final conversion = await convertLegacyDbToCurrentLayoutIfNeeded(tempPath);
    if (conversion.converted) {
      await manager.reencryptFromTemp(tempPath, password);
    }
    return OpenedDatabase(
      database: await _initialize(tempPath),
      conversion: conversion,
      encryptedSession: EncryptedDbSession(
        baseDbPath: path,
        tempDbPath: tempPath,
        password: password,
      ),
    );
  }

  Future<AppDatabase> _initialize(String path) async {
    final database = AppDatabase.fromFile(File(path));
    try {
      await database.initDefaults();
      return database;
    } catch (_) {
      await database.close();
      rethrow;
    }
  }

  Future<void> close(AppDatabase database, EncryptedDbSession? session) async {
    if (session == null) {
      await database.close();
    } else if (session.encryptionManager.isEncrypted) {
      await session.closeAndPersist(database);
    } else {
      // Encryption may have been disabled while this connection was open.
      try {
        await database.close();
      } finally {
        try {
          if (session.tempFile.existsSync()) await session.tempFile.delete();
        } catch (_) {
          // Closing must not fail because a stale temporary file is locked.
        }
      }
    }
  }
}
