/// Tracks an active decrypted session for an encrypted database.
///
/// When the database file is encrypted (stored as `<dbPath>.enc`), the app
/// decrypts it into a temporary SQLite file and opens Drift on that temp file.
/// On app exit, changes must be re-encrypted back into the `.enc` file.
library;

import 'dart:io';

import '../database/database.dart';
import 'encryption_manager.dart';

class EncryptedDbSession {
  EncryptedDbSession({
    required this.baseDbPath,
    required this.tempDbPath,
    required this.password,
  }) : encryptionManager = EncryptionManager(baseDbPath);

  /// Base path (without `.enc`) used by [EncryptionManager].
  final String baseDbPath;

  /// Temporary plaintext SQLite database file path.
  final String tempDbPath;

  /// Password used to decrypt/encrypt for this session (in-memory only).
  final String password;

  final EncryptionManager encryptionManager;

  DateTime? _lastPersistedAt;

  File get tempFile => File(tempDbPath);

  /// Persist the current temp database back into the encrypted `.enc` file.
  Future<void> persistFromTemp() async {
    await encryptionManager.reencryptFromTemp(tempDbPath, password);
    _lastPersistedAt = DateTime.now();
  }

  bool shouldPersistOnClose({Duration threshold = const Duration(seconds: 2)}) {
    final last = _lastPersistedAt;
    if (last == null) return true;
    return DateTime.now().difference(last) > threshold;
  }

  /// Close the database, persist, and clean up temp files.
  Future<void> closeAndPersist(AppDatabase db) async {
    try {
      await db.close();
    } finally {
      if (shouldPersistOnClose()) {
        await persistFromTemp();
      }
      // Clean up temp file and directory after database is closed
      await _cleanupTempFiles();
    }
  }
  
  /// Clean up temp files (call only after database is closed)
  Future<void> _cleanupTempFiles() async {
    try {
      final file = File(tempDbPath);
      if (await file.exists()) {
        await file.delete();
      }
      // Also try to delete the temp directory
      final dir = file.parent;
      if (await dir.exists() && dir.path.contains('UniKM_db_')) {
        await dir.delete();
      }
    } catch (e) {
      // Best effort cleanup - ignore errors
    }
  }
}
