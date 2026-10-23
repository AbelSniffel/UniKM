/// Tracks an active decrypted session for an encrypted database.
///
/// When the database file is encrypted (stored as `<dbPath>.enc`), the app
/// decrypts it into a temporary SQLite file and opens Drift on that temp file.
/// On app exit, changes must be re-encrypted back into the `.enc` file.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

import '../../shared/storage/encrypted_save_coordinator.dart';

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

  late final _saves = EncryptedSaveCoordinator(_writeSnapshot);
  bool _closing = false;

  File get tempFile => File(tempDbPath);

  Future<void> _writeSnapshot() async {
    // Use a separate SQLite connection so WAL contents are included. VACUUM
    // INTO produces a consistent database even while the app connection is open.
    final snapshotDirectory = await Directory.systemTemp.createTemp(
      'UniKM_snapshot_',
    );
    final snapshotPath = '${snapshotDirectory.path}/snapshot.db';
    final sourcePath = tempDbPath;
    try {
      await Isolate.run(() {
        final source = sqlite3.open(sourcePath, mode: OpenMode.readOnly);
        try {
          source.execute('PRAGMA busy_timeout = 5000');
          source.execute("VACUUM INTO '${snapshotPath.replaceAll("'", "''")}'");
        } finally {
          source.close();
        }
      });
      await encryptionManager.reencryptFromTemp(snapshotPath, password);
    } finally {
      await snapshotDirectory.delete(recursive: true);
    }
  }

  Future<void> persistFromTemp() {
    if (_closing) {
      return Future.error(StateError('Database session is closing'));
    }
    return _saves.save();
  }

  Future<void> closeAndPersist(AppDatabase db) async {
    _closing = true;
    // Drain all accepted saves before closing the SQLite connection. Never
    // remove the plaintext recovery file when encryption or replacement fails.
    await _saves.flush();
    await db.close();
    // Always capture a final snapshot: legacy writers do not all mark revisions.
    await _saves.save();
    if (encryptionManager.isEncrypted) {
      await encryptionManager.deletePlaintextDatabaseFile(
        throwOnFailure: false,
      );
    }
    await _cleanupTempFiles();
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
