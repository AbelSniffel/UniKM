/// Import/Export dialogs for database operations
library;

import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../core/database/database.dart';
import '../../core/settings/settings_model.dart';
import '../../core/services/encryption_manager.dart';
import '../../core/services/legacy_db_converter.dart';
import '../../core/services/legacy_encrypted_import.dart';
import '../../core/services/platform_file_actions.dart';
import '../../core/services/steamkm1_import.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
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
  await ref.read(settingsProvider.notifier).setSetting(
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
  return showDialog<void>(
    context: context,
    builder: (ctx) => const ExportDialog(),
  );
}

/// Show import dialog
Future<void> showImportDialog(BuildContext context) {
  return showDialog<void>(
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

      // Filter based on options
      final filteredGames = _includeUsed
          ? games
          : games.where((g) => !g.isUsed).toList();

      // Build export data
      String exportData;
      if (_exportFormat == 'json') {
        exportData = _buildJsonExport(filteredGames, tags);
      } else if (_exportFormat == 'csv') {
        exportData = _buildCsvExport(filteredGames, tags);
      } else {
        exportData = _buildTextExport(filteredGames);
      }

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

  String _buildJsonExport(List<dynamic> games, List<dynamic> tags) {
    final gamesList = games.map((g) {
      final map = <String, dynamic>{
        'title': g.title,
        'key': g.gameKey,
        'platform': g.platform,
        'is_used': g.isUsed,
        'is_dlc': g.isDlc,
        'rating': g.rating,
      };

      if (_includeTags && g.tagIds.isNotEmpty) {
        final tagNames = g.tagIds
            .map((id) => tags.where((t) => t.id == id).firstOrNull)
            .where((t) => t != null)
            .map((t) => t!.name)
            .toList();
        map['tags'] = tagNames;
      }

      if (_includeNotes && g.notes != null) {
        map['notes'] = g.notes;
      }

      if (g.coverImage != null) {
        map['cover_image'] = g.coverImage;
      }

      if (g.hasDeadline && g.deadlineDate != null) {
        map['deadline'] = g.deadlineDate!.toIso8601String();
      }

      return map;
    }).toList();

    return const JsonEncoder.withIndent('  ').convert({
      'exported_at': DateTime.now().toIso8601String(),
      'games': gamesList,
    });
  }

  String _buildCsvExport(List<dynamic> games, List<dynamic> tags) {
    final buffer = StringBuffer();

    // Header
    final headers = ['Title', 'Key', 'Platform', 'Used', 'DLC', 'Rating'];
    if (_includeTags) headers.add('Tags');
    if (_includeNotes) headers.add('Notes');
    buffer.writeln(headers.join(','));

    // Rows
    for (final g in games) {
      final row = [
        _csvEscape(g.title),
        _csvEscape(g.gameKey),
        _csvEscape(g.platform),
        g.isUsed ? 'Yes' : 'No',
        g.isDlc ? 'Yes' : 'No',
        g.rating.toString(),
      ];

      if (_includeTags) {
        final tagNames = g.tagIds
            .map((id) => tags.where((t) => t.id == id).firstOrNull)
            .where((t) => t != null)
            .map((t) => t!.name)
            .join(';');
        row.add(_csvEscape(tagNames));
      }

      if (_includeNotes) {
        row.add(_csvEscape(g.notes ?? ''));
      }

      buffer.writeln(row.join(','));
    }

    return buffer.toString();
  }

  String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  String _buildTextExport(List<dynamic> games) {
    final buffer = StringBuffer();
    for (final g in games) {
      buffer.writeln('${g.title} | ${g.gameKey}');
    }
    return buffer.toString();
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
            groupPosition: showsAdditionalInfo ? SectionGroupPosition.first : SectionGroupPosition.only,
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
  String _importMode = 'merge';
  bool _isImporting = false;
  int _previewCount = 0;
  bool _isDragging = false;
  bool _isHovering = false;
  bool _allowDuplicates = false;
  static final RegExp _windowsPathPattern = RegExp(r'^[a-zA-Z]:[\\/]');

  bool get _isMerge => _importMode == 'merge' || _importMode == 'skip';
  bool get _isReplace => _importMode == 'replace';
  bool get _isUpdate => _importMode == 'update';

  Future<bool> _confirmReplaceIfNeeded() async {
    if (!_isReplace) return true;
    final theme = ref.read(themeProvider);
    return showConfirmDialog(
      context: context,
      theme: theme,
      title: 'Replace all data?',
      message:
          'This will delete all existing games, tags, and backups before importing.',
      confirmLabel: 'Replace',
    );
  }

  Future<void> _selectFile() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Select Database File',
      type: FileType.custom,
      allowedExtensions: [
        'db',
        'sqlite',
        'sqlite3',
        'enc',
        'json',
        'csv',
        'txt',
        'bak',
      ],
    );

    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path != null) {
        await _handleSelectedFilePath(path);
      }
    }
  }

  Future<void> _handleSelectedFilePath(String path) async {
    final kind = _classifyImportFile(path);
    if (kind == _ImportFileKind.unsupported) {
      NotificationManager.instance.error(
        'Unsupported file type. Please select .db, .sqlite, .sqlite3, .enc, .json, .csv, .txt, or supported .bak backups',
      );
      return;
    }

    setState(() {
      _selectedFile = path;
      _previewCount = 0;
      _isDragging = false;
    });

    await _scanFileForCount(File(path));
  }

  _ImportFileKind _classifyImportFile(String path) {
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
    return _ImportFileKind.unsupported;
  }

  Future<void> _scanFileForCount(File file) async {
    try {
      final kind = _classifyImportFile(file.path);
      int count = 0;

      if (kind == _ImportFileKind.sqlite) {
        // Count games in SQLite
        final sourceDb = sqlite3.sqlite3.open(
          file.path,
          mode: sqlite3.OpenMode.readOnly,
        );
        try {
          final result = sourceDb.select('SELECT COUNT(*) as count FROM games');
          count = result.first['count'] as int;
        } finally {
          sourceDb.close();
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
        final lines = await file.readAsLines();
        count = lines.length - 1; // Exclude header
        if (count < 0) count = 0;
      }

      if (!mounted) return;
      setState(() => _previewCount = count);
    } catch (e) {
      // Ignore errors during preview count
    }
  }

  Future<void> _import() async {
    if (_selectedFile == null) return;

    if (!await _confirmReplaceIfNeeded()) return;

    setState(() => _isImporting = true);

    NotificationHandle? task;

    try {
      final file = File(_selectedFile!);
      final kind = _classifyImportFile(_selectedFile!);

      final db = ref.read(requireDatabaseProvider);
      if (_isReplace) {
        await db.clearAllData();
        await ref.read(gamesProvider.notifier).refresh();
        await ref.read(tagsProvider.notifier).refresh();
        await persistEncryptedDbIfNeeded(ref);
      }

      task = NotificationManager.instance.beginTask('Importing...');

      var completed = true;
      if (kind == _ImportFileKind.sqlite) {
        // Import SQLite database
        await _importSqliteDatabase(file, task: task);
      } else if (kind == _ImportFileKind.encrypted) {
        completed = await _importEncryptedFile(file, task: task);
      } else if (kind == _ImportFileKind.json) {
        // Import JSON
        await _importJson(file, task: task);
      } else if (kind == _ImportFileKind.txt) {
        // Import plain text export
        await _importTxt(file, task: task);
      } else if (kind == _ImportFileKind.csv) {
        // Import CSV
        await _importCsv(file, task: task);
      } else {
        throw Exception('Unsupported import file');
      }

      if (!completed) {
        task.dismiss();
        return;
      }

      task.completeSuccess('Import completed');

      if (mounted) Navigator.pop(context);
    } catch (e) {
      task?.completeError('Import failed: $e');
      NotificationManager.instance.error('Import failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
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
      final password = await _promptForImportPassword(
        title: title,
        message: message,
      );
      if (password == null) {
        return null;
      }

      try {
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
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          DatabaseUnlockDialog(theme: theme, title: title, message: message),
    );
  }

  Future<void> _importSqliteDatabase(
    File file, {
    NotificationHandle? task,
  }) async {
    final prepared = await prepareDatabaseForImport(file.path);
    final conversion = prepared.conversion;
    if (conversion.converted && conversion.actions.isNotEmpty) {
      task?.update(
        message:
            'Normalized legacy layout (${conversion.actions.length} changes)...',
      );
    }

    // Import from a normalized UniKM SQLite database
    final db = ref.read(requireDatabaseProvider);

    // Open source database using sqlite3 directly
    final sourceDb = sqlite3.sqlite3.open(
      prepared.preparedPath,
      mode: sqlite3.OpenMode.readOnly,
    );

    try {
      // Read all games from source (without GROUP_CONCAT for simplicity)
      final gameResult = sourceDb.select('SELECT * FROM games');

      // Read all tags from source
      final tagResult = sourceDb.select('SELECT * FROM tags');

      // Read game_tags for linking
      final gameTagsResult = sourceDb.select('SELECT * FROM game_tags');

      // Import tags first
      final tagIdMap = <int, int>{}; // old_id -> new_id

      // Build game -> tags map (pure in-memory, no DB)
      final gameTagsMap = <int, List<int>>{};
      for (final row in gameTagsResult) {
        final gameId = row['game_id'] as int;
        final tagId = row['tag_id'] as int;
        gameTagsMap.putIfAbsent(gameId, () => []).add(tagId);
      }

      // Pre-normalize cover image paths before opening the transaction so that
      // file I/O (copy, exists-check) stays outside the SQLite write path.
      final imagesDir = await _resolveManagedImagesDirectory();
      final importedCoverPathCache = <String, String>{};
      final copiedImagePaths = <String>{};
      final normalizedCoverImages = <int, String>{};
      for (final row in gameResult) {
        final oldGameId = row['id'] as int;
        final sourceCoverImage = row['cover_image'] as String? ?? '';
        final normalizedCoverImage = await _normalizeImportedCoverImagePath(
          sourceCoverImage,
          sourceDbFile: file,
          targetImagesDir: imagesDir,
          cache: importedCoverPathCache,
        );
        normalizedCoverImages[oldGameId] = normalizedCoverImage;
        if (sourceCoverImage.trim().isNotEmpty &&
            normalizedCoverImage != sourceCoverImage) {
          copiedImagePaths.add(normalizedCoverImage);
        }
      }

      // Wrap all DB writes in one transaction � the single biggest performance
      // gain for large imports (avoids an implicit transaction per statement).
      int importedCount = 0;
      int skippedCount = 0;
      int updatedCount = 0;
      await db.transaction(() async {
        // Import tags inside the transaction
        for (final row in tagResult) {
          final name = row['name'] as String;
          final color = row['color'] as String? ?? '#0078d4';
          final isSteamTag = (row['is_steam_tag'] as int?) == 1;

          final entry = await db.getOrCreateTag(
            name,
            color: color,
            isSteamTag: isSteamTag,
          );
          tagIdMap[row['id'] as int] = entry.id;
        }

        // Import games inside the same transaction
        for (final row in gameResult) {
          final key = row['game_key'] as String;
          final notes = row['notes'] as String? ?? '';
          final existingId = await db.getGameIdByKey(key);
          if (_isMerge && existingId != null && !_allowDuplicates) {
            skippedCount++;
            continue;
          }

          // Parse deadline date if present
          DateTime? deadlineDate;
          final rawDeadline = row['deadline_date'];
          if (rawDeadline is int && rawDeadline > 0) {
            deadlineDate = DateTime.fromMillisecondsSinceEpoch(
              rawDeadline * 1000,
            );
          } else if (rawDeadline is String && rawDeadline.isNotEmpty) {
            final epoch = int.tryParse(rawDeadline);
            if (epoch != null && epoch > 0) {
              deadlineDate = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
            }
          }

          final oldGameId = row['id'] as int;
          final normalizedCoverImage = normalizedCoverImages[oldGameId] ?? '';

          int gameId;
          if (_isUpdate && existingId != null) {
            gameId = existingId;
            await db.updateGameFields(
              gameId,
              title: row['title'] as String,
              platform: row['platform'] as String? ?? 'Steam',
              notes: notes,
              isUsed: (row['is_used'] as int?) == 1,
              coverImage: normalizedCoverImage,
              hasDeadline: (row['has_deadline'] as int?) == 1,
              deadlineDate: deadlineDate,
              isDlc: (row['is_dlc'] as int?) == 1,
              steamAppId: row['steam_app_id'] as String? ?? '',
              reviewScore: row['review_score'] as int? ?? 0,
              reviewCount: row['review_count'] as int? ?? 0,
              updatedAt: DateTime.now(),
            );
            updatedCount++;
          } else {
            gameId = await db.insertGame(
              GamesCompanion.insert(
                title: row['title'] as String,
                gameKey: key,
                platform: Value(row['platform'] as String? ?? 'Steam'),
                notes: Value(notes),
                isUsed: Value((row['is_used'] as int?) == 1),
                coverImage: Value(normalizedCoverImage),
                hasDeadline: Value((row['has_deadline'] as int?) == 1),
                deadlineDate: Value(deadlineDate),
                isDlc: Value((row['is_dlc'] as int?) == 1),
                steamAppId: Value(row['steam_app_id'] as String? ?? ''),
                reviewScore: Value(row['review_score'] as int? ?? 0),
                reviewCount: Value(row['review_count'] as int? ?? 0),
                updatedAt: Value(DateTime.now()),
              ),
            );
            importedCount++;
          }

          // Link tags using the old->new id map
          final oldTagIds = gameTagsMap[oldGameId] ?? [];
          final newTagIds = <int>[];
          for (final oldTagId in oldTagIds) {
            final newTagId = tagIdMap[oldTagId];
            if (newTagId != null) {
              newTagIds.add(newTagId);
            }
          }
          await db.setTagsForGame(gameId, newTagIds);

          if (task != null && importedCount + updatedCount + skippedCount > 0) {
            final done = importedCount + updatedCount + skippedCount;
            task.update(message: 'Imported $done...');
          }
        }
      });

      // Refresh games list
      await ref.read(gamesProvider.notifier).refresh();
      await ref.read(tagsProvider.notifier).refresh();
      await persistEncryptedDbIfNeeded(ref);
      await _markImportSyncDirty(ref, db);

      // Evict only the overwritten image paths from Flutter's cache so game
      // cards immediately display fresh artwork without reloading every other
      // cached image unnecessarily.
      for (final path in copiedImagePaths) {
        PaintingBinding.instance.imageCache.evict(FileImage(File(path)));
      }

      String message = 'Imported $importedCount games';
      if (updatedCount > 0) message += ', updated $updatedCount';
      message += ' and ${tagIdMap.length} tags';
      if (copiedImagePaths.isNotEmpty) {
        message += ', copied ${copiedImagePaths.length} cover images';
      }
      if (skippedCount > 0) {
        message += ' (skipped $skippedCount duplicates)';
      }
      NotificationManager.instance.success(message);
    } finally {
      sourceDb.close();
      await prepared.dispose();
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
      await sourceFile.copy(destinationFile.path);
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

    final db = ref.read(requireDatabaseProvider);

    try {
      final data = decoded is Map<String, dynamic> ? decoded : null;

      if (data == null || data['games'] == null) {
        throw Exception('Invalid JSON format - missing games array');
      }

      final games = data['games'] as List;

      // First pass: collect all tags
      final tagIdMap = <String, int>{}; // tag_name -> tag_id

      for (final gameData in games) {
        final gameTags = gameData['tags'] as List?;
        if (gameTags != null) {
          for (final tagName in gameTags) {
            final name = tagName.toString();
            if (!tagIdMap.containsKey(name)) {
              final tagEntry = await db.getOrCreateTag(name);
              tagIdMap[name] = tagEntry.id;
            }
          }
        }
      }

      // Import games
      int importedCount = 0;
      int skippedCount = 0;
      int updatedCount = 0;

      for (final gameData in games) {
        final key = gameData['key'] as String?;
        if (key == null || key.isEmpty) continue;

        final existingId = await db.getGameIdByKey(key);
        if (_isMerge && existingId != null && !_allowDuplicates) {
          skippedCount++;
          continue;
        }
        final notes = (gameData['notes'] as String?) ?? '';

        // Parse deadline date if present
        DateTime? deadlineDate;
        final deadline = gameData['deadline'] as String?;
        if (deadline != null && deadline.isNotEmpty) {
          try {
            deadlineDate = DateTime.parse(deadline);
          } catch (_) {}
        }

        int gameId;
        if (_isUpdate && existingId != null) {
          gameId = existingId;
          await db.updateGameFields(
            gameId,
            title: (gameData['title'] as String?) ?? 'Unknown',
            platform: (gameData['platform'] as String?) ?? 'Steam',
            notes: notes,
            isUsed: (gameData['is_used'] as bool?) ?? false,
            coverImage: (gameData['cover_image'] as String?) ?? '',
            hasDeadline: deadlineDate != null,
            deadlineDate: deadlineDate,
            isDlc: (gameData['is_dlc'] as bool?) ?? false,
            steamAppId: (gameData['steam_app_id'] as String?) ?? '',
            reviewScore: (gameData['rating'] as int?) ?? 0,
            updatedAt: DateTime.now(),
          );
          updatedCount++;
        } else {
          gameId = await db.insertGame(
            GamesCompanion.insert(
              title: (gameData['title'] as String?) ?? 'Unknown',
              gameKey: key,
              platform: Value((gameData['platform'] as String?) ?? 'Steam'),
              notes: Value(notes),
              isUsed: Value((gameData['is_used'] as bool?) ?? false),
              coverImage: Value((gameData['cover_image'] as String?) ?? ''),
              hasDeadline: Value(deadlineDate != null),
              deadlineDate: Value(deadlineDate),
              isDlc: Value((gameData['is_dlc'] as bool?) ?? false),
              steamAppId: Value((gameData['steam_app_id'] as String?) ?? ''),
              reviewScore: Value((gameData['rating'] as int?) ?? 0),
              updatedAt: Value(DateTime.now()),
            ),
          );
          importedCount++;
        }

        // Link tags (replace existing)
        final gameTags = gameData['tags'] as List?;
        if (gameTags != null) {
          final ids = <int>[];
          for (final tagName in gameTags) {
            final tagId = tagIdMap[tagName.toString()];
            if (tagId != null) ids.add(tagId);
          }
          await db.setTagsForGame(gameId, ids);
        }

        if (task != null && importedCount + updatedCount + skippedCount > 0) {
          final done = importedCount + updatedCount + skippedCount;
          task.update(message: 'Imported $done...');
        }
      }

      // Refresh
      await ref.read(gamesProvider.notifier).refresh();
      await ref.read(tagsProvider.notifier).refresh();
      await persistEncryptedDbIfNeeded(ref);
      await _markImportSyncDirty(ref, db);

      String message = 'Imported $importedCount games';
      if (updatedCount > 0) message += ', updated $updatedCount';
      if (skippedCount > 0) {
        message += ' (skipped $skippedCount duplicates)';
      }
      NotificationManager.instance.success(message);
    } catch (e) {
      throw Exception('JSON import failed: $e');
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
    final db = ref.read(requireDatabaseProvider);
    final imagesDir = await _resolveManagedImagesDirectory();
    final importedCoverPathCache = <String, String>{};
    final copiedImagePaths = <String>{};
    final categoryTagIdMap = <String, int>{};

    int importedCount = 0;
    int skippedCount = 0;
    int updatedCount = 0;

    for (final record in records) {
      final existingId = await db.getGameIdByKey(record.key);
      if (_isMerge && existingId != null && !_allowDuplicates) {
        skippedCount++;
        continue;
      }

      final sourceCoverImage = record.iconPath ?? '';
      final normalizedCoverImage = await _normalizeImportedCoverImagePath(
        sourceCoverImage,
        sourceDbFile: sourceFile,
        targetImagesDir: imagesDir,
        cache: importedCoverPathCache,
      );
      if (sourceCoverImage.trim().isNotEmpty &&
          normalizedCoverImage != sourceCoverImage) {
        copiedImagePaths.add(normalizedCoverImage);
      }

      final developer = record.developer?.trim();
      final reviewScore = record.reviewScore ?? 0;
      final reviewCount = record.reviewCount ?? 0;

      int gameId;
      if (_isUpdate && existingId != null) {
        gameId = existingId;
        await db.updateGameFields(
          gameId,
          title: record.title,
          platform: 'Steam',
          coverImage: normalizedCoverImage,
          steamAppId: record.appId ?? '',
          developer: developer != null && developer.isNotEmpty
              ? developer
              : null,
          reviewScore: reviewScore,
          reviewCount: reviewCount,
          updatedAt: DateTime.now(),
        );
        updatedCount++;
      } else {
        gameId = await db.insertGame(
          GamesCompanion.insert(
            title: record.title,
            gameKey: record.key,
            platform: const Value('Steam'),
            coverImage: Value(normalizedCoverImage),
            steamAppId: Value(record.appId ?? ''),
            developer: Value(developer ?? ''),
            reviewScore: Value(reviewScore),
            reviewCount: Value(reviewCount),
            updatedAt: Value(DateTime.now()),
          ),
        );
        if (developer != null && developer.isNotEmpty) {
          await db.updateGameFields(
            gameId,
            developer: developer,
            updatedAt: DateTime.now(),
          );
        }
        importedCount++;
      }

      final category = record.category?.trim() ?? '';
      if (category.isNotEmpty && category.toLowerCase() != 'new') {
        final existingTagId = categoryTagIdMap[category];
        final tagId = existingTagId ?? (await db.getOrCreateTag(category)).id;
        categoryTagIdMap[category] = tagId;
        await db.setTagsForGame(gameId, <int>[tagId]);
      } else {
        await db.setTagsForGame(gameId, const <int>[]);
      }

      if (task != null && importedCount + updatedCount + skippedCount > 0) {
        final done = importedCount + updatedCount + skippedCount;
        task.update(message: 'Imported $done from $sourceLabel...');
      }
    }

    await ref.read(gamesProvider.notifier).refresh();
    await ref.read(tagsProvider.notifier).refresh();
    await persistEncryptedDbIfNeeded(ref);
    await _markImportSyncDirty(ref, db);

    String message = 'Imported $importedCount games from $sourceLabel';
    if (updatedCount > 0) {
      message += ', updated $updatedCount';
    }
    if (categoryTagIdMap.isNotEmpty) {
      message += ', mapped ${categoryTagIdMap.length} categories to tags';
    }
    if (copiedImagePaths.isNotEmpty) {
      message += ', copied ${copiedImagePaths.length} cover images';
    }
    if (skippedCount > 0) {
      message += ' (skipped $skippedCount duplicates)';
    }
    NotificationManager.instance.success(message);
  }

  Future<void> _importCsv(File file, {NotificationHandle? task}) async {
    final lines = await file.readAsLines();
    if (lines.isEmpty) {
      throw Exception('CSV file is empty');
    }

    final db = ref.read(requireDatabaseProvider);

    // Parse header to find column indices
    final headers = _parseCsvLine(lines.first);
    final titleIdx = headers.indexOf('Title');
    final keyIdx = headers.indexOf('Key');
    final platformIdx = headers.indexOf('Platform');
    final usedIdx = headers.indexOf('Used');
    final dlcIdx = headers.indexOf('DLC');
    final ratingIdx = headers.indexOf('Rating');
    final tagsIdx = headers.indexOf('Tags');
    final notesIdx = headers.indexOf('Notes');

    if (keyIdx == -1) {
      throw Exception('CSV must have a "Key" column');
    }
    if (titleIdx == -1) {
      throw Exception('CSV must have a "Title" column');
    }

    // Tag name -> id map
    final tagIdMap = <String, int>{};

    int importedCount = 0;
    int skippedCount = 0;
    int updatedCount = 0;

    // Parse data rows
    for (var i = 1; i < lines.length; i++) {
      final values = _parseCsvLine(lines[i]);
      if (values.isEmpty) continue;

      final key = values.length > keyIdx ? values[keyIdx] : '';
      if (key.isEmpty) continue;

      final existingId = await db.getGameIdByKey(key);
      if (_isMerge && existingId != null && !_allowDuplicates) {
        skippedCount++;
        continue;
      }

      final title = values.length > titleIdx ? values[titleIdx] : 'Unknown';
      final platform = platformIdx >= 0 && values.length > platformIdx
          ? values[platformIdx]
          : 'Steam';
      final isUsed =
          usedIdx >= 0 &&
          values.length > usedIdx &&
          values[usedIdx].toLowerCase() == 'yes';
      final isDlc =
          dlcIdx >= 0 &&
          values.length > dlcIdx &&
          values[dlcIdx].toLowerCase() == 'yes';
      final rating = ratingIdx >= 0 && values.length > ratingIdx
          ? int.tryParse(values[ratingIdx]) ?? 0
          : 0;
      final notes = notesIdx >= 0 && values.length > notesIdx
          ? values[notesIdx]
          : '';

      int gameId;
      if (_isUpdate && existingId != null) {
        gameId = existingId;
        await db.updateGameFields(
          gameId,
          title: title,
          platform: platform,
          notes: notes,
          isUsed: isUsed,
          isDlc: isDlc,
          reviewScore: rating,
          updatedAt: DateTime.now(),
        );
        updatedCount++;
      } else {
        gameId = await db.insertGame(
          GamesCompanion.insert(
            title: title,
            gameKey: key,
            platform: Value(platform),
            notes: Value(notes),
            isUsed: Value(isUsed),
            isDlc: Value(isDlc),
            reviewScore: Value(rating),
            updatedAt: Value(DateTime.now()),
          ),
        );
        importedCount++;
      }

      // Handle tags (semicolon-separated) (replace existing)
      if (tagsIdx >= 0 &&
          values.length > tagsIdx &&
          values[tagsIdx].isNotEmpty) {
        final tagNames = values[tagsIdx]
            .split(';')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty);
        final ids = <int>[];
        for (final tagName in tagNames) {
          if (!tagIdMap.containsKey(tagName)) {
            final tagEntry = await db.getOrCreateTag(tagName);
            tagIdMap[tagName] = tagEntry.id;
          }
          final tagId = tagIdMap[tagName];
          if (tagId != null) ids.add(tagId);
        }
        await db.setTagsForGame(gameId, ids);
      } else {
        await db.setTagsForGame(gameId, const []);
      }

      if (task != null && importedCount + updatedCount + skippedCount > 0) {
        final done = importedCount + updatedCount + skippedCount;
        task.update(message: 'Imported $done...');
      }
    }

    // Refresh
    await ref.read(gamesProvider.notifier).refresh();
    await ref.read(tagsProvider.notifier).refresh();
    await persistEncryptedDbIfNeeded(ref);
    await _markImportSyncDirty(ref, db);

    String message = 'Imported $importedCount games from CSV';
    if (updatedCount > 0) message += ', updated $updatedCount';
    if (skippedCount > 0) {
      message += ' (skipped $skippedCount duplicates)';
    }
    NotificationManager.instance.success(message);
  }

  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    var inQuotes = false;
    var field = StringBuffer();

    for (var i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          // Escaped quote
          field.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        result.add(field.toString());
        field = StringBuffer();
      } else {
        field.write(char);
      }
    }
    result.add(field.toString());
    return result;
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
                    child: DropTarget(
                      enable: supportsDragAndDrop,
                      onDragDone: (details) async {
                        if (details.files.isNotEmpty) {
                          await _handleSelectedFilePath(
                            details.files.first.path,
                          );
                        }
                      },
                      onDragEntered: (_) => setState(() => _isDragging = true),
                      onDragExited: (_) => setState(() => _isDragging = false),
                      child: InkWell(
                        onTap: _selectFile,
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
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: kElementVSpacing),
                Text(
                  'Supported: .db, .sqlite, .enc, .json, .csv, .txt, and compatible .bak backups',
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
