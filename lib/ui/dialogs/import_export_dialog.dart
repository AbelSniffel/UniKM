/// Import/Export dialogs for database operations
library;

import '../widgets/file_drop_field.dart';

import '../../features/transfer/application/library_import.dart';
import '../../features/transfer/application/library_export.dart';
import 'dart:convert';
import 'dart:async';
import '../../features/transfer/application/sqlite_import_reader.dart';
import '../../features/transfer/application/import_image_checkpoint.dart';
import 'dart:io';

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
import '../pages/settings_sections/settings_control_cards.dart';
import 'database_unlock_dialog.dart';
import '../widgets/app_progress_indicator.dart';
import '../widgets/app_action_button.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/notification_system.dart';
import '../widgets/tinted_tiles.dart';

enum _ImportFileKind { sqlite, encrypted, json, csv, txt, unsupported }

typedef _DialogOption = ({
  String value,
  IconData icon,
  String title,
  String subtitle,
});

const _exportFormatOptions = <_DialogOption>[
  (
    value: 'db',
    icon: Icons.storage,
    title: 'SQLite (.db)',
    subtitle: 'Full database file (recommended backup)',
  ),
  (
    value: 'json',
    icon: Icons.data_object,
    title: 'JSON',
    subtitle: 'Full data with structure',
  ),
  (
    value: 'csv',
    icon: Icons.table_chart_outlined,
    title: 'CSV',
    subtitle: 'Spreadsheet compatible',
  ),
  (
    value: 'txt',
    icon: Icons.notes,
    title: 'Text',
    subtitle: 'Simple title | key format',
  ),
];

const _encryptedExportFormatOption = (
  value: 'enc',
  icon: Icons.lock_outline,
  title: 'Encrypted DB (.enc)',
  subtitle: 'Encrypted database file (no password included)',
);

const _importModeOptions = <_DialogOption>[
  (
    value: 'merge',
    icon: Icons.merge_type,
    title: 'Merge',
    subtitle: 'Add new games, skip duplicates',
  ),
  (
    value: 'replace',
    icon: Icons.delete_sweep_outlined,
    title: 'Replace',
    subtitle: 'Clear existing data and import',
  ),
  (
    value: 'update',
    icon: Icons.sync,
    title: 'Update',
    subtitle: 'Add new and update existing',
  ),
];

/// One tile per option, the [selected] one checked. Replace is tinted in the
/// error colour, as it clears the library.
List<Widget> _optionTiles(
  AppThemeData theme,
  Iterable<_DialogOption> options,
  String selected,
  ValueChanged<String> onSelected,
) => [
  for (final option in options)
    TintedOptionTile(
      theme: theme,
      icon: option.icon,
      title: option.title,
      subtitle: option.subtitle,
      selected: option.value == selected,
      color: option.value == 'replace' ? theme.error : null,
      onTap: () => onSelected(option.value),
    ),
];

/// Show export dialog
Future<void> showExportDialog(BuildContext context) => showAppDialog<void>(
  context: context,
  builder: (ctx) => const ExportDialog(),
);

