import 'dart:io';

/// Recognizes SQLite's file signature without opening a database connection.
bool hasSqliteHeader(List<int> bytes) {
  const magic = 'SQLite format 3\u0000';
  if (bytes.length < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (bytes[i] != magic.codeUnitAt(i)) return false;
  }
  return true;
}

/// Missing, unreadable, and truncated files are not SQLite candidates.
Future<bool> isLikelySqliteFile(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return false;
    return hasSqliteHeader(await file.openRead(0, 16).first);
  } catch (_) {
    return false;
  }
}
