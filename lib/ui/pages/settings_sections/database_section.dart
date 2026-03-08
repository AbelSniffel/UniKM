/// Database & security settings section.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/database.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/services/database_switching.dart';
import '../../../core/services/encryption_manager.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../dialogs/backup_dialogs.dart';
import '../../dialogs/encryption_dialogs.dart';
import '../../dialogs/import_export_dialog.dart';
import '../../widgets/dialog_helpers.dart';
import '../../widgets/notification_system.dart';
import '../../widgets/section_groupbox.dart';
import 'settings_common.dart';

/// Shows a dialog that asks the user which kind of database to create.
///
/// Returns 'unencrypted', 'encrypted' or `null` if cancelled. Public so it
/// can be reused and tested like other dialogs in the app.
Future<String?> showCreateDatabaseChoiceDialog(
  BuildContext context,
  AppThemeData theme,
) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        backgroundColor: theme.background,
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DialogHeader(
                icon: Icons.note_add,
                title: 'Create Database',
                theme: theme,
                showCloseButton: true,
              ),
              const SizedBox(height: 16),
              const Text('Choose the type of database you want to create.'),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'unencrypted'),
                icon: const Icon(Icons.note_add),
                label: const Text('Unencrypted database'),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'encrypted'),
                icon: const Icon(Icons.lock),
                label: const Text('Encrypted database'),
              ),
            ],
          ),
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
    description: 'The file UniKM is currently using',
  );
  static const SettingTextSpec maskKeysSpec = SettingTextSpec(
    label: 'Mask keys by default',
    description: 'Hide game keys until revealed',
  );
  static const SettingTextSpec autoHideKeysSpec = SettingTextSpec(
    label: 'Auto-hide keys',
    description: 'Automatically hide keys after copying',
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

  static List<String> get sectionSearchTexts => [
    'Database & Security',
    ...encryptionSearchGroup.indexTexts,
    ...dataManagementSearchGroup.indexTexts,
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
  String _defaultDbPath = '';
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

    _initializeEncryption(
      configuredPath: ref.read(currentDatabasePathProvider),
    );
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
      _defaultDbPath = defaultPath;
      _activeDbPath = resolvedPath;
      _encryptionManager = EncryptionManager(resolvedPath);
      _encryptionState = _encryptionManager!.state;
      _isLoading = false;
    });
  }

  Future<void> _openDatabase() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open UniKM Database',
      type: FileType.custom,
      allowedExtensions: const ['db', 'enc'],
      allowMultiple: false,
    );

    final selectedPath = result?.files.single.path;
    if (selectedPath == null || selectedPath.isEmpty) return;

    final callback = ref.read(databaseSwitchCallbackProvider);
    if (callback == null) return;
    await callback(OpenDatabaseRequest(selectedPath));
  }

  Future<void> _createDatabase({required bool encrypted}) async {
    final resultPath = await FilePicker.platform.saveFile(
      dialogTitle: encrypted ? 'Create Encrypted Database' : 'Create Database',
      fileName: encrypted ? 'UniKM_keys.enc' : 'UniKM_keys.db',
      type: FileType.custom,
      allowedExtensions: encrypted ? const ['enc'] : const ['db'],
    );

    if (resultPath == null || resultPath.isEmpty) return;

    final callback = ref.read(databaseSwitchCallbackProvider);
    if (callback == null) return;
    await callback(
      CreateDatabaseRequest(path: resultPath, encrypted: encrypted),
    );
  }

  Future<void> _openRecentDatabase(String baseDbPath) async {
    final callback = ref.read(databaseSwitchCallbackProvider);
    if (callback == null) return;
    await callback(OpenDatabaseRequest(baseDbPath));
  }

  Future<void> _useDefaultDatabase() async {
    if (_defaultDbPath.isEmpty) return;
    if (_defaultDbPath == _activeDbPath) return;

    final callback = ref.read(databaseSwitchCallbackProvider);
    if (callback == null) return;

    await callback(OpenDatabaseRequest(_defaultDbPath));
  }

  Future<void> _removeRecentDatabasePath(String baseDbPath) async {
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final recents = List<String>.from(
      ref.read(securitySettingsProvider).recentDatabasePaths,
    );

    final removed = recents.remove(baseDbPath);
    if (!removed) return;

    await settingsNotifier.setSetting(
      SettingsKeys.recentDatabasePaths,
      recents,
    );
  }

  Future<void> _showChangeDatabaseDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _ChangeDatabaseDialog(
        theme: widget.theme,
        isLoading: _isLoading,
        defaultDbPath: _defaultDbPath,
        activeDbPath: _activeDbPath,
        onUseDefault: _useDefaultDatabase,
        onOpen: _openDatabase,
        onOpenRecent: _openRecentDatabase,
        onRemoveRecent: _removeRecentDatabasePath,
      ),
    );
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
        await db.close();
        container.read(databaseNotifierProvider.notifier).clearDatabase();
      }

      await Future.delayed(const Duration(milliseconds: 100));

      await _encryptionManager!.enable(password);

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

  @override
  Widget build(BuildContext context) {
    final security = ref.watch(securitySettingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final isEncrypted = _encryptionState == EncryptionState.encrypted;
    final isUnlocked = ref.watch(encryptedDbSessionProvider) != null;
    final isSearching = widget.searchQuery.trim().isNotEmpty;

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
    final showKeyVisibility = shouldShowSettingsGroup(
      query: widget.searchQuery,
      matchesSearch: widget.matchesSearch,
      group: DatabaseSection.keyVisibilitySearchGroup,
    );

    if (isSearching &&
        !showEncryption &&
        !showDataManagement &&
        !showKeyVisibility) {
      return const SizedBox.shrink();
    }

    return SettingsSectionGroups(
      attachesToAbove: widget.attachesToAbove,
      entries: [
        // Database Encryption
        SectionGroupEntry(
          visible: showEncryption,
          builder: (position, isAlternate) => SearchableSectionGroupBox(
            theme: widget.theme,
            group: DatabaseSection.encryptionSearchGroup,
            titleIcon: Icons.lock,
            searchQuery: widget.searchQuery,
            matchesSearch: widget.matchesSearch,
            groupPosition: position,
            isAlternate: isAlternate,
            child: Column(
              children: [
                SettingRow(
                  theme: widget.theme,
                  label: _isLoading
                      ? DatabaseSection.encryptionStatusSpec.label
                      : isEncrypted
                          ? (isUnlocked
                                ? 'Encrypted (Unlocked)'
                                : 'Encrypted (Locked)')
                          : 'Not Encrypted',
                  labelColor: _isLoading
                      ? null
                      : isEncrypted
                          ? Colors.green
                          : Colors.orange,
                  description: DatabaseSection.encryptionStatusSpec.description,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isEncrypted)
                              ElevatedButton.icon(
                                onPressed: _enableEncryption,
                                icon: const Icon(Icons.lock, size: 18),
                                label: const Text('Enable'),
                              ),
                            if (isEncrypted) ...[
                              OutlinedButton.icon(
                                onPressed: _changePassword,
                                icon: const Icon(Icons.key),
                                label: const Text('Change Password'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: _disableEncryption,
                                icon: const Icon(Icons.lock_open),
                                label: const Text('Disable'),
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
        // Data Management (Backup/Restore)
        SectionGroupEntry(
          visible: showDataManagement,
          builder: (position, isAlternate) => _buildDataManagementSection(
            context,
            ref,
            searchQuery: widget.searchQuery,
            isSearchMatch: isSearching,
            groupPosition: position,
            alternateBackground: isAlternate,
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
    WidgetRef ref, {
    required String searchQuery,
    required bool isSearchMatch,
    SectionGroupPosition groupPosition = SectionGroupPosition.only,
    bool alternateBackground = false,
  }) {
    final nextBackupTime = ref.watch(nextAutoBackupTimeProvider);

    String formatNextBackupTime(DateTime nextTime) {
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
          SpecSettingRow(
            theme: widget.theme,
            spec: DatabaseSection.activeDatabaseSpec,
            child: Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _activeDbPath,
                        textAlign: TextAlign.right,
                        softWrap: true,
                        style: TextStyle(color: widget.theme.textSecondary),
                      ),
              ),
            ),
          ),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    showImportDialog(context);
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Import DB'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    showExportDialog(context);
                  },
                  icon: const Icon(Icons.upload),
                  label: const Text('Export DB'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showChangeDatabaseDialog,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Change DB'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final choice = await showCreateDatabaseChoiceDialog(
                      context,
                      widget.theme,
                    );
                    if (choice == 'unencrypted') {
                      await _createDatabase(encrypted: false);
                    } else if (choice == 'encrypted') {
                      await _createDatabase(encrypted: true);
                    }
                  },
                  icon: const Icon(Icons.note_add),
                  label: const Text('New DB'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (nextBackupTime != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.theme.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
                border: Border.all(
                  color: widget.theme.accent.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule, color: widget.theme.accent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Next Auto Backup',
                          style: TextStyle(
                            color: widget.theme.textPrimary,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatNextBackupTime(nextBackupTime),
                          style: TextStyle(
                            color: widget.theme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Move manual backup actions into the next-backup box (top-right)
                  const SizedBox(width: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            showBackupDialog(context);
                          },
                          icon: const Icon(Icons.backup),
                          label: const Text('Backup Manager'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // If the next-backup box is hidden, keep the manual backup buttons available
          if (nextBackupTime == null)
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
      ),
    );
  }
}

class _ChangeDatabaseDialog extends ConsumerStatefulWidget {
  const _ChangeDatabaseDialog({
    required this.theme,
    required this.isLoading,
    required this.defaultDbPath,
    required this.activeDbPath,
    required this.onUseDefault,
    required this.onOpen,
    required this.onOpenRecent,
    required this.onRemoveRecent,
  });

  final AppThemeData theme;
  final bool isLoading;
  final String defaultDbPath;
  final String activeDbPath;
  final Future<void> Function() onUseDefault;
  final Future<void> Function() onOpen;
  final Future<void> Function(String) onOpenRecent;
  final Future<void> Function(String) onRemoveRecent;

  @override
  ConsumerState<_ChangeDatabaseDialog> createState() =>
      _ChangeDatabaseDialogState();
}

class _ChangeDatabaseDialogState extends ConsumerState<_ChangeDatabaseDialog> {
  final _scrollController = ScrollController();

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

    return Dialog(
      backgroundColor: widget.theme.background,
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DialogHeader(
              icon: Icons.swap_horiz,
              title: 'Change Database',
              theme: widget.theme,
              showCloseButton: true,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        (widget.isLoading ||
                            widget.defaultDbPath.isEmpty ||
                            widget.defaultDbPath == widget.activeDbPath)
                        ? null
                        : () async {
                            Navigator.pop(context);
                            await widget.onUseDefault();
                          },
                    icon: const Icon(Icons.restore),
                    label: const Text('Use Default'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      await widget.onOpen();
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
            const SizedBox(height: 8),
            if (recents.isEmpty)
              Text(
                'No recent databases yet.',
                style: TextStyle(color: widget.theme.textSecondary),
              )
            else
              Expanded(
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
                          final selected = await showMenu<String>(
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
                            await widget.onRemoveRecent(basePath);
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
                          onOpen: exists
                              ? () async {
                                  Navigator.pop(context);
                                  await widget.onOpenRecent(basePath);
                                }
                              : null,
                          onRemove: () async {
                            await widget.onRemoveRecent(basePath);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
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
  });

  final AppThemeData theme;
  final String title;
  final String basePath;
  final String? sizeLabel;
  final bool exists;
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
        onHover: (value) => setState(() => _isHovering = value),
        onTap: widget.exists ? widget.onOpen : null,
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
                  color: widget.exists
                      ? widget.theme.accent.withValues(alpha: 0.1)
                      : Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  widget.exists ? Icons.storage : Icons.warning_amber,
                  color: widget.exists ? widget.theme.accent : Colors.orange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: widget.theme.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.sizeLabel == null
                          ? widget.basePath
                          : '${widget.sizeLabel} • ${widget.basePath}',
                      style: TextStyle(
                        color: widget.theme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if (!widget.exists)
                      Row(
                        children: [
                          const Icon(
                            Icons.warning_amber,
                            size: 14,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'File not found',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (!widget.exists)
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