/// Show import dialog
Future<void> showImportDialog(BuildContext context) => showAppDialog<void>(
  context: context,
  builder: (ctx) => const ImportDialog(),
);

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

  Future<void> _exportSqliteBackup(String destinationPath) async {
    final configured = ref.read(currentDatabasePathProvider);
    final sourcePath =
        ref.read(encryptedDbSessionProvider)?.tempDbPath ??
        (configured.isNotEmpty
            ? configured
            : await AppDatabase.getDatabasePath());

    // Use VACUUM INTO for a consistent, compact snapshot.
    final sourceDb = sqlite3.sqlite3.open(
      sourcePath,
      mode: sqlite3.OpenMode.readOnly,
    );
    try {
      sourceDb.execute(
        "VACUUM INTO '${destinationPath.replaceAll("'", "''")}'",
      );
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
      final subject = _exportFormat == 'enc'
          ? 'UniKM encrypted database export'
          : 'UniKM database export';
      final String successMessage;
      if (_exportFormat == 'db') {
        await _exportSqliteBackup(result);
        successMessage = 'Exported database to ${p.basename(result)}';
      } else if (_exportFormat == 'enc') {
        await _exportEncryptedDatabase(result);
        successMessage = 'Exported encrypted database to ${p.basename(result)}';
      } else {
        final games = ref.read(gamesProvider).games;
        final tags = ref.read(tagsProvider);
        final filteredGames = _includeUsed
            ? games
            : games.where((game) => !game.isUsed).toList();
        final exportData = LibraryBackupExporter(
          includeTags: _includeTags,
          includeNotes: _includeNotes,
        ).encode(filteredGames, tags, _exportFormat);
        await target.file.writeAsString(exportData);
        successMessage =
            'Exported ${filteredGames.length} games to ${p.basename(result)}';
      }

      final completed = await PlatformFileActions.completeExport(
        target,
        subject: subject,
      );
      if (!completed) return;
      NotificationManager.instance.success(successMessage);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      NotificationManager.instance.error('Export failed: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
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
        spacing: 16,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              TintedHeading(theme: theme, title: 'Format'),
              ..._optionTiles(
                theme,
                [
                  _exportFormatOptions.first,
                  if (hasEncryptedSession) _encryptedExportFormatOption,
                  ..._exportFormatOptions.skip(1),
                ],
                _exportFormat,
                (value) => setState(() => _exportFormat = value),
              ),
            ],
          ),
          if (showsAdditionalInfo)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                TintedHeading(theme: theme, title: 'Include'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppActionButton(
                      theme: theme,
                      label: 'Used Keys',
                      selected: _includeUsed,
                      onTap: () => setState(() => _includeUsed = !_includeUsed),
                    ),
                    if (_exportFormat != 'txt') ...[
                      AppActionButton(
                        theme: theme,
                        label: 'Tags',
                        selected: _includeTags,
                        onTap: () =>
                            setState(() => _includeTags = !_includeTags),
                      ),
                      AppActionButton(
                        theme: theme,
                        label: 'Notes',
                        selected: _includeNotes,
                        onTap: () =>
                            setState(() => _includeNotes = !_includeNotes),
                      ),
                    ],
                  ],
                ),
              ],
            ),
        ],
      ),
      actions: [
        ElevatedButton.icon(
          onPressed: _isExporting ? null : _export,
          icon: _isExporting
              ? const AppCircularProgressIndicator(size: 18)
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
        onAction: _importCommitted || _cancelRequested ? null : _requestCancel,
      );
    } else {
      _importTask!.update(
        message: _importMessage,
        progress: _importProgress,
        clearAction: _importCommitted || _cancelRequested,
      );
    }
  }

  void _requestCancel() {
    _cancelRequested = true;
    _importMessage = 'Cancelling import and restoring checkpoint...';
    _showImportProgress();
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
    final path = result?.path;
    if (path != null) await _handleSelectedFilePath(path);
  }

  Future<void> _handleSelectedFilePath(String path) async {
    if (_isImporting) return;
    final revision = ++_fileSelectionRevision;
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
    });

    await _scanFileForCount(File(path), revision);
  }

  void _clearFileSelection() {
    if (_isImporting) return;
    ++_fileSelectionRevision;
    setState(() {
      _selectedFile = null;
      _previewCount = 0;
    });
  }

  Future<_ImportFileKind> _classifyImportFile(String path) async {
    final lowerPath = path.toLowerCase();
    bool hasSuffix(List<String> suffixes, {bool backup = true}) => suffixes.any(
      (s) => lowerPath.endsWith(s) || (backup && lowerPath.endsWith('$s.bak')),
    );
    if (hasSuffix(['.db', '.sqlite', '.sqlite3'])) {
      return _ImportFileKind.sqlite;
    }
    if (hasSuffix(['.enc'])) return _ImportFileKind.encrypted;
    if (hasSuffix(['.json'])) return _ImportFileKind.json;
    if (hasSuffix(['.csv'], backup: false)) return _ImportFileKind.csv;
    if (hasSuffix(['.txt'], backup: false)) return _ImportFileKind.txt;

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
      if (hasSqliteHeader(firstBytes)) return _ImportFileKind.sqlite;

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
      final count = switch (await _classifyImportFile(file.path)) {
        _ImportFileKind.sqlite => _countSqliteGames(file.path),
        _ImportFileKind.json => switch (jsonDecode(await file.readAsString())) {
          {'games': final List games} => games.length,
          final data when looksLikeSteamKm1JsonExportData(data) =>
            parseSteamKm1JsonExportData(data).length,
          _ => 0,
        },
        _ImportFileKind.txt => parseSteamKm1TextExport(
          await file.readAsString(),
        ).length,
        _ImportFileKind.csv => parseLibraryCsv(
          await file.readAsString(),
        ).length,
        // Encrypted files cannot be counted without the password.
        _ImportFileKind.encrypted || _ImportFileKind.unsupported => 0,
      };

      if (!mounted || revision != _fileSelectionRevision) return;
      setState(() => _previewCount = count);
    } catch (e) {
      // Ignore errors during preview count
    }
  }

  static int _countSqliteGames(String path) {
    final sourceDb = sqlite3.sqlite3.open(
      path,
      mode: sqlite3.OpenMode.readOnly,
    );
    try {
      final tables = sourceDb.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='games'",
      );
      if (tables.isEmpty) return 0;
      return sourceDb
              .select('SELECT COUNT(*) as count FROM games')
              .first['count']
          as int;
    } finally {
      sourceDb.close();
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
          completed = await _importEncryptedFile(file);
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

  Future<bool> _importEncryptedFile(File file) async {
    switch (await detectEncryptedImportKind(file)) {
      case EncryptedImportKind.uniKmDatabase:
        return _importEncryptedDatabase(
          'UniKM',
          (password) => decryptUniKmDatabaseToTemp(file, password),
        );
      case EncryptedImportKind.steamKm2Database:
        return _importEncryptedDatabase(
          'SteamKM2',
          (password) => decryptSteamKm2DatabaseToTemp(file, password),
        );
      case EncryptedImportKind.steamKm1Json:
        return _importSteamKm1EncryptedBackup(file);
      case EncryptedImportKind.unknown:
        throw Exception('Unsupported encrypted import format');
    }
  }

  Future<bool> _importEncryptedDatabase(
    String appName,
    Future<PreparedEncryptedDatabaseImport> Function(String password) decrypt,
  ) async {
    final prepared = await _promptForEncryptedImport(appName, decrypt);
    if (prepared == null) return false;

    try {
      await _importSqliteDatabase(File(prepared.databasePath));
      return true;
    } finally {
      await prepared.dispose();
    }
  }

  Future<bool> _importSteamKm1EncryptedBackup(File file) async {
    final decryptedJson = await _promptForEncryptedImport<String>(
      'SteamKM1',
      (password) => decryptSteamKm1JsonExport(file, password),
    );
    if (decryptedJson == null) return false;

    final decoded = jsonDecode(decryptedJson);
    final records = parseSteamKm1JsonExportData(decoded);
    await _importSteamKm1Records(
      records,
      sourceFile: file,
      sourceLabel: 'SteamKM1 encrypted backup',
    );
    return true;
  }

  /// Asks for the password of an encrypted [appName] backup until [action]
  /// accepts it; null when the user cancels.
  Future<T?> _promptForEncryptedImport<T>(
    String appName,
    Future<T> Function(String password) action,
  ) async {
    while (true) {
      _checkImport();
      final password = await DatabaseUnlockDialog.show(
        context,
        ref.read(themeProvider),
        title: 'Unlock $appName Backup',
        message:
            'This $appName backup is encrypted. Enter the password to import it.',
      );
      if (password == null) return null;

      try {
        _checkImport();
        return await action(password);
      } on InvalidPasswordException {
        _importTask?.update(message: 'Incorrect password, try again...');
      }
    }
  }

  Future<void> _importSqliteDatabase(File file) async {
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
    final imagesDir = await AppDatabase.getSteamImagesDirectory();
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

    // One image per name: a same-named image from another source is
    // overwritten.
    final sourceName = p.basename(sourceFile.path);
    final destinationFile = File(
      p.join(
        targetImagesDir.path,
        sourceName.isEmpty
            ? 'cover_${DateTime.now().millisecondsSinceEpoch}.img'
            : sourceName,
      ),
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

  String _normalizeForCompare(String path) =>
      p.normalize(path).replaceAll('\\', '/').toLowerCase();

  Future<void> _importJson(File file) async {
    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (looksLikeSteamKm1JsonExportData(decoded)) {
      final records = parseSteamKm1JsonExportData(decoded);
      await _importSteamKm1Records(
        records,
        sourceFile: file,
        sourceLabel: 'SteamKM1 JSON',
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
    await db.bumpLocalSyncRevision();
    await ref
        .read(settingsProvider.notifier)
        .setSetting(
          SettingsKeys.syncDbRevisionId,
          DateTime.now().millisecondsSinceEpoch.toString(),
        );
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

  Future<void> _importTxt(File file) async {
    final records = parseSteamKm1TextExport(await file.readAsString());
    if (records.isEmpty) throw Exception('No valid games found in text import');

    await _importSteamKm1Records(
      records,
      sourceFile: file,
      sourceLabel: 'SteamKM1 text',
    );
  }

  Future<void> _importSteamKm1Records(
    List<SteamKm1ImportedGame> records, {
    required File sourceFile,
    required String sourceLabel,
  }) async {
    final imagesDir = await AppDatabase.getSteamImagesDirectory();
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

  Future<void> _importCsv(File file) async =>
      _commitLibraryImport(parseLibraryCsv(await file.readAsString()), 'CSV');

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);

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
        spacing: 16,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              TintedHeading(
                theme: theme,
                title: 'Source File',
                trailing: _selectedFile != null && _previewCount > 0
                    ? '$_previewCount games found in file'
                    : null,
              ),
              FileDropField(
                key: const ValueKey('import-source-file-target'),
                theme: theme,
                description:
                    'Supports SQLite, .enc, .json, .csv, .txt and compatible .bak backups',
                selectedName: _selectedFile == null
                    ? null
                    : p.basename(_selectedFile!),
                enabled: !_isImporting,
                onBrowse: _selectFile,
                onFileSelected: _handleSelectedFilePath,
                onClear: _clearFileSelection,
                invalidDropMessage: 'Drop one supported database import file.',
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              TintedHeading(theme: theme, title: 'Import Mode'),
              ..._optionTiles(
                theme,
                _importModeOptions,
                _importMode,
                (value) => setState(() => _importMode = value),
              ),
              SettingsToggleCard(
                theme: theme,
                icon: Icons.content_copy_outlined,
                label: 'Allow duplicate keys',
                value: _allowDuplicates,
                onChanged: (value) => setState(() => _allowDuplicates = value),
              ),
            ],
          ),
          if (_importMode == 'replace')
            DialogBanner.warning(
              theme: theme,
              message: 'Replace mode will delete all existing data!',
            ),
        ],
      ),
      actions: [
        if (_isImporting && !_importCommitted)
          OutlinedButton(
            onPressed: _cancelRequested ? null : _requestCancel,
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
