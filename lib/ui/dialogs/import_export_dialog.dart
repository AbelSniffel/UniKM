/// Import/Export dialogs for database operations
library;

import '../widgets/window_drop_target.dart';

import '../../features/transfer/application/library_import.dart';
import '../../features/transfer/application/library_export.dart';
import 'dart:convert';
import 'dart:async';
import '../../features/transfer/application/sqlite_import_reader.dart';
import '../../features/transfer/application/import_image_checkpoint.dart';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../core/database/sqlite_file.dart';
import '../../core/database/database.dart';
import '../../core/settings/settings_model.dart';
import '../../core/services/encryption_manager.dart';
import '../../core/services/legacy_encrypted_import.dart';
import '../../core/services/platform_file_actions.dart';
import '../../core/services/legacy_db_converter.dart';
import '../../core/services/steamkm1_import.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import 'legacy_conversion_dialog.dart';
import '../pages/settings_sections/settings_common.dart';
import 'database_unlock_dialog.dart';
import '../widgets/app_progress_indicator.dart';
import '../widgets/app_tag_chip.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/notification_system.dart';
import '../widgets/section_groupbox.dart';
import '../../core/constants/app_constants.dart';

enum _ImportFileKind { sqlite, encrypted, json, csv, txt, unsupported }

typedef _DialogRadioOption = ({String value, String title, String subtitle});

const _exportFormatOptions = <_DialogRadioOption>[
  (
    value: 'db',
    title: 'SQLite (.db)',
    subtitle: 'Full database file (recommended backup)',
  ),
  (value: 'json', title: 'JSON', subtitle: 'Full data with structure'),
  (value: 'csv', title: 'CSV', subtitle: 'Spreadsheet compatible'),
  (value: 'txt', title: 'Text', subtitle: 'Simple title | key format'),
];

const _encryptedExportFormatOption = (
  value: 'enc',
  title: 'Encrypted DB (.enc)',
  subtitle: 'Encrypted database file (no password included)',
);

const _importModeOptions = <_DialogRadioOption>[
  (value: 'merge', title: 'Merge', subtitle: 'Add new games, skip duplicates'),
  (
    value: 'replace',
    title: 'Replace',
    subtitle: 'Clear existing data and import',
  ),
  (value: 'update', title: 'Update', subtitle: 'Add new and update existing'),
];

Future<void> _markImportSyncDirty(WidgetRef ref, AppDatabase db) async {
  await db.bumpLocalSyncRevision();
  await ref
      .read(settingsProvider.notifier)
      .setSetting(
        SettingsKeys.syncDbRevisionId,
        DateTime.now().millisecondsSinceEpoch.toString(),
      );
}

Widget _buildDialogRadioOption(AppThemeData theme, _DialogRadioOption option) {
  return RadioListTile<String>(
    value: option.value,
    activeColor: theme.accent,
    title: Text(option.title, style: TextStyle(color: theme.textPrimary)),
    subtitle: Text(
      option.subtitle,
      style: TextStyle(color: theme.textSecondary),
    ),
  );
}

/// Show export dialog
Future<void> showExportDialog(BuildContext context) {
  return showAppDialog<void>(
    context: context,
    builder: (ctx) => const ExportDialog(),
  );
}

/// Show import dialog
Future<void> showImportDialog(BuildContext context) {
  return showAppDialog<void>(
    context: context,
    builder: (ctx) => const ImportDialog(),
  );
}

/// Export dialog
class ExportDialog extends ConsumerStatefulWidget {
  const ExportDialog({super.key});

