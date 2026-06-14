/// Database & security settings section.
library;

import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/database.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/services/database_switching.dart';
import '../../../core/services/encryption_manager.dart';
import '../../../core/services/platform_file_actions.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../dialogs/backup_dialogs.dart';
import '../../dialogs/encryption_dialogs.dart';
import '../../widgets/app_progress_indicator.dart';
import '../../dialogs/import_export_dialog.dart';
import '../../dialogs/device_sync_dialog.dart';
import '../../widgets/dialog_helpers.dart';
import '../../widgets/notification_system.dart';
import '../../widgets/popup_menu_helpers.dart';
import '../../widgets/section_groupbox.dart';
import '../../../core/constants/app_constants.dart';
import 'settings_common.dart';

/// Shows a dialog that asks the user which kind of database to create.
///
/// Returns the selected database creation config or `null` if cancelled.
class CreateDatabaseChoiceResult {
  const CreateDatabaseChoiceResult({
    required this.encrypted,
    this.fileName,
  });

  final bool encrypted;
  final String? fileName;
}

Future<CreateDatabaseChoiceResult?> showCreateDatabaseChoiceDialog(
  BuildContext context,
  AppThemeData theme,
  {
  bool forceMobileLayout = false,
}
) {
  var selectedType = 'unencrypted';
  final fileNameController = TextEditingController();
  String? fileNameError;
  final useMobileLayout =
      forceMobileLayout || PlatformFileActions.isMobilePlatform;

  return showDialog<CreateDatabaseChoiceResult>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return DialogInteractionScope(
        onDismiss: () => Navigator.pop(ctx),
        child: StatefulBuilder(
          builder: (context, setState) {
            return ThemedAlertDialog(
              theme: theme,
              maxWidth: 520,
              title: DialogHeader(
                icon: Icons.note_add,
                title: 'Create Database',
                theme: theme,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Choose the type of database you want to create.',
                    style: TextStyle(color: theme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  SectionGroupBox(
                    title: 'Type',
                    titleIcon: Icons.storage,
                    theme: theme,
                    child: RadioGroup<String>(
                      groupValue: selectedType,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => selectedType = value);
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          RadioListTile<String>(
                            value: 'unencrypted',
                            activeColor: theme.accent,
                            title: Text(
                              'Unencrypted database',
                              style: TextStyle(color: theme.textPrimary),
                            ),
                            subtitle: Text(
                              'Creates a standard SQLite database file.',
                              style: TextStyle(color: theme.textSecondary),
                            ),
                          ),
                          RadioListTile<String>(
                            value: 'encrypted',
                            activeColor: theme.accent,
                            title: Text(
                              'Encrypted database',
                              style: TextStyle(color: theme.textPrimary),
                            ),
                            subtitle: Text(
                              'Creates an encrypted database that requires a password.',
                              style: TextStyle(color: theme.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (useMobileLayout) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: fileNameController,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Database file name',
                        hintText: selectedType == 'encrypted'
                            ? 'UniKM_keys.enc'
                            : 'UniKM_keys.db',
                        errorText: fileNameError,
                      ),
                      onChanged: (_) {
                        if (fileNameError != null) {
                          setState(() => fileNameError = null);
                        }
                      },
                    ),
                  ],
                ],
              ),
              actions: [
                ElevatedButton.icon(
                  onPressed: () {
                    final trimmedFileName = fileNameController.text.trim();
                    if (useMobileLayout && trimmedFileName.isEmpty) {
                      setState(() => fileNameError = 'Please enter a file name');
                      return;
                    }
                    Navigator.pop(
                      ctx,
                      CreateDatabaseChoiceResult(
                        encrypted: selectedType == 'encrypted',
                        fileName: trimmedFileName.isEmpty ? null : trimmedFileName,
                      ),
                    );
                  },
                  style: themedFilledButtonStyle(theme),
                  icon: Icon(
                    selectedType == 'encrypted' ? Icons.lock : Icons.note_add,
                  ),
                  label: const Text('Create'),
                ),
              ],
            );
          },
        ),
      );
    },
  );
}

/// Database and security settings section
class DatabaseSection extends ConsumerStatefulWidget {
  const DatabaseSection({
    super.key,
    required this.theme,
    this.searchQuery = '',
    required this.matchesSearch,
    this.attachesToAbove = false,
  });

