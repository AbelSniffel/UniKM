/// Backup and restore dialogs for database management
library;

import '../widgets/window_drop_target.dart';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../widgets/app_tab_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/database/database.dart';
import '../../core/database/sqlite_file.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/database_switching.dart';
import '../../core/services/database_file_info.dart';
import '../widgets/database_file_row.dart';
import '../widgets/section_groupbox.dart';
import '../../core/settings/settings_model.dart';
import '../../core/services/platform_file_actions.dart';
import '../../providers/app_providers.dart';
import '../pages/settings_sections/settings_common.dart';
import '../widgets/app_progress_indicator.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/notification_system.dart';
import '../widgets/password_field.dart';
import 'database_unlock_dialog.dart';
import '../../core/constants/app_constants.dart';

/// Show the backup management dialog
Future<void> showBackupDialog(BuildContext context, {int initialTab = 0}) {
  return showAppDialog(
    context: context,
    builder: (context) => _BackupDialog(initialTab: initialTab),
  );
}

Future<void> _reloadDatabaseFromSettings(
  ProviderContainer container, {
  String? password,
}) async {
  final callback = container.read(databaseSwitchCallbackProvider);
  if (callback == null) {
    NotificationManager.instance.error(
      'Database reload is not available right now',
    );
    return;
  }

  final configuredPath = container.read(currentDatabasePathProvider);
  final basePath = configuredPath.isNotEmpty
      ? configuredPath
      : await AppDatabase.getDatabasePath();

  container.read(databaseSwitchingProvider.notifier).set(true);
  try {
    await callback(OpenDatabaseRequest(basePath, password: password));
  } catch (e) {
    NotificationManager.instance.error('Failed to reload database: $e');
  } finally {
    container.read(databaseSwitchingProvider.notifier).set(false);
  }
}

/// Backup management dialog
class _BackupDialog extends ConsumerStatefulWidget {
  const _BackupDialog({this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<_BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends ConsumerState<_BackupDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _backupInfoKey = GlobalKey<TooltipState>();
  bool _isCreatingBackup = false;
  List<BackupInfo> _backups = [];
  bool _isLoading = true;
  String? _selectedBackupPath;
  int _fileSelectionRevision = 0;
  String? _selectedBackupName;
  bool _isEncryptedBackup = false;
  bool _createBackupFirst = true;
  final _passwordController = TextEditingController();
  bool _isRestoring = false;
  bool _isDragging = false;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      initialIndex: widget.initialTab,
      vsync: this,
      animationDuration: kTabTransition,
    )..addListener(_onTabChanged);
    _loadBackups();
  }

