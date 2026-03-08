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

class PreparedImportDatabase {
  const PreparedImportDatabase({
    required this.preparedPath,
    required this.conversion,
    required this.sourceWasCopied,
  });

  final String preparedPath;
  final LegacyDbConversionResult conversion;
  final bool sourceWasCopied;

  Future<void> dispose() async {
    if (!sourceWasCopied) return;

    final file = File(preparedPath);
    final dir = file.parent;
    try {
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }
}

Future<PreparedImportDatabase> prepareDatabaseForImport(String sourceDbPath) async {
  final sourceFile = File(sourceDbPath);
  if (!sourceFile.existsSync()) {
    throw ArgumentError('Source database file does not exist: $sourceDbPath');
  }

  final tempDir = await Directory.systemTemp.createTemp('UniKM_import_');
  final preparedPath = '${tempDir.path}${Platform.pathSeparator}prepared_import.db';
  await sourceFile.copy(preparedPath);

  final conversion = await convertLegacyDbToCurrentLayoutIfNeeded(preparedPath);
  return PreparedImportDatabase(
    preparedPath: preparedPath,
    conversion: conversion,
    sourceWasCopied: true,
  );
}

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
      !gameColumns.contains('platform') ||
      !gameColumns.contains('notes') ||
      !gameColumns.contains('is_used') ||
      !gameColumns.contains('cover_image') ||
      !gameColumns.contains('has_deadline') ||
      !gameColumns.contains('deadline_date') ||
      !gameColumns.contains('is_dlc') ||
      !gameColumns.contains('steam_app_id') ||
      !gameColumns.contains('review_score') ||
      !gameColumns.contains('review_count') ||
      !gameColumns.contains('date_added') ||
      !gameColumns.contains('updated_at') ||
      !tagColumns.contains('color') ||
      !tagColumns.contains('is_steam_tag');

    final hasPendingLegacyData =
      _hasPendingPlatformMigration(db, gameColumns) ||
      _hasPendingImageMigration(db, gameColumns) ||
      _hasPendingDeadlineEnabledMigration(db, gameColumns) ||
      _hasPendingDeadlineDateMigration(db, gameColumns) ||
      _hasPendingDlcMigration(db, gameColumns) ||
      _hasPendingReviewScoreMigration(db, gameColumns) ||
      _hasPendingReviewCountMigration(db, gameColumns) ||
      _hasPendingBuiltinTagMigration(db, tagColumns);

    final needsNullSanitization =
      _hasNullValues(db, 'games', 'platform') ||
      _hasNullValues(db, 'games', 'notes') ||
      _hasNullValues(db, 'games', 'is_used') ||
      _hasNullValues(db, 'games', 'cover_image') ||
      _hasNullValues(db, 'games', 'has_deadline') ||
      _hasNullValues(db, 'games', 'is_dlc') ||
      _hasNullValues(db, 'games', 'steam_app_id') ||
      _hasNullValues(db, 'games', 'review_score') ||
      _hasNullValues(db, 'games', 'review_count') ||
      _hasNullValues(db, 'games', 'date_added') ||
      _hasNullValues(db, 'games', 'updated_at') ||
      _hasNullValues(db, 'tags', 'name') ||
      _hasNullValues(db, 'tags', 'color') ||
      _hasNullValues(db, 'tags', 'is_steam_tag');

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

