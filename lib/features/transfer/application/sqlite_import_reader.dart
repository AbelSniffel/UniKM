import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../../core/services/legacy_db_converter.dart';

class SqliteImportData {
  const SqliteImportData({required this.tables, required this.conversion});

  final Map<String, List<Map<String, dynamic>>> tables;
  final LegacyDbConversionResult conversion;
}

/// Read and normalize a private copy off the UI isolate. The worker can be
/// stopped without touching the source or the user's active database.
Future<SqliteImportData> readSqliteImport(
  String path, {
  void Function()? checkCancelled,
  Duration timeout = const Duration(seconds: 30),
}) async {
  checkCancelled?.call();
  final directory = await Directory.systemTemp.createTemp('unikm-import-read-');
  final messages = ReceivePort();
  final exited = ReceivePort();
  Isolate? worker;
  Timer? poll;
  Timer? deadline;
  try {
    final copy = await File(path).copy('${directory.path}/source.db');
    checkCancelled?.call();
    final result = Completer<SqliteImportData>();
    messages.listen((message) {
      if (result.isCompleted) return;
      if (message is SqliteImportData) {
        result.complete(message);
      } else {
        result.completeError(
          FormatException('Unsupported or damaged database: $message'),
        );
      }
    });
    worker = await Isolate.spawn(
      _readWorker,
      (copy.path, messages.sendPort),
      onExit: exited.sendPort,
      onError: messages.sendPort,
    );
    poll = Timer.periodic(const Duration(milliseconds: 100), (_) {
      try {
        checkCancelled?.call();
      } catch (error, stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      }
    });
    deadline = Timer(timeout, () {
      if (!result.isCompleted) {
        result.completeError(
          const FormatException(
            'Database validation timed out. The source may be damaged or use an unsupported structure.',
          ),
        );
      }
    });
    return await result.future;
  } finally {
    poll?.cancel();
    deadline?.cancel();
    worker?.kill(priority: Isolate.immediate);
    messages.close();
    if (worker == null) {
      exited.close();
      await directory.delete(recursive: true);
    } else {
      // A native SQLite call may take time to notice isolate termination.
      // Return the rejection promptly; remove its private copy after exit.
      final cleanup = exited.first.then((_) async {
        exited.close();
        await directory.delete(recursive: true);
      });
      try {
        await cleanup.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        unawaited(cleanup.catchError((Object _) {}));
      }
    }
  }
}

Future<void> _readWorker((String, SendPort) request) async {
  final (path, output) = request;
  try {
    var db = sqlite3.sqlite3.open(path);
    try {
      final tables = db
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((r) => r['name'])
          .toSet();
      void requireColumns(String table, Set<String> required) {
        final columns = db
            .select('PRAGMA table_info($table)')
            .map((r) => r['name'])
            .toSet();
        if (!columns.containsAll(required)) {
          throw FormatException('$table must contain ${required.join(', ')}');
        }
      }

      requireColumns('games', {'id', 'title', 'game_key'});
      if (tables.contains('tags')) requireColumns('tags', {'id', 'name'});
      if (tables.contains('game_tags')) {
        requireColumns('game_tags', {'game_id', 'tag_id'});
      }
    } finally {
      db.close();
    }
    final conversion = await convertLegacyDbToCurrentLayoutIfNeeded(path);
    db = sqlite3.sqlite3.open(path, mode: sqlite3.OpenMode.readOnly);
    try {
      output.send(
        SqliteImportData(
          conversion: conversion,
          tables: {
            for (final table in ['games', 'tags', 'game_tags'])
              table: db
                  .select('SELECT * FROM $table')
                  .map((r) => Map<String, dynamic>.from(r))
                  .toList(),
          },
        ),
      );
    } finally {
      db.close();
    }
  } catch (error) {
    output.send(error.toString());
  }
}
