import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/database/database.dart';
import '../../core/services/biometric_unlock.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/deadline_notification_service.dart';
import '../../core/services/encrypted_db_session.dart';
import '../../core/services/database_switching.dart';
import '../../core/services/display_refresh_rate.dart';
import '../../core/services/encryption_manager.dart';
import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../ui/dialogs/database_unlock_dialog.dart';
import '../../ui/dialogs/encryption_dialogs.dart';
import '../../ui/widgets/app_privacy_guard.dart';
import '../../ui/widgets/app_progress_indicator.dart';
import '../../ui/widgets/notification_system.dart';
import '../application/database_session_loader.dart';
import '../unikm_app.dart';

/// Bootstraps the database.
///
/// If an encrypted database exists (`.enc`), prompts for password and opens
/// Drift on a temporary decrypted copy for this session.
class UniKMBootstrap extends ConsumerStatefulWidget {
  const UniKMBootstrap({super.key});

  @override
  ConsumerState<UniKMBootstrap> createState() => _UniKMBootstrapState();
}

class _UniKMBootstrapState extends ConsumerState<UniKMBootstrap> {
  final _sessionLoader = const DatabaseSessionLoader();
  EncryptedDbSession? _encryptedSession;
  Object? _error;
  bool _booting = true;

  bool _bootstrapStarted = false;
  final Completer<BuildContext> _materialContextCompleter =
      Completer<BuildContext>();