      if (_ensureColumn(db, 'games', 'platform', "TEXT NOT NULL DEFAULT 'Steam'")) {
        actions.add('Added games.platform');
      }
      if (_ensureColumn(db, 'games', 'notes', "TEXT NOT NULL DEFAULT ''")) {
        actions.add('Added games.notes');
      }
      if (_ensureColumn(db, 'games', 'is_used', 'INTEGER NOT NULL DEFAULT 0')) {
        actions.add('Added games.is_used');
      }
      if (_ensureColumn(db, 'games', 'cover_image', "TEXT NOT NULL DEFAULT ''")) {
        actions.add('Added games.cover_image');
      }
      if (_ensureColumn(db, 'games', 'has_deadline', 'INTEGER NOT NULL DEFAULT 0')) {
        actions.add('Added games.has_deadline');
      }
      if (_ensureColumn(db, 'games', 'deadline_date', 'INTEGER')) {
        actions.add('Added games.deadline_date');
      }
      if (_ensureColumn(db, 'games', 'is_dlc', 'INTEGER NOT NULL DEFAULT 0')) {
        actions.add('Added games.is_dlc');
      }
      if (_ensureColumn(db, 'games', 'steam_app_id', "TEXT NOT NULL DEFAULT ''")) {
        actions.add('Added games.steam_app_id');
      }
      if (_ensureColumn(db, 'games', 'review_score', 'INTEGER NOT NULL DEFAULT 0')) {
        actions.add('Added games.review_score');
      }
      if (_ensureColumn(db, 'games', 'review_count', 'INTEGER NOT NULL DEFAULT 0')) {
        actions.add('Added games.review_count');
      }
      if (_ensureColumn(db, 'games', 'date_added', 'INTEGER NOT NULL DEFAULT 0')) {
        actions.add('Added games.date_added');
      }
      if (_ensureColumn(db, 'games', 'updated_at', 'INTEGER NOT NULL DEFAULT 0')) {
        actions.add('Added games.updated_at');
      }

      if (_ensureColumn(db, 'tags', 'color', "TEXT NOT NULL DEFAULT '#0078d4'")) {
        actions.add('Added tags.color');
      }
      if (_ensureColumn(db, 'tags', 'is_steam_tag', 'INTEGER NOT NULL DEFAULT 0')) {
        actions.add('Added tags.is_steam_tag');
      }

      if (_setDefaultForNulls(db, 'games', 'platform', "'Steam'")) {
        actions.add('Filled NULL games.platform with default');
      }
      if (_setDefaultForNulls(db, 'games', 'notes', "''")) {
        actions.add('Filled NULL games.notes with default');
      }
      if (_setDefaultForNulls(db, 'games', 'is_used', '0')) {
        actions.add('Filled NULL games.is_used with default');
      }
      if (_setDefaultForNulls(db, 'games', 'cover_image', "''")) {
        actions.add('Filled NULL games.cover_image with default');
      }
      if (_setDefaultForNulls(db, 'games', 'has_deadline', '0')) {
        actions.add('Filled NULL games.has_deadline with default');
      }
      if (_setDefaultForNulls(db, 'games', 'is_dlc', '0')) {
        actions.add('Filled NULL games.is_dlc with default');
      }
      if (_setDefaultForNulls(db, 'games', 'steam_app_id', "''")) {
        actions.add('Filled NULL games.steam_app_id with default');
      }
      if (_setDefaultForNulls(db, 'games', 'review_score', '0')) {
        actions.add('Filled NULL games.review_score with default');
      }
      if (_setDefaultForNulls(db, 'games', 'review_count', '0')) {
        actions.add('Filled NULL games.review_count with default');
      }
      if (_setDefaultForNulls(db, 'games', 'date_added', '0')) {
        actions.add('Filled NULL games.date_added with default');
      }
      if (_setDefaultForNulls(db, 'games', 'updated_at', '0')) {
        actions.add('Filled NULL games.updated_at with default');
      }
      if (_setDefaultForNulls(db, 'tags', 'name', "''")) {
        actions.add('Filled NULL tags.name with default');
      }
      if (_setDefaultForNulls(db, 'tags', 'color', "'#0078d4'")) {
        actions.add('Filled NULL tags.color with default');
      }
      if (_setDefaultForNulls(db, 'tags', 'is_steam_tag', '0')) {
        actions.add('Filled NULL tags.is_steam_tag with default');
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
    db.dispose();
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
