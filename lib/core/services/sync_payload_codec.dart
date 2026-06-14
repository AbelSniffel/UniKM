/// Codec that serialises and deserialises the sync payload exchanged between
/// devices.  Extracted from [DeviceSyncService] so the logic can be tested and
/// reasoned about independently of the transport layer.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../providers/app_providers.dart';
import '../database/database.dart';
import '../models/device_sync_models.dart';
import 'sync_entry_fingerprint.dart';
import 'steam_service.dart';

class SyncPayloadCodec {
  SyncPayloadCodec({required this.ref});

  final Ref ref;

  static final RegExp _windowsPathPattern = RegExp(r'^[a-zA-Z]:[\\/]');

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> buildDeltaPayload({
    required String syncRevisionId,
    required int baseRevision,
    required int baseSyncAtMillis,
    required int localRevision,
    String? deviceName,
    bool includeAllGames = false,
  }) async {
    final isFullDataset = includeAllGames || baseSyncAtMillis <= 0;
    final db = ref.read(databaseProvider);
    if (db == null) {
      return {
        'mode': 'delta',
        'fullDataset': isFullDataset,
        'syncRevisionId': syncRevisionId,
        'localRevision': localRevision,
        'dbTimestampMillis': 0,
        'baseRevision': baseRevision,
        'baseSyncAt': baseSyncAtMillis,
        'games': const <Map<String, dynamic>>[],
        'tombstones': const <Map<String, dynamic>>[],
      };
    }

    final allGames = await db.getAllGames();
    final since = DateTime.fromMillisecondsSinceEpoch(baseSyncAtMillis);
    final changedGames = isFullDataset
        ? allGames
        : allGames.where((g) => g.updatedAt.isAfter(since)).toList(growable: false);
    final gameIds = changedGames.map((g) => g.id).toList(growable: false);
    final tagsMap = gameIds.isEmpty
        ? <int, List<TagEntry>>{}
        : await db.getTagsForGames(gameIds);
    final tombstones = await db.getGameTombstonesSinceRevision(
      isFullDataset ? 0 : baseRevision,
    );

    final gamesJson = <Map<String, dynamic>>[];
    for (final game in changedGames) {
      final gameTags = tagsMap[game.id] ?? const <TagEntry>[];
      final coverPayload = await _serializeCoverImageForTransfer(
        rawCoverImagePath: game.coverImage,
        gameKey: game.gameKey,
      );
      final entrySyncId = await SyncEntryFingerprint.fromGameEntry(game, gameTags);

      gamesJson.add({
        'id': game.id,
        'title': game.title,
        'gameKey': game.gameKey,
        'platform': game.platform,
        'dateAdded': game.dateAdded.toIso8601String(),
        'updatedAt': game.updatedAt.toIso8601String(),
        'notes': game.notes,
        'isUsed': game.isUsed,
        'coverImage': game.coverImage,
        'hasCoverImage': game.coverImage.trim().isNotEmpty,
        'coverImageFile': coverPayload,
        'hasDeadline': game.hasDeadline,
        'deadlineDate': game.deadlineDate?.toIso8601String(),
        'isDlc': game.isDlc,
        'steamAppId': game.steamAppId,
        'developer': game.developer,
        'reviewScore': game.reviewScore,
        'reviewCount': game.reviewCount,
        'entrySyncId': entrySyncId,
        'tags': gameTags
            .map(
              (t) => {
                'name': t.name,
                'colorHex': t.color,
                'isSteamTag': t.isSteamTag,
              },
            )
            .toList(growable: false),
      });
    }

    final steamCache = await exportSteamCacheSnapshotForSync();
    return {
      'mode': 'delta',
      'fullDataset': isFullDataset,
      'syncRevisionId': syncRevisionId,
      'localRevision': localRevision,
      'dbTimestampMillis': await db.getSyncDbTimestampMillis(),
      'baseRevision': baseRevision,
      'baseSyncAt': baseSyncAtMillis,
      if (deviceName != null && deviceName.isNotEmpty) 'deviceName': deviceName,
      'steamCache': steamCache,
      'games': gamesJson,
      'tombstones': tombstones,
    };
  }

  // -------------------------------------------------------------------------
  // Apply
  // -------------------------------------------------------------------------