  @override
  ConsumerState<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends ConsumerState<ExportDialog> {
  String _exportFormat = 'db';
  bool _includeUsed = true;
  bool _includeTags = true;
  bool _includeNotes = true;
  bool _isExporting = false;

  Widget _buildExportOptionChip({
    required AppThemeData theme,
    required String label,
    required bool value,
    required VoidCallback onTap,
  }) {
    return AppOptionChip(
      theme: theme,
      label: label,
      isSelected: value,
      onTap: onTap,
    );
  }

  String _escapeSqlString(String value) {
    return value.replaceAll("'", "''");
  }

  Future<String> _resolveBaseDbPath() async {
    final configured = ref.read(currentDatabasePathProvider);
    if (configured.isNotEmpty) return configured;
    return AppDatabase.getDatabasePath();
  }

  Future<void> _exportSqliteBackup(String destinationPath) async {
    final session = ref.read(encryptedDbSessionProvider);
    final sourcePath = session?.tempDbPath ?? await _resolveBaseDbPath();

    // Use VACUUM INTO for a consistent, compact snapshot.
    final sourceDb = sqlite3.sqlite3.open(
      sourcePath,
      mode: sqlite3.OpenMode.readOnly,
    );
    try {
      sourceDb.execute("VACUUM INTO '${_escapeSqlString(destinationPath)}'");
    } finally {
      sourceDb.close();
    }
  }

  Future<void> _exportEncryptedDatabase(String destinationPath) async {
    final session = ref.read(encryptedDbSessionProvider);
    if (session == null) {
      throw StateError('No encrypted database is currently active');
    }

    // Ensure the on-disk .enc contains the latest changes.
    await session.persistFromTemp();

    final encPath = '${session.baseDbPath}.enc';
    await File(encPath).copy(destinationPath);
  }

  Future<bool> _completeShareIfNeeded(
    PlatformSaveTarget target, {
    required String subject,
  }) async {
    if (!target.shouldShareAfterWrite) {
      return true;
    }

    final shared = await PlatformFileActions.shareFile(
      target.file,
      subject: subject,
    );

    if (shared) {
      return true;
    }

    try {
      if (await target.file.exists()) {
        await target.file.delete();
      }
    } catch (_) {
      // Best effort cleanup only.
    }

    return false;
  }

  Future<void> _export() async {
    final ext = _exportFormat;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final defaultName = (ext == 'db' || ext == 'enc')
        ? 'UniKM_backup_$ts.$ext'
        : 'UniKM_export_$ts.$ext';

    final target = await PlatformFileActions.prepareExportTarget(
      dialogTitle: 'Export Database',
      fileName: defaultName,
      allowedExtensions: [ext],
    );

    if (target == null) return;

    final result = target.file.path;

    setState(() => _isExporting = true);

    try {
      if (_exportFormat == 'db') {
        await _exportSqliteBackup(result);
        final completed = await _completeShareIfNeeded(
          target,
          subject: 'UniKM database export',
        );
        if (!completed) {
          return;
        }
        NotificationManager.instance.success(
          'Exported database to ${p.basename(result)}',
        );
        if (mounted) Navigator.pop(context);
        return;
      }

      if (_exportFormat == 'enc') {
        await _exportEncryptedDatabase(result);
        final completed = await _completeShareIfNeeded(
          target,
          subject: 'UniKM encrypted database export',
        );
        if (!completed) {
          return;
        }
        NotificationManager.instance.success(
          'Exported encrypted database to ${p.basename(result)}',
        );
        if (mounted) Navigator.pop(context);
        return;
      }

      // Get all games
      final gamesState = ref.read(gamesProvider);
      final games = gamesState.games;
      final tags = ref.read(tagsProvider);

      final filteredGames = _includeUsed
          ? games
          : games.where((game) => !game.isUsed).toList();
      final exportData = LibraryBackupExporter(
        includeTags: _includeTags,
        includeNotes: _includeNotes,
      ).encode(filteredGames, tags, _exportFormat);

      // Write file
      await File(result).writeAsString(exportData);

      final completed = await _completeShareIfNeeded(
        target,
        subject: 'UniKM database export',
      );
      if (!completed) {
        return;
      }

      NotificationManager.instance.success(
        'Exported ${filteredGames.length} games to ${p.basename(result)}',
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      NotificationManager.instance.error('Export failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final hasEncryptedSession = ref.watch(encryptedDbSessionProvider) != null;
    final showsAdditionalInfo = _exportFormat != 'db' && _exportFormat != 'enc';

    return ThemedAlertDialog(
      theme: theme,

      maxWidth: 550,
      title: DialogHeader(
        icon: Icons.upload,
        title: 'Export Database',
        theme: theme,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Format selection
          SectionGroupBox(
            title: 'Format',
            titleIcon: Icons.format_align_center,
            theme: theme,
            groupPosition: showsAdditionalInfo
                ? SectionGroupPosition.first
                : SectionGroupPosition.only,
            child: RadioGroup<String>(
              groupValue: _exportFormat,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _exportFormat = v);
              },
              child: Column(
                children: [
                  _buildDialogRadioOption(theme, _exportFormatOptions[0]),
                  if (hasEncryptedSession)
                    _buildDialogRadioOption(
                      theme,
                      _encryptedExportFormatOption,
                    ),
                  for (final option in _exportFormatOptions.skip(1))
                    _buildDialogRadioOption(theme, option),
                ],
              ),
            ),
          ),

          // Options
          if (showsAdditionalInfo)
            SectionGroupBox(
              title: 'Include Additional Information',
              titleIcon: Icons.info_outline,
              theme: theme,
              groupPosition: SectionGroupPosition.last,
              alternateBackground: true,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildExportOptionChip(
                    theme: theme,
                    label: 'Used Keys',
                    value: _includeUsed,
                    onTap: () => setState(() => _includeUsed = !_includeUsed),
                  ),
                  if (_exportFormat != 'txt') ...[
                    _buildExportOptionChip(
                      theme: theme,
                      label: 'Tags',
                      value: _includeTags,
                      onTap: () => setState(() => _includeTags = !_includeTags),
                    ),
                    _buildExportOptionChip(
                      theme: theme,
                      label: 'Notes',
                      value: _includeNotes,
                      onTap: () =>
                          setState(() => _includeNotes = !_includeNotes),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
      actions: [
        ElevatedButton.icon(
          onPressed: _isExporting ? null : _export,
          icon: _isExporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: AppCircularProgressIndicator(),
                )
              : const Icon(Icons.upload),
          label: const Text('Export'),
        ),
      ],
    );
  }
}

/// Import dialog
class ImportDialog extends ConsumerStatefulWidget {
  const ImportDialog({super.key});

  @override
  ConsumerState<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<ImportDialog> {
  String? _selectedFile;
  int _fileSelectionRevision = 0;
  String _importMode = 'merge';
  ImportMode _activeImportMode = ImportMode.merge;
  bool _isImporting = false;
  bool _cancelRequested = false;
  bool _importCommitted = false;
  AppDatabase? _importDatabase;
  ImportImageCheckpoint? _imageCheckpoint;
  NotificationHandle? _importTask;
  Timer? _importHeartbeat;
  String _importMessage = 'Preparing import...';
  double? _importProgress;
  String _importSummary = 'Import completed';
  LegacyDbConversionResult? _legacyConversion;

  void _checkImport() {
    if (_cancelRequested ||
        !mounted ||
        !identical(ref.read(databaseProvider), _importDatabase)) {
      throw const ImportCancelled();
    }
  }

  void _showImportProgress() {
    if (!_isImporting) return;
    final manager = NotificationManager.instance;
    final visible = manager.currentNotifications.any(
      (n) => n.id == _importTask?.id && !n.isDismissing,
    );
    if (!visible) {
      _importTask = manager.beginTask(
        _importMessage,
        progress: _importProgress,
        actionLabel: _importCommitted || _cancelRequested
            ? null
            : 'Cancel import',
        onAction: _importCommitted || _cancelRequested
            ? null
            : () {
                _cancelRequested = true;
                _importMessage =
                    'Cancelling import and restoring checkpoint...';
                _showImportProgress();
              },
      );
    } else {
      _importTask!.update(
        message: _importMessage,
        progress: _importProgress,
        clearAction: _importCommitted || _cancelRequested,
      );
    }
  }

  void _reportImportProgress(int done, int total) {
    _importMessage = 'Importing games: $done of $total';
    _importProgress = total == 0 ? 1 : done / total;
    _showImportProgress();
  }

  @override
  void dispose() {
    _cancelRequested = true;
    _importHeartbeat?.cancel();
    super.dispose();
  }

  int _previewCount = 0;
  bool _isDragging = false;
  bool _isHovering = false;
  bool _allowDuplicates = false;
  static final RegExp _windowsPathPattern = RegExp(r'^[a-zA-Z]:[\\/]');

  bool get _isReplace => _importMode == 'replace';
  bool get _isUpdate => _importMode == 'update';

  Future<bool> _confirmReplaceIfNeeded() async {
    if (!_isReplace) return true;
    final theme = ref.read(themeProvider);
    return showConfirmDialog(
      context: context,
      theme: theme,
      title: 'Replace all data?',
      titleIcon: Icons.warning_amber_rounded,
      message:
          'This will delete all existing games, tags, and backups before importing.',
      confirmLabel: 'Replace',
      destructive: true,
    );
  }

  Future<void> _selectFile() async {
    final result = await FilePicker.pickFile(
      dialogTitle: 'Select Database File',
      type: FileType.any,
    );

    if (result != null) {
      final path = result.path;
      if (path != null) {
        await _handleSelectedFilePath(path);
      }
    }
  }

  Future<void> _handleSelectedFilePath(String path) async {
    if (_isImporting) return;
    final revision = ++_fileSelectionRevision;
    setState(() => _isDragging = false);
    final kind = await _classifyImportFile(path);
    if (!mounted || revision != _fileSelectionRevision) return;
    if (kind == _ImportFileKind.unsupported) {
      NotificationManager.instance.error(
        'Unsupported file type. Please select a .db, .sqlite, .sqlite3, .enc, .json, .csv, .txt, or supported .bak backup',
      );
      return;
    }

    setState(() {
      _selectedFile = path;
      _previewCount = 0;
      _isDragging = false;
    });

    await _scanFileForCount(File(path), revision);
  }

  void _clearFileSelection() {
    if (_isImporting) return;
    ++_fileSelectionRevision;
    setState(() {
      _selectedFile = null;
      _previewCount = 0;
      _isDragging = false;
    });
  }

  Future<_ImportFileKind> _classifyImportFile(String path) async {
    final lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.db') ||
        lowerPath.endsWith('.sqlite') ||
        lowerPath.endsWith('.sqlite3') ||
        lowerPath.endsWith('.db.bak') ||
        lowerPath.endsWith('.sqlite.bak') ||
        lowerPath.endsWith('.sqlite3.bak')) {
      return _ImportFileKind.sqlite;
    }
    if (lowerPath.endsWith('.enc') || lowerPath.endsWith('.enc.bak')) {
      return _ImportFileKind.encrypted;
    }
    if (lowerPath.endsWith('.json') || lowerPath.endsWith('.json.bak')) {
      return _ImportFileKind.json;
    }
    if (lowerPath.endsWith('.csv')) {
      return _ImportFileKind.csv;
    }
    if (lowerPath.endsWith('.txt')) {
      return _ImportFileKind.txt;
    }

    // Linux database files may have no suffix. Require the SQLite signature;
    // never reinterpret arbitrary extensionless files as a text import.
    if (p.extension(path).isEmpty && await isLikelySqliteFile(path)) {
      return _ImportFileKind.sqlite;
    }
    // Generic backup files may need content-based classification too.
    if (!lowerPath.endsWith('.bak')) return _ImportFileKind.unsupported;
    try {
      final file = File(path);
      if (!await file.exists()) return _ImportFileKind.unsupported;

      final firstBytes = await file.openRead(0, 16).first;
      if (hasSqliteHeader(firstBytes)) {
        return _ImportFileKind.sqlite;
      }

      // Legacy JSON backups may use only the .bak suffix.
      final header = await file
          .openRead(0, 256)
          .map((b) => String.fromCharCodes(b))
          .join();
      final trimmed = header.trimLeft();
      if (trimmed.isNotEmpty &&
          (trimmed.startsWith('{') || trimmed.startsWith('['))) {
        return _ImportFileKind.json;
      }
    } catch (_) {
      // File read failed — fall through to unsupported.
    }

    return _ImportFileKind.unsupported;
  }

  Future<void> _scanFileForCount(File file, int revision) async {
    try {
      final kind = await _classifyImportFile(file.path);
      int count = 0;

      if (kind == _ImportFileKind.sqlite) {
        // Count games in SQLite
        sqlite3.Database? sourceDb;
        try {
          sourceDb = sqlite3.sqlite3.open(
            file.path,
            mode: sqlite3.OpenMode.readOnly,
          );
          final tables = sourceDb.select(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='games'",
          );
          if (tables.isNotEmpty) {
            final result = sourceDb.select(
              'SELECT COUNT(*) as count FROM games',
            );
            count = result.first['count'] as int;
          }
        } finally {
          sourceDb?.close();
        }
      } else if (kind == _ImportFileKind.encrypted) {
        // Can't preview count without password.
        count = 0;
      } else if (kind == _ImportFileKind.json) {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        if (data is Map && data['games'] is List) {
          count = (data['games'] as List).length;
        } else if (looksLikeSteamKm1JsonExportData(data)) {
          count = parseSteamKm1JsonExportData(data).length;
        }
      } else if (kind == _ImportFileKind.txt) {
        final content = await file.readAsString();
        count = parseSteamKm1TextExport(content).length;
      } else if (kind == _ImportFileKind.csv) {
        count = parseLibraryCsv(await file.readAsString()).length;
      }

      if (!mounted || revision != _fileSelectionRevision) return;
      setState(() => _previewCount = count);
    } catch (e) {
      // Ignore errors during preview count
    }
  }

  Future<void> _import() async {
    if (_selectedFile == null || _isImporting) return;
    if (!await _confirmReplaceIfNeeded() || !mounted) return;
    _cancelRequested = false;
    _activeImportMode = _isReplace
        ? ImportMode.replace
        : _isUpdate
        ? ImportMode.update
        : _allowDuplicates
        ? ImportMode.addAnyway
        : ImportMode.merge;
    _importCommitted = false;
    _legacyConversion = null;
    _importDatabase = ref.read(requireDatabaseProvider);
    _imageCheckpoint = ImportImageCheckpoint();
    _importMessage = 'Validating import file...';
    _importProgress = null;
    setState(() => _isImporting = true);
    _showImportProgress();
    _importHeartbeat = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _showImportProgress(),
    );
    try {
      final file = File(_selectedFile!);
      final kind = await _classifyImportFile(_selectedFile!);
      _checkImport();
      var completed = true;
      switch (kind) {
        case _ImportFileKind.sqlite:
          await _importSqliteDatabase(file);
        case _ImportFileKind.encrypted:
          completed = await _importEncryptedFile(file, task: _importTask);
        case _ImportFileKind.json:
          await _importJson(file);
        case _ImportFileKind.txt:
          await _importTxt(file);
        case _ImportFileKind.csv:
          await _importCsv(file);
        case _ImportFileKind.unsupported:
          throw const FormatException('Unsupported import file');
      }
      if (!completed) {
        _importTask?.dismiss();
        return;
      }
      _showImportProgress();
      _importHeartbeat?.cancel();
      _importTask?.completeSuccess(_importSummary);
      final conversion = _legacyConversion;
      if (mounted && conversion != null && conversion.converted) {
        // Only successful imports show a report; startup and database reloads
        // never block on a conversion notice.
        await showLegacyConversionDialog(
          context,
          theme: ref.read(themeProvider),
          conversion: conversion,
          dbPath: _selectedFile!,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      final cancelled = error is ImportCancelled;
      if (cancelled) {
        _importMessage = 'Cancelling import and restoring checkpoint...';
        _showImportProgress();
      }
      final checkpoint = _imageCheckpoint;
      _imageCheckpoint = null;
      try {
        await checkpoint?.finish(committed: _importCommitted);
      } catch (restoreError) {
        _showImportProgress();
        _importTask?.completeError(
          'Database import stopped, but image recovery failed: $restoreError',
        );
        return;
      }
      _showImportProgress();
      if (cancelled) {
        _importTask?.completeSuccess(
          'Import cancelled. Previous library restored.',
        );
      } else {
        _importTask?.completeError(
          _importCommitted
              ? 'Import saved, but refreshing or saving the encrypted file failed: $error'
              : 'Import rejected; previous library preserved. $error',
        );
      }
    } finally {
      _importHeartbeat?.cancel();
      try {
        await _imageCheckpoint?.finish(committed: _importCommitted);
      } finally {
        _imageCheckpoint = null;
        if (mounted) setState(() => _isImporting = false);
      }
    }
  }

  Future<bool> _importEncryptedFile(
    File file, {
    NotificationHandle? task,
  }) async {
    final encryptedKind = await detectEncryptedImportKind(file);
    switch (encryptedKind) {
      case EncryptedImportKind.uniKmDatabase:
        return _importEncryptedDatabase(
          file,
          title: 'Unlock UniKM Backup',
          message:
              'This UniKM backup is encrypted. Enter the password to import it.',
          task: task,
          decrypt: (password) => decryptUniKmDatabaseToTemp(file, password),
        );
      case EncryptedImportKind.steamKm2Database:
        return _importEncryptedDatabase(
          file,
          title: 'Unlock SteamKM2 Backup',
          message:
              'This SteamKM2 backup is encrypted. Enter the password to import it.',
          task: task,
          decrypt: (password) => decryptSteamKm2DatabaseToTemp(file, password),
        );
      case EncryptedImportKind.steamKm1Json:
        return _importSteamKm1EncryptedBackup(file, task: task);
      case EncryptedImportKind.unknown:
        throw Exception('Unsupported encrypted import format');
    }
  }

  Future<bool> _importEncryptedDatabase(
    File file, {
    required String title,
    required String message,
    required Future<PreparedEncryptedDatabaseImport> Function(String password)
    decrypt,
    NotificationHandle? task,
  }) async {
    final prepared = await _promptForEncryptedImport(
      title: title,
      message: message,
      task: task,
      action: decrypt,
    );
    if (prepared == null) {
      return false;
    }

    try {
      await _importSqliteDatabase(File(prepared.databasePath), task: task);
      return true;
    } finally {
      await prepared.dispose();
    }
  }

  Future<bool> _importSteamKm1EncryptedBackup(
    File file, {
    NotificationHandle? task,
  }) async {
    final decryptedJson = await _promptForEncryptedImport<String>(
      title: 'Unlock SteamKM1 Backup',
      message:
          'This SteamKM1 backup is encrypted. Enter the password to import it.',
      task: task,
      action: (password) => decryptSteamKm1JsonExport(file, password),
    );
    if (decryptedJson == null) {
      return false;
    }

    final decoded = jsonDecode(decryptedJson);
    final records = parseSteamKm1JsonExportData(decoded);
    await _importSteamKm1Records(
      records,
      sourceFile: file,
      sourceLabel: 'SteamKM1 encrypted backup',
      task: task,
    );
    return true;
  }

  Future<T?> _promptForEncryptedImport<T>({
    required String title,
    required String message,
    required Future<T> Function(String password) action,
    NotificationHandle? task,
  }) async {
    while (true) {
      _checkImport();
      final password = await _promptForImportPassword(
        title: title,
        message: message,
      );
      if (password == null) {
        return null;
      }

      try {
        _checkImport();
        return await action(password);
      } on InvalidPasswordException {
        task?.update(message: 'Incorrect password, try again...');
      }
    }
  }

  Future<String?> _promptForImportPassword({
    required String title,
    required String message,
  }) {
    final theme = ref.read(themeProvider);
    return DatabaseUnlockDialog.show(
      context,
      theme,
      title: title,
      message: message,
    );
  }

  Future<void> _importSqliteDatabase(
    File file, {
    NotificationHandle? task,
  }) async {
    final prepared = await readSqliteImport(
      file.path,
      checkCancelled: _checkImport,
    );
    final source = prepared.tables;
    _legacyConversion = prepared.conversion;
    _checkImport();
    final tags = <int, ImportTagSpec>{};
    for (final row in source['tags']!) {
      tags[row['id'] as int] = (
        name: row['name'] as String,
        color: row['color'] as String? ?? '#0078d4',
        isSteamTag: row['is_steam_tag'] == 1,
      );
    }
    final links = <int, List<String>>{};
    final gameIds = source['games']!.map((r) => r['id'] as int).toSet();
    for (final row in source['game_tags']!) {
      final tag = tags[row['tag_id']];
      if (tag == null || !gameIds.contains(row['game_id'])) {
        throw const FormatException('Database contains invalid game/tag links');
      }
      links.putIfAbsent(row['game_id'] as int, () => []).add(tag.name);
    }
    final records = <ImportRecord>[];
    for (final row in source['games']!) {
      final rawDeadline = row['deadline_date'];
      final epoch = rawDeadline is int
          ? rawDeadline
          : int.tryParse('$rawDeadline');
      final game = GamesCompanion.insert(
        title: row['title'] as String,
        gameKey: row['game_key'] as String,
        platform: Value(row['platform'] as String? ?? 'Steam'),
        notes: Value(row['notes'] as String? ?? ''),
        isUsed: Value(row['is_used'] == 1),
        coverImage: Value(row['cover_image'] as String? ?? ''),
        hasDeadline: Value(row['has_deadline'] == 1),
        deadlineDate: Value(
          epoch != null && epoch > 0
              ? DateTime.fromMillisecondsSinceEpoch(epoch * 1000)
              : null,
        ),
        isDlc: Value(row['is_dlc'] == 1),
        steamAppId: Value(row['steam_app_id'] as String? ?? ''),
        developer: Value(row['developer'] as String? ?? ''),
        reviewScore: Value(row['review_score'] as int? ?? 0),
        reviewCount: Value(row['review_count'] as int? ?? 0),
        updatedAt: Value(DateTime.now()),
      );
      _importDatabase!.games
          .validateIntegrity(game, isInserting: true)
          .throwIfInvalid(game);
      records.add(ImportRecord(game, links[row['id']] ?? []));
    }
    final imagesDir = await _resolveManagedImagesDirectory();
    final cache = <String, String>{};
    final normalized = <ImportRecord>[];
    for (var i = 0; i < records.length; i++) {
      _checkImport();
      final record = records[i];
      final cover = await _normalizeImportedCoverImagePath(
        record.game.coverImage.value,
        sourceDbFile: file,
        targetImagesDir: imagesDir,
        cache: cache,
      );
      normalized.add(
        ImportRecord(
          record.game.copyWith(coverImage: Value(cover)),
          record.tagNames,
        ),
      );
      if (i % 100 == 0) {
        _importMessage = 'Preparing images: ${i + 1} of ${records.length}';
        _showImportProgress();
        await Future<void>.delayed(Duration.zero);
      }
    }
    await _commitLibraryImport(
      normalized,
      'database',
      tagSpecs: tags.values.toList(),
    );
    for (final path in cache.values) {
      PaintingBinding.instance.imageCache.evict(FileImage(File(path)));
    }
  }

  Future<Directory> _resolveManagedImagesDirectory() async {
    final dbPath = await AppDatabase.getDatabasePath();
    // Use the same path as SteamService: {dbDir}/images/steam/
    final imagesDir = Directory(p.join(p.dirname(dbPath), 'images', 'steam'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesDir;
  }

  Future<String> _normalizeImportedCoverImagePath(
    String rawCoverImage, {
    required File sourceDbFile,
    required Directory targetImagesDir,
    required Map<String, String> cache,
  }) async {
    final raw = rawCoverImage.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.startsWith('assets/')) return raw;

    final cached = cache[raw];
    if (cached != null) return cached;

    final sourceFile = _resolveSourceCoverImageFile(raw, sourceDbFile);
    if (sourceFile == null || !await sourceFile.exists()) {
      cache[raw] = raw;
      return raw;
    }

    final destinationFile = await _resolveImageDestination(
      sourceFile,
      targetImagesDir,
    );

    final sourceCanonical = _normalizeForCompare(sourceFile.absolute.path);
    final destinationCanonical = _normalizeForCompare(
      destinationFile.absolute.path,
    );
    if (sourceCanonical != destinationCanonical) {
      _checkImport();
      await _imageCheckpoint!.copy(sourceFile, destinationFile);
    }

    cache[raw] = destinationFile.path;
    return destinationFile.path;
  }

  File? _resolveSourceCoverImageFile(String raw, File sourceDbFile) {
    final uri = Uri.tryParse(raw);
    final fromFileUri = uri != null && uri.scheme.toLowerCase() == 'file'
        ? File.fromUri(uri)
        : null;
    if (fromFileUri != null) return fromFileUri;

    if (p.isAbsolute(raw) || _windowsPathPattern.hasMatch(raw)) {
      return File(raw);
    }

    final dbDir = sourceDbFile.parent;
    final normalizedRaw = raw.replaceAll('\\', Platform.pathSeparator);
    return File(p.normalize(p.join(dbDir.path, normalizedRaw)));
  }

  Future<File> _resolveImageDestination(
    File sourceFile,
    Directory targetImagesDir,
  ) async {
    final sourceName = p.basename(sourceFile.path);
    final safeName = sourceName.isEmpty
        ? 'cover_${DateTime.now().millisecondsSinceEpoch}.img'
        : sourceName;

    final initial = File(p.join(targetImagesDir.path, safeName));
    if (!await initial.exists()) {
      return initial;
    }

    final sourceCanonical = _normalizeForCompare(sourceFile.absolute.path);
    final initialCanonical = _normalizeForCompare(initial.absolute.path);
    if (sourceCanonical == initialCanonical) {
      return initial;
    }

    // A file with the same name already exists at the destination but the
    // source is a different path (e.g. re-importing the same database from
    // another location). Overwrite it so there is always exactly one image
    // per appID
    return initial;
  }

  String _normalizeForCompare(String path) {
    return p.normalize(path).replaceAll('\\', '/').toLowerCase();
  }

  Future<void> _importJson(File file, {NotificationHandle? task}) async {
    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (looksLikeSteamKm1JsonExportData(decoded)) {
      final records = parseSteamKm1JsonExportData(decoded);
      await _importSteamKm1Records(
        records,
        sourceFile: file,
        sourceLabel: 'SteamKM1 JSON',
        task: task,
      );
      return;
    }

    await _commitLibraryImport(parseLibraryJson(content), 'JSON');
  }

  Future<void> _commitLibraryImport(
    List<ImportRecord> records,
    String source, {
    List<ImportTagSpec> tagSpecs = const [],
  }) async {
    final db = ref.read(requireDatabaseProvider);
    _checkImport();
    final result = await LibraryImporter(db).commit(
      records,
      _activeImportMode,
      checkCancelled: _checkImport,
      onProgress: _reportImportProgress,
      tagSpecs: tagSpecs,
    );
    _importCommitted = true;
    _importMessage = 'Saving imported library...';
    _showImportProgress();
    if (!mounted || !identical(ref.read(databaseProvider), db)) return;
    await _markImportSyncDirty(ref, db);
    await persistEncryptedDbIfNeeded(ref);
    if (!mounted || !identical(ref.read(databaseProvider), db)) return;
    await ref.read(gamesProvider.notifier).refresh();
    await ref.read(tagsProvider.notifier).refresh();
    _importSummary =
        'Imported ${result.imported} games from $source, updated ${result.updated}';
    if (result.skipped > 0) {
      _importSummary += ' (skipped ${result.skipped} duplicates)';
    }
  }

  Future<void> _importTxt(File file, {NotificationHandle? task}) async {
    final content = await file.readAsString();
    final records = parseSteamKm1TextExport(content);
    if (records.isEmpty) {
      throw Exception('No valid games found in text import');
    }

    await _importSteamKm1Records(
      records,
      sourceFile: file,
      sourceLabel: 'SteamKM1 text',
      task: task,
    );
  }

  Future<void> _importSteamKm1Records(
    List<SteamKm1ImportedGame> records, {
    required File sourceFile,
    required String sourceLabel,
    NotificationHandle? task,
  }) async {
    final imagesDir = await _resolveManagedImagesDirectory();
    final cache = <String, String>{};
    final imported = <ImportRecord>[];
    for (var i = 0; i < records.length; i++) {
      _checkImport();
      final record = records[i];
      final cover = await _normalizeImportedCoverImagePath(
        record.iconPath ?? '',
        sourceDbFile: sourceFile,
        targetImagesDir: imagesDir,
        cache: cache,
      );
      final developer = record.developer?.trim() ?? '';
      final category = record.category?.trim() ?? '';
      imported.add(
        ImportRecord(
          GamesCompanion.insert(
            title: record.title,
            gameKey: record.key,
            platform: const Value('Steam'),
            coverImage: Value(cover),
            steamAppId: Value(record.appId ?? ''),
            developer: developer.isEmpty
                ? const Value.absent()
                : Value(developer),
            reviewScore: Value(record.reviewScore ?? 0),
            reviewCount: Value(record.reviewCount ?? 0),
            updatedAt: Value(DateTime.now()),
          ),
          category.isEmpty || category.toLowerCase() == 'new' ? [] : [category],
        ),
      );
      if (i % 100 == 0) await Future<void>.delayed(Duration.zero);
    }
    await _commitLibraryImport(imported, sourceLabel);
  }

  Future<void> _importCsv(File file) async {
    final records = parseLibraryCsv(await file.readAsString());
    await _commitLibraryImport(records, 'CSV');
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final supportsDragAndDrop = PlatformFileActions.supportsDragAndDrop;

    return ThemedAlertDialog(
      theme: theme,

      maxWidth: 550,
      title: DialogHeader(
        icon: Icons.download,
        title: 'Import Database',
        theme: theme,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // File selection
          SectionGroupBox(
            title: 'Source File',
            titleIcon: Icons.upload_file,
            theme: theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Focus(
                  autofocus: false,
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _isHovering = true),
                    onExit: (_) => setState(() => _isHovering = false),
                    child: WindowDropTarget(
                      enable: supportsDragAndDrop && !_isImporting,
                      onDragDone: (details) async {
                        setState(() => _isDragging = false);
                        if (details.files.length != 1 ||
                            details.files.single is DropItemDirectory) {
                          NotificationManager.instance.error(
                            'Drop one supported database import file.',
                          );
                          return;
                        }
                        await _handleSelectedFilePath(
                          details.files.single.path,
                        );
                      },
                      onDragEntered: (_) => setState(() => _isDragging = true),
                      onDragExited: (_) => setState(() => _isDragging = false),
                      child: InkWell(
                        onTap: _isImporting ? null : _selectFile,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _isDragging
                                ? theme.accent.withValues(alpha: 0.1)
                                : _isHovering
                                ? theme.accent.withValues(alpha: 0.05)
                                : theme.inputBackground,
                            borderRadius: BorderRadius.circular(
                              theme.cornerRadius,
                            ),
                            border: Border.all(
                              color: _isDragging
                                  ? theme.accent
                                  : _isHovering
                                  ? theme.accent.withValues(alpha: 0.5)
                                  : (_selectedFile != null
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
                                    : (_selectedFile != null
                                          ? Icons.check_circle
                                          : Icons.folder_open),
                                color: _isDragging
                                    ? theme.accent
                                    : (_selectedFile != null
                                          ? theme.accent
                                          : theme.textSecondary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _selectedFile != null
                                      ? p.basename(_selectedFile!)
                                      : (_isDragging && supportsDragAndDrop
                                            ? 'Drop file here...'
                                            : supportsDragAndDrop
                                            ? 'Click to select or drag file here...'
                                            : 'Tap to select a file...'),
                                  style: TextStyle(
                                    color: _isDragging
                                        ? theme.accent
                                        : (_selectedFile != null
                                              ? theme.textPrimary
                                              : theme.textHint),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_selectedFile != null)
                                IconButton(
                                  tooltip: 'Clear selection',
                                  style: theme.compactIconButtonStyle,
                                  onPressed: _isImporting
                                      ? null
                                      : _clearFileSelection,
                                  icon: const Icon(Icons.close, size: 20),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: kElementVSpacing),
                Text(
                  'Supported: SQLite databases (including files without an extension), .enc, .json, .csv, .txt, and compatible .bak backups',
                  style: TextStyle(color: theme.textSecondary, fontSize: 12),
                ),
                if (_selectedFile != null && _previewCount > 0) ...[
                  const SizedBox(height: kElementVSpacing),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(theme.cornerRadius),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: theme.accent),
                        const SizedBox(width: kElementHSpacing),
                        Text(
                          '$_previewCount games found in file',
                          style: TextStyle(
                            color: theme.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: kDialogSpacing),

          // Import mode and options in connected groupboxes
          SectionGroupBox(
            title: 'Import Mode',
            titleIcon: Icons.swap_horiz,
            theme: theme,
            groupPosition: SectionGroupPosition.first,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RadioGroup<String>(
                  groupValue: _importMode,
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _importMode = v);
                  },
                  child: Column(
                    children: [
                      for (final option in _importModeOptions)
                        _buildDialogRadioOption(theme, option),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SectionGroupBox(
            title: 'Options',
            titleIcon: Icons.settings,
            theme: theme,
            groupPosition: SectionGroupPosition.last,
            alternateBackground: true,
            child: ToggleSettingRow(
              theme: theme,
              label: 'Allow duplicate keys',
              value: _allowDuplicates,
              onChanged: (value) => setState(() => _allowDuplicates = value),
            ),
          ),

          if (_importMode == 'replace') ...[
            const SizedBox(height: 12),
            DialogBanner.caution(
              theme: theme,
              message: 'Replace mode will delete all existing data!',
            ),
          ],
        ],
      ),
      actions: [
        if (_isImporting && !_importCommitted)
          OutlinedButton(
            onPressed: _cancelRequested
                ? null
                : () {
                    _cancelRequested = true;
                    _importMessage =
                        'Cancelling import and restoring checkpoint...';
                    _showImportProgress();
                  },
            child: const Text('Cancel import'),
          ),
        DialogActionBar(
          theme: theme,
          onConfirm: _import,
          confirmIcon: Icons.download,
          confirmLabel: 'Import',
          isLoading: _isImporting,
          isEnabled: _selectedFile != null,
          spinnerSize: 18,
        ),
      ],
    );
  }
}
