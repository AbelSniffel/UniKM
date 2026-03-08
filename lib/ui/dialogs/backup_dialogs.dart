/// Backup and restore dialogs for database management
library;

import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/database/database.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/database_switching.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/notification_system.dart';

/// Show the backup management dialog
Future<void> showBackupDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) => const _BackupDialog(),
  );
}

Future<void> _reloadDatabaseFromSettings(ProviderContainer container, {String? password}) async {
  final callback = container.read(databaseSwitchCallbackProvider);
  if (callback == null) {
    NotificationManager.instance.error('Database reload is not available right now');
    return;
  }

  final configuredPath = container.read(currentDatabasePathProvider);
  final basePath = configuredPath.isNotEmpty
      ? configuredPath
      : await AppDatabase.getDatabasePath();

  container.read(databaseSwitchingProvider.notifier).setSwitching(true);
  try {
    await callback(OpenDatabaseRequest(basePath, password: password));
  } catch (e) {
    NotificationManager.instance.error('Failed to reload database: $e');
  } finally {
    container.read(databaseSwitchingProvider.notifier).setSwitching(false);
  }
}

/// Backup management dialog
class _BackupDialog extends ConsumerStatefulWidget {
  const _BackupDialog();

  @override
  ConsumerState<_BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends ConsumerState<_BackupDialog> {
  bool _isCreatingBackup = false;
  List<BackupInfo> _backups = [];
  bool _isLoading = true;
  String? _selectedBackupPath;
  String? _selectedBackupName;
  bool _isEncryptedBackup = false;
  bool _createBackupFirst = true;
  final _passwordController = TextEditingController();
  bool _isRestoring = false;
  bool _showPassword = false;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  @override
  void dispose() {
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
        NotificationManager.instance.success('Backup created: ${result.backupInfo?.fileName}');
        await _loadBackups();
      } else {
        NotificationManager.instance.error(result.error ?? 'Failed to create backup');
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
      if (Platform.isWindows) {
        await Process.run('explorer', [backupsDir.path]);
      }
    } catch (e) {
      NotificationManager.instance.error('Failed to open backup folder: $e');
    }
  }