  final AppThemeData theme;
  final String searchQuery;
  final bool Function(String) matchesSearch;
  final bool attachesToAbove;

  static const SettingTextSpec encryptionStatusSpec = SettingTextSpec(
    label: 'Encryption status',
    description: 'Your database encryption state',
  );
  static const SettingTextSpec activeDatabaseSpec = SettingTextSpec(
    label: 'Active database file',
  );
  static const SettingTextSpec maskKeysSpec = SettingTextSpec(
    label: 'Mask keys by default',
    description: 'Hide game keys until revealed',
  );
  static const SettingTextSpec autoHideKeysSpec = SettingTextSpec(
    label: 'Auto-hide keys',
    description: 'Automatically hide keys after copying',
  );
  static const SettingTextSpec enableLocalDeviceSyncSpec = SettingTextSpec(
    label: 'Enable Local Device Sync',
    description: 'Allows LAN discovery and manual sync between paired devices.',
  );
  static const SettingTextSpec autoSyncOnStartupSpec = SettingTextSpec(
    label: 'Auto-sync on Startup',
    description: 'Try syncing trusted devices when the app opens.',
  );

  static const SettingsSearchGroup encryptionSearchGroup = SettingsSearchGroup(
    title: 'Encryption',
    settings: [encryptionStatusSpec],
    extraTexts: [
      'Enable',
      'Change Password',
      'Disable',
      'Encrypted (Unlocked)',
      'Encrypted (Locked)',
      'Not Encrypted',
    ],
  );

  static const SettingsSearchGroup dataManagementSearchGroup =
      SettingsSearchGroup(
        title: 'Data Management',
        settings: [activeDatabaseSpec],
        extraTexts: [
          'Import DB',
          'Export DB',
          'Change DB',
          'New DB',
          'Next Auto Backup',
          'Backup Manager',
          'Create Backup',
        ],
      );

  static const SettingsSearchGroup keyVisibilitySearchGroup =
      SettingsSearchGroup(
        title: 'Key Visibility',
        settings: [maskKeysSpec, autoHideKeysSpec],
      );

  static const SettingsSearchGroup databaseSyncSearchGroup =
      SettingsSearchGroup(
        title: 'Database Sync',
        settings: [enableLocalDeviceSyncSpec, autoSyncOnStartupSpec],
      );

  static List<String> get sectionSearchTexts => [
    'Database & Security',
    ...encryptionSearchGroup.indexTexts,
    ...dataManagementSearchGroup.indexTexts,
    ...databaseSyncSearchGroup.indexTexts,
    ...keyVisibilitySearchGroup.indexTexts,
  ];

  @override
  ConsumerState<DatabaseSection> createState() => _DatabaseSectionState();
}

class _DatabaseSectionState extends ConsumerState<DatabaseSection> {
  EncryptionManager? _encryptionManager;
  EncryptionState _encryptionState = EncryptionState.unknown;
  bool _isLoading = true;
  String _activeDbPath = '';
  ProviderSubscription<String>? _dbPathSub;

  @override
  void initState() {
    super.initState();

    _dbPathSub = ref.listenManual<String>(currentDatabasePathProvider, (
      previous,
      next,
    ) {
      _initializeEncryption(configuredPath: next);
    });

    final configuredPath = ref.read(currentDatabasePathProvider);
    if (configuredPath.isNotEmpty) {
      // Path already known — initialize synchronously to avoid a loading flash.
      _activeDbPath = configuredPath;
      _encryptionManager = EncryptionManager(configuredPath);
      _encryptionState = _encryptionManager!.state;
      _isLoading = false;
    } else {
      _initializeEncryption(configuredPath: configuredPath);
    }
  }

  @override
  void dispose() {
    _dbPathSub?.close();
    super.dispose();
  }

  Future<void> _initializeEncryption({required String configuredPath}) async {
    final defaultPath = await AppDatabase.getDatabasePath();
    final resolvedPath = configuredPath.isNotEmpty
        ? configuredPath
        : defaultPath;

    if (!mounted) return;
    setState(() {
      _activeDbPath = resolvedPath;
      _encryptionManager = EncryptionManager(resolvedPath);
      _encryptionState = _encryptionManager!.state;
      _isLoading = false;
    });
  }

