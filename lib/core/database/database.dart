/// Drift database definition and connection
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';
import '../constants/legacy_default_tag_names.dart';
import 'tables.dart';

part 'database.g.dart';

/// Main database class for UniKM
@DriftDatabase(tables: [Games, Tags, GameTags, Backups])
class AppDatabase extends _$AppDatabase {
  static const String _syncMetadataTable = 'sync_metadata';
  static const String _syncGameTombstonesTable = 'sync_game_tombstones';
  static const String _legacySyncGameTombstonesTable =
      'sync_game_tombstones_legacy';
  static const String _syncPeerCheckpointsTable = 'sync_peer_checkpoints';
  static const String _syncMetadataLocalRevisionKey = 'local_revision';
  static const String _syncMetadataDbTimestampKey = 'db_timestamp_millis';

  AppDatabase() : super(_openConnection());

  /// Constructor for testing with custom executor
  AppDatabase.forTesting(super.e);

  /// Constructor for opening a specific database file
  AppDatabase.fromFile(File file)
    : super(NativeDatabase.createInBackground(file));

  @override
  int get schemaVersion => 8;

  /// Initialize database with defaults (call once at app startup)
  Future<void> initDefaults() async {
    // Ensure the migration has run (creates tables)
    // Drift handles this automatically on first query, but we can force it
    await customStatement('SELECT 1');
  }

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        await _createSyncMetadataTables();
        await _initializeSyncMetadata();
        // Create indexes for better query performance
        await _createIndexes();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        Future<bool> columnExists(String table, String column) async {
          final rows = await customSelect('PRAGMA table_info($table)').get();
          return rows.any((row) => row.data['name'] == column);
        }

        Future<bool> tableExists(String table) async {
          final rows = await customSelect(
            'SELECT name FROM sqlite_master WHERE type = ? AND name = ?',
            variables: [
              Variable.withString('table'),
              Variable.withString(table),
            ],
          ).get();
          return rows.isNotEmpty;
        }

        if (from < 2) {
          // Games table: Steam-related columns
          if (!await columnExists('games', 'cover_image')) {
            await customStatement(
              'ALTER TABLE games ADD COLUMN cover_image TEXT NOT NULL DEFAULT ""',
            );
          }
          if (!await columnExists('games', 'has_deadline')) {
            await customStatement(
              'ALTER TABLE games ADD COLUMN has_deadline INTEGER NOT NULL DEFAULT 0',
            );
          }
          if (!await columnExists('games', 'deadline_date')) {
            await customStatement(
              'ALTER TABLE games ADD COLUMN deadline_date TEXT',
            );
          }
          if (!await columnExists('games', 'is_dlc')) {
            await customStatement(
              'ALTER TABLE games ADD COLUMN is_dlc INTEGER NOT NULL DEFAULT 0',
            );
          }
          if (!await columnExists('games', 'steam_app_id')) {
            await customStatement(
              'ALTER TABLE games ADD COLUMN steam_app_id TEXT NOT NULL DEFAULT ""',
            );
          }
          if (!await columnExists('games', 'review_score')) {
            await customStatement(
              'ALTER TABLE games ADD COLUMN review_score INTEGER NOT NULL DEFAULT 0',
            );
          }
          if (!await columnExists('games', 'review_count')) {
            await customStatement(
              'ALTER TABLE games ADD COLUMN review_count INTEGER NOT NULL DEFAULT 0',
            );
          }

          // Tags table: Steam tag marker
          if (!await columnExists('tags', 'is_steam_tag')) {
            await customStatement(
              'ALTER TABLE tags ADD COLUMN is_steam_tag INTEGER NOT NULL DEFAULT 0',
            );
          }
        }

        if (from < 3) {
          if (!await columnExists('games', 'updated_at')) {
            await customStatement(
              'ALTER TABLE games ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
            );
          }
        }

        if (from < 4) {
          if (await columnExists('games', 'updated_at')) {
            await customStatement(
              "UPDATE games SET updated_at = date_added WHERE updated_at IS NULL OR updated_at = '' OR updated_at = 0 OR typeof(updated_at) != 'integer'",
            );
          }
        }

        // Clean up any orphaned entries which could have accumulated in
        // earlier versions where cascading deletes weren't enforced. Those
        // orphaned rows prevented `deleteUnusedTags` from working properly
        // and are the root cause of the bug reported by the user.
        if (from < 5) {
          await customStatement(
            'DELETE FROM game_tags WHERE game_id NOT IN (SELECT id FROM games) OR '
            'tag_id NOT IN (SELECT id FROM tags)',
          );
        }

