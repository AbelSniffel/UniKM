/// UniKM Flutter - Game Key Manager
/// Rewrite of UniKM-Sonnet in Flutter for better performance and UI
library;

import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as p;

import 'core/database/database.dart';
import 'core/services/deadline_notification_service.dart';
import 'core/services/encrypted_db_session.dart';
import 'core/services/database_switching.dart';
import 'core/services/encryption_manager.dart';
import 'core/services/legacy_db_converter.dart';
import 'core/settings/settings_model.dart';
import 'providers/app_providers.dart';
import 'ui/app_scaffold.dart';
import 'ui/dialogs/database_unlock_dialog.dart';
import 'ui/widgets/notification_system.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize window manager for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
  }

  // Initialize SharedPreferences
  final prefs = await SharedPreferences.getInstance();

  // Initialize OS-level notification plugin.
  await DeadlineNotificationService.instance.initialize();

  runApp(
    ProviderScope(
      overrides: [
        // Provide the SharedPreferences instance
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const _UniKMBootstrap(),
    ),
  );
}

/// Bootstraps the database.
///
/// If an encrypted database exists (`.enc`), prompts for password and opens
/// Drift on a temporary decrypted copy for this session.
class _UniKMBootstrap extends ConsumerStatefulWidget {
  const _UniKMBootstrap();

  @override
  ConsumerState<_UniKMBootstrap> createState() => _UniKMBootstrapState();
}

class _UniKMBootstrapState extends ConsumerState<_UniKMBootstrap> {
  EncryptedDbSession? _encryptedSession;
  Object? _error;
  bool _booting = true;

  bool _bootstrapStarted = false;
  final Completer<BuildContext> _materialContextCompleter = Completer<BuildContext>();