  /// Apply an incoming list of game records to the local database using a
  /// last-write-wins strategy with conflict detection.
  ///
  /// A *conflict* occurs when both sides modified the same game after
  /// [lastSyncAt].  Conflicting games are kept as-is locally rather than being
  /// silently overwritten.
  ///
  /// Uses a two-pass batch approach:
  /// 1. Classify — parse all incoming games and compare against local state.
  /// 2. Execute — batch-insert, batch-update, and batch-set tags in bulk.
  Future<SyncImportResult> applyPayload(
    List<Map<String, dynamic>> gamesJson, {
    DateTime? lastSyncAt,
  }) async {
    final db = ref.read(databaseProvider);
    if (db == null) {
      return const SyncImportResult(inserted: 0, updated: 0, conflicts: 0);
    }

    // ── Phase 1: Pre-cache existing state (3 queries total) ──────────────
    final allExisting = await db.getAllGames();
    final existingById = <int, GameEntry>{
      for (final g in allExisting) g.id: g,
    };
    final existingTagsMap = allExisting.isEmpty
        ? <int, List<TagEntry>>{}
        : await db.getTagsForGames(
            allExisting.map((g) => g.id).toList(growable: false),
          );

    // ── Phase 2: Parse & classify every incoming game ────────────────────
    // Intermediate structs for the classify pass (no DB I/O).
    final inserts = <_IncomingGame>[];
    final updates = <_IncomingGame>[];
    var conflicts = 0;

    // Collect all unique tag specs from ALL games first, so we can
    // resolve them in a single batch later.
    final allTagSpecs = <({String name, String color, bool isSteamTag})>[];

    for (final data in gamesJson) {
      final incomingId = (data['id'] as num?)?.toInt();
      final gameKey = (data['gameKey'] as String?)?.trim() ?? '';
      if (incomingId == null && gameKey.isEmpty) continue;

      final title = (data['title'] as String?) ?? '';
      final platform = (data['platform'] as String?) ?? 'Steam';
      final dateAdded = DateTime.tryParse(data['dateAdded'] as String? ?? '') ??
          DateTime.now();
      final updatedAt = DateTime.tryParse(data['updatedAt'] as String? ?? '') ??
          dateAdded;
      final notes = (data['notes'] as String?) ?? '';
      final isUsed = (data['isUsed'] as bool?) ?? false;
      final hasCoverImage = (data['hasCoverImage'] as bool?) ?? false;
      final hasDeadline = (data['hasDeadline'] as bool?) ?? false;
      final deadlineDate =
          DateTime.tryParse(data['deadlineDate'] as String? ?? '');
      final isDlc = (data['isDlc'] as bool?) ?? false;
      final steamAppId = (data['steamAppId'] as String?) ?? '';
      final developer = (data['developer'] as String?) ?? '';
      final reviewScore = (data['reviewScore'] as int?) ?? 0;
      final reviewCount = (data['reviewCount'] as int?) ?? 0;
      final tagsRaw = (data['tags'] as List<dynamic>?) ?? const [];

      // Collect tag specs for batch resolution.
      for (final tagRaw in tagsRaw) {
        if (tagRaw is! Map) continue;
        final tagMap = Map<String, dynamic>.from(tagRaw);
        final tagName = (tagMap['name'] as String?)?.trim() ?? '';
        if (tagName.isEmpty) continue;
        allTagSpecs.add((
          name: tagName,
          color: (tagMap['colorHex'] as String?) ?? '#0078d4',
          isSteamTag: (tagMap['isSteamTag'] as bool?) ?? false,
        ));
      }

      // Resolve cover image (file I/O — must stay per-entry).
      String? syncedCoverImagePath;
      final coverImageFile = data['coverImageFile'];
      if (coverImageFile is Map) {
        syncedCoverImagePath = await _persistIncomingCoverImage(
          gameKey: gameKey,
          payload: Map<String, dynamic>.from(coverImageFile),
        );
      }
      final incomingLegacyCoverPath = (data['coverImage'] as String?) ?? '';

      final resolvedCoverImage = await _resolveTranslatedCoverImagePath(
        gameKey: gameKey,
        hasCoverImage: hasCoverImage,
        syncedCoverImagePath: syncedCoverImagePath,
        incomingLegacyCoverPath: incomingLegacyCoverPath,
        existingCoverImagePath:
            incomingId != null ? existingById[incomingId]?.coverImage ?? '' : '',
      );

      final game = _IncomingGame(
        incomingId: incomingId,
        gameKey: gameKey,
        title: title,
        platform: platform,
        dateAdded: dateAdded,
        updatedAt: updatedAt,
        notes: notes,
        isUsed: isUsed,
        resolvedCoverImage: resolvedCoverImage,
        hasDeadline: hasDeadline,
        deadlineDate: deadlineDate,
        isDlc: isDlc,
        steamAppId: steamAppId,
        developer: developer,
        reviewScore: reviewScore,
        reviewCount: reviewCount,
        tagsRaw: tagsRaw,
      );

      final existing =
          incomingId != null ? existingById[incomingId] : null;

      if (existing == null) {
        inserts.add(game);
      } else if (_isIdentical(game, existing, existingTagsMap)) {
        // Identical content — skip DB writes.
      } else if (updatedAt.isAfter(existing.updatedAt)) {
        final localEditedSinceLastSync =
            lastSyncAt != null && existing.updatedAt.isAfter(lastSyncAt);
        if (localEditedSinceLastSync) {
          conflicts++;
        } else {
          updates.add(game);
        }
      } else {
        // Local is equal or newer — keep it.
      }
    }

    // ── Phase 3: Batch-resolve all tags (2 queries total) ────────────────
    final uniqueTagSpecs = allTagSpecs
        .fold<Map<String, ({String name, String color, bool isSteamTag})>>(
          {},
          (map, spec) => map..putIfAbsent(spec.name.toLowerCase(), () => spec),
        )
        .values
        .toList(growable: false);
    final tagEntries = await db.batchGetOrCreateTags(uniqueTagSpecs);

    // ── Phase 4: Batch-insert new games ──────────────────────────────────
    int inserted = 0;
    final insertGameTagMap = <int, List<int>>{};
    final insertsWithId = <GamesCompanion>[];
    final insertsWithoutId = <GamesCompanion>[];

    for (final game in inserts) {
      final tagIds = _resolveTagIds(game.tagsRaw, tagEntries);
      final companion = GamesCompanion(
        id: game.incomingId != null ? Value(game.incomingId!) : const Value.absent(),
        title: Value(game.title),
        gameKey: Value(game.gameKey),
        platform: Value(game.platform),
        dateAdded: Value(game.dateAdded),
        updatedAt: Value(game.updatedAt),
        notes: Value(game.notes),
        isUsed: Value(game.isUsed),
        coverImage: Value(game.resolvedCoverImage),
        hasDeadline: Value(game.hasDeadline),
        deadlineDate: Value(game.deadlineDate),
        isDlc: Value(game.isDlc),
        steamAppId: Value(game.steamAppId),
        developer: Value(game.developer),
        reviewScore: Value(game.reviewScore),
        reviewCount: Value(game.reviewCount),
      );

      if (game.incomingId != null) {
        insertsWithId.add(companion);
      } else {
        insertsWithoutId.add(companion);
      }

      // Tag IDs will be set after we know the generated IDs.
      // For ID-bearing inserts we know the ID already.
      if (game.incomingId != null) {
        insertGameTagMap[game.incomingId!] = tagIds;
        inserted++;
      }
    }

    // Batch insert games with known IDs (insertOrReplace).
    if (insertsWithId.isNotEmpty) {
      await db.batch((b) {
        b.insertAll(db.games, insertsWithId, mode: InsertMode.insertOrReplace);
      });
    }

    // Insert games without IDs one-by-one (need generated ID for tag map).
    for (var i = 0; i < insertsWithoutId.length; i++) {
      final gameId = await db.insertGame(insertsWithoutId[i]);
      final tagIds = _resolveTagIds(inserts[insertsWithId.length + i].tagsRaw, tagEntries);
      insertGameTagMap[gameId] = tagIds;
      inserted++;
    }

    // Batch set tags for all inserts.
    if (insertGameTagMap.isNotEmpty) {
      await db.batchSetTagsForGames(insertGameTagMap);
    }

    // ── Phase 5: Batch-update existing games ─────────────────────────────
    int updated = 0;
    final updateEntries = <GameEntry>[];
    final updateGameTagMap = <int, List<int>>{};

    for (final game in updates) {
      final existing = existingById[game.incomingId!]!;
      updateEntries.add(GameEntry(
        id: existing.id,
        title: game.title,
        gameKey: game.gameKey,
        platform: game.platform,
        dateAdded: game.dateAdded,
        updatedAt: game.updatedAt,
        notes: game.notes,
        isUsed: game.isUsed,
        coverImage: game.resolvedCoverImage,
        hasDeadline: game.hasDeadline,
        deadlineDate: game.deadlineDate,
        isDlc: game.isDlc,
        steamAppId: game.steamAppId,
        developer: game.developer,
        reviewScore: game.reviewScore,
        reviewCount: game.reviewCount,
      ));
      updateGameTagMap[existing.id] = _resolveTagIds(game.tagsRaw, tagEntries);
      updated++;
    }

    // Batch update games.
    if (updateEntries.isNotEmpty) {
      await db.batchUpdateGames(updateEntries);
    }

    // Batch set tags for all updates.
    if (updateGameTagMap.isNotEmpty) {
      await db.batchSetTagsForGames(updateGameTagMap);
    }

    // ── Phase 6: Trigger provider refresh and return ─────────────────────
    final currentDb = ref.read(databaseProvider);
    if (currentDb != null) {
      ref.read(databaseNotifierProvider.notifier).setDatabase(currentDb);
    }

    return SyncImportResult(
      inserted: inserted,
      updated: updated,
      conflicts: conflicts,
    );
  }

