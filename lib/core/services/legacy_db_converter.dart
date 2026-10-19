library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite3;

class LegacyDbConversionResult {
  const LegacyDbConversionResult({
    required this.converted,
    this.reason,
    this.actions = const <String>[],
  });

  final bool converted;
  final String? reason;
  final List<String> actions;
}

// One source for required columns, SQL defaults, and NULL repair. Keep the
// insertion order so conversion reports remain stable for existing databases.
const _layoutColumns = <String, Map<String, (String, String?)>>{
  'games': {
    'platform': ('TEXT', "'Steam'"),
    'notes': ('TEXT', "''"),
    'is_used': ('INTEGER', '0'),
    'cover_image': ('TEXT', "''"),
    'has_deadline': ('INTEGER', '0'),
    'deadline_date': ('INTEGER', null),
    'is_dlc': ('INTEGER', '0'),
    'steam_app_id': ('TEXT', "''"),
    'review_score': ('INTEGER', '0'),
    'review_count': ('INTEGER', '0'),
    'date_added': ('INTEGER', '0'),
    'updated_at': ('INTEGER', '0'),
  },
  'tags': {
    'color': ('TEXT', "'#0078d4'"),
    'is_steam_tag': ('INTEGER', '0'),
  },
};

final _nullDefaults = {
  for (final table in _layoutColumns.entries)
    table.key: {
      if (table.key == 'tags') 'name': "''",
      for (final column in table.value.entries)
        if (column.value.$2 case final String value) column.key: value,
    },
};