        if (from < 6) {
          if (!await columnExists('games', 'developer')) {
            await customStatement(
              'ALTER TABLE games ADD COLUMN developer TEXT NOT NULL DEFAULT ""',
            );
          }
        }

        if (from < 7) {
          await _createSyncMetadataTables();
          await _initializeSyncMetadata();
        }

        if (from < 8) {
          final tombstonesTableExists = await tableExists(
            _syncGameTombstonesTable,
          );
          if (tombstonesTableExists) {
            final hasGameId = await columnExists(
              _syncGameTombstonesTable,
              'game_id',
            );
            if (!hasGameId) {
              await customStatement(
                'DROP TABLE IF EXISTS $_legacySyncGameTombstonesTable',
              );
              await customStatement(
                'ALTER TABLE $_syncGameTombstonesTable '
                'RENAME TO $_legacySyncGameTombstonesTable',
              );
            }
          }

          // Recreate tombstones as SKM-ID centric. Legacy key-only tombstones
          // are intentionally dropped because they cannot be mapped safely
          // when duplicate keys exist.
          await customStatement(
            'CREATE TABLE IF NOT EXISTS $_syncGameTombstonesTable ('
            'game_id INTEGER PRIMARY KEY NOT NULL, '
            'game_key TEXT NOT NULL DEFAULT "", '
            'deleted_at INTEGER NOT NULL, '
            'local_revision INTEGER NOT NULL'
            ')',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_sync_game_tombstones_revision '
            'ON $_syncGameTombstonesTable(local_revision)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_sync_game_tombstones_deleted_at '
            'ON $_syncGameTombstonesTable(deleted_at)',
          );
          await customStatement(
            'DROP TABLE IF EXISTS $_legacySyncGameTombstonesTable',
          );
        }

