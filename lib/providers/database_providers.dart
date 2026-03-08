/// Database-related providers: database state, lifecycle, and encryption.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/database/database.dart';
import '../core/services/encrypted_db_session.dart';
import '../core/services/database_switching.dart';

// =============================================================================
// SHARED PREFERENCES PROVIDER
// =============================================================================

/// Provider for SharedPreferences instance
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be initialized before use');
});

// =============================================================================
// DATABASE PROVIDER
// =============================================================================

/// Holds the currently active database and revision number.
///
/// This is managed by the bootstrap process in main.dart.
/// The revision number is incremented each time the database is switched,
/// allowing dependent providers to invalidate themselves.
class DatabaseState {
  final AppDatabase? database;
  final int revision;

  const DatabaseState({this.database, this.revision = 0});

  DatabaseState copyWith({AppDatabase? database, int? revision}) {
    return DatabaseState(
      database: database ?? this.database,
      revision: revision ?? this.revision,
    );
  }
}

/// State notifier that manages the active database.
class DatabaseNotifier extends Notifier<DatabaseState> {
  @override
  DatabaseState build() => const DatabaseState();

  /// Sets the active database. Call this from the bootstrap process.
  void setDatabase(AppDatabase db) {
    state = DatabaseState(database: db, revision: state.revision + 1);
  }

  /// Clears the current database (call before switching).
  void clearDatabase() {
    state = DatabaseState(database: null, revision: state.revision);
  }

  /// Gets the current revision number.
  int get revision => state.revision;
}

/// Provider for the database state notifier.
final databaseNotifierProvider =
    NotifierProvider<DatabaseNotifier, DatabaseState>(DatabaseNotifier.new);

/// Provider for the main database instance.
///
/// This reads from the DatabaseNotifier managed by the bootstrap process.
/// When the database changes, all watchers will be notified.
///
/// Returns null if accessed before the database is initialized.
/// For methods that require a database, use [requireDatabaseProvider] instead.
final databaseProvider = Provider<AppDatabase?>((ref) {
  final state = ref.watch(databaseNotifierProvider);
  return state.database;
});

/// Provider that throws if database is not available.
/// Use this in methods that absolutely require the database to be present.
final requireDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) {
    throw StateError('Database not available');
  }
  return db;
});

/// In-memory session for encrypted databases (decrypted temp file + password).
///
/// Null when the active database is not encrypted.
final encryptedDbSessionProvider =
    NotifierProvider<EncryptedDbSessionNotifier, EncryptedDbSession?>(
      EncryptedDbSessionNotifier.new,
    );

class EncryptedDbSessionNotifier extends Notifier<EncryptedDbSession?> {
  @override
  EncryptedDbSession? build() => null;

  void setSession(EncryptedDbSession? session) {
    state = session;
  }
}

/// Persist encrypted database changes immediately after a write.
Future<void> persistEncryptedDbIfNeeded(dynamic ref) async {
  final session = ref.read(encryptedDbSessionProvider);
  if (session != null) {
    await session.persistFromTemp();
  }
}

/// Holds the callback for database switching, set by main.dart bootstrap.
final databaseSwitchCallbackProvider =
    NotifierProvider<DatabaseSwitchCallbackNotifier, DatabaseSwitchCallback?>(
      DatabaseSwitchCallbackNotifier.new,
    );

class DatabaseSwitchCallbackNotifier extends Notifier<DatabaseSwitchCallback?> {
  @override
  DatabaseSwitchCallback? build() => null;

  void setCallback(DatabaseSwitchCallback? callback) {
    state = callback;
  }
}

/// True while the app is intentionally switching databases.
final databaseSwitchingProvider =
    NotifierProvider<DatabaseSwitchingNotifier, bool>(
      DatabaseSwitchingNotifier.new,
    );

class DatabaseSwitchingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setSwitching(bool value) {
    state = value;
  }
}