  void _onTabChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadBackups() async {
    setState(() => _isLoading = true);
    try {
      final backupService = ref.read(backupServiceProvider);
      final backups = await backupService.listBackups();
      if (mounted) {
        setState(() {
          _backups = backups;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        NotificationManager.instance.error('Failed to load backups: $e');
      }
    }
  }

  Future<void> _createBackup() async {
    setState(() => _isCreatingBackup = true);
    try {
      final backupService = ref.read(backupServiceProvider);
      final result = await backupService.createBackup();
      if (result.success) {
        NotificationManager.instance.success(
          'Backup created: ${result.backupInfo?.fileName}',
        );
        await _loadBackups();
      } else {
        NotificationManager.instance.error(
          result.error ?? 'Failed to create backup',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreatingBackup = false);
      }
    }
  }

  Future<void> _deleteBackup(BackupInfo backup) async {
    final theme = ref.read(themeProvider);
    final confirmed = await showConfirmDialog(
      context: context,
      theme: theme,
      title: 'Delete Backup',
      titleIcon: Icons.delete_forever,
      message: 'Are you sure you want to delete "${backup.fileName}"?',
      confirmLabel: 'Delete',
      destructive: true,
    );

    if (confirmed) {
      final backupService = ref.read(backupServiceProvider);
      final deleted = await backupService.deleteBackup(backup.filePath);
      if (deleted) {
        NotificationManager.instance.success('Backup deleted');
        await _loadBackups();
      } else {
        NotificationManager.instance.error('Failed to delete backup');
      }
    }
  }

  Future<void> _openBackupFolder() async {
    try {
      final backupService = ref.read(backupServiceProvider);
      final backupsDir = await backupService.getBackupsDirectory();
      final opened = await PlatformFileActions.openDirectory(backupsDir.path);
      if (!opened && PlatformFileActions.isMobilePlatform) {
        await PlatformFileActions.shareText(
          'UniKM backups directory: ${backupsDir.path}',
          subject: 'UniKM backups directory',
        );
        NotificationManager.instance.info(
          'Shared the backups folder path because the platform could not open it directly',
        );
        return;
      }

      if (!opened) {
        NotificationManager.instance.error('Failed to open backup folder');
      }
    } catch (e) {
      NotificationManager.instance.error('Failed to open backup folder: $e');
    }
  }

  Future<void> _selectBackupFile() async {
    final result = await FilePicker.pickFile(
      type: FileType.any,
      dialogTitle: 'Select Backup File',
    );

    if (result != null && result.path != null) {
      await _handleFilePath(result.path!);
    }
  }

  Future<void> _handleFilePath(String path) async {
    if (_isRestoring) return;
    final revision = ++_fileSelectionRevision;
    final lower = path.toLowerCase();
    if (!lower.endsWith('.db') &&
        !lower.endsWith('.enc') &&
        !(p.extension(path).isEmpty && await isLikelySqliteFile(path))) {
      if (!mounted || revision != _fileSelectionRevision) return;
      setState(() => _isDragging = false);
      NotificationManager.instance.error(
        'Unsupported file type. Select a SQLite database or .enc file.',
      );
      return;
    }
    final info = await inspectDatabaseFile(
      path,
      resolveEncryptedSibling: false,
    );
    if (!mounted || revision != _fileSelectionRevision) return;
    setState(() {
      _isDragging = false;
      _selectedBackupPath = path;
      _selectedBackupName = p.basename(path);
      _isEncryptedBackup = info.isEncrypted;
    });
  }

  void _clearFileSelection() {
    if (_isRestoring) return;
    ++_fileSelectionRevision;
    _passwordController.clear();
    setState(() {
      _selectedBackupPath = null;
      _selectedBackupName = null;
      _isEncryptedBackup = false;
      _isDragging = false;
    });
  }

  Future<void> _restoreFromSelectedFile() async {
    if (_selectedBackupPath == null) {
      NotificationManager.instance.error('Please select a backup file');
      return;
    }

    if (_isEncryptedBackup && _passwordController.text.isEmpty) {
      NotificationManager.instance.error(
        'Password is required for encrypted backups',
      );
      return;
    }

    setState(() => _isRestoring = true);

    try {
      final backupService = ref.read(backupServiceProvider);
      final result = await backupService.restoreBackup(
        backupPath: _selectedBackupPath!,
        password: _isEncryptedBackup ? _passwordController.text : null,
        createBackupFirst: _createBackupFirst,
      );

      if (result.success) {
        if (!mounted) return;
        final container = ProviderScope.containerOf(context, listen: false);
        Navigator.pop(context);
        await _reloadDatabaseFromSettings(
          container,
          password: _isEncryptedBackup ? _passwordController.text : null,
        );
        NotificationManager.instance.success('Backup restored and reloaded');
      } else {
        NotificationManager.instance.error(
          result.error ?? 'Failed to restore backup',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final backupSettings = ref.watch(backupSettingsProvider);
    final maxBackups = backupSettings.maxCount;
    final supportsDragAndDrop = PlatformFileActions.supportsDragAndDrop;

    return ThemedAlertDialog(
      theme: theme,
      maxWidth: 600,
      maxHeight: 700,
      title: DialogHeader(
        icon: Icons.backup,
        title: 'Backup Manager',
        theme: theme,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTabBar(
            theme: theme,
            controller: _tabController,
            tabs: [
              AppTab('Backups (${_backups.length}/$maxBackups)'),
              const AppTab('Restore from File'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: AppTabView(
              controller: _tabController,
              children: [
                SectionGroupBox(
                  title: 'Backups',
                  titleIcon: Icons.backup_outlined,
                  titleLocation: SectionTitleLocation.top,
                  theme: theme,
                  headerCrossAxisAlignment: CrossAxisAlignment.center,
                  trailing: Tooltip(
                    key: _backupInfoKey,
                    message:
                        'Maximum $maxBackups backups are kept. Oldest backups are automatically deleted.',
                    child: IconButton(
                      style: theme.compactIconButtonStyle,
                      icon: const Icon(Icons.info_outline, size: 26),
                      color: theme.accent,
                      onPressed: () =>
                          _backupInfoKey.currentState?.ensureTooltipVisible(),
                    ),
                  ),
                  child: _isLoading
                      ? const Center(child: AppCircularProgressIndicator())
                      : _backups.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.backup_outlined,
                                size: 48,
                                color: theme.textSecondary.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No backups yet',
                                style: TextStyle(color: theme.textSecondary),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _backups.length,
                          itemBuilder: (listContext, index) {
                            final backup = _backups[index];
                            return DatabaseFileRow(
                              key: ValueKey(backup.filePath),
                              theme: theme,
                              title: backup.displayName,
                              subtitle:
                                  '${backup.formattedSize} • ${backup.fileName}',
                              isEncrypted: backup.isEncrypted,
                              actions: [
                                IconButton(
                                  icon: Icon(
                                    Icons.restore,
                                    color: theme.accent,
                                  ),
                                  tooltip: 'Restore this backup',
                                  onPressed: () async {
                                    final rootContext = Navigator.of(
                                      context,
                                      rootNavigator: true,
                                    ).context;
                                    final container = ProviderScope.containerOf(
                                      context,
                                      listen: false,
                                    );
                                    Navigator.pop(context);
                                    await Future.delayed(
                                      const Duration(milliseconds: 50),
                                    );
                                    if (rootContext.mounted) {
                                      final wasCancelled =
                                          await showRestoreConfirmDialog(
                                            rootContext,
                                            container,
                                            backup,
                                          );
                                      if (wasCancelled && rootContext.mounted) {
                                        await showBackupDialog(rootContext);
                                      }
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: theme.secondary,
                                  ),
                                  tooltip: 'Delete this backup',
                                  onPressed: () => _deleteBackup(backup),
                                ),
                              ],
                            );
                          },
                        ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Focus(
                              autofocus: false,
                              child: MouseRegion(
                                onEnter: (_) =>
                                    setState(() => _isHovering = true),
                                onExit: (_) =>
                                    setState(() => _isHovering = false),
                                child: WindowDropTarget(
                                  enable:
                                      supportsDragAndDrop &&
                                      _tabController.index == 1 &&
                                      !_isRestoring,
                                  onDragDone: (details) async {
                                    setState(() => _isDragging = false);
                                    if (details.files.length != 1 ||
                                        details.files.single
                                            is DropItemDirectory) {
                                      NotificationManager.instance.error(
                                        'Drop one .db or .enc backup file.',
                                      );
                                      return;
                                    }
                                    await _handleFilePath(
                                      details.files.single.path,
                                    );
                                  },
                                  onDragEntered: (_) =>
                                      setState(() => _isDragging = true),
                                  onDragExited: (_) =>
                                      setState(() => _isDragging = false),
                                  child: GestureDetector(
                                    onTap: _selectBackupFile,
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: _isDragging
                                            ? theme.accent.withValues(
                                                alpha: 0.1,
                                              )
                                            : _isHovering
                                            ? theme.accent.withValues(
                                                alpha: 0.05,
                                              )
                                            : theme.surface,
                                        borderRadius: BorderRadius.circular(
                                          theme.cornerRadius,
                                        ),
                                        border: Border.all(
                                          color: _isDragging
                                              ? theme.accent
                                              : _isHovering
                                              ? theme.accent.withValues(
                                                  alpha: 0.5,
                                                )
                                              : (_selectedBackupPath != null
                                                    ? theme.accent
                                                    : theme.border),
                                          width: _isDragging ? 2 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            _isDragging
                                                ? Icons.file_download
                                                : (_selectedBackupPath != null
                                                      ? (_isEncryptedBackup
                                                            ? Icons.lock
                                                            : Icons.storage)
                                                      : Icons.file_open),
                                            color: _isDragging
                                                ? theme.accent
                                                : (_selectedBackupPath != null
                                                      ? theme.accent
                                                      : theme.textSecondary),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  _selectedBackupName ??
                                                      (_isDragging &&
                                                              supportsDragAndDrop
                                                          ? 'Drop file here...'
                                                          : supportsDragAndDrop
                                                          ? 'Click to select or drag file here...'
                                                          : 'Tap to select a backup file...'),
                                                  style: TextStyle(
                                                    color: _isDragging
                                                        ? theme.accent
                                                        : (_selectedBackupPath !=
                                                                  null
                                                              ? theme
                                                                    .textPrimary
                                                              : theme
                                                                    .textSecondary),
                                                  ),
                                                ),
                                                if (_selectedBackupPath ==
                                                        null &&
                                                    !_isDragging) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Supports .db, .enc and extensionless SQLite files',
                                                    style: TextStyle(
                                                      color: theme.textHint,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          if (_selectedBackupPath != null)
                                            IconButton(
                                              tooltip: 'Clear selection',
                                              style:
                                                  theme.compactIconButtonStyle,
                                              onPressed: _isRestoring
                                                  ? null
                                                  : _clearFileSelection,
                                              icon: const Icon(
                                                Icons.close,
                                                size: 20,
                                              ),
                                            )
                                          else
                                            Icon(
                                              Icons.folder_open,
                                              color: theme.textSecondary,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (_isEncryptedBackup) ...[
                              const SizedBox(height: 12),
                              PasswordField(
                                controller: _passwordController,
                                labelText: 'Backup Password',
                              ),
                            ],
                            const SizedBox(height: kElementVSpacing),
                            ToggleSettingRow(
                              theme: theme,
                              label: 'Backup current database',
                              description: 'Recommended for safety',
                              value: _createBackupFirst,
                              onChanged: (value) =>
                                  setState(() => _createBackupFirst = value),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: kElementVSpacing),
                    DialogBanner.warning(
                      theme: theme,
                      message:
                          'Restoring a backup will replace your current database. This action cannot be undone.',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      actions: _tabController.index == 0
          ? [
              if (!PlatformFileActions.isMobilePlatform)
                OutlinedButton.icon(
                  onPressed: _openBackupFolder,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open Folder'),
                ),
              ElevatedButton.icon(
                onPressed: _isCreatingBackup ? null : _createBackup,
                icon: _isCreatingBackup
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: AppCircularProgressIndicator(),
                      )
                    : const Icon(Icons.backup),
                label: Text(
                  _isCreatingBackup ? 'Creating...' : 'Create Backup',
                ),
              ),
            ]
          : [
              DialogActionBar(
                theme: theme,
                onConfirm: _restoreFromSelectedFile,
                confirmIcon: Icons.restore,
                confirmLabel: 'Restore Backup',
                loadingLabel: 'Restoring...',
                isLoading: _isRestoring,
                isEnabled: _selectedBackupPath != null,
                spinnerSize: 18,
              ),
            ],
    );
  }
}

/// Show restore confirmation dialog for a specific backup
Future<bool> showRestoreConfirmDialog(
  BuildContext context,
  ProviderContainer container,
  BackupInfo backup,
) async {
  final theme = container.read(themeProvider);

  String? password;
  bool createBackupFirst = true;
  if (backup.isEncrypted) {
    password = await DatabaseUnlockDialog.show(
      context,
      theme,
      title: 'Unlock Backup',
      message: 'This backup is encrypted. Enter its password to restore it.',
      barrierDismissible: true,
    );

    if (password == null || password.isEmpty) return true;
  }

  // Show confirmation dialog
  if (!context.mounted) return false;

  final confirmed = await showAppDialog<bool>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return ThemedAlertDialog(
            theme: theme,

            title: DialogHeader(
              icon: Icons.restore,
              title: 'Restore Backup',
              theme: theme,
            ),
            maxHeight: 450,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Backup to restore:',
                  style: TextStyle(color: theme.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  backup.displayName,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: kDialogSpacing),
                ToggleSettingRow(
                  theme: theme,
                  label: 'Backup current database',
                  description: 'Recommended for safety',
                  value: createBackupFirst,
                  onChanged: (value) =>
                      setState(() => createBackupFirst = value),
                ),
                const SizedBox(height: kDialogSpacing),
                DialogBanner.warning(
                  theme: theme,
                  message:
                      'This will replace your current database with the backup.',
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Restore'),
              ),
            ],
          );
        },
      );
    },
  );

  if (!context.mounted) return false;

  if (confirmed != true) return true;

  // Perform the restore
  final backupService = container.read(backupServiceProvider);
  final result = await backupService.restoreBackup(
    backupPath: backup.filePath,
    password: password,
    createBackupFirst: createBackupFirst,
  );

  if (!context.mounted) return false;

  if (result.success) {
    await _reloadDatabaseFromSettings(container, password: password);
    NotificationManager.instance.success('Backup restored and reloaded');
  } else {
    NotificationManager.instance.error(
      result.error ?? 'Failed to restore backup',
    );
  }

  return false;
}
