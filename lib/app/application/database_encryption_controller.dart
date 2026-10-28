import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/biometric_unlock.dart';
import '../../core/services/database_switching.dart';
import '../../core/services/encryption_manager.dart';
import '../../core/settings/settings_model.dart';
import '../../providers/app_providers.dart';
import 'database_session_loader.dart';

/// Coordinates encryption changes with the active SQLite connection and its
/// encrypted save queue. UI callers can outlive the settings header on reopen.
class DatabaseEncryptionController {
  const DatabaseEncryptionController(this.container, this.manager);

  final ProviderContainer container;
  final EncryptionManager manager;

  Future<void> enable(String password) async {
    await _transition(
      operation: () => manager.enable(password, deletePlaintextFile: false),
      reopenPassword: password,
    );
    final prefs = container.read(sharedPreferencesProvider);
    await prefs.setString(
      EncryptionManager.pendingPlaintextDeletionKey,
      manager.dbPath,
    );
    unawaited(
      manager
          .deletePlaintextDatabaseFile(
            throwOnFailure: false,
            maxAttempts: 30,
            initialDelay: const Duration(milliseconds: 200),
          )
          .then((deleted) async {
            if (deleted &&
                prefs.getString(
                      EncryptionManager.pendingPlaintextDeletionKey,
                    ) ==
                    manager.dbPath) {
              await prefs.remove(EncryptionManager.pendingPlaintextDeletionKey);
            }
          }),
    );
  }

  Future<void> disable(String password) async {
    await _transition(
      verifyPassword: password,
      operation: () => manager.disable(password),
    );
    // A plain database has no password left to unlock with.
    await _biometric.forget(manager.dbPath);
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    await _transition(
      verifyPassword: currentPassword,
      reopenPassword: newPassword,
      operation: () => manager.changePassword(currentPassword, newPassword),
    );
    if (!await _biometric.isPaired(manager.dbPath)) return;
    // Keep the pairing with the new password; the phone asks to confirm.
    try {
      await _biometric.pair(manager.dbPath, newPassword);
    } catch (_) {
      await _biometric.forget(manager.dbPath);
    }
  }

  BiometricUnlock get _biometric => container.read(biometricUnlockProvider);

  /// The biometric pairing of this database, or null where this phone
  /// cannot unlock with biometrics (always null on desktop).
  Future<BiometricPairing?> biometricPairing() async {
    if (!await _biometric.isAvailable()) return null;
    return (
      paired: await _biometric.isPaired(manager.dbPath),
      pair: _pairBiometric,
      unpair: () => _biometric.forget(manager.dbPath),
    );
  }

  /// Pairs this database after checking [password], which the phone then
  /// stores behind a biometric check.
  Future<void> _pairBiometric(String password) async {
    final session = container.read(encryptedDbSessionProvider);
    final valid = session != null && session.baseDbPath == manager.dbPath
        ? session.password == password
        : await manager.verifyPassword(password);
    if (!valid) throw InvalidPasswordException();
    await _biometric.pair(manager.dbPath, password);
  }

  Future<void> _transition({
    required Future<void> Function() operation,
    String? verifyPassword,
    String? reopenPassword,
  }) async {
    if (container.read(databaseSwitchingProvider)) {
      throw StateError('A database operation is already in progress');
    }
    final configuredPath = container.read(currentDatabasePathProvider);
    if (configuredPath.isNotEmpty &&
        DatabaseSessionLoader.basePath(configuredPath) != manager.dbPath) {
      throw StateError(
        'The active database changed. Reopen encryption settings.',
      );
    }
    final callback = container.read(databaseSwitchCallbackProvider);
    if (callback == null) throw StateError('Database switching is unavailable');
    final database = container.read(databaseProvider);
    final session = container.read(encryptedDbSessionProvider);
    final wasEncrypted = manager.isEncrypted;
    var closed = false;
    var changed = false;
    container.read(databaseSwitchingProvider.notifier).set(true);
    try {
      // Reject incorrect passwords before closing the user's working database.
      if (verifyPassword != null) await manager.decrypt(verifyPassword);
      if (!identical(container.read(databaseProvider), database) ||
          !identical(container.read(encryptedDbSessionProvider), session)) {
        throw StateError(
          'The active database changed. Reopen encryption settings.',
        );
      }
      if (database != null) {
        if (session == null) {
          await database.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
        }
        // Include pending and final WAL edits before disabling or rekeying.
        await const DatabaseSessionLoader().close(database, session);
      }
      container.read(databaseNotifierProvider.notifier).clearDatabase();
      container.read(encryptedDbSessionProvider.notifier).set(null);
      closed = true;
      await operation();
      changed = true;
      await callback(
        OpenDatabaseRequest(manager.dbPath, password: reopenPassword),
      );
      await container
          .read(settingsProvider.notifier)
          .setSetting(SettingsKeys.encryptionEnabled, manager.isEncrypted);
      container.read(encryptionStateProvider.notifier).set(manager.state);
    } catch (_) {
      // A failed file operation keeps the existing file and password usable.
      if (closed) {
        await callback(
          OpenDatabaseRequest(
            manager.dbPath,
            password: changed
                ? reopenPassword
                : wasEncrypted
                ? verifyPassword
                : null,
          ),
        );
      }
      rethrow;
    } finally {
      container.read(databaseSwitchingProvider.notifier).set(false);
    }
  }
}
