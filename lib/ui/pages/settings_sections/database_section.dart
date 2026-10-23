/// Database & security settings section.
library;

import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../app/application/database_encryption_controller.dart';
import '../../../app/application/database_session_loader.dart';
import '../../../core/database/sqlite_file.dart';
import '../../../core/database/database.dart';
import '../../../core/services/backup_service.dart';
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
import '../../widgets/app_radio_list_tile.dart';
import '../../widgets/file_drop_field.dart';
import '../../dialogs/import_export_dialog.dart';
import '../../dialogs/device_sync_dialog.dart';
import '../../widgets/dialog_helpers.dart';
import '../../widgets/database_file_row.dart';
import '../../widgets/notification_system.dart';
import '../../widgets/popup_menu_helpers.dart';
import '../../widgets/section_groupbox.dart';
import '../../widgets/settings_header_actions.dart';
import '../../../core/constants/app_constants.dart';
import 'settings_common.dart';
import 'settings_control_cards.dart';

/// Shows a dialog that asks the user which kind of database to create.
///
/// Returns the selected database creation config or `null` if cancelled.
class CreateDatabaseChoiceResult {
  const CreateDatabaseChoiceResult({required this.encrypted, this.fileName});

  final bool encrypted;
  final String? fileName;
}

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
                  SectionGroupBox(
                    title: 'Database Type',
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
                          AppRadioListTile<String>(
                            theme: theme,
                            value: 'unencrypted',
                            title: 'Unencrypted database',
                            subtitle:
                                'Creates a standard SQLite database file.',
                          ),
                          AppRadioListTile<String>(
                            theme: theme,
                            value: 'encrypted',
                            title: 'Encrypted database',
                            subtitle:
                                'Creates an encrypted database that requires a password.',
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
                ElevatedButton(
                  onPressed: () {
                    final trimmedFileName = fileNameController.text.trim();
                    if (useMobileLayout && trimmedFileName.isEmpty) {
                      setState(
                        () => fileNameError = 'Please enter a file name',
                      );
                      return;
                    }
                    Navigator.pop(
                      ctx,
                      CreateDatabaseChoiceResult(
                        encrypted: selectedType == 'encrypted',
                        fileName: trimmedFileName.isEmpty
                            ? null
                            : trimmedFileName,
                      ),
                    );
                  },
                  style: themedFilledButtonStyle(theme),
                  child: const Text('Create'),
                ),
              ],
            );
          },
        ),
      );
    },
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
class DatabaseHeaderActions extends ConsumerWidget {
  const DatabaseHeaderActions({super.key, this.expanded = false});

  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final buttons = <Widget>[
      SettingsHeaderAction(
        theme: theme,
        icon: Icons.download,
        tooltip: 'Import DB',
        onTap: () => showImportDialog(context),
      ),
      SettingsHeaderAction(
        theme: theme,
        icon: Icons.upload,
        tooltip: 'Export DB',
        onTap: () => showExportDialog(context),
      ),
      SettingsHeaderAction(
        theme: theme,
        icon: Icons.note_add,
        tooltip: 'New DB',
        onTap: ref.watch(databaseSwitchingProvider)
            ? null
            : () => _createDatabase(context, ref),
      ),
    ];
    return SettingsHeaderActions(
      theme: theme,
      expanded: expanded,
      children: buttons,
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

class _DatabaseEncryptionButton extends ConsumerStatefulWidget {
  const _DatabaseEncryptionButton({required this.theme});
  final AppThemeData theme;

  @override
  ConsumerState<_DatabaseEncryptionButton> createState() =>
      _DatabaseEncryptionButtonState();
}

class _DatabaseEncryptionButtonState
    extends ConsumerState<_DatabaseEncryptionButton> {
  bool _opening = false;
  bool _hovering = false;

  Future<void> _open() async {
    if (_opening) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final theme = widget.theme;
    final configuredPath = container.read(currentDatabasePathProvider);
    setState(() => _opening = true);
    try {
      final path = DatabaseSessionLoader.basePath(
        configuredPath.isNotEmpty
            ? configuredPath
            : await AppDatabase.getDatabasePath(),
      );
      if (!mounted) return;
      final manager = container.read(encryptionManagerProvider(path));
      final controller = DatabaseEncryptionController(container, manager);
      if (manager.isEncrypted) {
        await EncryptionManagementDialog.show(
          context,
          theme,
          onDisable: controller.disable,
          onChangePassword: controller.changePassword,
        );
      } else {
        final password = await EnableEncryptionDialog.show(
          context,
          theme,
          manager,
        );
        if (password != null) await controller.enable(password);
      }
    } catch (error) {
      NotificationManager.instance.error('Failed to update encryption: $error');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final encrypted =
        ref.watch(_activeEncryptionStateProvider) == EncryptionState.encrypted;
    final switching = ref.watch(databaseSwitchingProvider);
    final enabled = !_opening && !switching;
    final showLocked = encrypted != (_hovering && enabled);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: IconButton(
        tooltip: encrypted ? 'Manage Encryption' : 'Enable Encryption',
        style: widget.theme.compactIconButtonStyle,
        onPressed: enabled ? _open : null,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Icon(
            showLocked ? Icons.lock : Icons.lock_open,
            key: ValueKey(showLocked),
            color: showLocked
                ? widget.theme.accent
                : widget.theme.textSecondary,
            size: 26,
          ),
        ),
      ),
    );
  }
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
    description: 'Allows LAN discovery between devices.',
  );
  static const SettingTextSpec autoSyncOnStartupSpec = SettingTextSpec(
    label: 'Auto-sync on Startup',
    description: 'Try syncing trusted devices when the app opens.',
  );