  /// Gets the current database from the notifier (may be null during boot/switch).
  AppDatabase? get _database => ref.read(databaseNotifierProvider).database;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Register the switch callback so the UI can trigger database switches
      ref.read(databaseSwitchCallbackProvider.notifier).setCallback(_switchDatabase);
      // Also update encrypted session provider when it changes
      _updateEncryptedSessionProvider();
      // Start bootstrapping after the first frame so we have a MaterialApp.
      _bootstrap();
    });
  }
  
  void _updateEncryptedSessionProvider() {
    ref.read(encryptedDbSessionProvider.notifier).setSession(_encryptedSession);
  }

  Future<String?> _promptForDatabasePassword() async {
    final dialogContext = await _materialContextCompleter.future;
    if (!mounted) return null;
    if (!dialogContext.mounted) return null;
    final theme = ref.read(themeProvider);
    return DatabaseUnlockDialog.show(dialogContext, theme);
  }

  Future<void> _showLegacyConversionReport(
    LegacyDbConversionResult conversion, {
    required String dbPath,
  }) async {
    if (!conversion.converted) return;

    final dialogContext = await _materialContextCompleter.future;
    if (!mounted) return;
    if (!dialogContext.mounted) return;

    final theme = ref.read(themeProvider);
    final actions = conversion.actions;

    await showDialog<void>(
      context: dialogContext,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: theme.background,
          title: Row(
            children: [
              Icon(Icons.upgrade, color: theme.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Legacy Database Converted',
                  style: TextStyle(color: theme.textPrimary),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'The selected database was upgraded to the current schema.',
                  style: TextStyle(color: theme.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  'File: ${p.basename(dbPath)}',
                  style: TextStyle(color: theme.textSecondary, fontSize: 12),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Changes applied:',
                    style: TextStyle(
                      color: theme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: SizedBox(
                      width: double.infinity,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final action in actions)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '• $action',
                                  style: TextStyle(color: theme.textPrimary),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _bootstrap() async {
    if (_bootstrapStarted) return;
    _bootstrapStarted = true;

    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final configuredPath = prefs.getString(SettingsKeys.databasePath) ?? '';
      final baseDbPath = configuredPath.isNotEmpty
          ? configuredPath
          : await AppDatabase.getDatabasePath();

      final encryptionManager = EncryptionManager(baseDbPath);

      if (encryptionManager.isEncrypted) {
        while (true) {
          final password = await _promptForDatabasePassword();
          if (password == null) {
            await windowManager.close();
            return;
          }

          try {
            final tempPath = await encryptionManager.decryptToTemp(password);
            final conversion = await convertLegacyDbToCurrentLayoutIfNeeded(
              tempPath,
            );

            if (conversion.converted) {
              await encryptionManager.reencryptFromTemp(tempPath, password);
            }

            final db = AppDatabase.fromFile(File(tempPath));
            await db.initDefaults();

            await _showLegacyConversionReport(conversion, dbPath: baseDbPath);

            // Set database via notifier instead of local state
            ref.read(databaseNotifierProvider.notifier).setDatabase(db);
            _encryptedSession = EncryptedDbSession(
              baseDbPath: baseDbPath,
              tempDbPath: tempPath,
              password: password,
            );
            _updateEncryptedSessionProvider();

            ref.read(encryptionStateProvider.notifier).setEncryptionState(EncryptionState.encrypted);
            break;
          } on InvalidPasswordException {
            NotificationManager.instance.error('Incorrect password');
          }
        }
      } else {
        final dbFile = File(baseDbPath);
        final conversion = await convertLegacyDbToCurrentLayoutIfNeeded(
          dbFile.path,
        );
        final db = AppDatabase.fromFile(dbFile);
        await db.initDefaults();
        await _showLegacyConversionReport(conversion, dbPath: baseDbPath);
        // Set database via notifier instead of local state
        ref.read(databaseNotifierProvider.notifier).setDatabase(db);
        _encryptedSession = null;
        _updateEncryptedSessionProvider();
        ref.read(encryptionStateProvider.notifier).setEncryptionState(EncryptionState.unencrypted);
      }

      await _addRecentDbPath(baseDbPath);

      if (!mounted) return;
      setState(() {
        _booting = false;
        _error = null;
      });

      // Start daily deadline reminders and run an initial check after a
      // short delay so the app has had time to fully load.
      DeadlineNotificationService.instance.startPeriodicCheck(ref);
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) DeadlineNotificationService.instance.runCheck(ref);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _booting = false;
        _error = e;
      });
    }
  }

  static String _toBaseDbPath(String selectedPath) {
    if (selectedPath.toLowerCase().endsWith('.enc')) {
      return selectedPath.substring(0, selectedPath.length - 4);
    }
    return selectedPath;
  }

  Future<void> _addRecentDbPath(String baseDbPath) async {
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final recents = List<String>.from(
      ref.read(securitySettingsProvider).recentDatabasePaths,
    );

    recents.removeWhere((p) => p == baseDbPath);
    recents.insert(0, baseDbPath);
    if (recents.length > 10) {
      recents.removeRange(10, recents.length);
    }

    await settingsNotifier.setSetting(SettingsKeys.recentDatabasePaths, recents);
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

      final baseDbPath = _toBaseDbPath(selectedPath);
      final encryptionManager = EncryptionManager(baseDbPath);

      // Close current database (and persist if encrypted) before switching.
      final oldDb = _database;
      final oldSession = _encryptedSession;
      
      // Clear database from notifier so providers know it's gone
      ref.read(databaseNotifierProvider.notifier).clearDatabase();
      _encryptedSession = null;

      if (oldDb != null) {
        if (oldSession != null) {
          // If the on-disk encrypted file was removed (user disabled encryption
          // while the app was running), don't attempt to re-encrypt from the
          // temp file because reencryptFromTemp() expects the existing `.enc`
          // (to read the salt). Instead, close the DB and best-effort cleanup
          // of the temp file. This prevents "file not found .enc" errors.
          if (!oldSession.encryptionManager.isEncrypted) {
            try {
              await oldDb.close();
            } finally {
              try {
                if (oldSession.tempFile.existsSync()) {
                  await oldSession.tempFile.delete();
                }
              } catch (_) {
                // ignore cleanup errors
              }
            }
          } else {
            await oldSession.closeAndPersist(oldDb);
          }
        } else {
          await oldDb.close();
        }
      }

      AppDatabase newDb;
      EncryptedDbSession? newSession;

      if (request is CreateDatabaseRequest) {
        // Ensure parent directory exists.
        await File(baseDbPath).parent.create(recursive: true);

        if (request.encrypted) {
          // Create a new plain DB at baseDbPath so EncryptionManager.enable() can
          // generate a fresh salt and write `$baseDbPath.enc`.
          final plainDb = AppDatabase.fromFile(File(baseDbPath));
          await plainDb.initDefaults();
          await plainDb.close();

          final password = await _promptForDatabasePassword();
          if (password == null) {
            // User cancelled; reopen the previous db by re-running bootstrap.
            setState(() {
              _booting = true;
              _bootstrapStarted = false;
            });
            await _bootstrap();
            return;
          }

          await encryptionManager.enable(password);
          final tempPath = await encryptionManager.decryptToTemp(password);
          newDb = AppDatabase.fromFile(File(tempPath));
          await newDb.initDefaults();

          newSession = EncryptedDbSession(
            baseDbPath: baseDbPath,
            tempDbPath: tempPath,
            password: password,
          );
          ref.read(encryptionStateProvider.notifier).setEncryptionState(EncryptionState.encrypted);
        } else {
          newDb = AppDatabase.fromFile(File(baseDbPath));
          await newDb.initDefaults();
          ref.read(encryptionStateProvider.notifier).setEncryptionState(EncryptionState.unencrypted);
        }
      } else {
        // Open existing database.
        if (encryptionManager.isEncrypted) {
          // If the request provided a password, use it; otherwise prompt.
          String? providedPassword = (request is OpenDatabaseRequest) ? request.password : null;

          while (true) {
            final password = providedPassword ?? await _promptForDatabasePassword();
            if (password == null) {
              // User cancelled; reopen the previous db by re-running bootstrap.
              setState(() {
                _booting = true;
                _bootstrapStarted = false;
              });
              await _bootstrap();
              return;
            }

            try {
              final tempPath = await encryptionManager.decryptToTemp(password);
              final conversion = await convertLegacyDbToCurrentLayoutIfNeeded(
                tempPath,
              );

              if (conversion.converted) {
                await encryptionManager.reencryptFromTemp(tempPath, password);
              }

              newDb = AppDatabase.fromFile(File(tempPath));
              await newDb.initDefaults();
              await _showLegacyConversionReport(conversion, dbPath: baseDbPath);

              newSession = EncryptedDbSession(
                baseDbPath: baseDbPath,
                tempDbPath: tempPath,
                password: password,
              );
              ref.read(encryptionStateProvider.notifier).setEncryptionState(EncryptionState.encrypted);
              break;
            } on InvalidPasswordException {
              NotificationManager.instance.error('Incorrect password');
              // If we attempted a provided password, clear it so the user is prompted
              // on the next loop iteration.
              providedPassword = null;
            }
          }
        } else {
          final plainFile = File(baseDbPath);
          if (!plainFile.existsSync()) {
            throw FileSystemException('Database file not found', baseDbPath);
          }
          final conversion = await convertLegacyDbToCurrentLayoutIfNeeded(
            plainFile.path,
          );
          newDb = AppDatabase.fromFile(plainFile);
          await newDb.initDefaults();
          await _showLegacyConversionReport(conversion, dbPath: baseDbPath);
          ref.read(encryptionStateProvider.notifier).setEncryptionState(EncryptionState.unencrypted);
        }
      }

      // Only persist settings after the new database has been opened.
      final settingsNotifier = ref.read(settingsProvider.notifier);
      await settingsNotifier.setSetting(SettingsKeys.databasePath, baseDbPath);
      await _addRecentDbPath(baseDbPath);

      if (!mounted) return;
      
      // Set the new database in the notifier - this will trigger all watchers to rebuild
      ref.read(databaseNotifierProvider.notifier).setDatabase(newDb);
      // Inform the user which file we're now using
      NotificationManager.instance.success('Using database: ${p.basename(baseDbPath)}');
      _encryptedSession = newSession;
      _updateEncryptedSessionProvider();
      
      setState(() {
        _booting = false;
        _error = null;
      });

      // Reset search and filters so the new database starts with a clean view.
      ref.read(gamesProvider.notifier).setSearchQuery('');
      ref.read(gamesProvider.notifier).clearAllFilters();

      // Reset session so old game IDs don't suppress notifications for the
      // new database, then restart the periodic check.
      DeadlineNotificationService.instance.resetSession();
      DeadlineNotificationService.instance.startPeriodicCheck(ref);
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) DeadlineNotificationService.instance.runCheck(ref);
      });
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

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: materialTheme,
      themeAnimationDuration: Duration.zero,
      themeAnimationCurve: Curves.linear,
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
                    CircularProgressIndicator(color: theme.accent),
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
                      Icon(Icons.error_outline, color: Colors.red.shade300, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'Failed to start UniKM',
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error?.toString() ?? 'Database not available',
                        style: TextStyle(color: theme.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _booting = true;
                            _error = null;
                            _bootstrapStarted = false;
                          });
                          _bootstrap();
                        },
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

/// Root application widget
/// 
/// Note: Theme is provided by the parent [_UniKMBootstrap] MaterialApp.
/// This widget only provides the app scaffold content.
class UniKMApp extends ConsumerWidget {
  const UniKMApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Configure text scaling while preserving theme from parent MaterialApp
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.0),
      ),
      child: const AppScaffold(),
    );
  }
}