  /// Check if an incoming game is identical to an existing local game,
  /// avoiding expensive SHA-256 fingerprinting when possible.
  static bool _isIdentical(
    _IncomingGame incoming,
    GameEntry existing,
    Map<int, List<TagEntry>> existingTagsMap,
  ) {
    if (incoming.title != existing.title) return false;
    if (incoming.gameKey != existing.gameKey) return false;
    if (incoming.platform != existing.platform) return false;
    if (incoming.notes != existing.notes) return false;
    if (incoming.isUsed != existing.isUsed) return false;
    if (incoming.resolvedCoverImage != existing.coverImage) return false;
    if (incoming.hasDeadline != existing.hasDeadline) return false;
    if (incoming.isDlc != existing.isDlc) return false;
    if (incoming.steamAppId != existing.steamAppId) return false;
    if (incoming.developer != existing.developer) return false;
    if (incoming.reviewScore != existing.reviewScore) return false;
    if (incoming.reviewCount != existing.reviewCount) return false;

    // Compare deadlines.
    if (incoming.deadlineDate != existing.deadlineDate) return false;

    // Compare tags as sorted name lists.
    final incomingTagNames = incoming.tagsRaw
        .whereType<Map>()
        .map((t) => (t['name'] as String?)?.trim() ?? '')
        .where((n) => n.isNotEmpty)
        .toList()
      ..sort();
    final localTags = existingTagsMap[existing.id] ?? const <TagEntry>[];
    final localTagNames = localTags.map((t) => t.name).toList()..sort();
    if (incomingTagNames.length != localTagNames.length) return false;
    for (var i = 0; i < incomingTagNames.length; i++) {
      if (incomingTagNames[i] != localTagNames[i]) return false;
    }

    return true;
  }

