/// Import/Export dialogs for database operations
library;

import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../core/database/database.dart';
import '../../core/services/legacy_db_converter.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/notification_system.dart';
import '../widgets/section_groupbox.dart';
import '../widgets/toggle_switch.dart';

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
  String _exportFormat = 'json';
  bool _includeUsed = true;
  bool _includeTags = true;
  bool _includeNotes = true;
  bool _isExporting = false;

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
      sourceDb.dispose();
    }

    NotificationManager.instance.success(
      'Exported database to ${p.basename(destinationPath)}',
    );
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

    NotificationManager.instance.success(
      'Exported encrypted database to ${p.basename(destinationPath)}',
    );
  }

  Future<void> _export() async {
    final ext = switch (_exportFormat) {
      'db' => 'db',
      'enc' => 'enc',
      _ => _exportFormat,
    };

    final defaultName = switch (_exportFormat) {
      'db' => 'UniKM_backup_${DateTime.now().millisecondsSinceEpoch}.$ext',
      'enc' => 'UniKM_backup_${DateTime.now().millisecondsSinceEpoch}.$ext',
      _ => 'UniKM_export_${DateTime.now().millisecondsSinceEpoch}.$ext',
    };

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Database',
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: [ext],
    );

    if (result == null) return;

    setState(() => _isExporting = true);

    try {
      if (_exportFormat == 'db') {
        await _exportSqliteBackup(result);
        if (mounted) Navigator.pop(context);
        return;
      }

      if (_exportFormat == 'enc') {
        await _exportEncryptedDatabase(result);
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
            .map((id) => tags.firstWhere((t) => t.id == id, orElse: () => null))
            .where((t) => t != null)
            .map((t) => t.name)
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

    // Simple JSON encoding without external package
    return _encodeJson({
      'games': gamesList,
      'exported_at': DateTime.now().toIso8601String(),
    });
  }

  String _encodeJson(Map<String, dynamic> data) {
    // Simple JSON encoding
    final buffer = StringBuffer();
    buffer.write('{\n');
    buffer.write('  "exported_at": "${data['exported_at']}",\n');
    buffer.write('  "games": [\n');

    final games = data['games'] as List;
    for (var i = 0; i < games.length; i++) {
      buffer.write('    ${_encodeJsonMap(games[i] as Map<String, dynamic>)}');
      if (i < games.length - 1) buffer.write(',');
      buffer.write('\n');
    }

    buffer.write('  ]\n');
    buffer.write('}');
    return buffer.toString();
  }

  String _encodeJsonMap(Map<String, dynamic> map) {
    final parts = <String>[];
    map.forEach((key, value) {
      if (value is String) {
        parts.add('"$key": "${_escapeString(value)}"');
      } else if (value is bool) {
        parts.add('"$key": $value');
      } else if (value is int) {
        parts.add('"$key": $value');
      } else if (value is List) {
        final items = value
            .map((v) => '"${_escapeString(v.toString())}"')
            .join(', ');
        parts.add('"$key": [$items]');
      }
    });
    return '{${parts.join(', ')}}';
  }

  String _escapeString(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
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
            .map((id) => tags.firstWhere((t) => t.id == id, orElse: () => null))
            .where((t) => t != null)
            .map((t) => t.name)
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

    return Dialog(
      backgroundColor: theme.background,
      child: Container(
        width: 550,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DialogHeader(
              icon: Icons.upload,
              title: 'Export Database',
              theme: theme,
              showCloseButton: true,
            ),
            const SizedBox(height: 16),
            // Format selection
            SectionGroupBox(
              title: 'Format',
              theme: theme,
              child: RadioGroup<String>(
                groupValue: _exportFormat,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _exportFormat = v);
                },
                child: Column(
                  children: [
                    RadioListTile<String>(
                      title: Text(
                        'SQLite (.db)',
                        style: TextStyle(color: theme.textPrimary),
                      ),
                      subtitle: Text(
                        'Full database file (recommended backup)',
                        style: TextStyle(color: theme.textSecondary),
                      ),
                      value: 'db',
                      activeColor: theme.accent,
                    ),
                    if (hasEncryptedSession)
                      RadioListTile<String>(
                        title: Text(
                          'Encrypted DB (.enc)',
                          style: TextStyle(color: theme.textPrimary),
                        ),
                        subtitle: Text(
                          'Encrypted database file (no password included)',
                          style: TextStyle(color: theme.textSecondary),
                        ),
                        value: 'enc',
                        activeColor: theme.accent,
                      ),
                    RadioListTile<String>(
                      title: Text(
                        'JSON',
                        style: TextStyle(color: theme.textPrimary),
                      ),
                      subtitle: Text(
                        'Full data with structure',
                        style: TextStyle(color: theme.textSecondary),
                      ),
                      value: 'json',
                      activeColor: theme.accent,
                    ),
                    RadioListTile<String>(
                      title: Text(
                        'CSV',
                        style: TextStyle(color: theme.textPrimary),
                      ),
                      subtitle: Text(
                        'Spreadsheet compatible',
                        style: TextStyle(color: theme.textSecondary),
                      ),
                      value: 'csv',
                      activeColor: theme.accent,
                    ),
                    RadioListTile<String>(
                      title: Text(
                        'Text',
                        style: TextStyle(color: theme.textPrimary),
                      ),
                      subtitle: Text(
                        'Simple title | key format',
                        style: TextStyle(color: theme.textSecondary),
                      ),
                      value: 'txt',
                      activeColor: theme.accent,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Options
            if (_exportFormat != 'db' && _exportFormat != 'enc')
              SectionGroupBox(
                title: 'Options',
                theme: theme,
                child: Column(
                  children: [
                    _OptionRow(
                      theme: theme,
                      label: 'Include used keys',
                      value: _includeUsed,
                      onChanged: (v) => setState(() => _includeUsed = v),
                    ),
                    if (_exportFormat != 'txt') ...[
                      _OptionRow(
                        theme: theme,
                        label: 'Include tags',
                        value: _includeTags,
                        onChanged: (v) => setState(() => _includeTags = v),
                      ),
                      _OptionRow(
                        theme: theme,
                        label: 'Include notes',
                        value: _includeNotes,
                        onChanged: (v) => setState(() => _includeNotes = v),
                      ),
                    ],
                  ],
                ),
              ),

            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: _isExporting ? null : _export,
                  icon: _isExporting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.primaryButtonText,
                          ),
                        )
                      : const Icon(Icons.upload),
                  label: const Text('Export'),
                ),
              ],
            ),
          ],
        ),
      ),
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
      message: 'This will delete all existing games, tags, and backups before importing.',
      confirmLabel: 'Replace',
    );
  }

  Future<void> _selectFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select Database File',
      type: FileType.custom,
      allowedExtensions: ['db', 'sqlite', 'sqlite3', 'enc', 'json', 'csv'],
    );

    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path != null) {
        await _handleSelectedFilePath(path);
      }
    }
  }

  Future<void> _handleSelectedFilePath(String path) async {
    final extension = p.extension(path).toLowerCase();
    const supported = {'.db', '.sqlite', '.sqlite3', '.enc', '.json', '.csv'};
    if (!supported.contains(extension)) {
      NotificationManager.instance.error(
        'Unsupported file type. Please select .db, .sqlite, .sqlite3, .enc, .json, or .csv',
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

  Future<void> _scanFileForCount(File file) async {
    try {
      final extension = p.extension(file.path).toLowerCase();
      int count = 0;

      if (extension == '.db' ||
          extension == '.sqlite' ||
          extension == '.sqlite3') {
        // Count games in SQLite
        final sourceDb = sqlite3.sqlite3.open(
          file.path,
          mode: sqlite3.OpenMode.readOnly,
        );
        try {
          final result = sourceDb.select('SELECT COUNT(*) as count FROM games');
          count = result.first['count'] as int;
        } finally {
          sourceDb.dispose();
        }
      } else if (extension == '.enc') {
        // Can't preview count without password.
        count = 0;
      } else if (extension == '.json') {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        if (data is Map && data['games'] is List) {
          count = (data['games'] as List).length;
        }
      } else if (extension == '.csv') {
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
      final extension = p.extension(_selectedFile!).toLowerCase();

      final db = ref.read(requireDatabaseProvider);
      if (_isReplace) {
        await db.clearAllData();
        await ref.read(gamesProvider.notifier).refresh();
        await ref.read(tagsProvider.notifier).refresh();
        await persistEncryptedDbIfNeeded(ref);
      }

      task = NotificationManager.instance.beginTask('Importing...');

      if (extension == '.db' ||
          extension == '.sqlite' ||
          extension == '.sqlite3' ||
          extension == '.enc') {
        // Import SQLite database
        await _importSqliteDatabase(file, task: task);
      } else if (extension == '.json') {
        // Import JSON
        await _importJson(file, task: task);
      } else if (extension == '.csv') {
        // Import CSV
        await _importCsv(file, task: task);
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

  Future<void> _importSqliteDatabase(
    File file, {
    NotificationHandle? task,
  }) async {
    final prepared = await prepareDatabaseForImport(file.path);
    final conversion = prepared.conversion;
    if (conversion.converted && conversion.actions.isNotEmpty) {
      task?.update(message: 'Normalized legacy layout (${conversion.actions.length} changes)...');
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

      // Build game -> tags map
      final gameTagsMap = <int, List<int>>{};
      for (final row in gameTagsResult) {
        final gameId = row['game_id'] as int;
        final tagId = row['tag_id'] as int;
        gameTagsMap.putIfAbsent(gameId, () => []).add(tagId);
      }

      final imagesDir = await _resolveManagedImagesDirectory();
      final importedCoverPathCache = <String, String>{};
      final copiedImagePaths = <String>{};

      // Import games
      int importedCount = 0;
      int skippedCount = 0;
      int updatedCount = 0;
      for (final row in gameResult) {
        // Check for duplicate keys
        final key = row['game_key'] as String;
        final existingId = await db.getGameIdByKey(key);
        if (_isMerge && existingId != null) {
          skippedCount++;
          continue;
        }

        // Parse deadline date if present
        DateTime? deadlineDate;
        final rawDeadline = row['deadline_date'];
        if (rawDeadline is int && rawDeadline > 0) {
          deadlineDate = DateTime.fromMillisecondsSinceEpoch(rawDeadline * 1000);
        } else if (rawDeadline is String && rawDeadline.isNotEmpty) {
          final epoch = int.tryParse(rawDeadline);
          if (epoch != null && epoch > 0) {
            deadlineDate = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
          }
        }

        final oldGameId = row['id'] as int;
        final sourceCoverImage = row['cover_image'] as String? ?? '';
        final normalizedCoverImage = await _normalizeImportedCoverImagePath(
          sourceCoverImage,
          sourceDbFile: file,
          targetImagesDir: imagesDir,
          cache: importedCoverPathCache,
        );
        if (sourceCoverImage.trim().isNotEmpty &&
            normalizedCoverImage != sourceCoverImage) {
          copiedImagePaths.add(normalizedCoverImage);
        }

        int gameId;
        if (_isUpdate && existingId != null) {
          gameId = existingId;
          await db.updateGameFields(
            gameId,
            title: row['title'] as String,
            platform: row['platform'] as String? ?? 'Steam',
            notes: row['notes'] as String? ?? '',
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
              notes: Value(row['notes'] as String? ?? ''),
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

      // Refresh games list
      await ref.read(gamesProvider.notifier).refresh();
      await ref.read(tagsProvider.notifier).refresh();
      await persistEncryptedDbIfNeeded(ref);

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
      sourceDb.dispose();
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
    final destinationCanonical = _normalizeForCompare(destinationFile.absolute.path);
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

    final stem = p.basenameWithoutExtension(safeName);
    final ext = p.extension(safeName);
    var suffix = 1;
    while (true) {
      final candidate = File(
        p.join(targetImagesDir.path, '${stem}_import$suffix$ext'),
      );
      if (!await candidate.exists()) {
        return candidate;
      }
      suffix++;
    }
  }

  String _normalizeForCompare(String path) {
    return p.normalize(path).replaceAll('\\', '/').toLowerCase();
  }

  Future<void> _importJson(File file, {NotificationHandle? task}) async {
    final content = await file.readAsString();
    final db = ref.read(requireDatabaseProvider);

    try {
      // Parse JSON using simple approach (no external package)
      final data = _parseJsonSimple(content);

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
        if (_isMerge && existingId != null) {
          skippedCount++;
          continue;
        }

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
            notes: (gameData['notes'] as String?) ?? '',
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
              notes: Value((gameData['notes'] as String?) ?? ''),
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

  Map<String, dynamic>? _parseJsonSimple(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return null;
    } catch (e) {
      return null;
    }
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
      if (_isMerge && existingId != null) {
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

    return Dialog(
      backgroundColor: theme.background,
      child: Container(
        width: 550,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DialogHeader(
              icon: Icons.download,
              title: 'Import Database',
              theme: theme,
              showCloseButton: true,
            ),
            const SizedBox(height: 16),
            // File selection
            SectionGroupBox(
              title: 'Source File',
              theme: theme,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Focus(
                    autofocus: false,
                    child: MouseRegion(
                      child: DropTarget(
                        enable: true,
                        onDragDone: (details) async {
                          if (details.files.isNotEmpty) {
                            await _handleSelectedFilePath(details.files.first.path);
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
                                  : theme.inputBackground,
                              borderRadius: BorderRadius.circular(theme.cornerRadius),
                              border: Border.all(
                                color: _isDragging
                                    ? theme.accent
                                    : (_selectedFile != null ? theme.accent : theme.border),
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
                                        : (_isDragging
                                            ? 'Drop file here...'
                                            : 'Click to select or drag file here...'),
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
                  const SizedBox(height: 8),
                  Text(
                    'Supported: .db, .sqlite, .enc, .json, .csv',
                    style: TextStyle(color: theme.textSecondary, fontSize: 12),
                  ),
                  if (_selectedFile != null && _previewCount > 0) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: theme.accent,
                          ),
                          const SizedBox(width: 8),
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

            const SizedBox(height: 16),

            // Import mode
            SectionGroupBox(
              title: 'Import Mode',
              theme: theme,
              child: RadioGroup<String>(
                groupValue: _importMode,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _importMode = v);
                },
                child: Column(
                  children: [
                    RadioListTile<String>(
                      title: Text(
                        'Merge',
                        style: TextStyle(color: theme.textPrimary),
                      ),
                      subtitle: Text(
                        'Add new games, skip duplicates',
                        style: TextStyle(color: theme.textSecondary),
                      ),
                      value: 'merge',
                      activeColor: theme.accent,
                    ),
                    RadioListTile<String>(
                      title: Text(
                        'Replace',
                        style: TextStyle(color: theme.textPrimary),
                      ),
                      subtitle: Text(
                        'Clear existing data and import',
                        style: TextStyle(color: theme.textSecondary),
                      ),
                      value: 'replace',
                      activeColor: theme.accent,
                    ),
                    RadioListTile<String>(
                      title: Text(
                        'Update',
                        style: TextStyle(color: theme.textPrimary),
                      ),
                      subtitle: Text(
                        'Add new and update existing',
                        style: TextStyle(color: theme.textSecondary),
                      ),
                      value: 'update',
                      activeColor: theme.accent,
                    ),
                  ],
                ),
              ),
            ),

            if (_importMode == 'replace') ...[
              const SizedBox(height: 12),
              DialogBanner.caution(
                theme: theme,
                message: 'Replace mode will delete all existing data!',
              ),
            ],

            const SizedBox(height: 16),

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
        ),
      ),
    );
  }
}

/// Option row helper
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.theme,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final AppThemeData theme;
  final String label;
  final bool value;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: theme.textPrimary)),
          ),
          AppToggleSwitch(value: value, onChanged: onChanged, theme: theme),
        ],
      ),
    );
  }
}
