/// Database & security settings section.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../app/application/database_encryption_controller.dart';
import '../../widgets/app_scrollbar.dart';
import '../../../app/application/database_session_loader.dart';
import '../../../core/database/sqlite_file.dart';
import '../../../core/database/database.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/services/biometric_unlock.dart';
import '../../../core/services/database_switching.dart';
import '../../../core/services/database_file_info.dart';
import '../../../core/services/encryption_manager.dart';
import '../../../core/services/platform_file_actions.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../dialogs/backup_dialogs.dart';
import '../../dialogs/encryption_dialogs.dart';
import '../../widgets/app_progress_indicator.dart';
import '../../widgets/file_drop_field.dart';
import '../../dialogs/import_export_dialog.dart';
import '../../dialogs/device_sync_dialog.dart';
import '../../widgets/dialog_helpers.dart';
import '../../widgets/database_file_row.dart';
import '../../widgets/notification_system.dart';
import '../../widgets/popup_menu_helpers.dart';
import '../../widgets/section_groupbox.dart';
import '../../widgets/tinted_tiles.dart';
import '../../widgets/settings_header_actions.dart';
import '../../../core/constants/app_constants.dart';
import 'settings_common.dart';
import 'settings_control_cards.dart';

/// Shows a dialog that asks the user which kind of database to create.
///
/// Returns the selected database creation config or `null` if cancelled.
class const CreateDatabaseChoiceResult({
  required final bool encrypted,
  final String? fileName,
});