  /// Gets the current database from the notifier (may be null during boot/switch).
  AppDatabase? get _database => ref.read(databaseNotifierProvider).database;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      frameRatePreferenceProvider,
      (_, preference) => applyFrameRatePreference(preference),
      fireImmediately: true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Register the switch callback so the UI can trigger database switches
      ref.read(databaseSwitchCallbackProvider.notifier).set(_switchDatabase);
      // Also update encrypted session provider when it changes
      _updateEncryptedSessionProvider();
      // Start bootstrapping after the first frame so we have a MaterialApp.
      _bootstrap();
    });
  }

  @override
  void dispose() {
    DeadlineNotificationService.instance.stopPeriodicCheck();
    super.dispose();
  }

  void _updateEncryptedSessionProvider() {
    ref.read(encryptedDbSessionProvider.notifier).set(_encryptedSession);
  }

  /// Shows a password dialog once the app's MaterialApp exists; null when
  /// this widget or that context is gone.
  Future<String?> _promptForPassword(
    Future<String?> Function(BuildContext context, AppThemeData theme) show,
  ) async {
    final dialogContext = await _materialContextCompleter.future;
    if (!mounted || !dialogContext.mounted) return null;
    return show(dialogContext, ref.read(themeProvider));
  }

  /// Opens the configured database again from the start.
  Future<void> _restartBootstrap() {
    setState(() {
      _booting = true;
      _error = null;
      _bootstrapStarted = false;
    });
    return _bootstrap();
  }

  Future<StartupDatabaseUnlockResult> _promptForStartupDatabasePassword(
    String currentDatabasePath,
    String baseDbPath,
  ) async {
    final biometricUnlock = await _biometricUnlockFor(baseDbPath);
    final dialogContext = await _materialContextCompleter.future;
    if (!mounted || !dialogContext.mounted) {
      return const StartupDatabaseUnlockResult.cancelled();
    }

    final theme = ref.read(themeProvider);
    return DatabaseUnlockDialog.showForStartup(
      dialogContext,
      theme,
      currentDatabasePath: currentDatabasePath,
      onBiometricUnlock: biometricUnlock,
    );
  }

  /// The password most recently read with a biometric check, so a pairing
  /// whose password no longer opens its file can be removed.
  String? _biometricPassword;

  /// Reads [baseDbPath]'s password with a biometric check when this phone
  /// has paired that database; null when only its password can unlock it.
  Future<Future<String?> Function()?> _biometricUnlockFor(
    String baseDbPath,
  ) async {
    final biometric = ref.read(biometricUnlockProvider);
    if (!await biometric.isPaired(baseDbPath) ||
        !await biometric.isAvailable()) {
      return null;
    }
    return () async =>
        _biometricPassword = await biometric.readPassword(baseDbPath);
  }

  /// Reports a wrong password, removing a stale biometric pairing when the
  /// password came from it.
  Future<void> _rejectPassword(String password, String baseDbPath) async {
    if (password != _biometricPassword) {
      NotificationManager.instance.error('Incorrect password');
      return;
    }
    _biometricPassword = null;
    await ref.read(biometricUnlockProvider).forget(baseDbPath);
    NotificationManager.instance.error(
      '${BiometricUnlock.label} unlock no longer matches this database '
      'and was turned off. Enter the password.',
    );
  }

  Future<void> _bootstrap() async {
    if (_bootstrapStarted) return;
    _bootstrapStarted = true;

    try {
      final prefs = ref.read(sharedPreferencesProvider);

      // Clean up any plaintext DB file that was locked during the previous
      // session's encryption process and could not be deleted at the time.
      final pendingDelete = prefs.getString(
        EncryptionManager.pendingPlaintextDeletionKey,
      );
      if (pendingDelete != null && pendingDelete.isNotEmpty) {
        try {
          final f = File(pendingDelete);
          if (await f.exists()) {
            await f.delete();
            debugPrint(
              '[Encryption] Deleted pending plaintext DB on startup: $pendingDelete',
            );
          }
        } catch (e) {
          debugPrint('[Encryption] Could not delete pending plaintext DB: $e');
        } finally {
          await prefs.remove(EncryptionManager.pendingPlaintextDeletionKey);
        }
      }

      final configuredPath = prefs.getString(SettingsKeys.databasePath) ?? '';
      final baseDbPath = configuredPath.isNotEmpty
          ? configuredPath
          : await AppDatabase.getDatabasePath();

      final encryptionManager = EncryptionManager(baseDbPath);

      if (encryptionManager.isEncrypted) {
        while (true) {
          final unlockResult = await _promptForStartupDatabasePassword(
            encryptionManager.encryptedPath,
            baseDbPath,
          );

          if (unlockResult.cancelled) exit(0);

          final selectedDatabasePath = unlockResult.selectedDatabasePath;
          if (selectedDatabasePath != null && selectedDatabasePath.isNotEmpty) {
            final selectedBasePath = DatabaseSessionLoader.basePath(
              selectedDatabasePath,
            );
            await ref
                .read(settingsProvider.notifier)
                .setSetting(SettingsKeys.databasePath, selectedBasePath);

            if (!mounted) return;
            await _restartBootstrap();
            return;
          }

          final password = unlockResult.password;
          if (password == null) continue;

          try {
            final opened = await _sessionLoader.openEncrypted(
              baseDbPath,
              password,
            );
            _activateDatabase(opened.database, opened.encryptedSession);
            break;
          } on InvalidPasswordException {
            await _rejectPassword(password, baseDbPath);
          }
        }
      } else {
        final opened = await _sessionLoader.openPlain(baseDbPath);
        _activateDatabase(opened.database, null);
      }

      await _addRecentDbPath(baseDbPath);

      if (!mounted) return;
      setState(() {
        _booting = false;
        _error = null;
      });

      // Start daily deadline reminders and run an initial check after a
      // short delay so the app has had time to fully load.
      _startDeadlineReminders();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _booting = false;
        _error = e;
      });
    }
  }

  void _activateDatabase(AppDatabase database, EncryptedDbSession? session) {
    ref.read(databaseNotifierProvider.notifier).setDatabase(database);
    _encryptedSession = session;
    _updateEncryptedSessionProvider();
    ref
        .read(encryptionStateProvider.notifier)
        .set(
          session == null
              ? EncryptionState.unencrypted
              : EncryptionState.encrypted,
        );
  }

  void _startDeadlineReminders() {
    DeadlineNotificationService.instance.startPeriodicCheck(ref);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) DeadlineNotificationService.instance.runCheck(ref);
    });
  }

  Future<void> _addRecentDbPath(String baseDbPath) async {
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final recents = List<String>.from(
      ref.read(securitySettingsProvider).recentDatabasePaths,
    );

    recents.removeWhere((p) => p == baseDbPath);
    recents.insert(0, baseDbPath);
    if (recents.length > 10) recents.removeRange(10, recents.length);

    await settingsNotifier.setSetting(
      SettingsKeys.recentDatabasePaths,
      recents,
    );
  }

  /// Closes the open database, saving an encrypted one back to its file.
  Future<void> _closeDatabase() async {
    final database = _database;
    final session = _encryptedSession;
    // Clear database from notifier so providers know it's gone
    ref.read(databaseNotifierProvider.notifier).clearDatabase();
    ref.read(encryptedDbSessionProvider.notifier).set(null);
    _encryptedSession = null;
    if (database != null) await _sessionLoader.close(database, session);
  }

  /// Closes the encrypted database after the app was idle and asks for its
  /// password again. Waits while a sync, Steam fetch or switch is running.
  Future<void> _lock() async {
    if (_booting ||
        _encryptedSession == null ||
        ref.read(databaseSwitchingProvider) ||
        ref.read(batchFetchProvider).isActive ||
        ref.read(deviceSyncServiceProvider).isReceiverSyncInFlight) {
      return;
    }
    final materialContext = await _materialContextCompleter.future;
    if (!mounted || !materialContext.mounted) return;
    // Dialogs and menus would outlive the database they show.
    Navigator.of(materialContext).popUntil((route) => route.isFirst);
    setState(() => _booting = true);
    try {
      await _closeDatabase();
    } catch (e) {
      // Saving failed: show the error and its Retry rather than reopening
      // the file without the latest changes.
      if (!mounted) return;
      setState(() {
        _booting = false;
        _error = e;
      });
      return;
    }
    await _restartBootstrap();
  }

  Future<void> _switchDatabase(DatabaseSwitchRequest request) async {
    if (_booting) return;

    setState(() {
      _booting = true;
      _error = null;
    });

    try {
      final selectedPath = request is OpenDatabaseRequest
          ? request.path
          : (request as CreateDatabaseRequest).path;

      final baseDbPath = DatabaseSessionLoader.basePath(selectedPath);
      final encryptionManager = EncryptionManager(baseDbPath);

      // Close current database (and persist if encrypted) before switching.
      await _closeDatabase();

      AppDatabase newDb;
      EncryptedDbSession? newSession;

      if (request is CreateDatabaseRequest) {
        // Ensure parent directory exists.
        await File(baseDbPath).parent.create(recursive: true);

        if (request.encrypted) {
          // Create a new plain DB at baseDbPath so EncryptionManager.enable() can
          // generate a fresh salt and write `$baseDbPath.enc`.
          final plainDb = await _sessionLoader.createPlain(baseDbPath);
          await plainDb.close();

          final password = await _promptForPassword(
            EnableEncryptionDialog.showForNewDatabase,
          );
          if (password == null) {
            // User declined; clean up the newly created files and reopen
            // the previous db by re-running bootstrap.
            for (final file in [File(baseDbPath), File('$baseDbPath.enc')]) {
              if (!file.existsSync()) continue;
              try {
                await file.delete();
              } catch (_) {}
            }
            await _restartBootstrap();
            return;
          }

          await encryptionManager.enable(password);
          final opened = await _sessionLoader.openEncrypted(
            baseDbPath,
            password,
          );
          newDb = opened.database;
          newSession = opened.encryptedSession;
        } else {
          newDb = await _sessionLoader.createPlain(baseDbPath);
        }
      } else {
        // Open existing database.
        if (encryptionManager.isEncrypted) {
          // If the request provided a password, use it; otherwise prompt.
          String? providedPassword = (request is OpenDatabaseRequest)
              ? request.password
              : null;

          while (true) {
            final biometricUnlock = providedPassword == null
                ? await _biometricUnlockFor(baseDbPath)
                : null;
            final password =
                providedPassword ??
                await _promptForPassword(
                  (context, theme) => DatabaseUnlockDialog.show(
                    context,
                    theme,
                    onBiometricUnlock: biometricUnlock,
                  ),
                );
            if (password == null) {
              // User cancelled; reopen the previous db by re-running bootstrap.
              await _restartBootstrap();
              return;
            }

            try {
              final opened = await _sessionLoader.openEncrypted(
                baseDbPath,
                password,
              );
              newDb = opened.database;
              newSession = opened.encryptedSession;
              break;
            } on InvalidPasswordException {
              await _rejectPassword(password, baseDbPath);
              // If we attempted a provided password, clear it so the user is prompted
              // on the next loop iteration.
              providedPassword = null;
            }
          }
        } else {
          final opened = await _sessionLoader.openPlain(
            baseDbPath,
            mustExist: true,
          );
          newDb = opened.database;
        }
      }

      // Only persist settings after the new database has been opened.
      final settingsNotifier = ref.read(settingsProvider.notifier);
      await settingsNotifier.setSetting(SettingsKeys.databasePath, baseDbPath);
      await _addRecentDbPath(baseDbPath);

      if (!mounted) return;

      // Set the new database in the notifier - this will trigger all watchers to rebuild
      _activateDatabase(newDb, newSession);
      // Inform the user which file we're now using
      NotificationManager.instance.success(
        'Using database: ${p.basename(baseDbPath)}',
      );

      setState(() {
        _booting = false;
        _error = null;
      });

      // Keep the current search query visible/active across database file
      // switches while still clearing non-search filters.
      final preservedSearchQuery = ref.read(gamesProvider).searchQuery;
      ref.read(gamesProvider.notifier).clearAllFilters();
      if (preservedSearchQuery.isNotEmpty) {
        ref.read(gamesProvider.notifier).setSearchQuery(preservedSearchQuery);
      }
      ref.read(gameLibraryScrollOffsetProvider.notifier).set(0);

      // Reset session so old game IDs don't suppress notifications for the
      // new database, then restart the periodic check.
      DeadlineNotificationService.instance.resetSession();
      _startDeadlineReminders();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _booting = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final materialTheme = ref.watch(themeDataProvider);
    // Watch the database state so we rebuild when it changes
    final dbState = ref.watch(databaseNotifierProvider);
    final (autoLockMinutes, hideInRecents) = ref.watch(
      securitySettingsProvider.select(
        (s) => (s.autoLockMinutes, s.hideInRecents),
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: materialTheme,
      themeAnimationDuration: Duration.zero,
      themeAnimationCurve: Curves.linear,
      builder: (context, child) => AppPrivacyGuard(
        lockAfter: _booting || _encryptedSession == null || autoLockMinutes <= 0
            ? null
            : Duration(minutes: autoLockMinutes),
        onLock: _lock,
        hideInRecents: hideInRecents,
        child: child!,
      ),
      home: Builder(
        builder: (materialContext) {
          final isSwitching = ref.watch(databaseSwitchingProvider);
          if (!_materialContextCompleter.isCompleted) {
            _materialContextCompleter.complete(materialContext);
          }

          if (_booting || isSwitching) {
            return Scaffold(
              backgroundColor: theme.background,
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppCircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Loading Database…',
                      style: TextStyle(color: theme.textSecondary),
                    ),
                  ],
                ),
              ),
            );
          }

          if (_error != null || dbState.database == null) {
            return Scaffold(
              backgroundColor: theme.background,
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error, color: theme.secondary, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'Failed to start UniKM',
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: kElementVSpacing),
                      Text(
                        _error?.toString() ?? 'Database not available',
                        style: TextStyle(color: theme.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _restartBootstrap,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          // No nested ProviderScope needed - providers read from databaseNotifierProvider
          return const UniKMApp();
        },
      ),
    );
  }
}