  static const SettingsSearchGroup dataManagementSearchGroup =
      SettingsSearchGroup(
        title: 'Data Management',
        settings: [activeDatabaseSpec],
        extraTexts: [
          'Encryption',
          'Enable Encryption',
          'Disable Encryption',
          'Change Password',
          'Import DB',
          'Export DB',
          'Change DB',
          'New DB',
          'Next Auto Backup',
          'Backup Manager',
          'Open Backup Manager',
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
        extraTexts: ['Device Sync'],
      );

  @override
  ConsumerState<DatabaseSection> createState() => _DatabaseSectionState();
}

class _DatabaseSectionState extends ConsumerState<DatabaseSection> {
  bool _isLoading = true;
  String _activeDbPath = '';
  final _backupInfoKey = GlobalKey<TooltipState>();
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
        final labelWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
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
          ],
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    labelWidget,
                    const SizedBox(height: kElementVSpacing),
                    Align(alignment: Alignment.centerRight, child: trailing),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: labelWidget),
                    const SizedBox(width: kElementHSpacing),
                    trailing,
                  ],
                ),
        );
      },
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
    final nextBackupTime = ref.watch(nextAutoBackupTimeProvider);
    final databaseSwitching = ref.watch(databaseSwitchingProvider);
    final isSearching = widget.searchQuery.trim().isNotEmpty;
    final showDataManagement = shouldShowSettingsGroup(
      query: widget.searchQuery,
      matchesSearch: widget.matchesSearch,
      group: DatabaseSection.dataManagementSearchGroup,
    );
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
        !showDataManagement &&
        !showDatabaseSync &&
        !showKeyVisibility) {
      return const SizedBox.shrink();
    }

    return SettingsSectionGroups(
      attachesToAbove: widget.attachesToAbove,
      entries: [
        // Data Management (Backup/Restore)
        SectionGroupEntry(
          visible: showDataManagement,
          builder: (position, isAlternate) => _buildDataManagementSection(
            nextBackupTime: nextBackupTime,
            databaseSwitching: databaseSwitching,
            searchQuery: widget.searchQuery,
            isSearchMatch: isSearching,
            groupPosition: position,
            alternateBackground: isAlternate,
          ),
        ),
        // Database Sync
        SectionGroupEntry(
          visible: showDatabaseSync,
          builder: (position, isAlternate) => SectionGroupBox(
            title: DatabaseSection.databaseSyncSearchGroup.title,
            theme: widget.theme,
            titleIcon: Icons.sync,
            headerCrossAxisAlignment: CrossAxisAlignment.center,
            trailing: IconButton(
              tooltip: 'Device Sync',
              style: widget.theme.compactIconButtonStyle,
              icon: const Icon(Icons.sync, size: 26),
              color: widget.theme.accent,
              onPressed: () => showDeviceSyncDialog(context),
            ),
            searchQuery: widget.searchQuery,
            isSearchMatch: isSearching,
            groupPosition: position,
            alternateBackground: isAlternate,
            child: SettingsControlWrap(
              children: [
                SettingsToggleCard(
                  theme: widget.theme,
                  label: DatabaseSection.enableLocalDeviceSyncSpec.label,
                  description:
                      DatabaseSection.enableLocalDeviceSyncSpec.description,
                  value: syncEnabled,
                  onChanged: (value) {
                    syncNotifier.setEnabled(value);
                  },
                ),
                SettingsToggleCard(
                  theme: widget.theme,
                  label: DatabaseSection.autoSyncOnStartupSpec.label,
                  description:
                      DatabaseSection.autoSyncOnStartupSpec.description,
                  value: syncAutoOnStartup,
                  onChanged: syncEnabled
                      ? (value) => syncNotifier.setAutoOnStartup(value)
                      : null,
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
            child: SettingsControlWrap(
              children: [
                SettingsToggleCard(
                  theme: widget.theme,
                  label: DatabaseSection.maskKeysSpec.label,
                  description: DatabaseSection.maskKeysSpec.description,
                  value: security.maskKeys,
                  onChanged: (value) =>
                      settingsNotifier.setSetting(SettingsKeys.maskKeys, value),
                ),
                SettingsToggleCard(
                  theme: widget.theme,
                  label: DatabaseSection.autoHideKeysSpec.label,
                  description: DatabaseSection.autoHideKeysSpec.description,
                  value: security.autoHideKeys,
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

  Widget _buildDataManagementSection({
    required String searchQuery,
    required DateTime? nextBackupTime,
    required bool databaseSwitching,
    required bool isSearchMatch,
    SectionGroupPosition groupPosition = SectionGroupPosition.only,
    bool alternateBackground = false,
  }) {
    return SectionGroupBox(
      title: DatabaseSection.dataManagementSearchGroup.title,
      theme: widget.theme,
      titleIcon: Icons.backup,
      headerBottomPadding: 0,
      searchQuery: searchQuery,
      isSearchMatch: isSearchMatch,
      groupPosition: groupPosition,
      alternateBackground: alternateBackground,
      headerCrossAxisAlignment: CrossAxisAlignment.center,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: kElementHSpacing,
        children: [
          _DatabaseEncryptionButton(theme: widget.theme),
          IconButton(
            tooltip: 'Backup Manager',
            style: widget.theme.compactIconButtonStyle,
            color: widget.theme.accent,
            icon: const Icon(Icons.backup, size: 26),
            onPressed: databaseSwitching
                ? null
                : () => showBackupDialog(context),
          ),
          if (nextBackupTime != null)
            Tooltip(
              key: _backupInfoKey,
              message:
                  'Next auto backup: ${_formatNextBackupTime(nextBackupTime)}',
              child: IconButton(
                style: widget.theme.compactIconButtonStyle,
                icon: const Icon(Icons.info_outline, size: 26),
                color: widget.theme.accent,
                onPressed: () =>
                    _backupInfoKey.currentState?.ensureTooltipVisible(),
              ),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(
            key: const ValueKey('data-management-separator'),
            height: 8,
            color: widget.theme.border,
          ),
          _buildResponsiveSettingRow(
            label: DatabaseSection.activeDatabaseSpec.label,
            description: _activeDbPath,
            trailingBuilder: (stacked) => Row(
              mainAxisSize: MainAxisSize.min,
              spacing: kElementHSpacing,
              children: [
                if (_isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: AppCircularProgressIndicator(),
                  ),
                IconButton(
                  tooltip: 'Change DB',
                  style: widget.theme.compactIconButtonStyle,
                  icon: const Icon(Icons.swap_horiz, size: 26),
                  color: widget.theme.accent,
                  onPressed: databaseSwitching
                      ? null
                      : () => showChangeDatabaseDialog(context, widget.theme),
                ),
              ],
            ),
          ),
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
    _fileRefreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshDatabaseFiles(),
    );
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

  Future<void> _useDefaultDatabase() async {
    if (_defaultDbPath.isEmpty || _defaultDbPath == _activeDbPath) return;
    final callback = widget.container.read(databaseSwitchCallbackProvider);
    if (callback == null) return;
    await callback(OpenDatabaseRequest(_defaultDbPath));
  }

  Future<void> _openDatabase() async {
    if (_choosingFile) return;
    setState(() => _choosingFile = true);
    try {
      final result = await FilePicker.pickFile(
        dialogTitle: 'Open UniKM Database',
        type: FileType.any,
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
    if (!mounted) return;
    final callback = widget.container.read(databaseSwitchCallbackProvider);
    if (callback == null) return;
    Navigator.pop(context);
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
            await _useDefaultDatabase();
          };
    return LayoutBuilder(
      builder: (context, constraints) => ThemedAlertDialog(
        theme: widget.theme,
        backgroundColor: widget.theme.background,
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
        title: DialogHeader(
          icon: Icons.swap_horiz,
          title: 'Change Database',
          theme: widget.theme,
          showCloseButton: false,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FileDropField(
              key: const ValueKey('change-database-drop'),
              theme: widget.theme,
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
            const SizedBox(height: 12),
            SectionGroupBox(
              title: 'Current',
              titleIcon: Icons.storage,
              titleLocation: SectionTitleLocation.top,
              theme: widget.theme,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: AppCircularProgressIndicator(),
                    )
                  : DatabaseFileRow(
                      theme: widget.theme,
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
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SectionGroupBox(
                title: 'Recent',
                titleIcon: Icons.history,
                titleLocation: SectionTitleLocation.top,
                theme: widget.theme,
                child: recents.isEmpty
                    ? Text(
                        'No other recent databases.',
                        style: TextStyle(color: widget.theme.textSecondary),
                      )
                    : Scrollbar(
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
                              onSecondaryTapDown: (details) async {
                                final overlay =
                                    Overlay.of(
                                          context,
                                        ).context.findRenderObject()
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
                              child: DatabaseFileRow(
                                key: ValueKey(basePath),
                                theme: widget.theme,
                                title: p.basename(resolvedPath),
                                subtitle: sizeBytes == null
                                    ? resolvedPath
                                    : '${_formatBytes(sizeBytes)} • $resolvedPath',
                                isEncrypted: file?.isEncrypted ?? false,
                                available: file?.exists ?? false,
                                onTap: file?.exists == true
                                    ? () async {
                                        Navigator.pop(context);
                                        await _openRecentDatabase(resolvedPath);
                                      }
                                    : null,
                                actions: [
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete_outline,
                                      color: widget.theme.secondary,
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
            ),
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

Future<void> showChangeDatabaseDialog(
  BuildContext context,
  AppThemeData theme,
) {
  final container = ProviderScope.containerOf(context, listen: false);
  return showAppDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _ChangeDatabaseDialog(theme: theme, container: container),
  );
}
