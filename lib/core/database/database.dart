/// Drift database definition and connection
library;

import 'dart:io';

import 'package:collection/collection.dart' show IterableExtension;
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
  static const String _syncRecordsTable = 'sync_records';
  static const String _syncTagRecordsTable = 'sync_tag_records';
  static const String _syncClockKey = 'logical_clock';
  static const String _syncOriginKey = 'database_origin';

  AppDatabase() : super(_openConnection());

  /// Constructor for testing with custom executor
  AppDatabase.forTesting(super.e);

  /// Constructor for opening a specific database file
  AppDatabase.fromFile(File file)
    : super(NativeDatabase.createInBackground(file));

  @override
  int get schemaVersion => 9;

  /// Initialize database with defaults (call once at app startup)
  Future<void> initDefaults() async {
    // Ensure the migration has run (creates tables)
    // Drift handles this automatically on first query, but we can force it
    await customStatement('SELECT 1');
  }

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      beforeOpen: (_) async {
        // Repair only dangling relationships left by older connections.
        await customStatement(
          'DELETE FROM game_tags WHERE game_id NOT IN '
          '(SELECT id FROM games) OR tag_id NOT IN (SELECT id FROM tags)',
        );
        await customStatement('PRAGMA foreign_keys = ON');
      },
      onCreate: (Migrator m) async {
        await m.createAll();
        await _createSyncMetadataTables();
        await _initializeSyncMetadata();
        await _createSyncConvergenceTables();
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

        Future<void> addColumnIfMissing(
          String table,
          String column,
          String definition,
        ) async {
          if (!await columnExists(table, column)) {
            await customStatement(
              'ALTER TABLE $table ADD COLUMN $column $definition',
            );
          }
        }

        if (from < 2) {
          for (final column in {
            'cover_image': 'TEXT NOT NULL DEFAULT ""',
            'has_deadline': 'INTEGER NOT NULL DEFAULT 0',
            'deadline_date': 'TEXT',
            'is_dlc': 'INTEGER NOT NULL DEFAULT 0',
            'steam_app_id': 'TEXT NOT NULL DEFAULT ""',
            'review_score': 'INTEGER NOT NULL DEFAULT 0',
            'review_count': 'INTEGER NOT NULL DEFAULT 0',
          }.entries) {
            await addColumnIfMissing('games', column.key, column.value);
          }
          await addColumnIfMissing(
            'tags',
            'is_steam_tag',
            'INTEGER NOT NULL DEFAULT 0',
          );
        }

        if (from < 3) {
          await addColumnIfMissing(
            'games',
            'updated_at',
            'INTEGER NOT NULL DEFAULT 0',
          );
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
          await addColumnIfMissing(
            'games',
            'developer',
            'TEXT NOT NULL DEFAULT ""',
          );
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
          await _createSyncTombstonesTable();
          await customStatement(
            'DROP TABLE IF EXISTS $_legacySyncGameTombstonesTable',
          );
        }

        if (from < 9) await _createSyncConvergenceTables();

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

    await _createSyncTombstonesTable();

    await customStatement(
      'CREATE TABLE IF NOT EXISTS $_syncPeerCheckpointsTable ('
      'peer_id TEXT PRIMARY KEY NOT NULL, '
      'last_revision INTEGER NOT NULL DEFAULT 0, '
      'last_sync_at INTEGER NOT NULL DEFAULT 0, '
      'remote_revision_id TEXT NOT NULL DEFAULT ""'
      ')',
    );
  }

  Future<void> _createSyncTombstonesTable() async {
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

  /// Version 9 adds an identity and a Lamport version independent of the local
  /// integer primary key. SQL triggers journal every write, including batch
  /// imports and changes to tag relationships made outside repository helpers.
  Future<void> _createSyncConvergenceTables() async {
    await customStatement(
      'INSERT OR IGNORE INTO $_syncMetadataTable(key, value) '
      "VALUES('$_syncOriginKey', lower(hex(randomblob(16))))",
    );
    await customStatement(
      'INSERT OR IGNORE INTO $_syncMetadataTable(key, value) '
      "VALUES('$_syncClockKey', '1')",
    );
    await customStatement(
      'CREATE TABLE IF NOT EXISTS $_syncRecordsTable ('
      'sync_id TEXT PRIMARY KEY NOT NULL, '
      'local_game_id INTEGER, '
      'game_key TEXT NOT NULL DEFAULT "", '
      'change_clock INTEGER NOT NULL, '
      'change_origin TEXT NOT NULL, '
      'deleted_at INTEGER NOT NULL DEFAULT 0, '
      'local_revision INTEGER NOT NULL)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_records_active_game '
      'ON $_syncRecordsTable(local_game_id) WHERE deleted_at = 0',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sync_records_revision '
      'ON $_syncRecordsTable(local_revision)',
    );
    await customStatement(
      'CREATE TABLE IF NOT EXISTS $_syncTagRecordsTable ('
      'tag_id INTEGER PRIMARY KEY NOT NULL, change_clock INTEGER NOT NULL, '
      'change_origin TEXT NOT NULL)',
    );
    await customStatement(
      'INSERT OR IGNORE INTO $_syncTagRecordsTable(tag_id, change_clock, change_origin) '
      "SELECT id, 1, 'legacy' FROM tags",
    );
    // Copies synchronised by the old protocol have the same key, id and
    // creation time. Bootstrap them with the same identity; new rows use
    // random identities so independent additions cannot collide.
    await customStatement(
      'INSERT OR IGNORE INTO $_syncRecordsTable '
      '(sync_id, local_game_id, game_key, change_clock, change_origin, '
      'deleted_at, local_revision) '
      "SELECT 'legacy:' || id || ':' || lower(hex(game_key)) || ':' || date_added, "
      "id, game_key, MAX(1, updated_at * 1000), 'legacy', 0, "
      "(SELECT CAST(value AS INTEGER) FROM $_syncMetadataTable WHERE key = '$_syncMetadataLocalRevisionKey') "
      'FROM games',
    );
    await customStatement(
      'INSERT OR IGNORE INTO $_syncRecordsTable '
      '(sync_id, local_game_id, game_key, change_clock, change_origin, '
      'deleted_at, local_revision) '
      "SELECT 'legacy-delete:' || game_id || ':' || lower(hex(game_key)), "
      "game_id, game_key, MAX(1, deleted_at), 'legacy', deleted_at, local_revision "
      'FROM $_syncGameTombstonesTable',
    );
    await customStatement(
      'UPDATE $_syncMetadataTable SET value = MAX(CAST(value AS INTEGER), '
      '(SELECT COALESCE(MAX(change_clock), 1) FROM $_syncRecordsTable)) WHERE key = ?',
      [_syncClockKey],
    );
    final advance =
        "UPDATE $_syncMetadataTable SET value = CAST(value AS INTEGER) + 1 WHERE key IN ('$_syncMetadataLocalRevisionKey', '$_syncClockKey'); "
        "UPDATE $_syncMetadataTable SET value = CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER) WHERE key = '$_syncMetadataDbTimestampKey'; ";
    final revision =
        "(SELECT CAST(value AS INTEGER) FROM $_syncMetadataTable WHERE key = '$_syncMetadataLocalRevisionKey')";
    final clock =
        "(SELECT CAST(value AS INTEGER) FROM $_syncMetadataTable WHERE key = '$_syncClockKey')";
    final origin =
        "(SELECT value FROM $_syncMetadataTable WHERE key = '$_syncOriginKey')";
    String touch(String gameIds) =>
        'UPDATE $_syncRecordsTable SET change_clock = $clock, '
        'change_origin = $origin, local_revision = $revision '
        'WHERE deleted_at = 0 AND local_game_id IN ($gameIds); ';
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS sync_journal_game_insert AFTER INSERT ON games BEGIN '
      '$advance'
      'INSERT INTO $_syncRecordsTable(sync_id, local_game_id, game_key, '
      'change_clock, change_origin, deleted_at, local_revision) '
      'VALUES(lower(hex(randomblob(16))), NEW.id, NEW.game_key, $clock, $origin, 0, $revision); '
      'END',
    );
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS sync_journal_game_update AFTER UPDATE ON games '
      'WHEN OLD.title IS NOT NEW.title OR OLD.game_key IS NOT NEW.game_key '
      'OR OLD.platform IS NOT NEW.platform OR OLD.date_added IS NOT NEW.date_added '
      'OR OLD.updated_at IS NOT NEW.updated_at OR OLD.notes IS NOT NEW.notes '
      'OR OLD.is_used IS NOT NEW.is_used OR OLD.cover_image IS NOT NEW.cover_image '
      'OR OLD.has_deadline IS NOT NEW.has_deadline OR OLD.deadline_date IS NOT NEW.deadline_date '
      'OR OLD.is_dlc IS NOT NEW.is_dlc OR OLD.steam_app_id IS NOT NEW.steam_app_id '
      'OR OLD.developer IS NOT NEW.developer OR OLD.review_score IS NOT NEW.review_score '
      'OR OLD.review_count IS NOT NEW.review_count BEGIN '
      '$advance'
      '${touch('NEW.id')}'
      'UPDATE $_syncRecordsTable SET game_key = NEW.game_key WHERE local_game_id = NEW.id AND deleted_at = 0; '
      'END',
    );
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS sync_journal_game_delete AFTER DELETE ON games BEGIN '
      '$advance'
      'UPDATE $_syncRecordsTable SET change_clock = $clock, change_origin = $origin, '
      'deleted_at = MAX(1, CAST((julianday(\'now\') - 2440587.5) * 86400000 AS INTEGER)), '
      'local_revision = $revision WHERE local_game_id = OLD.id AND deleted_at = 0; '
      'END',
    );
    for (final operation in ['INSERT', 'DELETE']) {
      final record = operation == 'INSERT' ? 'NEW' : 'OLD';
      await customStatement(
        'CREATE TRIGGER IF NOT EXISTS sync_journal_relationship_${operation.toLowerCase()} '
        'AFTER $operation ON game_tags BEGIN '
        '$advance${touch('$record.game_id')}END',
      );
    }
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS sync_journal_tag_insert AFTER INSERT ON tags BEGIN '
      '$advance'
      'INSERT INTO $_syncTagRecordsTable(tag_id, change_clock, change_origin) '
      'VALUES(NEW.id, $clock, $origin); END',
    );
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS sync_journal_tag_update AFTER UPDATE ON tags '
      'WHEN OLD.name IS NOT NEW.name OR OLD.color IS NOT NEW.color OR OLD.is_steam_tag IS NOT NEW.is_steam_tag BEGIN '
      '$advance${touch('SELECT game_id FROM game_tags WHERE tag_id = NEW.id')}'
      'UPDATE $_syncTagRecordsTable SET change_clock = $clock, change_origin = $origin WHERE tag_id = NEW.id; END',
    );
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS sync_journal_tag_delete AFTER DELETE ON tags BEGIN '
      'DELETE FROM $_syncTagRecordsTable WHERE tag_id = OLD.id; END',
    );
  }

  Future<Map<int, Map<String, dynamic>>> getSyncTagVersions() async {
    final rows = await customSelect(
      'SELECT tag_id, change_clock, change_origin FROM $_syncTagRecordsTable',
    ).get();
    return {
      for (final row in rows)
        row.read<int>('tag_id'): {
          'changeClock': row.read<int>('change_clock'),
          'changeOrigin': row.read<String>('change_origin'),
        },
    };
  }

  Future<void> acceptRemoteTagVersion(
    int tagId,
    int clock,
    String origin,
  ) async {
    final revision = await markLocalDataChanged();
    await customStatement(
      'UPDATE $_syncMetadataTable SET value = MAX(CAST(value AS INTEGER), ?) WHERE key = ?',
      [clock, _syncClockKey],
    );
    await customStatement(
      'INSERT INTO $_syncTagRecordsTable(tag_id, change_clock, change_origin) VALUES(?, ?, ?) '
      'ON CONFLICT(tag_id) DO UPDATE SET change_clock = excluded.change_clock, change_origin = excluded.change_origin',
      [tagId, clock, origin],
    );
    await customStatement(
      'UPDATE $_syncRecordsTable SET local_revision = ? WHERE deleted_at = 0 '
      'AND local_game_id IN (SELECT game_id FROM game_tags WHERE tag_id = ?)',
      [revision, tagId],
    );
  }

  /// Receiving a tag update is not a new local edit of every attached game.
  /// Preserve their logical versions while retaining the trigger's journal
  /// cursor, which still forwards the new tag metadata to other peers.
  Future<void> restoreSyncRecordVersions(
    List<Map<String, dynamic>> records,
  ) => batch((batch) {
    for (final record in records) {
      batch.customStatement(
        'UPDATE $_syncRecordsTable SET change_clock = ?, change_origin = ? WHERE sync_id = ?',
        [record['changeClock'], record['changeOrigin'], record['syncId']],
      );
    }
  });

  /// Emits once initially and after committed content changes. Checkpoints and
  /// timestamps alone do not wake listeners; transactions coalesce emissions.
  Stream<int> watchSyncRevision() =>
      customSelect(
            'SELECT value FROM $_syncMetadataTable WHERE key = ?',
            variables: [Variable.withString(_syncMetadataLocalRevisionKey)],
            readsFrom: {games, tags, gameTags},
          )
          .watch()
          .map((rows) => int.parse(rows.single.read<String>('value')))
          .distinct();

  /// Include the database origin: replace-import resets the journal and may
  /// finish at the same (or a larger) revision as the previous library.
  Stream<(String, int)> watchLibraryRevision() =>
      customSelect(
            'SELECT '
            "(SELECT value FROM $_syncMetadataTable WHERE key = '$_syncOriginKey') AS origin, "
            "(SELECT value FROM $_syncMetadataTable WHERE key = '$_syncMetadataLocalRevisionKey') AS revision",
            readsFrom: {games, tags, gameTags},
          )
          .watch()
          .map(
            (rows) => (
              rows.single.read<String>('origin'),
              int.parse(rows.single.read<String>('revision')),
            ),
          )
          .distinct();

  Future<List<Map<String, dynamic>>> getSyncRecords({
    int sinceRevision = 0,
    List<int>? attachedTagIds,
  }) async {
    if (attachedTagIds != null && attachedTagIds.isEmpty) return [];
    final tagFilter = attachedTagIds == null
        ? ''
        : ' AND local_game_id IN (SELECT game_id FROM game_tags WHERE tag_id IN (${List.filled(attachedTagIds.length, '?').join(', ')}))';
    final rows = await customSelect(
      'SELECT sync_id, local_game_id, game_key, change_clock, change_origin, '
      'deleted_at, local_revision FROM $_syncRecordsTable WHERE local_revision > ?$tagFilter',
      variables: [
        Variable.withInt(sinceRevision),
        ...?attachedTagIds?.map(Variable.withInt),
      ],
    ).get();
    return rows
        .map(
          (row) => <String, dynamic>{
            'syncId': row.read<String>('sync_id'),
            'id': row.readNullable<int>('local_game_id'),
            'gameKey': row.read<String>('game_key'),
            'changeClock': row.read<int>('change_clock'),
            'changeOrigin': row.read<String>('change_origin'),
            'deletedAt': row.read<int>('deleted_at'),
            'localRevision': row.read<int>('local_revision'),
          },
        )
        .toList(growable: false);
  }

  Future<String> getSyncDatabaseOrigin() async =>
      await _readSyncMetadataValue(_syncOriginKey) ?? '';

  Future<Set<String>> getSyncRecordIds() async {
    final rows = await customSelect(
      'SELECT sync_id FROM $_syncRecordsTable',
    ).get();
    return rows.map((row) => row.read<String>('sync_id')).toSet();
  }

  /// Retains an imported version unchanged for subsequent relays. The local
  /// journal cursor advances, but the origin/version never become a new edit.
  Future<void> acceptRemoteSyncRecord({
    required String syncId,
    required int? localGameId,
    required String gameKey,
    required int changeClock,
    required String changeOrigin,
    int deletedAt = 0,
  }) async {
    final revision = await markLocalDataChanged();
    await customStatement(
      'UPDATE $_syncMetadataTable SET value = MAX(CAST(value AS INTEGER), ?) WHERE key = ?',
      [changeClock, _syncClockKey],
    );
    if (localGameId != null && deletedAt == 0) {
      await customStatement(
        'DELETE FROM $_syncRecordsTable WHERE local_game_id = ? AND deleted_at = 0 AND sync_id != ?',
        [localGameId, syncId],
      );
      await clearGameTombstone(localGameId);
    }
    await customStatement(
      'INSERT INTO $_syncRecordsTable(sync_id, local_game_id, game_key, '
      'change_clock, change_origin, deleted_at, local_revision) VALUES(?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(sync_id) DO UPDATE SET local_game_id = excluded.local_game_id, '
      'game_key = excluded.game_key, change_clock = excluded.change_clock, '
      'change_origin = excluded.change_origin, deleted_at = excluded.deleted_at, '
      'local_revision = excluded.local_revision',
      [
        syncId,
        localGameId,
        gameKey,
        changeClock,
        changeOrigin,
        deletedAt,
        revision,
      ],
    );
  }

  Future<void> acceptRemoteSyncRecords(
    List<Map<String, dynamic>> records,
  ) async {
    if (records.isEmpty) return;
    final revision = await markLocalDataChanged();
    var maxClock = 0;
    for (final record in records) {
      final clock = (record['changeClock'] as num).toInt();
      if (clock > maxClock) maxClock = clock;
    }
    await customStatement(
      'UPDATE $_syncMetadataTable SET value = MAX(CAST(value AS INTEGER), ?) WHERE key = ?',
      [maxClock, _syncClockKey],
    );
    await batch((batch) {
      for (final record in records) {
        final localId = record['id'];
        final deletedAt = record['deletedAt'] ?? 0;
        if (localId != null && deletedAt == 0) {
          batch.customStatement(
            'DELETE FROM $_syncRecordsTable WHERE local_game_id = ? AND deleted_at = 0 AND sync_id != ?',
            [localId, record['syncId']],
          );
          batch.customStatement(
            'DELETE FROM $_syncGameTombstonesTable WHERE game_id = ?',
            [localId],
          );
        }
        batch.customStatement(
          'INSERT INTO $_syncRecordsTable(sync_id, local_game_id, game_key, change_clock, '
          'change_origin, deleted_at, local_revision) VALUES(?, ?, ?, ?, ?, ?, ?) '
          'ON CONFLICT(sync_id) DO UPDATE SET local_game_id = excluded.local_game_id, '
          'game_key = excluded.game_key, change_clock = excluded.change_clock, '
          'change_origin = excluded.change_origin, deleted_at = excluded.deleted_at, '
          'local_revision = excluded.local_revision',
          [
            record['syncId'],
            localId,
            record['gameKey'],
            record['changeClock'],
            record['changeOrigin'],
            deletedAt,
            revision,
          ],
        );
      }
    });
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

  Future<void> _writeSyncMetadataValue(String key, String value) async {
    await customStatement(
      'INSERT INTO $_syncMetadataTable(key, value) VALUES(?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      <Object>[key, value],
    );
    if (key == _syncMetadataLocalRevisionKey) {
      notifyUpdates({TableUpdate('games', kind: UpdateKind.update)});
    }
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

  /// Clear legacy tombstones for a bounded import batch. Sync journal triggers
  /// already record the individual writes in the surrounding transaction.
  Future<void> clearImportedGameTombstones(List<int> ids) async {
    if (ids.isEmpty) return;
    await customStatement(
      'DELETE FROM $_syncGameTombstonesTable WHERE game_id IN (${List.filled(ids.length, '?').join(',')})',
      ids,
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

    final syncAtMillis = (lastSyncAt ?? DateTime.now()).millisecondsSinceEpoch;

    await customStatement(
      'INSERT INTO $_syncPeerCheckpointsTable('
      'peer_id, last_revision, last_sync_at, remote_revision_id'
      ') VALUES(?, ?, ?, ?) '
      'ON CONFLICT(peer_id) DO UPDATE SET '
      'last_revision = excluded.last_revision, '
      'last_sync_at = excluded.last_sync_at, '
      'remote_revision_id = excluded.remote_revision_id',
      <Object>[trimmedPeerId, lastRevision, syncAtMillis, remoteRevisionId],
    );
  }

  // ===========================================================================
  // GAME OPERATIONS
  // ===========================================================================

  /// Get all games
  Future<List<GameEntry>> getAllGames() => select(games).get();

  Future<List<GameEntry>> getGamesByIds(Iterable<int> gameIds) async {
    final result = <GameEntry>[];
    for (final ids in _idBatches(gameIds)) {
      result.addAll(
        await (select(games)..where((game) => game.id.isIn(ids))).get(),
      );
    }
    return result;
  }

  Future<int> getNextGameIdForSync() async {
    final row = await customSelect(
      "SELECT MAX(COALESCE((SELECT MAX(id) FROM games), 0), COALESCE((SELECT seq FROM sqlite_sequence WHERE name = 'games'), 0)) + 1 AS next_id",
    ).getSingle();
    return row.read<int>('next_id');
  }

  /// Get a single game by ID
  Future<GameEntry?> getGameById(int id) {
    return (select(games)..where((g) => g.id.equals(id))).getSingleOrNull();
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

  /// Supply the schema's declared defaults explicitly: legacy tables may have
  /// NOT NULL columns without the SQL defaults present in new databases.
  /// Caller-supplied values remain intact; updates don't use this helper.
  Insertable<GameEntry> gameInsertWithDefaults(GamesCompanion game) {
    final values = game.toColumns(true);
    for (final column in games.$columns) {
      final defaultValue = column.defaultValue;
      if (defaultValue != null) {
        values.putIfAbsent(column.name, () => defaultValue);
      }
    }
    return RawValuesInsertable(values);
  }

  /// Insert a new game
  Future<int> insertGame(GamesCompanion game) {
    return transaction(() async {
      final id = await into(games).insert(gameInsertWithDefaults(game));
      final revision = await markLocalDataChanged();
      await recordGameUpsert(id, localRevision: revision);
      return id;
    });
  }

  /// Insert multiple games in a batch
  Future<void> insertGames(List<GamesCompanion> gamesList) {
    return batch((b) {
      b.insertAll(games, gamesList.map(gameInsertWithDefaults).toList());
    });
  }

  /// Update a game
  Future<bool> updateGame(GameEntry game) {
    return transaction(() async {
      final changed = await update(games).replace(game);
      if (changed) {
        final revision = await markLocalDataChanged();
        await recordGameUpsert(game.id, localRevision: revision);
      }
      return changed;
    });
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
      deadlineDate: hasDeadline == false
          ? const Value(null)
          : deadlineDate != null
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

  /// Delete games and their tag links atomically, retaining both sync journals.
  Future<int> deleteGame(int id) => deleteGames([id]);

  Future<int> deleteGames(List<int> ids) {
    final uniqueIds = ids.where((id) => id > 0).toSet().toList();
    if (uniqueIds.isEmpty) return Future.value(0);
    return transaction(() async {
      final before = await getGamesCount();
      final revision = await markLocalDataChanged();
      final deletedAt = DateTime.now().millisecondsSinceEpoch;
      // Send bounded statements together to the database worker. INSERT SELECT
      // records the real keys without 10,000 awaited per-game writes or a large
      // list of key rows crossing the isolate boundary.
      await batch((batch) {
        for (var start = 0; start < uniqueIds.length; start += 500) {
          final chunk = uniqueIds.skip(start).take(500).toList();
          final placeholders = List.filled(chunk.length, '?').join(',');
          batch.customStatement(
            'INSERT INTO $_syncGameTombstonesTable(game_id, game_key, deleted_at, local_revision) '
            'SELECT id, trim(game_key), ?, ? FROM games WHERE id IN ($placeholders) '
            'ON CONFLICT(game_id) DO UPDATE SET game_key = excluded.game_key, '
            'deleted_at = excluded.deleted_at, local_revision = excluded.local_revision',
            [deletedAt, revision, ...chunk],
          );
          // Explicit link cleanup also supports databases created by older
          // versions that did not enforce cascading foreign keys.
          batch.deleteWhere(gameTags, (link) => link.gameId.isIn(chunk));
          batch.deleteWhere(games, (game) => game.id.isIn(chunk));
        }
      });
      return before - await getGamesCount();
    });
  }

  /// Mark games as used/unused in bounded updates within one transaction.
  ///
  /// Returns the number of rows updated.
  Future<int> setGamesUsed(List<int> ids, bool isUsed) {
    if (ids.isEmpty) return Future.value(0);
    return transaction(() async {
      final fields = GamesCompanion(
        isUsed: Value(isUsed),
        updatedAt: Value(DateTime.now()),
      );
      var count = 0;
      for (final batch in _idBatches(ids)) {
        count += await (update(
          games,
        )..where((g) => g.id.isIn(batch))).write(fields);
      }
      if (count > 0) await markLocalDataChanged();
      return count;
    });
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

  /// Delete all custom tags in one statement. Foreign keys remove their game
  /// relationships atomically; Steam tags and their relationships are retained.
  Future<int> deleteAllCustomTags() {
    return (delete(tags)..where((t) => t.isSteamTag.equals(false))).go();
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

  /// Keep ID queries below SQLite parameter limits and avoid duplicate rows
  /// when an ID appears in more than one batch.
  static Iterable<List<int>> _idBatches(Iterable<int> ids) =>
      ids.toSet().slices(500);

  /// Get tags for a game using the same relationship query as bulk reads.
  Future<List<TagEntry>> getTagsForGame(int gameId) async =>
      (await getTagsForGames([gameId]))[gameId] ?? [];

  /// Read tags in bounded queries within one consistent database snapshot.
  Future<Map<int, List<TagEntry>>> getTagsForGames(List<int> gameIds) async {
    if (gameIds.isEmpty) return {};
    return transaction(() async {
      final tagsByGame = <int, List<TagEntry>>{};
      for (final ids in _idBatches(gameIds)) {
        final query = select(tags).join([
          innerJoin(gameTags, gameTags.tagId.equalsExp(tags.id)),
        ])..where(gameTags.gameId.isIn(ids));
        for (final row in await query.get()) {
          tagsByGame
              .putIfAbsent(row.readTable(gameTags).gameId, () => [])
              .add(row.readTable(tags));
        }
      }
      return tagsByGame;
    });
  }

  /// Add a tag to a game
  Future<void> addTagToGame(int gameId, int tagId) {
    return into(gameTags).insert(
      GameTagsCompanion.insert(gameId: gameId, tagId: tagId),
      mode: InsertMode.insertOrIgnore,
    );
  }

  /// Set tags for a game (replaces existing tags)
  Future<void> setTagsForGame(
    int gameId,
    List<int> tagIds, {
    bool touchGameUpdatedAt = true,
  }) => batchSetTagsForGames({
    gameId: tagIds,
  }, touchGameUpdatedAt: touchGameUpdatedAt);

  // ===========================================================================
  // BATCH OPERATIONS (for high-performance sync)
  // ===========================================================================

  /// Bulk-resolve tag specs into TagEntry objects. Existing tags are loaded
  /// in a single query; missing tags are inserted in one batch.
  Future<Map<String, TagEntry>> batchGetOrCreateTags(
    List<({String name, String color, bool isSteamTag})> tagSpecs,
  ) async {
    if (tagSpecs.isEmpty) return {};

    // Normalize once; the last specification supplies new-tag attributes.
    final specsByNameLower =
        <String, ({String name, String color, bool isSteamTag})>{};
    for (final spec in tagSpecs) {
      final key = spec.name.trim().toLowerCase();
      if (key.isNotEmpty) specsByNameLower[key] = spec;
    }
    if (specsByNameLower.isEmpty) return {};

    // SQLite's lower() only folds ASCII. Normalize in Dart so tags such as
    // "Çok Oyunculu" match the same keys used by imports and device sync.
    final result = <String, TagEntry>{};
    void collect(List<TagEntry> rows) {
      for (final row in rows) {
        final key = row.name.trim().toLowerCase();
        if (specsByNameLower.containsKey(key)) {
          result.putIfAbsent(key, () => row);
        }
      }
    }

    collect(await getAllTags());

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

      // Use the same Unicode normalization when resolving inserted IDs.
      collect(await getAllTags());
    }

    return result;
  }

  /// Atomically replace relationships; sync/import callers retain timestamps.
  Future<void> batchSetTagsForGames(
    Map<int, List<int>> gameTagMap, {
    bool touchGameUpdatedAt = false,
  }) async {
    if (gameTagMap.isEmpty) return;
    await transaction(() async {
      await batchDeleteGameTags(gameTagMap.keys.toList());
      await batch((b) {
        b.insertAll(gameTags, [
          for (final entry in gameTagMap.entries)
            for (final tagId in entry.value.toSet())
              GameTagsCompanion.insert(gameId: entry.key, tagId: tagId),
        ], mode: InsertMode.insertOrIgnore);
      });
      if (touchGameUpdatedAt) {
        final timestamp = GamesCompanion(updatedAt: Value(DateTime.now()));
        for (final ids in _idBatches(gameTagMap.keys)) {
          await (update(games)..where((g) => g.id.isIn(ids))).write(timestamp);
        }
      }
    });
  }

  /// Delete relationships in bounded queries, rolling back every batch on error.
  Future<int> batchDeleteGameTags(List<int> gameIds) async {
    if (gameIds.isEmpty) return 0;
    return transaction(() async {
      var deleted = 0;
      for (final ids in _idBatches(gameIds)) {
        deleted += await (delete(
          gameTags,
        )..where((gt) => gt.gameId.isIn(ids))).go();
      }
      return deleted;
    });
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
      await customStatement('DELETE FROM $_syncRecordsTable');
      await customStatement('DELETE FROM $_syncTagRecordsTable');
      await _initializeSyncMetadata();
      await _createSyncConvergenceTables();
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