  /// Resolve tag names from raw JSON to tag IDs using pre-resolved map.
  static List<int> _resolveTagIds(
    List<dynamic> tagsRaw,
    Map<String, TagEntry> tagEntries,
  ) {
    final ids = <int>[];
    for (final tagRaw in tagsRaw) {
      if (tagRaw is! Map) continue;
      final tagMap = Map<String, dynamic>.from(tagRaw);
      final name = (tagMap['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      final entry = tagEntries[name.toLowerCase()];
      if (entry != null) ids.add(entry.id);
    }
    return ids;
  }

  Future<SyncImportResult> applyDeltaPayload(
    List<Map<String, dynamic>> gamesJson, {
    List<Map<String, dynamic>> tombstones = const [],
    DateTime? lastSyncAt,
  }) async {
    final db = ref.read(databaseProvider);
    if (db == null) {
      return const SyncImportResult(inserted: 0, updated: 0, conflicts: 0);
    }

    int deleted = 0;
    int conflicts = 0;

    // ── Phase 1: Classify tombstones ────────────────────────────────────
    if (tombstones.isNotEmpty) {
      final allExisting = await db.getAllGames();
      final existingById = <int, GameEntry>{
        for (final g in allExisting) g.id: g,
      };

      final deletableIds = <int>[];

      for (final tombstone in tombstones) {
        final tombstoneId = (tombstone['id'] as num?)?.toInt();
        if (tombstoneId == null || tombstoneId <= 0) continue;

        final deletedAtMillis =
            (tombstone['deletedAt'] as num?)?.toInt() ?? 0;
        final deletedAt = deletedAtMillis <= 0
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : DateTime.fromMillisecondsSinceEpoch(deletedAtMillis);
        final existing = existingById[tombstoneId];
        if (existing == null) {
          // Already gone locally — count as deleted.
          deletableIds.add(tombstoneId);
          deleted++;
          continue;
        }

        if (existing.updatedAt.isAfter(deletedAt)) {
          // Local copy is newer — conflict, keep local.
          conflicts++;
          continue;
        }

        deletableIds.add(tombstoneId);
        deleted++;
      }

      // ── Phase 2: Batch-delete tombstoned games ──────────────────────
      if (deletableIds.isNotEmpty) {
        await db.transaction(() async {
          await db.batchDeleteGameTags(deletableIds);
          await (db.delete(db.games)
                ..where((g) => g.id.isIn(deletableIds)))
              .go();
        });
      }
    }

    // ── Phase 3: Batch-apply upserts ──────────────────────────────────
    final upsertResult = await applyPayload(gamesJson, lastSyncAt: lastSyncAt);

    // When this device receives only upserts (no tombstones), the local
    // revision must still advance so other trusted peers can detect that this
    // database changed and pull the propagated updates.
    if (tombstones.isEmpty &&
        (upsertResult.inserted > 0 || upsertResult.updated > 0)) {
      await db.markLocalDataChanged();
    }

    return SyncImportResult(
      inserted: upsertResult.inserted + deleted,
      updated: upsertResult.updated,
      conflicts: upsertResult.conflicts + conflicts,
    );
  }

  // -------------------------------------------------------------------------
  // Cover image serialisation helpers
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>?> _serializeCoverImageForTransfer({
    required String rawCoverImagePath,
    required String gameKey,
  }) async {
    final raw = rawCoverImagePath.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return null;
    if (raw.startsWith('assets/')) return null;

    File sourceFile;
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.scheme.toLowerCase() == 'file') {
      sourceFile = File.fromUri(uri);
    } else {
      sourceFile = File(raw);
    }

    if (!await sourceFile.exists()) return null;
    final bytes = await sourceFile.readAsBytes();
    if (bytes.isEmpty) return null;

    final sourceName = p.basename(sourceFile.path).trim();
    final ext = p.extension(sourceFile.path).toLowerCase();
    final safeKey = gameKey.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final fileName = sourceName.isNotEmpty
        ? sourceName
        : '${safeKey.isEmpty ? 'cover' : safeKey}${ext.isEmpty ? '.img' : ext}';
    return {
      'fileName': fileName,
      'bytesBase64': base64Encode(bytes),
    };
  }

  Future<String?> _persistIncomingCoverImage({
    required String gameKey,
    required Map<String, dynamic> payload,
  }) async {
    final bytesBase64 = (payload['bytesBase64'] as String?)?.trim() ?? '';
    if (bytesBase64.isEmpty) return null;

    List<int> bytes;
    try {
      bytes = base64Decode(bytesBase64);
    } catch (_) {
      return null;
    }
    if (bytes.isEmpty) return null;

    final imagesDir = await _resolveManagedImagesDirectory();
    final incomingName = (payload['fileName'] as String?)?.trim() ?? '';
    final fallbackName =
        '${gameKey.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}_${DateTime.now().millisecondsSinceEpoch}.img';
    final safeName =
        p.basename(incomingName.isEmpty ? fallbackName : incomingName);
    final target = File(p.join(imagesDir.path, safeName));
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  Future<String> _resolveTranslatedCoverImagePath({
    required String gameKey,
    required bool hasCoverImage,
    required String? syncedCoverImagePath,
    required String incomingLegacyCoverPath,
    required String existingCoverImagePath,
  }) async {
    if (!hasCoverImage) return '';

    if (syncedCoverImagePath != null && syncedCoverImagePath.trim().isNotEmpty) {
      return syncedCoverImagePath.trim();
    }

    final fromIncoming = await _translateCoverImagePathForCurrentDevice(
      rawPath: incomingLegacyCoverPath,
      gameKey: gameKey,
    );
    if (fromIncoming.isNotEmpty) return fromIncoming;

    final fromExisting = await _translateCoverImagePathForCurrentDevice(
      rawPath: existingCoverImagePath,
      gameKey: gameKey,
    );
    if (fromExisting.isNotEmpty) return fromExisting;

    return '';
  }

  Future<String> _translateCoverImagePathForCurrentDevice({
    required String rawPath,
    required String gameKey,
  }) async {
    final raw = rawPath.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('assets/')) return raw;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return '';

    final sourceFile = _fileFromRawPath(raw);
    if (sourceFile != null && await sourceFile.exists()) {
      return _copyCoverImageToManagedPath(sourceFile, gameKey: gameKey);
    }

    final maybeByName = await _findManagedImageByName(raw);
    if (maybeByName != null) return maybeByName.path;

    return '';
  }

  File? _fileFromRawPath(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.scheme.toLowerCase() == 'file') {
      return File.fromUri(uri);
    }
    if (_looksLikePathForCurrentPlatform(raw)) return File(raw);
    // Legacy support for cross-platform paths (basename extraction only).
    if (_windowsPathPattern.hasMatch(raw) || raw.startsWith('/')) return File(raw);
    return null;
  }

