import 'dart:convert';
import 'dart:math' as math;

import 'package:csv/csv.dart';
import 'package:drift/drift.dart';

import '../../../core/database/database.dart';

class ImportCancelled implements Exception {
  const ImportCancelled();
  @override
  String toString() => 'Import cancelled';
}

typedef ImportTagSpec = ({String name, String color, bool isSteamTag});

enum ImportMode { merge, update, addAnyway, replace }

class ImportRecord {
  ImportRecord(this.game, this.tagNames);
  final GamesCompanion game;
  // null preserves existing tags when the source omits the tags field.
  final List<String>? tagNames;
}

class ImportResult {
  const ImportResult(this.imported, this.updated, this.skipped);
  final int imported;
  final int updated;
  final int skipped;
}

/// Keeps CSV fields as strings so activation keys retain leading zeroes.
final libraryCsv = Csv(autoDetect: false);

List<ImportRecord> parseLibraryCsv(String content) {
  final rows = libraryCsv.decode(content);
  if (rows.isEmpty) throw const FormatException('CSV file is empty');
  final headers = rows.first.map((v) => v.toString()).toList();
  // Preserve the first occurrence when an export repeats a column name.
  final columns = <String, int>{};
  for (var i = 0; i < headers.length; i++) {
    columns.putIfAbsent(headers[i], () => i);
  }
  for (final required in ['Title', 'Key']) {
    if (!columns.containsKey(required)) {
      throw FormatException('CSV must have a "$required" column');
    }
  }
  final records = <ImportRecord>[];
  for (final row in rows.skip(1)) {
    String field(String name, [String fallback = '']) {
      final index = columns[name];
      return index == null || index >= row.length
          ? fallback
          : row[index].toString();
    }

    final key = field('Key');
    if (key.isEmpty) continue;
    final deadline = DateTime.tryParse(field('Deadline'));
    records.add(
      ImportRecord(
        GamesCompanion.insert(
          title: field('Title', 'Unknown'),
          gameKey: key,
          platform: Value(field('Platform', 'Steam')),
          notes: Value(field('Notes')),
          coverImage: Value(field('Cover')),
          steamAppId: Value(field('SteamAppId')),
          hasDeadline: Value(deadline != null),
          deadlineDate: Value(deadline),
          isUsed: Value(field('Used').toLowerCase() == 'yes'),
          isDlc: Value(field('DLC').toLowerCase() == 'yes'),
          reviewScore: Value(int.tryParse(field('Rating')) ?? 0),
          updatedAt: Value(DateTime.now()),
        ),
        columns.containsKey('Tags')
            ? field('Tags')
                  .split(';')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList()
            : null,
      ),
    );
  }
  return records;
}

List<ImportRecord> parseLibraryJson(String content) {
  final data = jsonDecode(content);
  if (data is! Map || data['games'] is! List) {
    throw const FormatException('Invalid JSON format - missing games array');
  }
  final records = <ImportRecord>[];
  for (final raw in data['games'] as List) {
    if (raw is! Map) throw const FormatException('Invalid game record');
    final key = raw['key'] as String?;
    if (key == null || key.isEmpty) {
      throw const FormatException(
        'Every JSON game must have a non-empty key field',
      );
    }
    final deadline = DateTime.tryParse((raw['deadline'] as String?) ?? '');
    records.add(
      ImportRecord(
        GamesCompanion.insert(
          title: (raw['title'] as String?) ?? 'Unknown',
          gameKey: key,
          platform: Value((raw['platform'] as String?) ?? 'Steam'),
          notes: Value((raw['notes'] as String?) ?? ''),
          isUsed: Value((raw['is_used'] as bool?) ?? false),
          coverImage: Value((raw['cover_image'] as String?) ?? ''),
          hasDeadline: Value(deadline != null),
          deadlineDate: Value(deadline),
          isDlc: Value((raw['is_dlc'] as bool?) ?? false),
          steamAppId: Value((raw['steam_app_id'] as String?) ?? ''),
          reviewScore: Value((raw['rating'] as int?) ?? 0),
          updatedAt: Value(DateTime.now()),
        ),
        (raw['tags'] as List?)?.map((v) => v.toString()).toList(),
      ),
    );
  }
  return records;
}

/// Commits a parsed import as one transaction, including tags and sync metadata.
/// No UI, provider, notification, or file-system dependencies.
class LibraryImporter {
  const LibraryImporter(this.database);
  final AppDatabase database;