Future<LegacyDbConversionResult> convertLegacyDbToCurrentLayoutIfNeeded(
  String dbPath,
) async {
  final file = File(dbPath);
  if (!file.existsSync()) {
    return const LegacyDbConversionResult(
      converted: false,
      reason: 'Database file does not exist',
    );
  }

  final db = sqlite3.sqlite3.open(dbPath);
  try {
    if (!_tableExists(db, 'games')) {
      return const LegacyDbConversionResult(
        converted: false,
        reason: 'No games table found',
      );
    }

    final gameColumns = _getTableColumns(db, 'games');
    final tagColumns = _tableExists(db, 'tags')
        ? _getTableColumns(db, 'tags')
        : <String>{};

    final missingCoreLayout =
      !_tableExists(db, 'tags') ||
      !_tableExists(db, 'game_tags') ||
      !_tableExists(db, 'backups') ||
      !gameColumns.containsAll(_layoutColumns['games']!.keys) ||
      !tagColumns.containsAll(_layoutColumns['tags']!.keys);

    final hasPendingLegacyData =
      _hasPendingPlatformMigration(db, gameColumns) ||
      _hasPendingImageMigration(db, gameColumns) ||
      _hasPendingDeadlineEnabledMigration(db, gameColumns) ||
      _hasPendingDeadlineDateMigration(db, gameColumns) ||
      _hasPendingDlcMigration(db, gameColumns) ||
      _hasPendingReviewScoreMigration(db, gameColumns) ||
      _hasPendingReviewCountMigration(db, gameColumns) ||
      _hasPendingBuiltinTagMigration(db, tagColumns);

    final needsNullSanitization = _nullDefaults.entries.any(
      (table) => table.value.keys.any(
        (column) => _hasNullValues(db, table.key, column),
      ),
    );

    final needsTimestampNormalization =
        _hasTextTimestampValues(db, 'games', 'date_added') ||
        _hasTextTimestampValues(db, 'games', 'updated_at') ||
        _hasTextTimestampValues(db, 'games', 'deadline_date');

    final needsConversion =
      missingCoreLayout ||
      hasPendingLegacyData ||
      needsNullSanitization ||
      needsTimestampNormalization;

    if (!needsConversion) {
      return const LegacyDbConversionResult(
        converted: false,
        reason: 'Schema already current',
      );
    }

    final actions = <String>[];

    db.execute('PRAGMA foreign_keys = OFF');
    db.execute('BEGIN IMMEDIATE');
    try {
      if (_ensureTableBackups(db)) {
        actions.add('Created missing backups table');
      }
      if (_ensureTableTags(db)) {
        actions.add('Created missing tags table');
      }
      if (_ensureTableGameTags(db)) {
        actions.add('Created missing game_tags table');
      }

      for (final table in _layoutColumns.entries) {
        for (final column in table.value.entries) {
          final (type, defaultSql) = column.value;
          final definition = defaultSql == null
              ? type
              : '$type NOT NULL DEFAULT $defaultSql';
          if (_ensureColumn(db, table.key, column.key, definition)) {
            actions.add('Added ${table.key}.${column.key}');
          }
        }
      }

      for (final table in _nullDefaults.entries) {
        for (final column in table.value.entries) {
          if (_setDefaultForNulls(db, table.key, column.key, column.value)) {
            actions.add('Filled NULL ${table.key}.${column.key} with default');
          }
        }
      }

      final refreshedGameColumns = _getTableColumns(db, 'games');
      final refreshedTagColumns = _getTableColumns(db, 'tags');

      if (_hasPendingPlatformMigration(db, refreshedGameColumns)) {
        db.execute(
          "UPDATE games SET platform = platform_type "
          "WHERE platform_type IS NOT NULL AND platform_type != '' "
          "AND (platform IS NULL OR platform = '')",
        );
        actions.add('Migrated platform_type → platform');
      }

      if (_hasPendingImageMigration(db, refreshedGameColumns)) {
        db.execute(
          "UPDATE games SET cover_image = image_path "
          "WHERE image_path IS NOT NULL AND image_path != '' "
          "AND (cover_image IS NULL OR cover_image = '')",
        );
        actions.add('Migrated image_path → cover_image');
      }

      if (_hasPendingDeadlineEnabledMigration(db, refreshedGameColumns)) {
        db.execute(
          'UPDATE games SET has_deadline = deadline_enabled '
          'WHERE deadline_enabled IS NOT NULL',
        );
        actions.add('Migrated deadline_enabled → has_deadline');
      }

      if (_hasPendingDeadlineDateMigration(db, refreshedGameColumns)) {
        db.execute(
          'UPDATE games SET deadline_date = deadline_at '
          'WHERE deadline_at IS NOT NULL '
          "AND (deadline_at != '' OR typeof(deadline_at) = 'integer') "
          'AND deadline_date IS NULL',
        );
        actions.add('Migrated deadline_at → deadline_date');
      }

      if (_normalizeTextDateColumnToEpoch(
        db,
        'games',
        'date_added',
        fallbackSql: '0',
      )) {
        actions.add('Normalized games.date_added text timestamps');
      }

      if (_normalizeTextDateColumnToEpoch(
        db,
        'games',
        'deadline_date',
        fallbackSql: 'NULL',
      )) {
        actions.add('Normalized games.deadline_date text timestamps');
      }

      if (_hasPendingDlcMigration(db, refreshedGameColumns)) {
        db.execute(
          'UPDATE games SET is_dlc = dlc_enabled '
          'WHERE dlc_enabled IS NOT NULL',
        );
        actions.add('Migrated dlc_enabled → is_dlc');
      }

      if (_hasPendingReviewScoreMigration(db, refreshedGameColumns)) {
        db.execute(
          'UPDATE games SET review_score = steam_review_score '
          'WHERE steam_review_score IS NOT NULL '
          'AND (review_score IS NULL OR review_score = 0)',
        );
        actions.add('Migrated steam_review_score → review_score');
      }

      if (_hasPendingReviewCountMigration(db, refreshedGameColumns)) {
        db.execute(
          'UPDATE games SET review_count = steam_review_count '
          'WHERE steam_review_count IS NOT NULL '
          'AND (review_count IS NULL OR review_count = 0)',
        );
        actions.add('Migrated steam_review_count → review_count');
      }

      if (_hasMissingOrZeroValues(db, 'games', 'updated_at')) {
        db.execute(
          'UPDATE games SET updated_at = date_added '
          'WHERE updated_at IS NULL OR updated_at = 0',
        );
        actions.add('Backfilled games.updated_at from date_added');
      }

      if (_normalizeTextDateColumnToEpoch(
        db,
        'games',
        'updated_at',
        fallbackSql: 'COALESCE(NULLIF(CAST(date_added AS INTEGER), 0), 0)',
      )) {
        actions.add('Normalized games.updated_at text timestamps');
      }

      if (_hasPendingBuiltinTagMigration(db, refreshedTagColumns)) {
        db.execute(
          'UPDATE tags SET is_steam_tag = is_builtin '
          'WHERE is_builtin IS NOT NULL',
        );
        actions.add('Migrated tags.is_builtin → is_steam_tag');
      }

      db.execute('COMMIT');
      db.execute('PRAGMA foreign_keys = ON');

      if (actions.isEmpty) {
        return const LegacyDbConversionResult(
          converted: false,
          reason: 'Schema already current',
        );
      }

      return LegacyDbConversionResult(
        converted: true,
        reason: 'Legacy schema converted to current layout',
        actions: actions,
      );
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  } finally {
    db.close();
  }
}

bool _tableExists(sqlite3.Database db, String table) {
  final result = db.select(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    [table],
  );
  return result.isNotEmpty;
}

bool _hasTextTimestampValues(
  sqlite3.Database db,
  String table,
  String column,
) {
  final columns = _getTableColumns(db, table);
  if (!columns.contains(column)) return false;
  final result = db.select(
    "SELECT 1 FROM $table WHERE typeof($column) = 'text' "
    "AND trim(COALESCE($column, '')) != '' LIMIT 1",
  );
  return result.isNotEmpty;
}

bool _hasNullValues(
  sqlite3.Database db,
  String table,
  String column,
) {
  final columns = _getTableColumns(db, table);
  if (!columns.contains(column)) return false;
  final result = db.select(
    'SELECT 1 FROM $table WHERE $column IS NULL LIMIT 1',
  );
  return result.isNotEmpty;
}

bool _setDefaultForNulls(
  sqlite3.Database db,
  String table,
  String column,
  String defaultSql,
) {
  if (!_hasNullValues(db, table, column)) return false;
  db.execute(
    'UPDATE $table SET $column = $defaultSql WHERE $column IS NULL',
  );
  return true;
}

bool _hasMissingOrZeroValues(
  sqlite3.Database db,
  String table,
  String column,
) {
  final columns = _getTableColumns(db, table);
  if (!columns.contains(column)) return false;
  final result = db.select(
    'SELECT 1 FROM $table WHERE $column IS NULL OR $column = 0 LIMIT 1',
  );
  return result.isNotEmpty;
}

bool _normalizeTextDateColumnToEpoch(
  sqlite3.Database db,
  String table,
  String column,
  {
  required String fallbackSql,
}
) {
  final beforeCount = _countTextTimestampValues(db, table, column);
  if (beforeCount == 0) return false;

  db.execute(
    "UPDATE $table "
    "SET $column = CAST(trim($column) AS INTEGER) "
    "WHERE typeof($column) = 'text' "
    "AND trim(COALESCE($column, '')) != '' "
    "AND trim($column) NOT GLOB '*[^0-9]*'",
  );

  db.execute(
    "UPDATE $table "
    "SET $column = CAST(strftime('%s', REPLACE($column, 'T', ' ')) AS INTEGER) "
    "WHERE typeof($column) = 'text' "
    "AND trim(COALESCE($column, '')) != '' "
    "AND strftime('%s', REPLACE($column, 'T', ' ')) IS NOT NULL",
  );

  db.execute(
    "UPDATE $table "
    "SET $column = $fallbackSql "
    "WHERE typeof($column) = 'text' "
    "AND trim(COALESCE($column, '')) != ''",
  );

  final afterCount = _countTextTimestampValues(db, table, column);
  return afterCount < beforeCount;
}

int _countTextTimestampValues(
  sqlite3.Database db,
  String table,
  String column,
) {
  final columns = _getTableColumns(db, table);
  if (!columns.contains(column)) return 0;
  final result = db.select(
    "SELECT COUNT(*) AS count FROM $table WHERE typeof($column) = 'text' "
    "AND trim(COALESCE($column, '')) != ''",
  );
  return result.first['count'] as int? ?? 0;
}

bool _hasPendingPlatformMigration(
  sqlite3.Database db,
  Set<String> gameColumns,
) {
  if (!gameColumns.contains('platform_type') || !gameColumns.contains('platform')) {
    return false;
  }
  final result = db.select(
    "SELECT 1 FROM games WHERE platform_type IS NOT NULL AND platform_type != '' "
    "AND (platform IS NULL OR platform = '') LIMIT 1",
  );
  return result.isNotEmpty;
}

bool _hasPendingImageMigration(
  sqlite3.Database db,
  Set<String> gameColumns,
) {
  if (!gameColumns.contains('image_path') || !gameColumns.contains('cover_image')) {
    return false;
  }
  final result = db.select(
    "SELECT 1 FROM games WHERE image_path IS NOT NULL AND image_path != '' "
    "AND (cover_image IS NULL OR cover_image = '') LIMIT 1",
  );
  return result.isNotEmpty;
}

bool _hasPendingDeadlineEnabledMigration(
  sqlite3.Database db,
  Set<String> gameColumns,
) {
  if (!gameColumns.contains('deadline_enabled') || !gameColumns.contains('has_deadline')) {
    return false;
  }
  final result = db.select(
    'SELECT 1 FROM games WHERE deadline_enabled IS NOT NULL '
    'AND (has_deadline IS NULL OR has_deadline != deadline_enabled) LIMIT 1',
  );
  return result.isNotEmpty;
}

bool _hasPendingDeadlineDateMigration(
  sqlite3.Database db,
  Set<String> gameColumns,
) {
  if (!gameColumns.contains('deadline_at') || !gameColumns.contains('deadline_date')) {
    return false;
  }
  final result = db.select(
    'SELECT 1 FROM games WHERE deadline_at IS NOT NULL '
    "AND (deadline_at != '' OR typeof(deadline_at) = 'integer') "
    'AND (deadline_date IS NULL OR deadline_date = 0) LIMIT 1',
  );
  return result.isNotEmpty;
}

bool _hasPendingDlcMigration(
  sqlite3.Database db,
  Set<String> gameColumns,
) {
  if (!gameColumns.contains('dlc_enabled') || !gameColumns.contains('is_dlc')) {
    return false;
  }
  final result = db.select(
    'SELECT 1 FROM games WHERE dlc_enabled IS NOT NULL '
    'AND (is_dlc IS NULL OR is_dlc != dlc_enabled) LIMIT 1',
  );
  return result.isNotEmpty;
}

bool _hasPendingReviewScoreMigration(
  sqlite3.Database db,
  Set<String> gameColumns,
) {
  if (!gameColumns.contains('steam_review_score') || !gameColumns.contains('review_score')) {
    return false;
  }
  final result = db.select(
    'SELECT 1 FROM games WHERE steam_review_score IS NOT NULL '
    'AND steam_review_score != 0 '
    'AND (review_score IS NULL OR review_score = 0) LIMIT 1',
  );
  return result.isNotEmpty;
}

bool _hasPendingReviewCountMigration(
  sqlite3.Database db,
  Set<String> gameColumns,
) {
  if (!gameColumns.contains('steam_review_count') || !gameColumns.contains('review_count')) {
    return false;
  }
  final result = db.select(
    'SELECT 1 FROM games WHERE steam_review_count IS NOT NULL '
    'AND steam_review_count != 0 '
    'AND (review_count IS NULL OR review_count = 0) LIMIT 1',
  );
  return result.isNotEmpty;
}

bool _hasPendingBuiltinTagMigration(
  sqlite3.Database db,
  Set<String> tagColumns,
) {
  if (!tagColumns.contains('is_builtin') || !tagColumns.contains('is_steam_tag')) {
    return false;
  }
  final result = db.select(
    'SELECT 1 FROM tags WHERE is_builtin IS NOT NULL '
    'AND (is_steam_tag IS NULL OR is_steam_tag != is_builtin) LIMIT 1',
  );
  return result.isNotEmpty;
}

Set<String> _getTableColumns(sqlite3.Database db, String table) {
  if (!_tableExists(db, table)) return <String>{};
  final rows = db.select('PRAGMA table_info($table)');
  return rows.map((r) => r['name'] as String).toSet();
}

bool _ensureColumn(
  sqlite3.Database db,
  String table,
  String column,
  String definition,
) {
  final columns = _getTableColumns(db, table);
  if (columns.contains(column)) return false;
  db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  return true;
}

bool _ensureTableTags(sqlite3.Database db) {
  final existed = _tableExists(db, 'tags');
  db.execute(
    'CREATE TABLE IF NOT EXISTS tags ('
    'id INTEGER PRIMARY KEY AUTOINCREMENT, '
    'name TEXT NOT NULL UNIQUE, '
    "color TEXT NOT NULL DEFAULT '#0078d4', "
    'is_steam_tag INTEGER NOT NULL DEFAULT 0'
    ')',
  );
  return !existed;
}

bool _ensureTableGameTags(sqlite3.Database db) {
  final existed = _tableExists(db, 'game_tags');
  db.execute(
    'CREATE TABLE IF NOT EXISTS game_tags ('
    'game_id INTEGER NOT NULL, '
    'tag_id INTEGER NOT NULL, '
    'PRIMARY KEY(game_id, tag_id), '
    'FOREIGN KEY(game_id) REFERENCES games(id) ON DELETE CASCADE, '
    'FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE'
    ')',
  );
  return !existed;
}

bool _ensureTableBackups(sqlite3.Database db) {
  final existed = _tableExists(db, 'backups');
  db.execute(
    'CREATE TABLE IF NOT EXISTS backups ('
    'id INTEGER PRIMARY KEY AUTOINCREMENT, '
    'filename TEXT NOT NULL, '
    'created_at INTEGER NOT NULL DEFAULT 0, '
    "label TEXT NOT NULL DEFAULT 'auto', "
    'size_bytes INTEGER NOT NULL DEFAULT 0'
    ')',
  );
  return !existed;
}