  Future<void> _createDatabase({
    required bool encrypted,
    String? suggestedFileName,
  }) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final defaultFileName = encrypted ? 'UniKM_keys.enc' : 'UniKM_keys.db';
    final normalizedFileName = (() {
      final trimmed = suggestedFileName?.trim();
      if (trimmed == null || trimmed.isEmpty) {
        return defaultFileName;
      }
      final expectedExtension = encrypted ? '.enc' : '.db';
      final hasExtension = p.extension(trimmed).isNotEmpty;
      return hasExtension ? trimmed : '$trimmed$expectedExtension';
    })();
    final resultPath = await PlatformFileActions.resolveDatabaseCreationPath(
      dialogTitle: encrypted ? 'Create Encrypted Database' : 'Create Database',
      fileName: normalizedFileName,
      allowedExtensions: encrypted ? const ['enc'] : const ['db'],
    );

    if (resultPath == null || resultPath.isEmpty) return;

    final callback = container.read(databaseSwitchCallbackProvider);
    if (callback == null) return;
    await callback(
      CreateDatabaseRequest(path: resultPath, encrypted: encrypted),
    );
  }

  Future<void> _showChangeDatabaseDialog() async {
    await showChangeDatabaseDialog(context, widget.theme);
  }

  Future<void> _enableEncryption() async {
    if (_encryptionManager == null) return;

    final container = ProviderScope.containerOf(context, listen: false);

    final password = await EnableEncryptionDialog.show(
      context,
      widget.theme,
      _encryptionManager!,
    );

    if (password == null || !mounted) return;

    try {
      container.read(databaseSwitchingProvider.notifier).setSwitching(true);

      final db = container.read(databaseProvider);
      if (db != null) {
        // Flush WAL data to the main .db file before closing so the background
        // SQLite isolate holds the lock for as short a time as possible.
        try {
          await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
        } catch (_) {}
        await db.close();
        container.read(databaseNotifierProvider.notifier).clearDatabase();
      }

      await Future.delayed(const Duration(milliseconds: 300));

      await _encryptionManager!.enable(password, deletePlaintextFile: false);

      if (mounted) {
        setState(() => _encryptionState = EncryptionState.encrypted);
      }
      await container
          .read(settingsProvider.notifier)
          .setSetting(SettingsKeys.encryptionEnabled, true);

      final callback = container.read(databaseSwitchCallbackProvider);
      if (callback != null) {
        await callback(
          OpenDatabaseRequest(_encryptionManager!.dbPath, password: password),
        );
      }

      // Schedule deferred deletion in a background retry loop.
      // Windows Defender / Search can hold the file lock long after close();
      // we store the path so _bootstrap() can retry on the next launch too.
      final prefs = container.read(sharedPreferencesProvider);
      await prefs.setString(
        EncryptionManager.pendingPlaintextDeletionKey,
        _encryptionManager!.dbPath,
      );
      unawaited(
        _encryptionManager!
            .deletePlaintextDatabaseFile(
              throwOnFailure: false,
              maxAttempts: 30,
              initialDelay: const Duration(milliseconds: 200),
            )
            .then((deleted) async {
              if (deleted) {
                await prefs.remove(
                  EncryptionManager.pendingPlaintextDeletionKey,
                );
              }
            }),
      );
    } catch (e) {
      NotificationManager.instance.error('Failed to enable encryption: $e');
      final callback = container.read(databaseSwitchCallbackProvider);
      if (callback != null) {
        await callback(OpenDatabaseRequest(_encryptionManager!.dbPath));
      }
    } finally {
      container.read(databaseSwitchingProvider.notifier).setSwitching(false);
    }
  }

  Future<void> _changePassword() async {
    if (_encryptionManager == null) return;

    await ChangePasswordDialog.show(context, widget.theme, _encryptionManager!);
  }

  Future<void> _disableEncryption() async {
    if (_encryptionManager == null) return;

    final container = ProviderScope.containerOf(context, listen: false);

    final password = await DisableEncryptionDialog.show(
      context,
      widget.theme,
      _encryptionManager!,
    );

    if (password == null || !mounted) return;

    try {
      container.read(databaseSwitchingProvider.notifier).setSwitching(true);

      final db = container.read(databaseProvider);
      if (db != null) {
        await db.close();
        container.read(databaseNotifierProvider.notifier).clearDatabase();
      }

      await Future.delayed(const Duration(milliseconds: 100));

      await _encryptionManager!.disable(password);

      if (mounted) {
        setState(() => _encryptionState = EncryptionState.unencrypted);
      }
      await container
          .read(settingsProvider.notifier)
          .setSetting(SettingsKeys.encryptionEnabled, false);

      final callback = container.read(databaseSwitchCallbackProvider);
      if (callback != null && _encryptionManager != null) {
        await callback(OpenDatabaseRequest(_encryptionManager!.dbPath));
      }

      NotificationManager.instance.success('Database encryption disabled');
    } on InvalidPasswordException {
      NotificationManager.instance.error('Password is incorrect');
    } catch (e) {
      NotificationManager.instance.error('Failed to disable encryption: $e');
      final callback = container.read(databaseSwitchCallbackProvider);
      if (callback != null && _encryptionManager != null) {
        await callback(OpenDatabaseRequest(_encryptionManager!.dbPath));
      }
    } finally {
      container.read(databaseSwitchingProvider.notifier).setSwitching(false);
    }
  }

  Widget _buildResponsiveSettingRow({
    required String label,
    String? description,
    Color? labelColor,
    double stackedBreakpoint = 220,
    required Widget Function(bool stacked) trailingBuilder,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < stackedBreakpoint;
        final trailing = trailingBuilder(stacked);

        if (!stacked) {
          return SettingRow(
            theme: widget.theme,
            label: label,
            description: description,
            labelColor: labelColor,
            child: trailing,
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: labelColor ?? widget.theme.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    color: widget.theme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: kElementVSpacing),
              trailing,
            ],
          ),
        );
      },
    );
  }


  List<Widget> _buildEncryptionActionButtons(bool isEncrypted) {
    return [
      if (!isEncrypted)
        ElevatedButton.icon(
          onPressed: _enableEncryption,
          icon: const Icon(Icons.lock),
          label: _singleLineButtonLabel('Enable'),
        ),
      if (isEncrypted)
        OutlinedButton.icon(
          onPressed: _changePassword,
          icon: const Icon(Icons.key),
          label: _singleLineButtonLabel('Change Password'),
        ),
      if (isEncrypted)
        ElevatedButton.icon(
          onPressed: _disableEncryption,
          icon: const Icon(Icons.lock_open),
          label: _singleLineButtonLabel('Disable'),
        ),
    ];
  }

  Widget _singleLineButtonLabel(String text) {
    return Text(
      text,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.fade,
    );
  }

  String _formatNextBackupTime(DateTime nextTime) {
    final now = DateTime.now();
    final diff = nextTime.difference(now);

    if (diff.isNegative) {
      return 'Running now...';
    }

    if (diff.inMinutes < 1) {
      return 'In less than a minute';
    } else if (diff.inMinutes == 1) {
      return 'In 1 minute';
    } else if (diff.inMinutes < 60) {
      return 'In ${diff.inMinutes} minutes';
    } else {
      final hours = diff.inHours;
      final mins = diff.inMinutes % 60;
      if (mins == 0) {
        return 'In $hours hour${hours > 1 ? 's' : ''}';
      }
      return 'In $hours hour${hours > 1 ? 's' : ''} $mins min';
    }
  }

  Widget _buildDataManagementStatusSection(
    BuildContext context, {
    required bool showEncryptionContent,
    required bool showBackupContent,
    required String encryptionStatusLabel,
    required Color encryptionStatusColor,
    required bool isEncrypted,
    required DateTime? nextBackupTime,
  }) {
    return Column(
      children: [
        if (showEncryptionContent) ...[
          SettingsStatusActionCard(
            theme: widget.theme,
            icon: Icons.lock_open,
            iconColor: widget.theme.accent,
            title: encryptionStatusLabel,
            subtitle: DatabaseSection.encryptionStatusSpec.description,
            titleColor: encryptionStatusColor,
            stackedColumnsForWidth: (_, count) => count,
            actions: _isLoading
                ? const [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: AppCircularProgressIndicator(),
                    ),
                  ]
                : _buildEncryptionActionButtons(isEncrypted),
          ),
          if (showBackupContent) const SizedBox(height: 12),
        ],
        if (showBackupContent && nextBackupTime != null)
          SettingsStatusActionCard(
            theme: widget.theme,
            icon: Icons.schedule,
            iconColor: widget.theme.accent,
            title: 'Next Auto Backup',
            subtitle: _formatNextBackupTime(nextBackupTime),
            titleColor: widget.theme.textPrimary,
            stretchActionsWhenStacked: true,
            actions: [
              ElevatedButton.icon(
                onPressed: () {
                  showBackupDialog(context);
                },
                icon: const Icon(Icons.backup),
                label: const Text('Backup Manager'),
              ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final security = ref.watch(securitySettingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final syncNotifier = ref.read(deviceSyncProvider.notifier);
    final syncAsync = ref.watch(deviceSyncProvider);
    final fallbackSyncEnabled = ref.watch(
      settingsProvider.select(
        (s) =>
            (s[SettingsKeys.syncEnabled] as bool?) ??
            DefaultSettings.syncEnabled,
      ),
    );
    final fallbackSyncAutoOnStartup = ref.watch(
      settingsProvider.select(
        (s) =>
            (s[SettingsKeys.syncAutoOnStartup] as bool?) ??
            DefaultSettings.syncAutoOnStartup,
      ),
    );
    final syncEnabled = syncAsync.asData?.value.enabled ?? fallbackSyncEnabled;
    final syncAutoOnStartup =
        syncAsync.asData?.value.autoOnStartup ?? fallbackSyncAutoOnStartup;
    final isEncrypted = _encryptionState == EncryptionState.encrypted;
    final isUnlocked = ref.watch(encryptedDbSessionProvider) != null;
    final nextBackupTime = ref.watch(nextAutoBackupTimeProvider);
    final isSearching = widget.searchQuery.trim().isNotEmpty;
    final encryptionStatusLabel = _isLoading
        ? DatabaseSection.encryptionStatusSpec.label
        : isEncrypted
        ? (isUnlocked ? 'Encrypted (Unlocked)' : 'Encrypted (Locked)')
        : 'Not Encrypted';
    final encryptionStatusColor = _isLoading
        ? widget.theme.textPrimary
        : isEncrypted
        ? (isUnlocked ? widget.theme.accent : widget.theme.secondary)
        : widget.theme.textPrimary;

    final showEncryption = shouldShowSettingsGroup(
      query: widget.searchQuery,
      matchesSearch: widget.matchesSearch,
      group: DatabaseSection.encryptionSearchGroup,
    );
    final showDataManagement = shouldShowSettingsGroup(
      query: widget.searchQuery,
      matchesSearch: widget.matchesSearch,
      group: DatabaseSection.dataManagementSearchGroup,
    );
    final showStatusCards =
        showEncryption || (showDataManagement && nextBackupTime != null);
    final showKeyVisibility = shouldShowSettingsGroup(
      query: widget.searchQuery,
      matchesSearch: widget.matchesSearch,
      group: DatabaseSection.keyVisibilitySearchGroup,
    );
    final showDatabaseSync = shouldShowSettingsGroup(
      query: widget.searchQuery,
      matchesSearch: widget.matchesSearch,
      group: DatabaseSection.databaseSyncSearchGroup,
    );

    if (isSearching &&
        !showStatusCards &&
        !showDataManagement &&
        !showDatabaseSync &&
        !showKeyVisibility) {
      return const SizedBox.shrink();
    }

    return SettingsSectionGroups(
      attachesToAbove: widget.attachesToAbove,
      entries: [
        buildTitlelessSectionEntry(
          visible: showStatusCards,
          theme: widget.theme,
          searchQuery: widget.searchQuery,
          isSearchMatch: isSearching,
          childBuilder: () => _buildDataManagementStatusSection(
            context,
            showEncryptionContent: showEncryption,
            showBackupContent: showDataManagement && nextBackupTime != null,
            encryptionStatusLabel: encryptionStatusLabel,
            encryptionStatusColor: encryptionStatusColor,
            isEncrypted: isEncrypted,
            nextBackupTime: nextBackupTime,
          ),
        ),
        // Data Management (Backup/Restore)
        SectionGroupEntry(
          visible: showDataManagement,
          builder: (position, isAlternate) => _buildDataManagementSection(
            context,
            searchQuery: widget.searchQuery,
            isSearchMatch: isSearching,
            groupPosition: position,
            alternateBackground: isAlternate,
            nextBackupTime: nextBackupTime,
          ),
        ),
        // Database Sync
        SectionGroupEntry(
          visible: showDatabaseSync,
          builder: (position, isAlternate) => SectionGroupBox(
            title: DatabaseSection.databaseSyncSearchGroup.title,
            theme: widget.theme,
            titleIcon: Icons.sync,
            searchQuery: widget.searchQuery,
            isSearchMatch: isSearching,
            groupPosition: position,
            alternateBackground: isAlternate,
            child: Column(
              children: [
                SpecToggleSettingRow(
                  theme: widget.theme,
                  spec: DatabaseSection.enableLocalDeviceSyncSpec,
                  value: syncEnabled,
                  onChanged: (value) {
                    syncNotifier.setEnabled(value);
                  },
                ),
                SpecToggleSettingRow(
                  theme: widget.theme,
                  spec: DatabaseSection.autoSyncOnStartupSpec,
                  value: syncAutoOnStartup,
                  showDividerBelow: false,
                  onChanged: (value) {
                    if (!syncEnabled) return;
                    syncNotifier.setAutoOnStartup(value);
                  },
                ),
              ],
            ),
          ),
        ),
        // Key Visibility
        SectionGroupEntry(
          visible: showKeyVisibility,
          builder: (position, isAlternate) => SectionGroupBox(
            title: DatabaseSection.keyVisibilitySearchGroup.title,
            theme: widget.theme,
            titleIcon: Icons.visibility,
            searchQuery: widget.searchQuery,
            isSearchMatch: isSearching,
            groupPosition: position,
            alternateBackground: isAlternate,
            child: Column(
              children: [
                SpecToggleSettingRow(
                  theme: widget.theme,
                  spec: DatabaseSection.maskKeysSpec,
                  value: security.maskKeys,
                  onChanged: (value) =>
                      settingsNotifier.setSetting(SettingsKeys.maskKeys, value),
                ),
                SpecToggleSettingRow(
                  theme: widget.theme,
                  spec: DatabaseSection.autoHideKeysSpec,
                  value: security.autoHideKeys,
                  showDividerBelow: false,
                  onChanged: (value) => settingsNotifier.setSetting(
                    SettingsKeys.autoHideKeys,
                    value,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDataManagementSection(
    BuildContext context,
    {
    required String searchQuery,
    required bool isSearchMatch,
    required DateTime? nextBackupTime,
    SectionGroupPosition groupPosition = SectionGroupPosition.only,
    bool alternateBackground = false,
  }) {
    return SectionGroupBox(
      title: DatabaseSection.dataManagementSearchGroup.title,
      theme: widget.theme,
      titleIcon: Icons.backup,
      searchQuery: searchQuery,
      isSearchMatch: isSearchMatch,
      groupPosition: groupPosition,
      alternateBackground: alternateBackground,
      child: Column(
        children: [
          _buildResponsiveSettingRow(
            label: DatabaseSection.activeDatabaseSpec.label,
            description: _activeDbPath,
            trailingBuilder: (stacked) => Align(
              alignment: stacked ? Alignment.centerLeft : Alignment.centerRight,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: AppCircularProgressIndicator(),
                    )
                  : const SizedBox.shrink(),
            ),
          ),

          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 8.0;
              final w = constraints.maxWidth;
              final cols = w < 500 ? 1 : (w < 650 ? 2 : 4);
              final btnWidth = (w - spacing * (cols - 1)) / cols;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final btn in [
                    OutlinedButton.icon(
                      onPressed: () => showImportDialog(context),
                      icon: const Icon(Icons.download),
                      label: const Text('Import DB'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => showExportDialog(context),
                      icon: const Icon(Icons.upload),
                      label: const Text('Export DB'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _showChangeDatabaseDialog,
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Change DB'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final choice = await showCreateDatabaseChoiceDialog(
                          context,
                          widget.theme,
                        );
                        if (choice != null) {
                          await _createDatabase(
                            encrypted: choice.encrypted,
                            suggestedFileName: choice.fileName,
                          );
                        }
                      },
                      icon: const Icon(Icons.note_add),
                      label: const Text('New DB'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => showDeviceSyncDialog(context),
                      icon: const Icon(Icons.sync),
                      label: const Text('Device Sync'),
                    ),
                  ])
                    SizedBox(width: btnWidth, child: btn),
                ],
              );
            },
          ),
          if (nextBackupTime == null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      showBackupDialog(context);
                    },
                    icon: const Icon(Icons.backup),
                    label: const Text('Create Backup'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ChangeDatabaseDialog extends ConsumerStatefulWidget {
  const _ChangeDatabaseDialog({required this.theme, required this.container});

  final AppThemeData theme;
  final ProviderContainer container;

  @override
  ConsumerState<_ChangeDatabaseDialog> createState() =>
      _ChangeDatabaseDialogState();
}

class _ChangeDatabaseDialogState extends ConsumerState<_ChangeDatabaseDialog> {
  final _scrollController = ScrollController();
  bool _isLoading = true;
  String _defaultDbPath = '';
  String _activeDbPath = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final configuredPath = widget.container.read(currentDatabasePathProvider);
    final defaultPath = await AppDatabase.getDatabasePath();
    final resolvedPath = configuredPath.isNotEmpty
        ? configuredPath
        : defaultPath;
    if (!mounted) return;
    setState(() {
      _defaultDbPath = defaultPath;
      _activeDbPath = resolvedPath;
      _isLoading = false;
    });
  }

  Future<void> _useDefaultDatabase() async {
    if (_defaultDbPath.isEmpty || _defaultDbPath == _activeDbPath) return;
    final callback = widget.container.read(databaseSwitchCallbackProvider);
    if (callback == null) return;
    await callback(OpenDatabaseRequest(_defaultDbPath));
  }

  Future<void> _openDatabase() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Open UniKM Database',
      type: FileType.custom,
      allowedExtensions: const ['db', 'enc'],
      allowMultiple: false,
    );
    final selectedPath = result?.files.single.path;
    if (selectedPath == null || selectedPath.isEmpty) return;
    final callback = widget.container.read(databaseSwitchCallbackProvider);
    if (callback == null) return;
    await callback(OpenDatabaseRequest(selectedPath));
  }

  Future<void> _openRecentDatabase(String baseDbPath) async {
    final callback = widget.container.read(databaseSwitchCallbackProvider);
    if (callback == null) return;
    await callback(OpenDatabaseRequest(baseDbPath));
  }

  Future<void> _removeRecentDatabasePath(String baseDbPath) async {
    final settingsNotifier = widget.container.read(settingsProvider.notifier);
    final recents = List<String>.from(
      widget.container.read(securitySettingsProvider).recentDatabasePaths,
    );
    final removed = recents.remove(baseDbPath);
    if (!removed) return;
    await settingsNotifier.setSetting(
      SettingsKeys.recentDatabasePaths,
      recents,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex += 1;
    }

    final precision = size >= 100 ? 0 : (size >= 10 ? 1 : 2);
    return '${size.toStringAsFixed(precision)} ${units[unitIndex]}';
  }

  @override
  Widget build(BuildContext context) {
    final recents = ref.watch(securitySettingsProvider).recentDatabasePaths;

    return ThemedAlertDialog(
      theme: widget.theme,
      backgroundColor: widget.theme.background,
      maxWidth: 520,
      maxHeight: 600,
      title: DialogHeader(
        icon: Icons.swap_horiz,
        title: 'Change Database',
        theme: widget.theme,
        showCloseButton: false,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Current',
            style: TextStyle(
              color: widget.theme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: kElementVSpacing),
          if (_isLoading)
            const SizedBox(
              width: 20,
              height: 20,
              child: AppCircularProgressIndicator(),
            )
          else
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: widget.theme.surface,
                borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
                border: Border.all(color: widget.theme.accent.withValues(alpha: 0.6), width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: widget.theme.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.storage, color: widget.theme.accent, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.basename(_activeDbPath).isEmpty
                              ? _activeDbPath
                              : p.basename(_activeDbPath),
                          style: TextStyle(
                            color: widget.theme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          _activeDbPath,
                          style: TextStyle(
                            color: widget.theme.textSecondary,
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed:
                      (_isLoading ||
                          _defaultDbPath.isEmpty ||
                          _defaultDbPath == _activeDbPath)
                      ? null
                      : () async {
                          Navigator.pop(context);
                          await _useDefaultDatabase();
                        },
                  icon: const Icon(Icons.restore),
                  label: const Text('Use Default'),
                ),
              ),
              const SizedBox(width: kElementHSpacing),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _openDatabase();
                  },
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open…'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Recent',
            style: TextStyle(
              color: widget.theme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: kElementVSpacing),
          if (recents.isEmpty)
            Text(
              'No recent databases yet.',
              style: TextStyle(color: widget.theme.textSecondary),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: Scrollbar(
                controller: _scrollController,
                child: ListView.builder(
                  controller: _scrollController,
                  primary: false,
                  itemCount: recents.length,
                  itemBuilder: (context, index) {
                    final basePath = recents[index];
                    final label = p.basename(basePath);
                    final file = File(basePath);
                    final exists = file.existsSync();
                    final sizeBytes = exists ? file.lengthSync() : null;
                    final encPath = '$basePath.enc';
                    final encExists = !exists && File(encPath).existsSync();

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onSecondaryTapDown: (details) async {
                        final overlay =
                            Overlay.of(context).context.findRenderObject()
                                as RenderBox;
                        final position = RelativeRect.fromRect(
                          Rect.fromPoints(
                            details.globalPosition,
                            details.globalPosition,
                          ),
                          Offset.zero & overlay.size,
                        );
                        final selected = await showAppMenu<String>(
                          context: context,
                          position: position,
                          items: const [
                            PopupMenuItem(
                              value: 'remove',
                              child: Text('Remove from recents'),
                            ),
                          ],
                        );

                        if (selected == 'remove') {
                          await _removeRecentDatabasePath(basePath);
                        }
                      },
                      child: _RecentDbListItem(
                        theme: widget.theme,
                        title: label.isEmpty ? basePath : label,
                        basePath: basePath,
                        sizeLabel: sizeBytes == null
                            ? null
                            : _formatBytes(sizeBytes),
                        exists: exists,
                        encExists: encExists,
                        onOpen: exists
                            ? () async {
                                Navigator.pop(context);
                                await _openRecentDatabase(basePath);
                              }
                            : encExists
                            ? () async {
                                Navigator.pop(context);
                                await _openRecentDatabase(encPath);
                              }
                            : null,
                        onRemove: () async {
                          await _removeRecentDatabasePath(basePath);
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentDbListItem extends StatefulWidget {
  const _RecentDbListItem({
    required this.theme,
    required this.title,
    required this.basePath,
    required this.exists,
    required this.onRemove,
    this.sizeLabel,
    this.onOpen,
    this.encExists = false,
  });

  final AppThemeData theme;
  final String title;
  final String basePath;
  final String? sizeLabel;
  final bool exists;
  final bool encExists;
  final VoidCallback onRemove;
  final VoidCallback? onOpen;

  @override
  State<_RecentDbListItem> createState() => _RecentDbListItemState();
}

class _RecentDbListItemState extends State<_RecentDbListItem> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = _isHovering ? widget.theme.accent : widget.theme.border;
    final resolvedTitle = widget.encExists ? '${widget.title}.enc' : widget.title;
    final resolvedPath = widget.encExists ? '${widget.basePath}.enc' : widget.basePath;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
        onHover: (value) => setState(() => _isHovering = value),
        onTap: (widget.exists || widget.encExists) ? widget.onOpen : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: widget.theme.surface,
            borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (widget.exists || widget.encExists)
                      ? widget.theme.accent.withValues(alpha: 0.1)
                      : Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  widget.exists
                      ? Icons.storage
                      : widget.encExists
                      ? Icons.lock_outline
                      : Icons.warning_amber,
                  color: (widget.exists || widget.encExists)
                      ? widget.theme.accent
                      : Colors.orange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resolvedTitle,
                      style: TextStyle(
                        color: widget.theme.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      widget.sizeLabel == null
                          ? resolvedPath
                          : '${widget.sizeLabel} • $resolvedPath',
                      style: TextStyle(
                        color: widget.theme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: 'Remove from recents',
                onPressed: widget.onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// PUBLIC HELPER — callable from anywhere in the app
// =============================================================================

Future<void> showChangeDatabaseDialog(
  BuildContext context,
  AppThemeData theme,
) {
  final container = ProviderScope.containerOf(context, listen: false);
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _ChangeDatabaseDialog(theme: theme, container: container),
  );
}