Future<CreateDatabaseChoiceResult?> showCreateDatabaseChoiceDialog(
  BuildContext context,
  AppThemeData theme, {
  bool forceMobileLayout = false,
}) {
  var selectedType = 'unencrypted';
  final fileNameController = TextEditingController();
  String? fileNameError;
  final useMobileLayout =
      forceMobileLayout || PlatformFileActions.isMobilePlatform;

  return showAppDialog<CreateDatabaseChoiceResult>(
    context: context,
    builder: (ctx) => DialogInteractionScope(
      onDismiss: () => Navigator.pop(ctx),
      child: StatefulBuilder(
        builder: (context, setState) => ThemedAlertDialog(
          maxWidth: 520,
          title: DialogHeader(icon: Icons.note_add, title: 'Create Database'),
          contentSpacing: 8,
          contentChildren: [
            TintedHeading(title: 'Database Type'),
            for (final (type, icon, title, subtitle) in [
              (
                'unencrypted',
                Icons.lock_open,
                'Unencrypted database',
                'Creates a standard SQLite database file.',
              ),
              (
                'encrypted',
                Icons.lock,
                'Encrypted database',
                'Creates an encrypted database that requires a password.',
              ),
            ])
              TintedOptionTile(
                icon: icon,
                title: title,
                subtitle: subtitle,
                selected: selectedType == type,
                onTap: () => setState(() => selectedType = type),
              ),
            if (useMobileLayout)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: fileNameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Database file name',
                    border: theme.resolveInputBorder(labelInside: true),
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
              ),
          ],
          actions: [
            ElevatedButton(
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
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _createDatabase(BuildContext context, WidgetRef ref) async {
  final theme = ref.read(themeProvider);
  final choice = await showCreateDatabaseChoiceDialog(context, theme);
  if (choice == null || !context.mounted) return;
  final defaultFileName = choice.encrypted ? 'UniKM_keys.enc' : 'UniKM_keys.db';
  final trimmed = choice.fileName?.trim();
  final fileName = trimmed == null || trimmed.isEmpty
      ? defaultFileName
      : p.extension(trimmed).isEmpty
      ? '$trimmed${choice.encrypted ? '.enc' : '.db'}'
      : trimmed;
  final path = await PlatformFileActions.resolveDatabaseCreationPath(
    dialogTitle: choice.encrypted
        ? 'Create Encrypted Database'
        : 'Create Database',
    fileName: fileName,
    allowedExtensions: choice.encrypted ? const ['enc'] : const ['db'],
  );
  if (path == null || path.isEmpty || !context.mounted) return;
  final callback = ref.read(databaseSwitchCallbackProvider);
  await callback?.call(
    CreateDatabaseRequest(path: path, encrypted: choice.encrypted),
  );
}

/// Icon actions shared by the Database header and selected subpage.
class const DatabaseHeaderActions({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final switching = ref.watch(databaseSwitchingProvider);
    return SettingsHeaderActionRow(
      children: [
        for (final (icon, tooltip, onTap) in [
          (Icons.download, 'Import DB', () => showImportDialog(context)),
          (Icons.upload, 'Export DB', () => showExportDialog(context)),
          (
            Icons.note_add,
            'New DB',
            switching ? null : () => _createDatabase(context, ref),
          ),
        ])
          SettingsHeaderAction(icon: icon, tooltip: tooltip, onTap: onTap),
      ],
    );
  }
}

// Cache the file check for startup/fallback states instead of repeating it
// whenever a header rebuilds. Bootstrap publishes the live encryption state.
final _activeEncryptionStateProvider = Provider<EncryptionState>((ref) {
  final state = ref.watch(encryptionStateProvider);
  if (state != EncryptionState.unknown) return state;
  final path = ref.watch(currentDatabasePathProvider);
  ref.watch(databaseNotifierProvider.select((state) => state.revision));
  return path.isEmpty
      ? EncryptionState.unknown
      : ref
            .watch(
              encryptionManagerProvider(DatabaseSessionLoader.basePath(path)),
            )
            .state;
});

/// Whether this phone can pair biometric unlock, and whether the active
/// database is paired; null while the database is not encrypted.
final _biometricStateProvider =
    FutureProvider.autoDispose<({bool available, bool paired})?>((ref) async {
      if (ref.watch(_activeEncryptionStateProvider) !=
          EncryptionState.encrypted) {
        return null;
      }
      final path = ref.watch(currentDatabasePathProvider);
      final unlock = ref.watch(biometricUnlockProvider);
      final available = await unlock.isAvailable();
      return (
        available: available,
        paired:
            available &&
            await unlock.isPaired(DatabaseSessionLoader.basePath(path)),
      );
    });

/// Encryption, password and biometric unlock controls for the active
/// database. Each toggle follows the real state, so a cancelled flow leaves
/// it unchanged.
class const _EncryptionControls({
  /// Places the header [action] (change password, when encrypted) and the
  /// toggle [cards].
  required final Widget Function(Widget? action, List<Widget> cards) builder,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_EncryptionControls> createState() =>
      _EncryptionControlsState();
}

class _EncryptionControlsState extends ConsumerState<_EncryptionControls> {
  bool _busy = false;

  Future<void> _run(
    Future<void> Function(DatabaseEncryptionController controller) action,
  ) async {
    if (_busy) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final configuredPath = container.read(currentDatabasePathProvider);
    setState(() => _busy = true);
    try {
      final path = DatabaseSessionLoader.basePath(
        configuredPath.isNotEmpty
            ? configuredPath
            : await AppDatabase.getDatabasePath(),
      );
      if (!mounted) return;
      final manager = container.read(encryptionManagerProvider(path));
      await action(DatabaseEncryptionController(container, manager));
    } catch (error) {
      NotificationManager.instance.error('Failed to update encryption: $error');
    } finally {
      if (mounted) {
        ref.invalidate(_biometricStateProvider);
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _setEncrypted(bool on) => _run((controller) async {
    if (!on) {
      await DisableEncryptionDialog.show(context, controller.disable);
      return;
    }
    final password = await EnableEncryptionDialog.show(
      context,
      context.appTheme,
      controller.manager,
    );
    if (password == null) return;
    await controller.enable(password);
    NotificationManager.instance.success('Database encryption enabled');
  });

  Future<void> _setBiometric(bool on) => _run((controller) async {
    final pairing = await controller.biometricPairing();
    if (pairing == null || !mounted) return;
    if (on) {
      await BiometricPairDialog.show(context, pairing.pair);
    } else {
      await pairing.unpair();
      NotificationManager.instance.success(
        '${BiometricUnlock.label} unlock turned off for this database',
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final encrypted =
        ref.watch(_activeEncryptionStateProvider) == EncryptionState.encrypted;
    final enabled = !_busy && !ref.watch(databaseSwitchingProvider);
    final biometric = ref.watch(_biometricStateProvider).asData?.value;
    final biometricHint = !ref.watch(biometricUnlockProvider).supported
        ? 'Available on mobile'
        : !encrypted
        ? 'Turn on encryption first'
        : biometric != null && !biometric.available
        ? 'Not set up on this device'
        : null;
    return widget.builder(
      encrypted
          ? IconButton(
              tooltip: 'Change Password',
              style: theme.compactIconButtonStyle,
              color: theme.accent,
              icon: const Icon(Icons.key, size: 26),
              onPressed: enabled
                  ? () => _run(
                      (controller) => ChangePasswordDialog.show(
                        context,
                        controller.changePassword,
                      ),
                    )
                  : null,
            )
          : null,
      [
        SettingsToggleCard(
          label: DatabaseSection.encryptionSpec.label,
          icon: DatabaseSection.encryptionSpec.icon,
          value: encrypted,
          onChanged: enabled ? _setEncrypted : null,
        ),
        SettingsToggleCard(
          label: '${BiometricUnlock.label} unlock',
          icon: DatabaseSection.biometricSpec.icon,
          description: biometricHint,
          value: biometric?.paired ?? false,
          onChanged: enabled && biometric?.available == true
              ? _setBiometric
              : null,
        ),
      ],
    );
  }
}

/// Database and security settings section
class const DatabaseSection({
  super.key,
  final String searchQuery = '',
  final bool attachesToAbove = false,
}) extends ConsumerStatefulWidget {
  static const SettingTextSpec activeDatabaseSpec = SettingTextSpec(
    label: 'Change Database',
    icon: Icons.description_outlined,
  );
  static const SettingTextSpec encryptionSpec = SettingTextSpec(
    label: 'Encryption',
    icon: Icons.lock_outline,
  );
  static const SettingTextSpec biometricSpec = SettingTextSpec(
    label: 'Fingerprint unlock',
    icon: Icons.fingerprint,
  );
  static const SettingTextSpec maskKeysSpec = SettingTextSpec(
    label: 'Mask keys',
    icon: Icons.visibility_off_outlined,
  );
  static const SettingTextSpec autoHideKeysSpec = SettingTextSpec(
    label: 'Hide after copy',
    icon: Icons.timer_outlined,
  );
  static const SettingTextSpec autoLockSpec = SettingTextSpec(
    label: 'Auto-lock',
    icon: Icons.lock_clock_outlined,
  );
  static const SettingTextSpec hideInRecentsSpec = SettingTextSpec(
    label: 'Hide in recents',
    icon: Icons.privacy_tip_outlined,
  );
  static const SettingTextSpec backupManagerSpec = SettingTextSpec(
    label: 'Backup Manager',
    icon: Icons.backup_outlined,
  );
  static const SettingTextSpec deviceSyncSpec = SettingTextSpec(
    label: 'Device Sync',
    icon: Icons.devices_outlined,
  );
  static const SettingTextSpec enableLocalDeviceSyncSpec = SettingTextSpec(
    label: 'Local sync',
    icon: Icons.lan_outlined,
  );
  static const SettingTextSpec autoSyncOnStartupSpec = SettingTextSpec(
    label: 'Sync on startup',
    icon: Icons.sync,
  );

  static const SettingsSearchGroup dataManagementSearchGroup =
      SettingsSearchGroup(
        title: 'Data Management',
        settings: [activeDatabaseSpec, backupManagerSpec],
        extraTexts: [
          'Import DB',
          'Export DB',
          'Change DB',
          'New DB',
          'Next Auto Backup',
          'Next backup',
          'Auto backup is off',
          'Current database file',
          'Database in use',
          'Open Backup Manager',
          'Create Backup',
        ],
      );

  static const SettingsSearchGroup keyVisibilitySearchGroup =
      SettingsSearchGroup(
        title: 'Key Security',
        settings: [
          encryptionSpec,
          biometricSpec,
          maskKeysSpec,
          autoHideKeysSpec,
          autoLockSpec,
          hideInRecentsSpec,
        ],
        extraTexts: [
          'Enable Encryption',
          'Disable Encryption',
          'Change Password',
          'Face ID',
          'Touch ID',
          'Biometric',
          'Key Visibility',
          'Mask keys by default',
          'Auto-hide keys',
          'Hide in recent apps',
          'Clipboard',
          'Lock',
          'Screenshots',
        ],
        info:
            'Copied keys clear from the clipboard after a minute. Auto-lock '
            'only affects encrypted databases.',
      );

  static const SettingsSearchGroup databaseSyncSearchGroup =
      SettingsSearchGroup(
        title: 'Database Sync',
        settings: [
          deviceSyncSpec,
          enableLocalDeviceSyncSpec,
          autoSyncOnStartupSpec,
        ],
        extraTexts: ['Enable Local Device Sync', 'LAN', 'Paired devices'],
      );

  @override
  ConsumerState<DatabaseSection> createState() => _DatabaseSectionState();
}

class _DatabaseSectionState extends ConsumerState<DatabaseSection> {
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
      _initializeDatabasePath(configuredPath: next);
    });

    final configuredPath = ref.read(currentDatabasePathProvider);
    if (configuredPath.isNotEmpty) {
      // Path already known — initialize synchronously to avoid a loading flash.
      _activeDbPath = configuredPath;
      _isLoading = false;
    } else {
      _initializeDatabasePath(configuredPath: configuredPath);
    }
  }

  @override
  void dispose() {
    _dbPathSub?.close();
    super.dispose();
  }

  int _pathRequest = 0;

  Future<void> _initializeDatabasePath({required String configuredPath}) async {
    final request = ++_pathRequest;
    final resolvedPath = configuredPath.isNotEmpty
        ? configuredPath
        : await AppDatabase.getDatabasePath();
    if (!mounted || request != _pathRequest) return;
    setState(() {
      _activeDbPath = resolvedPath;
      _isLoading = false;
    });
  }

  static String _formatNextBackupTime(DateTime nextTime) {
    final diff = nextTime.difference(clock.now());
    final minutes = diff.inMinutes;
    if (diff.isNegative) return 'Next backup is running now';
    if (minutes < 1) return 'Next backup in less than a minute';
    if (minutes == 1) return 'Next backup in 1 minute';
    if (minutes < 60) return 'Next backup in $minutes minutes';
    final hours = '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''}';
    return minutes % 60 == 0
        ? 'Next backup in $hours'
        : 'Next backup in $hours ${minutes % 60} min';
  }

  @override
  Widget build(BuildContext context) {
    final security = ref.watch(securitySettingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final syncNotifier = ref.read(deviceSyncProvider.notifier);
    final syncAsync = ref.watch(deviceSyncProvider);
    bool storedFlag(String key, bool fallback) => ref.watch(
      settingsProvider.select((s) => (s[key] as bool?) ?? fallback),
    );
    final syncEnabled =
        syncAsync.asData?.value.enabled ??
        storedFlag(SettingsKeys.syncEnabled, DefaultSettings.syncEnabled);
    final syncAutoOnStartup =
        syncAsync.asData?.value.autoOnStartup ??
        storedFlag(
          SettingsKeys.syncAutoOnStartup,
          DefaultSettings.syncAutoOnStartup,
        );
    final nextBackupTime = ref.watch(nextAutoBackupTimeProvider);
    final databaseSwitching = ref.watch(databaseSwitchingProvider);
    bool shows(SettingsSearchGroup group) =>
        shouldShowSettingsGroup(widget.searchQuery, group);

    return SettingsSectionGroups(
      attachesToAbove: widget.attachesToAbove,
      entries: [
        // Data Management (Backup/Restore)
        SectionGroupEntry(
          visible: shows(DatabaseSection.dataManagementSearchGroup),
          builder: (position, isAlternate) => SectionGroupBox(
            title: DatabaseSection.dataManagementSearchGroup.title,
            titleIcon: Icons.backup,
            searchQuery: widget.searchQuery,
            groupPosition: position,
            alternateBackground: isAlternate,
            // The section's own title names it.
            showTitle: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: kElementVSpacing,
              children: [
                // The active file's name; a tap opens the Change Database
                // dialog, which also shows the full path.
                TintedOptionTile(
                  icon: DatabaseSection.activeDatabaseSpec.icon,
                  title: DatabaseSection.activeDatabaseSpec.label,
                  subtitle: _isLoading
                      ? null
                      : 'Current: ${p.basename(_activeDbPath)}',
                  onTap: _isLoading || databaseSwitching
                      ? null
                      : () => showChangeDatabaseDialog(context),
                ),
                // The countdown to the next auto backup stays current.
                _EveryMinute(
                  enabled: nextBackupTime != null,
                  builder: (context) => TintedOptionTile(
                    icon: DatabaseSection.backupManagerSpec.icon,
                    title: DatabaseSection.backupManagerSpec.label,
                    subtitle: switch (nextBackupTime) {
                      final next? => _formatNextBackupTime(next),
                      null => 'Auto backup is off',
                    },
                    onTap: databaseSwitching
                        ? null
                        : () => showBackupDialog(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Database Sync
        SectionGroupEntry(
          visible: shows(DatabaseSection.databaseSyncSearchGroup),
          builder: (position, isAlternate) => SectionGroupBox(
            title: DatabaseSection.databaseSyncSearchGroup.title,
            titleIcon: Icons.sync,
            headerCrossAxisAlignment: CrossAxisAlignment.center,
            searchQuery: widget.searchQuery,
            groupPosition: position,
            alternateBackground: isAlternate,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: kElementVSpacing,
              children: [
                TintedOptionTile(
                  icon: DatabaseSection.deviceSyncSpec.icon,
                  title: DatabaseSection.deviceSyncSpec.label,
                  subtitle:
                      switch (syncAsync.asData?.value.trustedPeers.length) {
                        null => null,
                        0 => 'No paired devices',
                        1 => '1 paired device',
                        final count => '$count paired devices',
                      },
                  onTap: () => showDeviceSyncDialog(context),
                ),
                buildSpecToggleSettingList(
                  theme: context.appTheme,
                  entries: [
                    (
                      spec: DatabaseSection.enableLocalDeviceSyncSpec,
                      value: syncEnabled,
                      onChanged: syncNotifier.setEnabled,
                    ),
                    (
                      spec: DatabaseSection.autoSyncOnStartupSpec,
                      value: syncAutoOnStartup,
                      onChanged: syncEnabled
                          ? syncNotifier.setAutoOnStartup
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Key Security
        SectionGroupEntry(
          visible: shows(DatabaseSection.keyVisibilitySearchGroup),
          builder: (position, isAlternate) => _EncryptionControls(
            builder: (passwordAction, encryptionCards) => SectionGroupBox(
              title: DatabaseSection.keyVisibilitySearchGroup.title,
              titleIcon: Icons.security,
              headerCrossAxisAlignment: CrossAxisAlignment.center,
              trailing: SettingsHeaderActionRow(
                children: [
                  ?passwordAction,
                  SettingsInfoButton(
                    message: DatabaseSection.keyVisibilitySearchGroup.info!,
                  ),
                ],
              ),
              searchQuery: widget.searchQuery,
              groupPosition: position,
              alternateBackground: isAlternate,
              child: SettingsControlWrap(
                children: [
                  ...encryptionCards,
                  for (final (spec, value, key) in [
                    (
                      DatabaseSection.maskKeysSpec,
                      security.maskKeys,
                      SettingsKeys.maskKeys,
                    ),
                    (
                      DatabaseSection.autoHideKeysSpec,
                      security.autoHideKeys,
                      SettingsKeys.autoHideKeys,
                    ),
                    if (PlatformFileActions.isMobilePlatform)
                      (
                        DatabaseSection.hideInRecentsSpec,
                        security.hideInRecents,
                        SettingsKeys.hideInRecents,
                      ),
                  ])
                    SettingsToggleCard(
                      label: spec.label,
                      icon: spec.icon,
                      value: value,
                      onChanged: settingsNotifier.setter(key),
                    ),
                  SettingsChoiceCard<int>(
                    label: DatabaseSection.autoLockSpec.label,
                    icon: DatabaseSection.autoLockSpec.icon,
                    value: security.autoLockMinutes,
                    choices: const [
                      SettingsChoice(5, '5 minutes'),
                      SettingsChoice(15, '15 minutes'),
                      SettingsChoice(0, 'No limit'),
                    ],
                    onChanged: settingsNotifier.setter(
                      SettingsKeys.autoLockMinutes,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class const _ChangeDatabaseDialog({required final ProviderContainer container})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ChangeDatabaseDialog> createState() =>
      _ChangeDatabaseDialogState();
}

class _ChangeDatabaseDialogState extends ConsumerState<_ChangeDatabaseDialog>
    with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  bool _isLoading = true;
  String _defaultDbPath = '';
  String _activeDbPath = '';
  String _activeFilePath = '';
  Map<String, DatabaseFileInfo> _databaseFiles = {};
  Timer? _fileRefreshTimer;
  bool _refreshingFiles = false;
  bool _choosingFile = false;

  /// Set once the first read has taken long enough to need a spinner.
  bool _slowLoad = false;
  Timer? _slowLoadTimer;

  @override
  void initState() {
    super.initState();
    final preview = AppDialogPreviewScope.maybeOf(context);
    if (preview != null) {
      _databaseFiles = preview.databaseFiles;
      _defaultDbPath = _databaseFiles.keys.first;
      _activeDbPath = _defaultDbPath;
      _activeFilePath = _databaseFiles[_activeDbPath]!.path;
      _isLoading = false;
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    // Skip disk checks while the window is hidden; resuming refreshes at once.
    _fileRefreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final state = WidgetsBinding.instance.lifecycleState;
      if (state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused) {
        return;
      }
      _refreshDatabaseFiles();
    });
    _slowLoadTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _isLoading) setState(() => _slowLoad = true);
    });
    _init();
  }

  Future<void> _init() async {
    final configuredPath = widget.container.read(currentDatabasePathProvider);
    final defaultPath = await AppDatabase.getDatabasePath();
    final resolvedPath = configuredPath.isNotEmpty
        ? configuredPath
        : defaultPath;
    if (!mounted) return;
    _defaultDbPath = defaultPath;
    _activeDbPath = resolvedPath;
    await _refreshDatabaseFiles();
  }

  Future<void> _refreshDatabaseFiles() async {
    if (!mounted || _refreshingFiles || _activeDbPath.isEmpty) return;
    _refreshingFiles = true;
    try {
      final paths = {
        _activeDbPath,
        ...widget.container.read(securitySettingsProvider).recentDatabasePaths,
      };
      final entries = await Future.wait(
        paths.map(
          (path) async => MapEntry(path, await inspectDatabaseFile(path)),
        ),
      );
      if (!mounted) return;
      final files = Map.fromEntries(entries);
      if (_isLoading ||
          files.length != _databaseFiles.length ||
          files.entries.any(
            (entry) => _databaseFiles[entry.key] != entry.value,
          )) {
        setState(() {
          _databaseFiles = files;
          _activeFilePath = files[_activeDbPath]!.path;
          _isLoading = false;
        });
      }
    } finally {
      _refreshingFiles = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshDatabaseFiles();
  }

  @override
  void dispose() {
    _fileRefreshTimer?.cancel();
    _slowLoadTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _openCurrentFolder() async {
    if (_activeFilePath.isEmpty) return;
    try {
      final opened = await PlatformFileActions.openDirectory(
        p.dirname(_activeFilePath),
      );
      if (!opened) {
        NotificationManager.instance.error('Failed to open database folder');
      }
    } catch (error) {
      NotificationManager.instance.error(
        'Failed to open database folder: $error',
      );
    }
  }

  Future<void> _switchTo(String path) async => await widget.container
      .read(databaseSwitchCallbackProvider)
      ?.call(OpenDatabaseRequest(path));

  Future<void> _openDatabase() async {
    if (_choosingFile) return;
    setState(() => _choosingFile = true);
    try {
      final result = await FilePicker.pickFile(
        dialogTitle: 'Open UniKM Database',
      );
      if (!mounted) return;
      final selectedPath = result?.path;
      if (selectedPath == null || selectedPath.isEmpty) return;
      await _openDatabasePath(selectedPath);
    } finally {
      if (mounted) {
        setState(() => _choosingFile = false);
        _refreshDatabaseFiles();
      }
    }
  }

  Future<void> _openDatabasePath(String selectedPath) async {
    if (_isLoading) return;
    final lower = selectedPath.toLowerCase();
    final hasValidExt = lower.endsWith('.db') || lower.endsWith('.enc');
    if (!hasValidExt && !await isLikelySqliteFile(selectedPath)) {
      NotificationManager.instance.error(
        'Unsupported file type. Please select a .db or .enc file.',
      );
      return;
    }
    if (!mounted ||
        widget.container.read(databaseSwitchCallbackProvider) == null) {
      return;
    }
    Navigator.pop(context);
    await _switchTo(selectedPath);
  }

  Future<void> _removeRecentDatabasePath(String baseDbPath) async {
    final recents = List<String>.from(
      widget.container.read(securitySettingsProvider).recentDatabasePaths,
    );
    if (!recents.remove(baseDbPath)) return;
    await widget.container
        .read(settingsProvider.notifier)
        .set(SettingsKeys.recentDatabasePaths, recents);
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
    final theme = context.appTheme;
    String basePath(String path) => p.normalize(
      path.endsWith('.enc') ? path.substring(0, path.length - 4) : path,
    );
    final recents = ref
        .watch(securitySettingsProvider)
        .recentDatabasePaths
        .where((path) => basePath(path) != basePath(_activeDbPath))
        .toList();

    final VoidCallback? chooseDefault =
        _isLoading || _defaultDbPath.isEmpty || _defaultDbPath == _activeDbPath
        ? null
        : () async {
            Navigator.pop(context);
            await _switchTo(_defaultDbPath);
          };
    return LayoutBuilder(
      builder: (context, constraints) => ThemedAlertDialog(
        backgroundColor: theme.background,
        maxWidth: 520,
        maxHeight: 600,
        fullscreen: constraints.maxHeight < 480,
        titleActions: constraints.maxHeight < 480
            ? [
                IconButton(
                  tooltip: 'Use Default',
                  onPressed: chooseDefault,
                  icon: const Icon(Icons.restore),
                ),
              ]
            : null,
        title: DialogHeader(icon: Icons.swap_horiz, title: 'Change Database'),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FileDropField(
              key: const ValueKey('change-database-drop'),
              description: 'Supports .db, .enc and extensionless SQLite files',
              enabled: !_isLoading && !_choosingFile,
              onBrowse: _openDatabase,
              onFileSelected: (path) async {
                if (_choosingFile) return;
                setState(() => _choosingFile = true);
                try {
                  await _openDatabasePath(path);
                } finally {
                  if (mounted) setState(() => _choosingFile = false);
                }
              },
              invalidDropMessage: 'Drop one .db or .enc database file.',
            ),
            // Nothing until the files are read, so rows never show before
            // their details (or the current database among the recent
            // ones); a slow read shows a spinner.
            if (_isLoading)
              Expanded(
                child: _slowLoad
                    ? const Center(
                        child: AppCircularProgressIndicator(size: 20),
                      )
                    : const SizedBox.shrink(),
              )
            else ...[
              const SizedBox(height: 16),
              TintedHeading(title: 'Current'),
              const SizedBox(height: 8),
              DatabaseFileRow(
                title: p.basename(_activeFilePath),
                subtitle: _activeFilePath,
                isEncrypted:
                    _databaseFiles[_activeDbPath]?.isEncrypted ?? false,
                available: _databaseFiles[_activeDbPath]?.exists ?? false,
                highlighted: true,
                margin: EdgeInsets.zero,
                actions: [
                  IconButton(
                    onPressed: _activeFilePath.isEmpty
                        ? null
                        : _openCurrentFolder,
                    tooltip: 'Open database folder',
                    icon: const Icon(Icons.folder_open),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TintedHeading(title: 'Recent', trailing: '${recents.length}'),
              const SizedBox(height: 8),
              Expanded(
                child: recents.isEmpty
                    ? Text(
                        'No other recent databases.',
                        style: TextStyle(color: theme.textSecondary),
                      )
                    : AppScrollbar(
                        controller: _scrollController,
                        child: ListView.builder(
                          controller: _scrollController,
                          primary: false,
                          itemCount: recents.length,
                          itemBuilder: (context, index) {
                            final basePath = recents[index];
                            final file = _databaseFiles[basePath];
                            final resolvedPath = file?.path ?? basePath;
                            final sizeBytes = file?.sizeBytes;

                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onSecondaryTapDown: (details) =>
                                  showAppContextMenu(
                                    context: context,
                                    theme: theme,
                                    position: details.globalPosition,
                                    menuChildren: [
                                      appMenuItem(
                                        theme,
                                        onPressed: () =>
                                            _removeRecentDatabasePath(basePath),
                                        child: const Text(
                                          'Remove from recents',
                                        ),
                                      ),
                                    ],
                                  ),
                              child: DatabaseFileRow(
                                key: ValueKey(basePath),
                                title: p.basename(resolvedPath),
                                subtitle: sizeBytes == null
                                    ? resolvedPath
                                    : '${_formatBytes(sizeBytes)} • $resolvedPath',
                                isEncrypted: file?.isEncrypted ?? false,
                                available: file?.exists ?? false,
                                onTap: file?.exists == true
                                    ? () async {
                                        Navigator.pop(context);
                                        await _switchTo(resolvedPath);
                                      }
                                    : null,
                                actions: [
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete,
                                      color: theme.secondary,
                                    ),
                                    tooltip: 'Remove from recents',
                                    onPressed: () =>
                                        _removeRecentDatabasePath(basePath),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ],
        ),
        actions: constraints.maxHeight < 480
            ? null
            : [
                OutlinedButton.icon(
                  onPressed: chooseDefault,
                  icon: const Icon(Icons.restore),
                  label: const Text('Use Default'),
                ),
                ElevatedButton.icon(
                  onPressed: _isLoading || _choosingFile ? null : _openDatabase,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open…'),
                ),
              ],
      ),
    );
  }
}

// =============================================================================
// PUBLIC HELPER — callable from anywhere in the app
// =============================================================================

Future<void> showChangeDatabaseDialog(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  return showAppDialog<void>(
    context: context,
    builder: (ctx) => _ChangeDatabaseDialog(container: container),
  );
}

/// Rebuilds once a minute while [enabled], so a countdown stays current.
class const _EveryMinute({
  required final bool enabled,
  required final WidgetBuilder builder,
}) extends StatefulWidget {
  @override
  State<_EveryMinute> createState() => _EveryMinuteState();
}

class _EveryMinuteState extends State<_EveryMinute> {
  Timer? _timer;

  void _sync() {
    _timer?.cancel();
    _timer = widget.enabled
        ? Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}))
        : null;
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_EveryMinute oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