  bool _looksLikePathForCurrentPlatform(String raw) {
    if (kIsWeb) return false;
    if (Platform.isWindows) {
      return _windowsPathPattern.hasMatch(raw) || raw.startsWith('\\\\');
    }
    return raw.startsWith('/');
  }

  Future<File?> _findManagedImageByName(String rawPath) async {
    final uri = Uri.tryParse(rawPath);
    final sourcePath =
        (uri != null && uri.scheme.toLowerCase() == 'file') ? uri.path : rawPath;
    final fileName = p.basename(sourcePath);
    if (fileName.trim().isEmpty) return null;

    final syncDir = await _resolveManagedImagesDirectory();
    final directSync = File(p.join(syncDir.path, fileName));
    if (await directSync.exists()) return directSync;

    final steamDir = await _resolveSteamImagesDirectory();
    final directSteam = File(p.join(steamDir.path, fileName));
    if (await directSteam.exists()) return directSteam;

    return null;
  }

  Future<String> _copyCoverImageToManagedPath(
    File sourceFile, {
    required String gameKey,
  }) async {
    final sourceCanonical = p.normalize(sourceFile.absolute.path);
    final syncDir = await _resolveManagedImagesDirectory();
    final steamDir = await _resolveSteamImagesDirectory();

    if (sourceCanonical.startsWith(p.normalize(syncDir.path)) ||
        sourceCanonical.startsWith(p.normalize(steamDir.path))) {
      return sourceFile.path;
    }

    final ext = p.extension(sourceFile.path);
    final safeKey = gameKey.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final fallback =
        'cover_${DateTime.now().millisecondsSinceEpoch}${ext.isEmpty ? '.img' : ext}';
    final fileName = safeKey.isEmpty
        ? fallback
        : '$safeKey${ext.isEmpty ? '.img' : ext}';

    final target = File(p.join(syncDir.path, fileName));
    await sourceFile.copy(target.path);
    return target.path;
  }

