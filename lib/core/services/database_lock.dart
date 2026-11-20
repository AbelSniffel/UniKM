/// Keeps two UniKM windows from opening the same database file.
///
/// Each window keeps its own copy of an encrypted database and its own
/// settings, so a second window could disable encryption or rewrite the file
/// underneath the first, whose edits would then be lost.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Another UniKM window already has [databasePath] open.
class const DatabaseInUseException(final String databasePath)
    implements Exception {
  @override
  String toString() =>
      '${p.basename(databasePath)} is already open in another UniKM window. '
      'Close that window, then try again.';
}

/// The lock on this process's active database. The operating system releases
/// it when the process exits, so a crash leaves nothing to clean up.
class DatabaseLock._() {
  static String? _heldPath;
  static RandomAccessFile? _held;

  /// The hidden lock file kept beside [basePath]. It is never deleted: another
  /// window may be about to lock it.
  static String lockPathFor(String basePath) {
    final absolute = p.normalize(p.absolute(basePath));
    return p.join(p.dirname(absolute), '.${p.basename(absolute)}.lock');
  }

  /// Makes [basePath] this process's database, releasing the previous one's
  /// lock once the new one is held. Throws [DatabaseInUseException] when
  /// another process holds it. Locks only conflict between processes.
  static Future<void> acquire(String basePath) async {
    if (!(Platform.isLinux || Platform.isWindows || Platform.isMacOS)) return;
    final lockPath = lockPathFor(basePath);
    if (_heldPath == lockPath) return;
    await Directory(p.dirname(lockPath)).create(recursive: true);
    final file = await File(lockPath).open(mode: FileMode.append);
    try {
      await file.lock(FileLock.exclusive, 0, 1);
    } on FileSystemException {
      await file.close();
      throw DatabaseInUseException(basePath);
    }
    final previous = _held;
    _held = file;
    _heldPath = lockPath;
    await previous?.close();
  }
}
