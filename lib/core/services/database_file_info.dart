import 'dart:io';

import '../database/sqlite_file.dart';
import 'encryption_manager.dart';

/// A lightweight file snapshot; equality also detects renames and replacements.
typedef DatabaseFileInfo = ({
  String path,
  bool exists,
  bool isEncrypted,
  int? sizeBytes,
});

/// Reads only the header, without opening a database or decrypting its contents.
/// Session paths prefer the encrypted sibling, as the database loader does.
Future<DatabaseFileInfo> inspectDatabaseFile(
  String path, {
  bool resolveEncryptedSibling = true,
}) async {
  if (resolveEncryptedSibling) {
    final base = path.toLowerCase().endsWith('.enc')
        ? path.substring(0, path.length - 4)
        : path;
    path = await File('$base.enc').exists() ? '$base.enc' : base;
  }
  final file = File(path);
  final stat = await file.stat();
  if (stat.type != FileSystemEntityType.file) {
    return (path: path, exists: false, isEncrypted: false, sizeBytes: null);
  }
  var encrypted = path.toLowerCase().endsWith('.enc');
  try {
    final handle = await file.open();
    try {
      final header = await handle.read(16);
      if (hasSqliteHeader(header)) {
        encrypted = false;
      } else if (header.isNotEmpty &&
          header.first == EncryptionConfig.metaVersion &&
          stat.size >=
              1 +
                  EncryptionConfig.saltLength +
                  EncryptionConfig.nonceLength +
                  16) {
        encrypted = true;
      }
    } finally {
      await handle.close();
    }
  } on FileSystemException {
    // A locked or atomically replaced file can be checked again on refresh.
  }
  return (
    path: path,
    exists: true,
    isEncrypted: encrypted,
    sizeBytes: stat.size,
  );
}