        // Always try to create indexes (will be ignored if they exist)
        await _createIndexes();
      },
    );
  }

  Future<void> _createSyncMetadataTables() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS $_syncMetadataTable ('
      'key TEXT PRIMARY KEY NOT NULL, '
      'value TEXT NOT NULL'
      ')',
    );

    await customStatement(
      'CREATE TABLE IF NOT EXISTS $_syncGameTombstonesTable ('
      'game_id INTEGER PRIMARY KEY NOT NULL, '
      'game_key TEXT NOT NULL DEFAULT "", '
      'deleted_at INTEGER NOT NULL, '
      'local_revision INTEGER NOT NULL'
      ')',
    );

    await customStatement(
      'CREATE TABLE IF NOT EXISTS $_syncPeerCheckpointsTable ('
      'peer_id TEXT PRIMARY KEY NOT NULL, '
      'last_revision INTEGER NOT NULL DEFAULT 0, '
      'last_sync_at INTEGER NOT NULL DEFAULT 0, '
      'remote_revision_id TEXT NOT NULL DEFAULT ""'
      ')',
    );

    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sync_game_tombstones_revision '
      'ON $_syncGameTombstonesTable(local_revision)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sync_game_tombstones_deleted_at '
      'ON $_syncGameTombstonesTable(deleted_at)',
    );
  }

  Future<void> _initializeSyncMetadata() async {
    final currentRevision = await getLocalSyncRevision();
    if (currentRevision <= 0) {
      await _writeSyncMetadataValue(
        _syncMetadataLocalRevisionKey,
        DateTime.now().microsecondsSinceEpoch.toString(),
      );
    }

    final currentDbTimestamp = await getSyncDbTimestampMillis();
    if (currentDbTimestamp <= 0) {
      await _writeSyncMetadataValue(
        _syncMetadataDbTimestampKey,
        DateTime.now().millisecondsSinceEpoch.toString(),
      );
    }
  }

  /// Create indexes for better query performance
  Future<void> _createIndexes() async {
    // Index on games.title for search queries
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_games_title ON games(title)',
    );
    // Index on games.platform for filter queries
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_games_platform ON games(platform)',
    );
    // Index on game_tags.game_id for efficient tag lookups
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_game_tags_game_id ON game_tags(game_id)',
    );
    // Index on game_tags.tag_id for efficient reverse lookups
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_game_tags_tag_id ON game_tags(tag_id)',
    );
    // Index on games.steam_app_id for Steam duplicate detection
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_games_steam_app_id ON games(steam_app_id)',
    );
  }

  Future<void> _writeSyncMetadataValue(String key, String value) {
    return customStatement(
      'INSERT INTO $_syncMetadataTable(key, value) VALUES(?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      <Object>[key, value],
    );
  }

  Future<String?> _readSyncMetadataValue(String key) async {
    final rows = await customSelect(
      'SELECT value FROM $_syncMetadataTable WHERE key = ?',
      variables: [Variable.withString(key)],
      readsFrom: const {},
    ).get();
    if (rows.isEmpty) return null;
    return rows.first.data['value'] as String?;
  }

  Future<int> getLocalSyncRevision() async {
    final raw = await _readSyncMetadataValue(_syncMetadataLocalRevisionKey);
    return int.tryParse(raw ?? '') ?? 0;
  }

  Future<int> bumpLocalSyncRevision() async {
    final current = await getLocalSyncRevision();
    var next = DateTime.now().microsecondsSinceEpoch;
    if (next <= current) {
      next = current + 1;
    }
    await _writeSyncMetadataValue(
      _syncMetadataLocalRevisionKey,
      next.toString(),
    );
    return next;
  }

  Future<int> getSyncDbTimestampMillis() async {
    final raw = await _readSyncMetadataValue(_syncMetadataDbTimestampKey);
    return int.tryParse(raw ?? '') ?? 0;
  }

  Future<int> setSyncDbTimestampMillis(int timestampMillis) async {
    final next = timestampMillis > 0
        ? timestampMillis
        : DateTime.now().millisecondsSinceEpoch;
    await _writeSyncMetadataValue(_syncMetadataDbTimestampKey, next.toString());
    return next;
  }

  /// Marks local database content as changed.
  ///
  /// This updates both the monotonic local revision and the database-level
  /// timestamp used to coordinate multi-device sync ordering.
  Future<int> markLocalDataChanged({int? timestampMillis}) async {
    final revision = await bumpLocalSyncRevision();
    await setSyncDbTimestampMillis(
      timestampMillis ?? DateTime.now().millisecondsSinceEpoch,
    );
    return revision;
  }

  Future<void> clearGameTombstone(int gameId) async {
    if (gameId <= 0) return;
    await customStatement(
      'DELETE FROM $_syncGameTombstonesTable WHERE game_id = ?',
      <Object>[gameId],
    );
  }

  Future<void> recordGameUpsert(int gameId, {int? localRevision}) async {
    if (gameId <= 0) return;

    if (localRevision == null) {
      await bumpLocalSyncRevision();
    }
    await clearGameTombstone(gameId);
  }

  Future<void> recordGameDeletionTombstones(
    List<int> gameIds, {
    Map<int, String>? gameKeysById,
    int? localRevision,
    int? deletedAtMillis,
  }) async {
    final normalizedIds = gameIds
        .where((id) => id > 0)
        .toSet()
        .toList(growable: false);
    if (normalizedIds.isEmpty) return;

    final revision = localRevision ?? await bumpLocalSyncRevision();
    final deletedAt = deletedAtMillis ?? DateTime.now().millisecondsSinceEpoch;
    for (final gameId in normalizedIds) {
      final gameKey = (gameKeysById?[gameId] ?? '').trim();
      await customStatement(
        'INSERT INTO $_syncGameTombstonesTable(game_id, game_key, deleted_at, local_revision) '
        'VALUES(?, ?, ?, ?) '
        'ON CONFLICT(game_id) DO UPDATE SET '
        'game_key = excluded.game_key, '
        'deleted_at = excluded.deleted_at, '
        'local_revision = excluded.local_revision',
        <Object>[gameId, gameKey, deletedAt, revision],
      );
    }
  }

  Future<List<Map<String, dynamic>>> getGameTombstonesSinceRevision(
    int revision,
  ) async {
    final rows = await customSelect(
      'SELECT game_id, game_key, deleted_at, local_revision '
      'FROM $_syncGameTombstonesTable '
      'WHERE local_revision > ? '
      'ORDER BY local_revision ASC, game_id ASC',
      variables: [Variable.withInt(revision)],
      readsFrom: const {},
    ).get();

    return rows
        .map(
          (row) => <String, dynamic>{
            'id': row.data['game_id'],
            'gameKey': row.data['game_key'],
            'deletedAt': row.data['deleted_at'],
            'localRevision': row.data['local_revision'],
          },
        )
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> getPeerSyncCheckpoint(String peerId) async {
    final trimmedPeerId = peerId.trim();
    if (trimmedPeerId.isEmpty) return null;

    final rows = await customSelect(
      'SELECT peer_id, last_revision, last_sync_at, remote_revision_id '
      'FROM $_syncPeerCheckpointsTable WHERE peer_id = ?',
      variables: [Variable.withString(trimmedPeerId)],
      readsFrom: const {},
    ).get();
    if (rows.isEmpty) return null;

    final data = rows.first.data;
    return <String, dynamic>{
      'peerId': data['peer_id'],
      'lastRevision': data['last_revision'],
      'lastSyncAt': data['last_sync_at'],
      'remoteRevisionId': data['remote_revision_id'],
    };
  }

  Future<void> savePeerSyncCheckpoint({
    required String peerId,
    required int lastRevision,
    DateTime? lastSyncAt,
    String remoteRevisionId = '',
  }) async {
    final trimmedPeerId = peerId.trim();
    if (trimmedPeerId.isEmpty) return;

    final syncAtMillis =
        (lastSyncAt ?? DateTime.now()).millisecondsSinceEpoch;

    await customStatement(
      'INSERT INTO $_syncPeerCheckpointsTable('
      'peer_id, last_revision, last_sync_at, remote_revision_id'
      ') VALUES(?, ?, ?, ?) '
      'ON CONFLICT(peer_id) DO UPDATE SET '
      'last_revision = excluded.last_revision, '
      'last_sync_at = excluded.last_sync_at, '
      'remote_revision_id = excluded.remote_revision_id',
      <Object>[
        trimmedPeerId,
        lastRevision,
        syncAtMillis,
        remoteRevisionId,
      ],
    );
  }

  // ===========================================================================
  // GAME OPERATIONS
  // ===========================================================================

  /// Get all games
  Future<List<GameEntry>> getAllGames() => select(games).get();

  /// Watch all games (for real-time updates)
  Stream<List<GameEntry>> watchAllGames() => select(games).watch();

  /// Get a single game by ID
  Future<GameEntry?> getGameById(int id) {
    return (select(games)..where((g) => g.id.equals(id))).getSingleOrNull();
  }

  /// Search games by title
  Future<List<GameEntry>> searchGamesByTitle(String query) {
    return (select(games)..where((g) => g.title.like('%$query%'))).get();
  }

  /// Get a game's id by key.
  Future<int?> getGameIdByKey(String key) async {
    final query = selectOnly(games)
      ..where(games.gameKey.equals(key))
      ..orderBy([OrderingTerm.asc(games.id)])
      ..limit(1);
    query.addColumns([games.id]);
    final row = await query.getSingleOrNull();
    return row?.read(games.id);
  }

  /// Insert a new game
  Future<int> insertGame(GamesCompanion game) {
    return into(games).insert(game);
  }

  /// Insert multiple games in a batch
  Future<void> insertGames(List<GamesCompanion> gamesList) {
    return batch((b) {
      b.insertAll(games, gamesList);
    });
  }

  /// Update a game
  Future<bool> updateGame(GameEntry game) {
    return update(games).replace(game);
  }

  /// Update specific fields of a game
  Future<int> updateGameFields(
    int id, {
    String? title,
    String? gameKey,
    String? platform,
    String? notes,
    bool? isUsed,
    String? coverImage,
    bool? hasDeadline,
    DateTime? deadlineDate,
    bool? isDlc,
    String? steamAppId,
    String? developer,
    int? reviewScore,
    int? reviewCount,
    DateTime? updatedAt,
  }) async {
    final existing = await getGameById(id);
    if (existing == null) {
      return 0;
    }

    final updated = existing.copyWith(
      title: title ?? existing.title,
      gameKey: gameKey ?? existing.gameKey,
      platform: platform ?? existing.platform,
      notes: notes ?? existing.notes,
      isUsed: isUsed ?? existing.isUsed,
      coverImage: coverImage ?? existing.coverImage,
      hasDeadline: hasDeadline ?? existing.hasDeadline,
      deadlineDate: deadlineDate != null
          ? Value(deadlineDate)
          : const Value.absent(),
      isDlc: isDlc ?? existing.isDlc,
      steamAppId: steamAppId ?? existing.steamAppId,
      developer: developer ?? existing.developer,
      reviewScore: reviewScore ?? existing.reviewScore,
      reviewCount: reviewCount ?? existing.reviewCount,
      updatedAt: updatedAt ?? existing.updatedAt,
    );

    return await updateGame(updated) ? 1 : 0;
  }

  /// Delete a game by ID
  /// Delete a game by ID.
  ///
  /// Also removes any relationships in [gameTags] to keep the database
  /// clean. Prior versions of the app relied on `ON DELETE CASCADE` in the
  /// schema, but SQLite did not enforce it for existing databases. To ensure
  /// tags become truly unused after the last game is removed we manually
  /// clear the junction rows here. This method runs in a transaction so the
  /// two operations are atomic.
  Future<int> deleteGame(int id) {
    return transaction(() async {
      final revision = await bumpLocalSyncRevision();
      final deletedAt = DateTime.now().millisecondsSinceEpoch;
      final row = await customSelect(
        'SELECT game_key FROM games WHERE id = ?',
        variables: [Variable.withInt(id)],
        readsFrom: {games},
      ).getSingleOrNull();
      final gameKey = (row?.data['game_key'] as String?)?.trim() ?? '';

      // Remove any orphaned relationships first (defensive).
      await (delete(gameTags)..where((gt) => gt.gameId.equals(id))).go();
      final deleted = await (delete(games)..where((g) => g.id.equals(id))).go();
      if (deleted > 0) {
        await recordGameDeletionTombstones(
          [id],
          gameKeysById: gameKey.isEmpty ? null : {id: gameKey},
          localRevision: revision,
          deletedAtMillis: deletedAt,
        );
      }
      return deleted;
    });
  }

  /// Delete multiple games by IDs.
  ///
  /// The implementation mirrors [deleteGame] but operates on a list of
  /// identifiers. It also clears the corresponding entries in [gameTags]
  /// so that downstream operations, such as `deleteUnusedTags`, correctly
  /// recognise when a tag is no longer associated with any remaining game.
  Future<int> deleteGames(List<int> ids) {
    if (ids.isEmpty) return Future.value(0);
    return transaction(() async {
      final revision = await bumpLocalSyncRevision();
      final deletedAt = DateTime.now().millisecondsSinceEpoch;
      final keyRows = await customSelect(
        'SELECT id, game_key FROM games WHERE id IN (${List.filled(ids.length, '?').join(', ')})',
        variables: ids.map(Variable.withInt).toList(growable: false),
        readsFrom: {games},
      ).get();
      final gameKeysById = <int, String>{};
      final deletedIds = <int>[];
      for (final row in keyRows) {
        final gameId = (row.data['id'] as num?)?.toInt();
        if (gameId == null || gameId <= 0) continue;
        deletedIds.add(gameId);
        final key = (row.data['game_key'] as String?)?.trim() ?? '';
        if (key.isNotEmpty) {
          gameKeysById[gameId] = key;
        }
      }

      await (delete(gameTags)..where((gt) => gt.gameId.isIn(ids))).go();
      final deleted = await (delete(games)..where((g) => g.id.isIn(ids))).go();
      if (deleted > 0 && deletedIds.isNotEmpty) {
        await recordGameDeletionTombstones(
          deletedIds,
          gameKeysById: gameKeysById,
          localRevision: revision,
          deletedAtMillis: deletedAt,
        );
      }
      return deleted;
    });
  }

  /// Mark game as used/unused
  Future<bool> setGameUsed(int id, bool isUsed) async {
    final game = await getGameById(id);
    if (game == null) return false;
    return updateGame(game.copyWith(isUsed: isUsed));
  }

  /// Mark multiple games as used/unused in a single update.
  ///
  /// Returns the number of rows updated.
  Future<int> setGamesUsed(List<int> ids, bool isUsed) {
    if (ids.isEmpty) return Future.value(0);
    return (update(games)..where((g) => g.id.isIn(ids))).write(
      GamesCompanion(
        isUsed: Value(isUsed),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Get games count
  Future<int> getGamesCount() async {
    final count = countAll();
    final query = selectOnly(games)..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  // ===========================================================================
  // TAG OPERATIONS
  // ===========================================================================

  /// Get all tags
  Future<List<TagEntry>> getAllTags() => select(tags).get();

  /// Watch all tags
  Stream<List<TagEntry>> watchAllTags() => select(tags).watch();

  /// Get tag by name (case-insensitive)
  Future<TagEntry?> getTagByName(String name) {
    return (select(tags)
          ..where((t) => t.name.lower().equals(name.toLowerCase()))
          ..orderBy([(t) => OrderingTerm.asc(t.id)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Get or create tag by name
  Future<TagEntry> getOrCreateTag(
    String name, {
    String? color,
    bool isSteamTag = false,
  }) async {
    final existing = await getTagByName(name);
    if (existing != null) {
      // If the stored name differs only in casing and this is a Steam tag,
      // update the stored name so the correct casing is persisted (e.g.
      // fixing a previously saved "Pve" → "PvE").
      if (isSteamTag && existing.name != name) {
        final updated = existing.copyWith(name: name);
        await update(tags).replace(updated);
        return updated;
      }
      return existing;
    }

    final id = await into(tags).insert(
      TagsCompanion.insert(
        name: name,
        color: Value(color ?? '#0078d4'),
        isSteamTag: Value(isSteamTag),
      ),
    );

    return TagEntry(
      id: id,
      name: name,
      color: color ?? '#0078d4',
      isSteamTag: isSteamTag,
    );
  }

  /// Insert a new tag
  Future<int> insertTag(TagsCompanion tag) {
    return into(tags).insert(tag);
  }

  /// Update a tag
  Future<bool> updateTag(TagEntry tag) {
    return update(tags).replace(tag);
  }

  /// Delete a tag by ID
  Future<int> deleteTag(int id) {
    return (delete(tags)..where((t) => t.id.equals(id))).go();
  }

  /// Delete unused tags (tags not associated with any game)
  Future<int> deleteUnusedTags() async {
    // Compute the set of tag IDs that are still referenced by *existing*
    // games. Older schema versions did not cascade deletes from `games` into
    // `game_tags`, so it's possible to have orphaned rows here; joining with
    // `games` filters those out.
    final usedTagIds = selectOnly(gameTags, distinct: true)
      ..addColumns([gameTags.tagId])
      ..join([innerJoin(games, games.id.equalsExp(gameTags.gameId))]);

    return (delete(tags)..where((t) => t.id.isNotInQuery(usedTagIds))).go();
  }

  /// One-time cleanup: remove legacy default tags (custom-only).
  ///
  /// This removes the legacy tags and their game relationships.
  ///
  /// IMPORTANT: This targets only non-Steam tags to avoid interfering with
  /// Steam-provided tags.
  Future<int> deleteLegacyDefaultCustomTags() async {
    if (kLegacyDefaultTagNames.isEmpty) return 0;

    final legacyTags =
        await (select(tags)..where(
              (t) =>
                  t.isSteamTag.equals(false) &
                  t.name.isIn(kLegacyDefaultTagNames.toList()),
            ))
            .get();

    if (legacyTags.isEmpty) return 0;
    final legacyIds = legacyTags.map((t) => t.id).toList(growable: false);

    return transaction(() async {
      // Remove relationships first to avoid FK issues.
      await (delete(gameTags)..where((gt) => gt.tagId.isIn(legacyIds))).go();
      return (delete(tags)..where((t) => t.id.isIn(legacyIds))).go();
    });
  }

  /// Clear unused tags that are NOT user-created custom tags.
  ///
  /// - Deletes unused Steam tags.
  /// - Deletes unused legacy default custom tags.
  /// - Keeps unused user custom tags.
  Future<int> deleteUnusedNonUserTags() async {
    final usedTagIds = selectOnly(gameTags, distinct: true)
      ..addColumns([gameTags.tagId])
      ..join([innerJoin(games, games.id.equalsExp(gameTags.gameId))]);

    final deletedSteamUnused =
        await (delete(tags)..where(
              (t) => t.isSteamTag.equals(true) & t.id.isNotInQuery(usedTagIds),
            ))
            .go();

    if (kLegacyDefaultTagNames.isEmpty) return deletedSteamUnused;

    final deletedLegacyUnused =
        await (delete(tags)..where(
              (t) =>
                  t.isSteamTag.equals(false) &
                  t.name.isIn(kLegacyDefaultTagNames.toList()) &
                  t.id.isNotInQuery(usedTagIds),
            ))
            .go();

    return deletedSteamUnused + deletedLegacyUnused;
  }

  // ===========================================================================
  // GAME-TAG RELATIONSHIP OPERATIONS
  // ===========================================================================

  /// Get tags for a game
  Future<List<TagEntry>> getTagsForGame(int gameId) async {
    final query = select(tags).join([
      innerJoin(gameTags, gameTags.tagId.equalsExp(tags.id)),
    ])..where(gameTags.gameId.equals(gameId));

    final results = await query.get();
    return results.map((row) => row.readTable(tags)).toList();
  }

  /// Get tags for multiple games in a single query (batch fetch).
  /// Returns a map of gameId to a list of [TagEntry] objects.
  Future<Map<int, List<TagEntry>>> getTagsForGames(List<int> gameIds) async {
    if (gameIds.isEmpty) return {};

    final query = select(tags).join([
      innerJoin(gameTags, gameTags.tagId.equalsExp(tags.id)),
    ])..where(gameTags.gameId.isIn(gameIds));

    final results = await query.get();
    final Map<int, List<TagEntry>> tagsByGame = {};

    for (final row in results) {
      final gameId = row.readTable(gameTags).gameId;
      final tag = row.readTable(tags);
      tagsByGame.putIfAbsent(gameId, () => []).add(tag);
    }

    return tagsByGame;
  }

  /// Watch tags for a game
  Stream<List<TagEntry>> watchTagsForGame(int gameId) {
    final query = select(tags).join([
      innerJoin(gameTags, gameTags.tagId.equalsExp(tags.id)),
    ])..where(gameTags.gameId.equals(gameId));

    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(tags)).toList(),
    );
  }

  /// Get games for a tag
  Future<List<GameEntry>> getGamesForTag(int tagId) async {
    final query = select(games).join([
      innerJoin(gameTags, gameTags.gameId.equalsExp(games.id)),
    ])..where(gameTags.tagId.equals(tagId));

    final results = await query.get();
    return results.map((row) => row.readTable(games)).toList();
  }

  /// Get games by Steam AppID
  Future<List<GameEntry>> getGamesBySteamAppId(String appId) async {
    return (select(games)..where((g) => g.steamAppId.equals(appId))).get();
  }

  /// Add a tag to a game
  Future<void> addTagToGame(int gameId, int tagId) {
    return into(gameTags).insert(
      GameTagsCompanion.insert(gameId: gameId, tagId: tagId),
      mode: InsertMode.insertOrIgnore,
    );
  }

  /// Remove a tag from a game
  Future<int> removeTagFromGame(int gameId, int tagId) {
    return (delete(
      gameTags,
    )..where((gt) => gt.gameId.equals(gameId) & gt.tagId.equals(tagId))).go();
  }

  /// Set tags for a game (replaces existing tags)
  Future<void> setTagsForGame(
    int gameId,
    List<int> tagIds, {
    bool touchGameUpdatedAt = true,
  }) async {
    await transaction(() async {
      // Remove existing tags
      await (delete(gameTags)..where((gt) => gt.gameId.equals(gameId))).go();

      // Add new tags
      if (tagIds.isNotEmpty) {
        await batch((b) {
          b.insertAll(
            gameTags,
            tagIds
                .map(
                  (tagId) =>
                      GameTagsCompanion.insert(gameId: gameId, tagId: tagId),
                )
                .toList(),
            mode: InsertMode.insertOrIgnore,
          );
        });
      }

      if (touchGameUpdatedAt) {
        await (update(games)..where((g) => g.id.equals(gameId))).write(
          GamesCompanion(updatedAt: Value(DateTime.now())),
        );
      }
    });
  }

  // ===========================================================================
  // BATCH OPERATIONS (for high-performance sync)
  // ===========================================================================

  /// Bulk-resolve tag specs into TagEntry objects. Existing tags are loaded
  /// in a single query; missing tags are inserted in one batch.
  Future<Map<String, TagEntry>> batchGetOrCreateTags(
    List<({String name, String color, bool isSteamTag})> tagSpecs,
  ) async {
    if (tagSpecs.isEmpty) return {};

    final namesLower = tagSpecs
        .map((s) => s.name.trim().toLowerCase())
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (namesLower.isEmpty) return {};

    // Single query: SELECT * FROM tags WHERE name IN (...)
    final existingRows = await (select(tags)
          ..where((t) => t.name.lower().isIn(namesLower)))
        .get();

    final result = <String, TagEntry>{};
    final existingByNameLower = <String, TagEntry>{};
    for (final row in existingRows) {
      final key = row.name.toLowerCase();
      result[key] = row;
      existingByNameLower[key] = row;
    }

    // Determine which names need inserting
    final specsByNameLower = <String, ({String name, String color, bool isSteamTag})>{};
    for (final spec in tagSpecs) {
      final key = spec.name.trim().toLowerCase();
      if (key.isEmpty) continue;
      specsByNameLower[key] = spec;
    }

    final missingSpecs = <({String name, String color, bool isSteamTag})>[];
    for (final entry in specsByNameLower.entries) {
      if (!result.containsKey(entry.key)) {
        missingSpecs.add(entry.value);
      }
    }

    if (missingSpecs.isNotEmpty) {
      // Batch insert missing tags
      await batch((b) {
        b.insertAll(
          tags,
          missingSpecs.map((s) {
            return TagsCompanion.insert(
              name: s.name.trim(),
              color: Value(s.color.trim()),
              isSteamTag: Value(s.isSteamTag),
            );
          }).toList(),
        );
      });

      // Re-query the newly inserted tags to get their IDs
      final missingNames = missingSpecs
          .map((s) => s.name.trim().toLowerCase())
          .toList();
      final insertedRows = await (select(tags)
            ..where((t) => t.name.lower().isIn(missingNames)))
          .get();
      for (final row in insertedRows) {
        final key = row.name.toLowerCase();
        result[key] = row;
      }
    }

    return result;
  }

  /// Set tags for multiple games in a single batch.
  /// Replaces all tag associations for each game in [gameTagMap].
  Future<void> batchSetTagsForGames(Map<int, List<int>> gameTagMap) async {
    if (gameTagMap.isEmpty) return;

    final gameIds = gameTagMap.keys.toList(growable: false);

    await transaction(() async {
      // Single DELETE for all affected games
      await (delete(gameTags)..where((gt) => gt.gameId.isIn(gameIds))).go();

      // Batch INSERT all new relationships
      final companions = <GameTagsCompanion>[];
      for (final entry in gameTagMap.entries) {
        for (final tagId in entry.value) {
          companions.add(GameTagsCompanion.insert(
            gameId: entry.key,
            tagId: tagId,
          ));
        }
      }
      if (companions.isNotEmpty) {
        await batch((b) {
          b.insertAll(gameTags, companions, mode: InsertMode.insertOrIgnore);
        });
      }
    });
  }

  /// Delete all game_tags rows for the given game IDs in one query.
  Future<int> batchDeleteGameTags(List<int> gameIds) async {
    if (gameIds.isEmpty) return 0;
    return (delete(gameTags)..where((gt) => gt.gameId.isIn(gameIds))).go();
  }

  /// Update multiple games in a single batch.
  Future<void> batchUpdateGames(List<GameEntry> gamesList) async {
    if (gamesList.isEmpty) return;
    await batch((b) {
      for (final game in gamesList) {
        b.replace(games, game);
      }
    });
  }

  // ===========================================================================
  // BACKUP OPERATIONS
  // ===========================================================================

  /// Get all backups
  Future<List<BackupEntry>> getAllBackups() {
    return (select(
      backups,
    )..orderBy([(b) => OrderingTerm.desc(b.createdAt)])).get();
  }

  /// Insert a backup record
  Future<int> insertBackup(BackupsCompanion backup) {
    return into(backups).insert(backup);
  }

  /// Delete old backups keeping only the most recent N
  Future<void> pruneBackups(int keepCount) async {
    final allBackups = await getAllBackups();
    if (allBackups.length <= keepCount) return;

    final toDelete = allBackups.skip(keepCount).map((b) => b.id).toList();
    await (delete(backups)..where((b) => b.id.isIn(toDelete))).go();
  }

  // ===========================================================================
  // UTILITY METHODS
  // ===========================================================================

  /// Get database file path
  static Future<String> getDatabasePath() async {
    final dir = await getApplicationDocumentsDirectory();
    final uniKMDir = Directory(p.join(dir.path, 'UniKM'));
    if (!await uniKMDir.exists()) {
      await uniKMDir.create(recursive: true);
    }
    return p.join(uniKMDir.path, kDatabaseName);
  }

  /// Get database file
  static Future<File> getDatabaseFile() async {
    final path = await getDatabasePath();
    return File(path);
  }

  /// Check if a key already exists in the database
  Future<bool> keyExists(String key) async {
    final query = selectOnly(games)..where(games.gameKey.equals(key));
    query.addColumns([games.id]);
    final result = await query.getSingleOrNull();
    return result != null;
  }

  /// Get duplicate keys from a list
  Future<List<String>> findDuplicateKeys(List<String> keys) async {
    final query = select(games)..where((g) => g.gameKey.isIn(keys));
    final results = await query.get();
    return results.map((g) => g.gameKey).toList();
  }

  /// Clear all user data (games/tags/relationships/backups) but keep schema.
  Future<void> clearAllData() async {
    await transaction(() async {
      await delete(gameTags).go();
      await delete(games).go();
      await delete(tags).go();
      await delete(backups).go();
      await customStatement('DELETE FROM $_syncGameTombstonesTable');
      await customStatement('DELETE FROM $_syncPeerCheckpointsTable');
      await customStatement('DELETE FROM $_syncMetadataTable');
      await _initializeSyncMetadata();
    });
  }
}

/// Open the database connection
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final file = await AppDatabase.getDatabaseFile();
    return NativeDatabase.createInBackground(file);
  });
}
