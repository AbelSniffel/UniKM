/// Database schema definition using Drift (SQLite)
/// Matches the original UniKM Python database schema
library;

import 'package:drift/drift.dart';

// =============================================================================
// GAMES TABLE
// =============================================================================
/// Games table - stores all game entries with their keys and metadata
@DataClassName('GameEntry')
class Games extends Table {
  /// Primary key, auto-increment
  IntColumn get id => integer().autoIncrement()();
  
  /// Game title (required)
  TextColumn get title => text().withLength(min: 1, max: 500)();
  
  /// Activation key (required)
  TextColumn get gameKey => text().named('game_key').withLength(min: 1, max: 500)();
  
  /// Platform (Steam, Epic, GOG, etc.)
  TextColumn get platform => text().withDefault(const Constant('Steam'))();
  
  /// Date the game was added to the database
  DateTimeColumn get dateAdded => dateTime().named('date_added').withDefault(currentDateAndTime)();

  /// Date the game was last updated in the database
  DateTimeColumn get updatedAt => dateTime().named('updated_at').withDefault(currentDateAndTime)();
  
  /// User notes
  TextColumn get notes => text().withDefault(const Constant(''))();
  
  /// Whether the key has been redeemed/used
  BoolColumn get isUsed => boolean().named('is_used').withDefault(const Constant(false))();
  
  /// Path or URL to cover image
  TextColumn get coverImage => text().named('cover_image').withDefault(const Constant(''))();
  
  /// Whether the game has a time-limited redemption deadline
  BoolColumn get hasDeadline => boolean().named('has_deadline').withDefault(const Constant(false))();
  
  /// The deadline datetime (if hasDeadline is true)
  DateTimeColumn get deadlineDate => dateTime().named('deadline_date').nullable()();
  
  /// Whether this is DLC content
  BoolColumn get isDlc => boolean().named('is_dlc').withDefault(const Constant(false))();
  
  /// Steam AppID for API integration
  TextColumn get steamAppId => text().named('steam_app_id').withDefault(const Constant(''))();
  
  /// Review score from Steam (0-100)
  IntColumn get reviewScore => integer().named('review_score').withDefault(const Constant(0))();
  
  /// Number of reviews from Steam
  IntColumn get reviewCount => integer().named('review_count').withDefault(const Constant(0))();
}

// =============================================================================
// TAGS TABLE
// =============================================================================
/// Tags table - stores all available tags for categorizing games
@DataClassName('TagEntry')
class Tags extends Table {
  /// Primary key, auto-increment
  IntColumn get id => integer().autoIncrement()();
  
  /// Tag name (unique)
  TextColumn get name => text().withLength(min: 1, max: 100).unique()();
  
  /// Hex color code (e.g., #0078d4)
  TextColumn get color => text().withDefault(const Constant('#0078d4'))();
  
  /// Whether this tag was fetched from Steam
  BoolColumn get isSteamTag => boolean().named('is_steam_tag').withDefault(const Constant(false))();
}

// =============================================================================
// GAME_TAGS TABLE (Many-to-Many Relationship)
// =============================================================================
/// Junction table linking games to their tags
@DataClassName('GameTagEntry')
class GameTags extends Table {
  /// Foreign key to games.id (CASCADE delete)
  IntColumn get gameId => integer()
      .named('game_id')
      .references(Games, #id, onDelete: KeyAction.cascade)();
  
  /// Foreign key to tags.id (CASCADE delete)
  IntColumn get tagId => integer()
      .named('tag_id')
      .references(Tags, #id, onDelete: KeyAction.cascade)();
  
  @override
  Set<Column> get primaryKey => {gameId, tagId};
}

// =============================================================================
// BACKUPS TABLE (Optional - for tracking backup metadata)
// =============================================================================
/// Backups table - stores metadata about database backups
@DataClassName('BackupEntry')
class Backups extends Table {
  /// Primary key, auto-increment
  IntColumn get id => integer().autoIncrement()();
  
  /// Backup filename
  TextColumn get filename => text()();
  
  /// Backup creation timestamp
  DateTimeColumn get createdAt => dateTime().named('created_at').withDefault(currentDateAndTime)();
  
  /// Backup label (manual, auto, pre-migration)
  TextColumn get label => text().withDefault(const Constant('auto'))();
  
  /// File size in bytes
  IntColumn get sizeBytes => integer().named('size_bytes').withDefault(const Constant(0))();
}
