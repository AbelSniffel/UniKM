import 'package:drift/drift.dart';

import '../../../core/database/database.dart';
import '../../../models/game.dart' as model;

/// Owns atomic game and tag edits for one database session.
class LibraryRepository {
  const LibraryRepository(this.database);

  final AppDatabase database;

  /// Read only journaled changes after the initial snapshot. The cursor, rows,
  /// and relationships are read in one transaction so concurrent writes cannot
  /// be skipped or expose half an edit. Drift coalesces transaction wakeups.
  Stream<List<model.Game>> watchSnapshot() {
    final cached = <int, model.Game>{};
    var sharedTags = <int, model.Tag>{};
    List<model.Game> snapshot = const [];
    int? cursor;
    String? origin;
    return database
        .watchLibraryRevision()
        .asyncMap((_) async {
          final result = await database.transaction(() async {
            final revision = await database.getLocalSyncRevision();
            final nextOrigin = await database.getSyncDatabaseOrigin();
            final full =
                cursor == null || origin != nextOrigin || revision < cursor!;
            final ids = full
                ? null
                : (await database.getSyncRecords(
                    sinceRevision: cursor!,
                  )).map((record) => record['id']).whereType<int>().toSet();
            final entries = full
                ? await database.getAllGames()
                : await database.getGamesByIds(ids!);
            final tags = await database.getTagsForGames(
              entries.map((entry) => entry.id).toList(),
            );
            return (revision, nextOrigin, full, ids, entries, tags);
          });
          final (revision, nextOrigin, full, ids, entries, tags) = result;
          var changed = cursor == null;
          if (full) {
            cached.clear();
            changed = true;
          } else {
            final present = entries.map((entry) => entry.id).toSet();
            for (final id in ids!) {
              if (!present.contains(id) && cached.remove(id) != null) {
                changed = true;
              }
            }
          }
          for (final entry in entries) {
            final next = model.Game.fromEntry(
              entry,
              tags: [
                for (final tag in tags[entry.id] ?? <TagEntry>[])
                  sharedTags.update(
                    tag.id,
                    (old) =>
                        old.name == tag.name &&
                            old.colorHex == tag.color &&
                            old.isSteamTag == tag.isSteamTag
                        ? old
                        : model.Tag.fromEntry(tag),
                    ifAbsent: () => model.Tag.fromEntry(tag),
                  ),
              ],
            );
            if (cached[entry.id] != next) {
              cached[entry.id] = next;
              changed = true;
            }
          }
          cursor = revision;
          origin = nextOrigin;
          if (changed) {
            // Match database row order, including explicitly inserted/reused IDs.
            final orderedIds = cached.keys.toList()..sort();
            snapshot = List.unmodifiable(orderedIds.map((id) => cached[id]!));
            // Keep only live tags; deleted libraries must not accumulate caches.
            sharedTags = {
              for (final game in snapshot)
                for (final tag in game.tags) tag.id: tag,
            };
          }
          return snapshot;
        })
        .distinct(identical);
  }

  /// A replacement retains its identity and creation date. Duplicate keys are
  /// deliberately allowed when [replaceId] is absent.
  Future<int> saveNewGame(
    GamesCompanion game, {
    List<int> tagIds = const [],
    int? replaceId,
  }) => database.transaction(() async {
    final int id;
    if (replaceId == null) {
      id = await database.insertGame(game);
    } else {
      if (await database.getGameById(replaceId) == null) {
        throw StateError('The game being replaced no longer exists');
      }
      id = replaceId;
      await (database.update(
        database.games,
      )..where((g) => g.id.equals(id))).write(
        game.copyWith(
          id: const Value.absent(),
          dateAdded: const Value.absent(),
        ),
      );
    }
    await database.setTagsForGame(id, tagIds);
    final revision = await database.markLocalDataChanged();
    await database.recordGameUpsert(id, localRevision: revision);
    return id;
  });

  /// Omitted tags preserve the current database relationships, including tags
  /// attached by metadata fetching since the editor's snapshot was taken.
  Future<void> updateGame(GameEntry game, {List<int>? tagIds}) =>
      database.transaction(() async {
        if (!await database.updateGame(game)) {
          throw StateError('The game no longer exists');
        }
        if (tagIds != null) {
          await database.setTagsForGame(game.id, tagIds);
        }
        final revision = await database.markLocalDataChanged();
        await database.recordGameUpsert(game.id, localRevision: revision);
      });
}
