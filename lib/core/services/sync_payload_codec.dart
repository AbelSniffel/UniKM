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
  Future<SyncImportResult> applyPayload(
    List<Map<String, dynamic>> gamesJson, {
    DateTime? lastSyncAt,
  }) async {
    final db = ref.read(databaseProvider);
    if (db == null) return const SyncImportResult(inserted: 0, updated: 0, conflicts: 0);

    final allExisting = await db.getAllGames();
    final existingTagsMap = allExisting.isEmpty
      ? <int, List<TagEntry>>{}
      : await db.getTagsForGames(allExisting.map((g) => g.id).toList(growable: false));
    final existingById = <int, GameEntry>{for (final g in allExisting) g.id: g};
    final localEntrySyncIdById = <int, String>{};

    int inserted = 0;
    int updated = 0;
    int conflicts = 0;

    Future<void> syncIncomingTags(int gameId, List<dynamic> tagsRaw) async {
      if (tagsRaw.isEmpty) {
        existingTagsMap[gameId] = const <TagEntry>[];
        localEntrySyncIdById.remove(gameId);
        return;
      }

      final tagIds = <int>[];
      for (final tagRaw in tagsRaw) {
        if (tagRaw is! Map) continue;
        final tagMap = Map<String, dynamic>.from(tagRaw);
        final tagName = (tagMap['name'] as String?)?.trim() ?? '';
        if (tagName.isEmpty) continue;
        final colorHex = (tagMap['colorHex'] as String?) ?? '#0078d4';
        final isSteamTag = (tagMap['isSteamTag'] as bool?) ?? false;
        final tagEntry = await db.getOrCreateTag(
          tagName,
          color: colorHex,
          isSteamTag: isSteamTag,
        );
        tagIds.add(tagEntry.id);
      }

      await db.setTagsForGame(gameId, tagIds, touchGameUpdatedAt: false);
      existingTagsMap[gameId] = await db.getTagsForGame(gameId);
      localEntrySyncIdById.remove(gameId);
    }

    Future<String?> readLocalEntrySyncId(int gameId) async {
      final localGame = await db.getGameById(gameId);
      if (localGame == null) return null;

      final localTags =
          existingTagsMap[gameId] ?? await db.getTagsForGame(gameId);
      existingTagsMap[gameId] = localTags;

      final localEntrySyncId = await SyncEntryFingerprint.fromGameEntry(
        localGame,
        localTags,
      );
      localEntrySyncIdById[gameId] = localEntrySyncId;
      return localEntrySyncId;
    }

    Future<void> writeIncomingGameState({
      required int gameId,
      required String title,
      required String gameKey,
      required String platform,
      required DateTime dateAdded,
      required DateTime updatedAt,
      required String notes,
      required bool isUsed,
      required String resolvedCoverImage,
      required bool hasDeadline,
      required DateTime? deadlineDate,
      required bool isDlc,
      required String steamAppId,
      required String developer,
      required int reviewScore,
      required int reviewCount,
      required List<dynamic> tagsRaw,
    }) async {
      await db.updateGame(
        GameEntry(
          id: gameId,
          title: title,
          gameKey: gameKey,
          platform: platform,
          dateAdded: dateAdded,
          updatedAt: updatedAt,
          notes: notes,
          isUsed: isUsed,
          coverImage: resolvedCoverImage,
          hasDeadline: hasDeadline,
          deadlineDate: deadlineDate,
          isDlc: isDlc,
          steamAppId: steamAppId,
          developer: developer,
          reviewScore: reviewScore,
          reviewCount: reviewCount,
        ),
      );
      await syncIncomingTags(gameId, tagsRaw);
    }

    for (final data in gamesJson) {
      final incomingId = (data['id'] as num?)?.toInt();
      final gameKey = (data['gameKey'] as String?)?.trim() ?? '';
      if (incomingId == null && gameKey.isEmpty) continue;

      final title = (data['title'] as String?) ?? '';
      final platform = (data['platform'] as String?) ?? 'Steam';
      final dateAdded =
          DateTime.tryParse(data['dateAdded'] as String? ?? '') ?? DateTime.now();
      final updatedAt =
          DateTime.tryParse(data['updatedAt'] as String? ?? '') ?? dateAdded;
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

      String? syncedCoverImagePath;
      final coverImageFile = data['coverImageFile'];
      if (coverImageFile is Map) {
        syncedCoverImagePath = await _persistIncomingCoverImage(
          gameKey: gameKey,
          payload: Map<String, dynamic>.from(coverImageFile),
        );
      }
      final incomingLegacyCoverPath = (data['coverImage'] as String?) ?? '';

      final existing = incomingId != null ? existingById[incomingId] : null;

      String localEntrySyncId = '';
      if (existing != null) {
        final cached = localEntrySyncIdById[existing.id];
        if (cached != null && cached.isNotEmpty) {
          localEntrySyncId = cached;
        } else {
          final existingTags = existingTagsMap[existing.id] ?? const <TagEntry>[];
          localEntrySyncId = await SyncEntryFingerprint.fromGameEntry(
            existing,
            existingTags,
          );
          localEntrySyncIdById[existing.id] = localEntrySyncId;
        }
      }

      final resolvedCoverImage = await _resolveTranslatedCoverImagePath(
        gameKey: gameKey,
        hasCoverImage: hasCoverImage,
        syncedCoverImagePath: syncedCoverImagePath,
        incomingLegacyCoverPath: incomingLegacyCoverPath,
        existingCoverImagePath: existing?.coverImage ?? '',
      );
      final expectedLocalEntrySyncId = await SyncEntryFingerprint.fromPayload(
        <String, dynamic>{
          ...data,
          'coverImage': resolvedCoverImage,
        },
      );

      int gameId;
      var shouldVerifyIncomingState = false;

      if (existing == null) {
        // Brand-new game on this device — insert and preserve remote SKM-ID
        // when available so future edits resolve by immutable identity.
        gameId = incomingId != null
            ? await db.into(db.games).insert(
                GamesCompanion(
                  id: Value(incomingId),
                  title: Value(title),
                  gameKey: Value(gameKey),
                  platform: Value(platform),
                  dateAdded: Value(dateAdded),
                  updatedAt: Value(updatedAt),
                  notes: Value(notes),
                  isUsed: Value(isUsed),
                  coverImage: Value(resolvedCoverImage),
                  hasDeadline: Value(hasDeadline),
                  deadlineDate: Value(deadlineDate),
                  isDlc: Value(isDlc),
                  steamAppId: Value(steamAppId),
                  developer: Value(developer),
                  reviewScore: Value(reviewScore),
                  reviewCount: Value(reviewCount),
                ),
                mode: InsertMode.insertOrReplace,
              )
            : await db.insertGame(
                GamesCompanion.insert(
                  title: title,
                  gameKey: gameKey,
                  platform: Value(platform),
                  dateAdded: Value(dateAdded),
                  updatedAt: Value(updatedAt),
                  notes: Value(notes),
                  isUsed: Value(isUsed),
                  coverImage: Value(resolvedCoverImage),
                  hasDeadline: Value(hasDeadline),
                  deadlineDate: Value(deadlineDate),
                  isDlc: Value(isDlc),
                  steamAppId: Value(steamAppId),
                  developer: Value(developer),
                  reviewScore: Value(reviewScore),
                  reviewCount: Value(reviewCount),
                ),
              );
        inserted++;
        await syncIncomingTags(gameId, tagsRaw);
        shouldVerifyIncomingState = true;
      } else if (expectedLocalEntrySyncId == localEntrySyncId) {
        // Identical content: skip DB writes to avoid unnecessary churn.
        gameId = existing.id;
      } else if (updatedAt.isAfter(existing.updatedAt)) {
        // Remote is newer than local copy.
        // Check for a conflict: local was also edited since the last sync.
        final localEditedSinceLastSync =
            lastSyncAt != null && existing.updatedAt.isAfter(lastSyncAt);

        if (localEditedSinceLastSync) {
          // Both devices changed this game — keep local to avoid data loss.
          conflicts++;
          gameId = existing.id;
        } else {
          await writeIncomingGameState(
            gameId: existing.id,
            title: title,
            gameKey: gameKey,
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
          updated++;
          gameId = existing.id;
          shouldVerifyIncomingState = true;
        }
      } else if (updatedAt.isAtSameMomentAs(existing.updatedAt) &&
          expectedLocalEntrySyncId.compareTo(localEntrySyncId) > 0) {
        // Deterministic tie-breaker when timestamps are equal but content differs.
        await writeIncomingGameState(
          gameId: existing.id,
          title: title,
          gameKey: gameKey,
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
        updated++;
        gameId = existing.id;
        shouldVerifyIncomingState = true;
      } else {
        // Local is equal or newer — keep it.
        gameId = existing.id;
      }

      if (shouldVerifyIncomingState) {
        final localEntrySyncIdAfterApply = await readLocalEntrySyncId(gameId);
        if (localEntrySyncIdAfterApply != expectedLocalEntrySyncId) {
          final debugLabel = gameKey.isNotEmpty ? gameKey : '$gameId';
          debugPrint(
            'Sync: entry mismatch detected after apply for $debugLabel. Retrying authoritative row.',
          );
          await writeIncomingGameState(
            gameId: gameId,
            title: title,
            gameKey: gameKey,
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
          final repairedEntrySyncId = await readLocalEntrySyncId(gameId);
          if (repairedEntrySyncId != expectedLocalEntrySyncId) {
            debugPrint(
              'Sync: entry mismatch persisted after retry for $debugLabel.',
            );
          }
        }
      }

      final refreshed = await db.getGameById(gameId);
      if (refreshed != null) {
        existingById[refreshed.id] = refreshed;
        localEntrySyncIdById.remove(refreshed.id);
      }
    }

    // Trigger games/tags providers to reload.
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

  Future<SyncImportResult> applyDeltaPayload(
    List<Map<String, dynamic>> gamesJson, {
    List<Map<String, dynamic>> tombstones = const [],
    DateTime? lastSyncAt,
  }) async {
    final db = ref.read(databaseProvider);
    if (db == null) {
      return const SyncImportResult(inserted: 0, updated: 0, conflicts: 0);
    }

    final allExisting = await db.getAllGames();
    final existingById = <int, GameEntry>{for (final g in allExisting) g.id: g};

    int inserted = 0;
    int updated = 0;
    int conflicts = 0;
    int deleted = 0;

    if (tombstones.isNotEmpty) {
      // Bump the local revision up front so any *local* game writes triggered
      // by the rest of the apply step (insertions, updates, conflict
      // resolutions) get a revision strictly newer than every tombstone we
      // are about to record.  This keeps the revision ordering monotonic
      // even if a single sync round mixes incoming deletes with our own
      // edits.
      final incomingDeleteRevision = await db.bumpLocalSyncRevision();
      final deletedIds = <int>{};
      final deletedKeysById = <int, String>{};
      var maxSenderLocalRevision = 0;
      for (final tombstone in tombstones) {
        final tombstoneId = (tombstone['id'] as num?)?.toInt();
        final gameKey = (tombstone['gameKey'] as String?)?.trim() ?? '';
        if (tombstoneId == null || tombstoneId <= 0) {
          // Ignore legacy key-only tombstones to avoid deleting a wrong row
          // when duplicate keys exist locally.
          continue;
        }

        final deletedAtMillis = (tombstone['deletedAt'] as num?)?.toInt() ?? 0;
        final deletedAt = deletedAtMillis <= 0
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : DateTime.fromMillisecondsSinceEpoch(deletedAtMillis);
        // Use the *sender's* `localRevision` (already in the payload) when
        // recording the tombstone locally.  This is the value the sender used
        // when it originally deleted the game, so both sides end up with the
        // same `local_revision` for the same tombstone.  That consistency is
        // what lets the sender safely prune its own table up to the revision
        // it just transmitted, and lets any future peer filter tombstones
        // using a peer-known revision that actually matches what the sender
        // produced.
        final tombstoneLocalRevision =
            (tombstone['localRevision'] as num?)?.toInt() ?? 0;
        if (tombstoneLocalRevision > maxSenderLocalRevision) {
          maxSenderLocalRevision = tombstoneLocalRevision;
        }
        final existing = existingById[tombstoneId];
        if (existing == null) {
          deletedIds.add(tombstoneId);
          if (gameKey.isNotEmpty) {
            deletedKeysById[tombstoneId] = gameKey;
          }
          continue;
        }

        if (existing.updatedAt.isAfter(deletedAt)) {
          conflicts++;
          continue;
        }

        await (db.delete(db.gameTags)..where((gt) => gt.gameId.equals(existing.id))).go();
        await (db.delete(db.games)..where((g) => g.id.equals(existing.id))).go();
        existingById.remove(existing.id);
        deletedIds.add(existing.id);
        if (existing.gameKey.trim().isNotEmpty) {
          deletedKeysById[existing.id] = existing.gameKey;
        }
        deleted++;
      }
      if (deletedIds.isNotEmpty) {
        // Record tombstones with the sender's `localRevision` (or, if the
        // payload was missing it, fall back to the revision we just bumped
        // so the row still has a sensible value).  Falling back to a value
        // strictly greater than every other recent revision also guarantees
        // it cannot accidentally subsume a future sender-side prune.
        final recordRevision = maxSenderLocalRevision > 0
            ? maxSenderLocalRevision
            : incomingDeleteRevision;
        await db.recordGameDeletionTombstones(
          deletedIds.toList(growable: false),
          gameKeysById: deletedKeysById,
          localRevision: recordRevision,
        );
      }
    }

    final upsertResult = await applyPayload(gamesJson, lastSyncAt: lastSyncAt);
    inserted += upsertResult.inserted;
    updated += upsertResult.updated;
    conflicts += upsertResult.conflicts;

    // When this device receives only upserts (no tombstones), the local
    // revision must still advance so other trusted peers can detect that this
    // database changed and pull the propagated updates.
    if (tombstones.isEmpty && (upsertResult.inserted > 0 || upsertResult.updated > 0)) {
      await db.markLocalDataChanged();
    }

    return SyncImportResult(
      inserted: inserted + deleted,
      updated: updated,
      conflicts: conflicts,
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
