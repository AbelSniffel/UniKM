/// Types for switching/creating the active database at runtime.
///
/// This is used by the bootstrapper in `main.dart` to rebuild the app's
/// ProviderScope with a new `AppDatabase` instance.
library;

sealed class DatabaseSwitchRequest {
  const DatabaseSwitchRequest();
}

class OpenDatabaseRequest extends DatabaseSwitchRequest {
  const OpenDatabaseRequest(this.path, {this.password});

  /// Path selected by the user.
  ///
  /// May be either a plain sqlite file (e.g. `.db`) or an encrypted file
  /// (e.g. `.enc`).
  final String path;

  /// Optional password to use when opening an encrypted database. When
  /// provided the bootstrap/switch logic will attempt to use this password
  /// and will NOT prompt the user.
  final String? password;
}

class CreateDatabaseRequest extends DatabaseSwitchRequest {
  const CreateDatabaseRequest({
    required this.path,
    required this.encrypted,
  });

  /// Target path selected by the user.
  ///
  /// If `encrypted == true`, this may end with `.enc` or any other filename;
  /// the encrypted file will be written as `$basePath.enc`.
  final String path;

  /// Whether the newly created database should be encrypted.
  final bool encrypted;
}

typedef DatabaseSwitchCallback = Future<void> Function(DatabaseSwitchRequest request);