  Future<ImportResult> commit(
    List<ImportRecord> records,
    ImportMode mode, {
    void Function()? checkCancelled,
    void Function(int done, int total)? onProgress,
    List<ImportTagSpec> tagSpecs = const [],
  }) async {
    checkCancelled?.call();
    if (records.isEmpty) {
      throw const FormatException('No importable games found');
    }
    // Validate the entire payload before acquiring the write transaction.
    for (final record in records) {
      database.games
          .validateIntegrity(record.game, isInserting: true)
          .throwIfInvalid(record.game);
      for (final name in record.tagNames ?? const <String>[]) {
        if (name.isEmpty || name.length > 100) {
          throw const FormatException(
            'Tag names must contain 1 to 100 characters',
          );
        }
      }
    }
    for (final tag in tagSpecs) {
      if (tag.name.trim().isEmpty || tag.name.length > 100) {
        throw const FormatException('Invalid tag name in source database');
      }
    }
    // One transaction is the import checkpoint. A cancellation or exception
    // rolls back every chunk, including replacement deletes and sync triggers.
    return database.transaction(() async {
      checkCancelled?.call();
      if (mode == ImportMode.replace) await database.clearAllData();
      final existingRows = await database
          .customSelect('SELECT id, game_key FROM games ORDER BY id')
          .get();
      final existingByKey = <String, int>{};
      for (final row in existingRows) {
        existingByKey.putIfAbsent(
          row.read<String>('game_key'),
          () => row.read<int>('id'),
        );
      }
      final sequence = await database
          .customSelect(
            "SELECT MAX(value) AS value FROM (SELECT COALESCE(MAX(id), 0) AS value FROM games UNION ALL SELECT seq FROM sqlite_sequence WHERE name = 'games')",
          )
          .getSingle();
      var nextId = sequence.read<int>('value') + 1;
      final tags = <String, TagEntry>{};
      // Chunk tag queries too, staying below SQLite's bind-variable limit.
      Future<void> resolveTags(List<ImportTagSpec> specs) async {
        for (var offset = 0; offset < specs.length; offset += 200) {
          checkCancelled?.call();
          tags.addAll(
            await database.batchGetOrCreateTags(
              specs.sublist(offset, math.min(offset + 200, specs.length)),
            ),
          );
        }
      }

      await resolveTags(tagSpecs);
      var imported = 0;
      var updated = 0;
      var skipped = 0;
      for (var offset = 0; offset < records.length; offset += 100) {
        checkCancelled?.call();
        final end = math.min(offset + 100, records.length);
        final writes = <({int id, ImportRecord record, bool update})>[];
        final missingTags = <String, ImportTagSpec>{};
        for (final record in records.sublist(offset, end)) {
          final key = record.game.gameKey.value;
          final existing = existingByKey[key];
          if (mode == ImportMode.merge && existing != null) {
            skipped++;
            continue;
          }
          final update = mode == ImportMode.update && existing != null;
          final id = update ? existing : nextId++;
          existingByKey.putIfAbsent(key, () => id);
          writes.add((id: id, record: record, update: update));
          if (update) {
            updated++;
          } else {
            imported++;
          }
          for (final name in record.tagNames ?? const <String>[]) {
            final normalized = name.trim().toLowerCase();
            if (!tags.containsKey(normalized)) {
              missingTags[normalized] = (
                name: name,
                color: '#0078d4',
                isSteamTag: false,
              );
            }
          }
        }
        await resolveTags(missingTags.values.toList());
        await database.batch((batch) {
          for (final write in writes) {
            final game = write.record.game;
            if (write.update) {
              batch.update(
                database.games,
                game.copyWith(
                  id: const Value.absent(),
                  dateAdded: const Value.absent(),
                ),
                where: (g) => g.id.equals(write.id),
              );
            } else {
              batch.insert(
                database.games,
                database.gameInsertWithDefaults(
                  game.copyWith(id: Value(write.id)),
                ),
              );
            }
            final names = write.record.tagNames;
            if (names != null) {
              batch.deleteWhere(
                database.gameTags,
                (t) => t.gameId.equals(write.id),
              );
              for (final id
                  in names
                      .map((n) => tags[n.trim().toLowerCase()]!.id)
                      .toSet()) {
                batch.insert(
                  database.gameTags,
                  GameTagsCompanion.insert(gameId: write.id, tagId: id),
                  mode: InsertMode.insertOrIgnore,
                );
              }
            }
          }
        });
        await database.clearImportedGameTombstones(
          writes.map((w) => w.id).toList(),
        );
        onProgress?.call(end, records.length);
        // Let cancellation and UI input run between bounded write chunks.
        await Future<void>.delayed(Duration.zero);
        checkCancelled?.call();
      }
      if (imported + updated > 0) await database.markLocalDataChanged();
      checkCancelled?.call();
      return ImportResult(imported, updated, skipped);
    });
  }
}