  Future<void> _selectBackupFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db', 'enc'],
      dialogTitle: 'Select Backup File',
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      _handleFilePath(path);
    }
  }

  void _handleFilePath(String path) {
    final lower = path.toLowerCase();
    if (!lower.endsWith('.db') && !lower.endsWith('.enc')) {
      NotificationManager.instance.error('Please select a .db or .enc backup file');
      return;
    }

    setState(() {
      _selectedBackupPath = path;
      _selectedBackupName = p.basename(path);
      _isEncryptedBackup = path.endsWith('.enc') || _selectedBackupName!.contains('_encrypted');
    });
  }

  Future<void> _restoreFromSelectedFile() async {
    if (_selectedBackupPath == null) {
      NotificationManager.instance.error('Please select a backup file');
      return;
    }

    if (_isEncryptedBackup && _passwordController.text.isEmpty) {
      NotificationManager.instance.error('Password is required for encrypted backups');
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
        final rootContext = Navigator.of(context, rootNavigator: true).context;
        final container = ProviderScope.containerOf(context, listen: false);
        Navigator.pop(context);
        await Future.delayed(const Duration(milliseconds: 50));
        if (!rootContext.mounted) return;
        await _showReloadRequiredDialog(
          rootContext,
          container: container,
          password: _isEncryptedBackup ? _passwordController.text : null,
        );
      } else {
        NotificationManager.instance.error(result.error ?? 'Failed to restore backup');
      }
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }

  Future<void> _showReloadRequiredDialog(
    BuildContext dialogContext, {
    required ProviderContainer container,
    String? password,
  }) async {
    await showDialog(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) {
        final theme = container.read(themeProvider);
        return AlertDialog(
          backgroundColor: theme.background,
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 28),
              const SizedBox(width: 12),
              Text('Restore Complete', style: TextStyle(color: theme.textPrimary)),
            ],
          ),
          content: Text(
            'The backup has been restored successfully.\n\n'
            'Reload the database to use the restored data.',
            style: TextStyle(color: theme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                await _reloadDatabaseFromSettings(container, password: password);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Reload Now'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final backupSettings = ref.watch(backupSettingsProvider);
    final maxBackups = backupSettings.maxCount;

    return Dialog(
      backgroundColor: theme.background,
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        padding: const EdgeInsets.all(20),
        child: DefaultTabController(
          length: 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DialogHeader(
                icon: Icons.backup,
                title: 'Backup Manager',
                theme: theme,
                showCloseButton: true,
              ),
              const SizedBox(height: 8),
              Text(
                'Maximum $maxBackups backups are kept. Oldest backups are automatically deleted.',
                style: TextStyle(color: theme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isCreatingBackup ? null : _createBackup,
                      icon: _isCreatingBackup
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.textPrimary,
                              ),
                            )
                          : const Icon(Icons.add),
                      label: Text(_isCreatingBackup ? 'Creating...' : 'Create Backup Now'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _openBackupFolder,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Open Folder'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TabBar(
                labelColor: theme.textPrimary,
                unselectedLabelColor: theme.textSecondary,
                indicatorColor: theme.accent,
                tabs: [
                  Tab(text: 'Existing Backups (${_backups.length}/$maxBackups)'),
                  const Tab(text: 'Restore from File'),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  children: [
                    _isLoading
                        ? Center(child: CircularProgressIndicator(color: theme.accent))
                        : _backups.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.backup_outlined,
                                      size: 48,
                                      color: theme.textSecondary.withValues(alpha: 0.5),
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
                                  return _BackupListItem(
                                    backup: backup,
                                    theme: theme,
                                    onDelete: () => _deleteBackup(backup),
                                    onRestore: () async {
                                      final rootContext = Navigator.of(context, rootNavigator: true).context;
                                      final container = ProviderScope.containerOf(context, listen: false);
                                      Navigator.pop(context);
                                      await Future.delayed(const Duration(milliseconds: 50));
                                      if (rootContext.mounted) {
                                        final wasCancelled = await showRestoreConfirmDialog(rootContext, container, backup);
                                        if (wasCancelled && rootContext.mounted) {
                                          await showBackupDialog(rootContext);
                                        }
                                      }
                                    },
                                  );
                                },
                              ),
                    SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DialogBanner.warning(
                            theme: theme,
                            message: 'Restoring a backup will replace your current database. This action cannot be undone.',
                          ),
                          const SizedBox(height: 12),
                          Focus(
                            autofocus: false,
                            child: MouseRegion(
                              child: DropTarget(
                                enable: true,
                                onDragDone: (details) {
                                  if (details.files.isNotEmpty) {
                                    _handleFilePath(details.files.first.path);
                                  }
                                },
                                onDragEntered: (_) => setState(() => _isDragging = true),
                                onDragExited: (_) => setState(() => _isDragging = false),
                                child: GestureDetector(
                                  onTap: _selectBackupFile,
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: _isDragging ? theme.accent.withValues(alpha: 0.1) : theme.surface,
                                      borderRadius: BorderRadius.circular(theme.cornerRadius),
                                      border: Border.all(
                                        color: _isDragging
                                            ? theme.accent
                                            : (_selectedBackupPath != null ? theme.accent : theme.border),
                                        width: _isDragging ? 2 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          _isDragging
                                              ? Icons.file_download
                                              : (_selectedBackupPath != null
                                                    ? (_isEncryptedBackup ? Icons.lock : Icons.storage)
                                                    : Icons.file_open),
                                          color: _isDragging
                                              ? theme.accent
                                              : (_selectedBackupPath != null ? theme.accent : theme.textSecondary),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                _selectedBackupName ??
                                                    (_isDragging ? 'Drop file here...' : 'Click to select or drag file here...'),
                                                style: TextStyle(
                                                  color: _isDragging
                                                      ? theme.accent
                                                      : (_selectedBackupPath != null
                                                          ? theme.textPrimary
                                                          : theme.textSecondary),
                                                ),
                                              ),
                                              if (_selectedBackupPath == null && !_isDragging) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Supports .db and .enc files',
                                                  style: TextStyle(color: theme.textHint, fontSize: 12),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        Icon(Icons.folder_open, color: theme.textSecondary),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_isEncryptedBackup) ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: _passwordController,
                              obscureText: !_showPassword,
                              decoration: InputDecoration(
                                hintText: 'Enter backup password',
                                filled: true,
                                fillColor: theme.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(theme.cornerRadius),
                                  borderSide: BorderSide(color: theme.border),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _showPassword ? Icons.visibility_off : Icons.visibility,
                                    color: theme.textSecondary,
                                  ),
                                  onPressed: () => setState(() => _showPassword = !_showPassword),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          CheckboxListTile(
                            value: _createBackupFirst,
                            onChanged: (value) => setState(() => _createBackupFirst = value ?? true),
                            title: Text(
                              'Create backup of current database first',
                              style: TextStyle(color: theme.textPrimary),
                            ),
                            subtitle: Text(
                              'Recommended for safety',
                              style: TextStyle(color: theme.textSecondary, fontSize: 12),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                          ),
                          const SizedBox(height: 8),
                          DialogActionBar(
                            theme: theme,
                            onConfirm: _restoreFromSelectedFile,
                            confirmIcon: Icons.restore,
                            confirmLabel: 'Restore Backup',
                            loadingLabel: 'Restoring...',
                            isLoading: _isRestoring,
                            isEnabled: _selectedBackupPath != null,
                            spinnerSize: 18,
                            showCancel: false,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single backup item in the list
class _BackupListItem extends StatelessWidget {
  const _BackupListItem({
    required this.backup,
    required this.theme,
    required this.onDelete,
    required this.onRestore,
  });

  final BackupInfo backup;
  final AppThemeData theme;
  final VoidCallback onDelete;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        border: Border.all(color: theme.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              backup.isEncrypted ? Icons.lock : Icons.storage,
              color: theme.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  backup.displayName,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${backup.formattedSize} • ${backup.fileName}',
                  style: TextStyle(
                    color: theme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.restore, color: theme.accent),
            tooltip: 'Restore this backup',
            onPressed: onRestore,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'Delete this backup',
            onPressed: onDelete,
          ),
        ],
      ),
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
    // Show password dialog first
    password = await showDialog<String>(
      context: context,
      builder: (context) {
        final passwordController = TextEditingController();
        bool showPassword = false;
        
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: theme.background,
              title: Row(
                children: [
                  Icon(Icons.lock, color: Colors.amber),
                  const SizedBox(width: 12),
                  Text('Encrypted Backup', style: TextStyle(color: theme.textPrimary)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This backup is encrypted. Please enter the password to restore it.',
                    style: TextStyle(color: theme.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: !showPassword,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      filled: true,
                      fillColor: theme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(theme.cornerRadius),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          showPassword ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () => setState(() => showPassword = !showPassword),
                      ),
                    ),
                    onSubmitted: (value) => Navigator.pop(context, value),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, passwordController.text),
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );

    if (password == null || password.isEmpty) return true;
  }

  // Show confirmation dialog
  if (!context.mounted) return false;
  
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: theme.background,
            title: Row(
              children: [
                Icon(Icons.restore, color: theme.accent),
                const SizedBox(width: 12),
                Text('Restore Backup', style: TextStyle(color: theme.textPrimary)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber, color: Colors.amber),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This will replace your current database with the backup.',
                          style: TextStyle(color: theme.textPrimary, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: createBackupFirst,
                  onChanged: (value) => setState(() => createBackupFirst = value ?? true),
                  title: Text(
                    'Create backup of current database first',
                    style: TextStyle(color: theme.textPrimary, fontSize: 14),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
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
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: theme.background,
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 28),
              const SizedBox(width: 12),
              Text('Restore Complete', style: TextStyle(color: theme.textPrimary)),
            ],
          ),
          content: Text(
            'The backup has been restored successfully.\n\n'
            'Reload the database to use the restored data.',
            style: TextStyle(color: theme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                await _reloadDatabaseFromSettings(container, password: password);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Reload Now'),
            ),
          ],
        );
      },
    );
  } else {
    NotificationManager.instance.error(result.error ?? 'Failed to restore backup');
  }

  return false;
}
