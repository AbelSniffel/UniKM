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

/// A legacy column whose values are copied into its current column: [pending]
/// finds rows still to copy, and [update] selects the rows the copy writes.
typedef _LegacyCopy = ({
  String table,
  String from,
  String to,
  String pending,
  String update,
});

// Applied in this order around the timestamp steps, keeping reports stable.
const _gameCopiesBeforeDates = <_LegacyCopy>[
  (
    table: 'games',
    from: 'platform_type',
    to: 'platform',
    pending:
        "platform_type IS NOT NULL AND platform_type != '' "
        "AND (platform IS NULL OR platform = '')",
    update:
        "platform_type IS NOT NULL AND platform_type != '' "
        "AND (platform IS NULL OR platform = '')",
  ),
  (
    table: 'games',
    from: 'image_path',
    to: 'cover_image',
    pending:
        "image_path IS NOT NULL AND image_path != '' "
        "AND (cover_image IS NULL OR cover_image = '')",
    update:
        "image_path IS NOT NULL AND image_path != '' "
        "AND (cover_image IS NULL OR cover_image = '')",
  ),
  (
    table: 'games',
    from: 'deadline_enabled',
    to: 'has_deadline',
    pending:
        'deadline_enabled IS NOT NULL '
        'AND (has_deadline IS NULL OR has_deadline != deadline_enabled)',
    update: 'deadline_enabled IS NOT NULL',
  ),
  (
    table: 'games',
    from: 'deadline_at',
    to: 'deadline_date',
    pending:
        'deadline_at IS NOT NULL '
        "AND (deadline_at != '' OR typeof(deadline_at) = 'integer') "
        'AND (deadline_date IS NULL OR deadline_date = 0)',
    update:
        'deadline_at IS NOT NULL '
        "AND (deadline_at != '' OR typeof(deadline_at) = 'integer') "
        'AND deadline_date IS NULL',
  ),
];

const _gameCopiesAfterDates = <_LegacyCopy>[
  (
    table: 'games',
    from: 'dlc_enabled',
    to: 'is_dlc',
    pending:
        'dlc_enabled IS NOT NULL '
        'AND (is_dlc IS NULL OR is_dlc != dlc_enabled)',
    update: 'dlc_enabled IS NOT NULL',
  ),
  (
    table: 'games',
    from: 'steam_review_score',
    to: 'review_score',
    pending:
        'steam_review_score IS NOT NULL AND steam_review_score != 0 '
        'AND (review_score IS NULL OR review_score = 0)',
    update:
        'steam_review_score IS NOT NULL '
        'AND (review_score IS NULL OR review_score = 0)',
  ),
  (
    table: 'games',
    from: 'steam_review_count',
    to: 'review_count',
    pending:
        'steam_review_count IS NOT NULL AND steam_review_count != 0 '
        'AND (review_count IS NULL OR review_count = 0)',
    update:
        'steam_review_count IS NOT NULL '
        'AND (review_count IS NULL OR review_count = 0)',
  ),
];

const _tagCopies = <_LegacyCopy>[
  (
    table: 'tags',
    from: 'is_builtin',
    to: 'is_steam_tag',
    pending:
        'is_builtin IS NOT NULL '
        'AND (is_steam_tag IS NULL OR is_steam_tag != is_builtin)',
    update: 'is_builtin IS NOT NULL',
  ),
];

bool _hasPendingCopy(
  sqlite3.Database db,
  _LegacyCopy copy,
  Set<String> columns,
) =>
    columns.contains(copy.from) &&
    columns.contains(copy.to) &&
    db
        .select('SELECT 1 FROM ${copy.table} WHERE ${copy.pending} LIMIT 1')
        .isNotEmpty;

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
      [..._gameCopiesBeforeDates, ..._gameCopiesAfterDates].any(
        (copy) => _hasPendingCopy(db, copy, gameColumns),
      ) ||
      _tagCopies.any((copy) => _hasPendingCopy(db, copy, tagColumns));

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
      for (final (table, columns) in _requiredTables) {
        if (_tableExists(db, table)) continue;
        db.execute('CREATE TABLE IF NOT EXISTS $table ($columns)');
        actions.add('Created missing $table table');
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

      final refreshedColumns = {
        'games': _getTableColumns(db, 'games'),
        'tags': _getTableColumns(db, 'tags'),
      };
      void copyLegacyColumns(List<_LegacyCopy> copies) {
        for (final copy in copies) {
          if (!_hasPendingCopy(db, copy, refreshedColumns[copy.table]!)) {
            continue;
          }
          db.execute(
            'UPDATE ${copy.table} SET ${copy.to} = ${copy.from} '
            'WHERE ${copy.update}',
          );
          final table = copy.table == 'games' ? '' : '${copy.table}.';
          actions.add('Migrated $table${copy.from} → ${copy.to}');
        }
      }

      copyLegacyColumns(_gameCopiesBeforeDates);

      for (final (column, fallbackSql) in const [
        ('date_added', '0'),
        ('deadline_date', 'NULL'),
      ]) {
        if (_normalizeTextDateColumnToEpoch(
          db,
          'games',
          column,
          fallbackSql: fallbackSql,
        )) {
          actions.add('Normalized games.$column text timestamps');
        }
      }

      copyLegacyColumns(_gameCopiesAfterDates);

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

      copyLegacyColumns(_tagCopies);

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

/// Whether [table] has [column] and a row matching [condition].
bool _hasRowWhere(
  sqlite3.Database db,
  String table,
  String column,
  String condition,
) {
  if (!_getTableColumns(db, table).contains(column)) return false;
  return db
      .select('SELECT 1 FROM $table WHERE $condition LIMIT 1')
      .isNotEmpty;
}

bool _hasTextTimestampValues(
  sqlite3.Database db,
  String table,
  String column,
) => _hasRowWhere(
  db,
  table,
  column,
  "typeof($column) = 'text' AND trim(COALESCE($column, '')) != ''",
);

bool _hasNullValues(sqlite3.Database db, String table, String column) =>
    _hasRowWhere(db, table, column, '$column IS NULL');

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
) => _hasRowWhere(db, table, column, '$column IS NULL OR $column = 0');

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

/// Tables created when missing, in creation order, with their column SQL.
const _requiredTables = [
  (
    'backups',
    'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'filename TEXT NOT NULL, '
        'created_at INTEGER NOT NULL DEFAULT 0, '
        "label TEXT NOT NULL DEFAULT 'auto', "
        'size_bytes INTEGER NOT NULL DEFAULT 0',
  ),
  (
    'tags',
    'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'name TEXT NOT NULL UNIQUE, '
        "color TEXT NOT NULL DEFAULT '#0078d4', "
        'is_steam_tag INTEGER NOT NULL DEFAULT 0',
  ),
  (
    'game_tags',
    'game_id INTEGER NOT NULL, '
        'tag_id INTEGER NOT NULL, '
        'PRIMARY KEY(game_id, tag_id), '
        'FOREIGN KEY(game_id) REFERENCES games(id) ON DELETE CASCADE, '
        'FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE',
  ),
];