  Future<Directory> _resolveManagedImagesDirectory() async {
    final dbPath = await AppDatabase.getDatabasePath();
    final imagesDir = Directory(p.join(p.dirname(dbPath), 'images', 'sync'));
    if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
    return imagesDir;
  }

  Future<Directory> _resolveSteamImagesDirectory() async {
    final dbPath = await AppDatabase.getDatabasePath();
    final imagesDir = Directory(p.join(p.dirname(dbPath), 'images', 'steam'));
    if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
    return imagesDir;
  }
}

/// Intermediate struct for an incoming game during the classify pass.
/// Avoids repeated JSON field extraction inside loops.
class _IncomingGame {
  const _IncomingGame({
    required this.incomingId,
    required this.gameKey,
    required this.title,
    required this.platform,
    required this.dateAdded,
    required this.updatedAt,
    required this.notes,
    required this.isUsed,
    required this.resolvedCoverImage,
    required this.hasDeadline,
    required this.deadlineDate,
    required this.isDlc,
    required this.steamAppId,
    required this.developer,
    required this.reviewScore,
    required this.reviewCount,
    required this.tagsRaw,
  });

  final int? incomingId;
  final String gameKey;
  final String title;
  final String platform;
  final DateTime dateAdded;
  final DateTime updatedAt;
  final String notes;
  final bool isUsed;
  final String resolvedCoverImage;
  final bool hasDeadline;
  final DateTime? deadlineDate;
  final bool isDlc;
  final String steamAppId;
  final String developer;
  final int reviewScore;
  final int reviewCount;
  final List<dynamic> tagsRaw;
}
