/// Codec that serialises and deserialises the sync payload exchanged between
/// devices.  Extracted from [DeviceSyncService] so the logic can be tested and
/// reasoned about independently of the transport layer.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../database/database.dart';
import '../models/device_sync_models.dart';
import 'sync_entry_fingerprint.dart';
import 'steam_service.dart';

class SyncPayloadCodec {
  SyncPayloadCodec({
    required this.getDatabase,
    this.exportSteamCache = exportSteamCacheSnapshotForSync,
  });

  final AppDatabase? Function() getDatabase;
  final Future<Map<String, dynamic>> Function() exportSteamCache;

  static final RegExp _windowsPathPattern = RegExp(r'^[a-zA-Z]:[\\/]');

  int? _digestRevision;
  String? _digest;
  String? _digestOrigin;
  AppDatabase? _digestDatabase;
  final _recordSignatures = <String, String>{};

  /// Hashes only journalled changes after the initial snapshot. Health checks
  /// reuse the completed digest while the database revision is unchanged.
  Future<String> getDatasetDigest() async {
    final db = getDatabase();
    if (db == null) return '';
    return _getDatasetDigest(db);
  }

  Future<String> _getDatasetDigest(AppDatabase db) {
    return db.transaction(() async {
      final revision = await db.getLocalSyncRevision();
      final origin = await db.getSyncDatabaseOrigin();
      final sameDatabase =
          identical(_digestDatabase, db) && _digestOrigin == origin;
      if (sameDatabase && _digestRevision == revision && _digest != null) {
        return _digest!;
      }
      final reset =
          !sameDatabase ||
          _digestRevision == null ||
          revision < _digestRevision!;
      if (reset) _recordSignatures.clear();
      final records = await db.getSyncRecords(
        sinceRevision: reset ? 0 : _digestRevision!,
      );
      final games = await db.getGamesByIds([
        for (final record in records)
          if (record['deletedAt'] == 0 && record['id'] is int)
            record['id'] as int,
      ]);
      final tags = await db.getTagsForGames(
        games.map((game) => game.id).toList(),
      );
      final byId = {for (final game in games) game.id: game};
      final tagVersions = await db.getSyncTagVersions();
      for (final record in records) {
        final syncId = record['syncId'] as String;
        final game = byId[record['id']];
        final deleted = (record['deletedAt'] as int) > 0;
        if (!deleted && game == null) {
          _recordSignatures.remove(syncId);
          continue;
        }
        final gameTags = deleted
            ? const <TagEntry>[]
            : tags[game!.id] ?? const <TagEntry>[];
        final tagSignatures =
            gameTags
                .map(
                  (tag) => jsonEncode([
                    tag.name,
                    tagVersions[tag.id]?['changeClock'],
                    tagVersions[tag.id]?['changeOrigin'],
                  ]),
                )
                .toList()
              ..sort();
        final content = deleted
            ? 'deleted'
            : await SyncEntryFingerprint.fromGameEntry(game!, gameTags);
        _recordSignatures[syncId] = jsonEncode([
          syncId,
          record['changeClock'],
          record['changeOrigin'],
          content,
          tagSignatures,
        ]);
      }
      if (!reset) {
        // Identity adoption can remove the prior sync record without changing
        // any game fields. Prune metadata-only removals without rehashing the
        // unchanged rows in the library.
        final currentIds = await db.getSyncRecordIds();
        _recordSignatures.removeWhere((id, _) => !currentIds.contains(id));
      }
      final signatures = _recordSignatures.values.toList()..sort();
      final digest = await SyncEntryFingerprint.hashBytes(
        utf8.encode(jsonEncode(signatures)),
      );
      _digestRevision = revision;
      _digestDatabase = db;
      _digestOrigin = origin;
      _digest = digest;
      return digest;
    });
  }

  Future<Map<String, dynamic>> buildDeltaPayload({
    required String syncRevisionId,
    required int baseRevision,
    required int baseSyncAtMillis,
    required int localRevision,
    String? deviceName,
    bool includeAllGames = false,
    bool includeSteamCache = true,
  }) async {
    final db = getDatabase();
    final full = includeAllGames || baseRevision <= 0;
    if (db == null) {
      return {
        'mode': 'delta',
        'fullDataset': full,
        'syncProtocol': 3,
        'syncRevisionId': syncRevisionId,
        'localRevision': 0,
        'dbTimestampMillis': 0,
        'baseRevision': baseRevision,
        'baseSyncAt': baseSyncAtMillis,
        'games': const <Map<String, dynamic>>[],
        'tombstones': const <Map<String, dynamic>>[],
      };
    }
    // The cursor and records describe the same snapshot. A later edit must
    // never fall behind a checkpoint for an earlier payload.
    return db.transaction(() async {
      final snapshotRevision = await db.getLocalSyncRevision();
      final full =
          includeAllGames ||
          baseRevision <= 0 ||
          baseRevision > snapshotRevision;
      final records = await db.getSyncRecords(
        sinceRevision: full ? 0 : baseRevision,
      );
      final liveById = <int, Map<String, dynamic>>{
        for (final record in records)
          if (record['deletedAt'] == 0 && record['id'] is int)
            record['id'] as int: record,
      };
      final changed = await db.getGamesByIds(liveById.keys);
      final tags = await db.getTagsForGames(
        changed.map((game) => game.id).toList(),
      );
      final tagVersions = await db.getSyncTagVersions();
      final serialized = <Map<String, dynamic>>[];
      for (final game in changed) {
        final record = liveById[game.id]!;
        final gameTags = tags[game.id] ?? const <TagEntry>[];
        final cover = await _serializeCoverImageForTransfer(
          rawCoverImagePath: game.coverImage,
          gameKey: game.gameKey,
        );
        serialized.add({
          'id': game.id,
          'syncId': record['syncId'],
          'changeClock': record['changeClock'],
          'changeOrigin': record['changeOrigin'],
          'title': game.title,
          'gameKey': game.gameKey,
          'platform': game.platform,
          'dateAdded': game.dateAdded.toUtc().toIso8601String(),
          'updatedAt': game.updatedAt.toUtc().toIso8601String(),
          'notes': game.notes,
          'isUsed': game.isUsed,
          'coverImage': game.coverImage,
          'hasCoverImage': game.coverImage.trim().isNotEmpty,
          'coverDigest': cover.digest,
          'coverImageFile': cover.file,
          'hasDeadline': game.hasDeadline,
          'deadlineDate': game.deadlineDate?.toUtc().toIso8601String(),
          'isDlc': game.isDlc,
          'steamAppId': game.steamAppId,
          'developer': game.developer,
          'reviewScore': game.reviewScore,
          'reviewCount': game.reviewCount,
          'entrySyncId': await SyncEntryFingerprint.fromGameEntry(
            game,
            gameTags,
            coverDigest: cover.digest,
          ),
          'tags': gameTags
              .map(
                (tag) => {
                  'name': tag.name,
                  'colorHex': tag.color,
                  'isSteamTag': tag.isSteamTag,
                  ...?tagVersions[tag.id],
                },
              )
              .toList(growable: false),
        });
      }
      return {
        'mode': 'delta',
        'fullDataset': full,
        'syncProtocol': 3,
        'syncRevisionId': syncRevisionId,
        'localRevision': snapshotRevision,
        'dbTimestampMillis': await db.getSyncDbTimestampMillis(),
        'contentDigest': await _getDatasetDigest(db),
        'baseRevision': baseRevision,
        'baseSyncAt': baseSyncAtMillis,
        if (deviceName != null && deviceName.isNotEmpty)
          'deviceName': deviceName,
        if (includeSteamCache) 'steamCache': await exportSteamCache(),
        'games': serialized,
        'tombstones': records
            .where((record) => (record['deletedAt'] as int) > 0)
            .toList(growable: false),
      };
    });
  }

  static bool _modern(Map<String, dynamic> data) =>
      (data['syncId'] as String? ?? '').isNotEmpty &&
      (data['changeClock'] as num? ?? 0) > 0 &&
      (data['changeOrigin'] as String? ?? '').isNotEmpty;

  static String _legacyIdentity(Map<String, dynamic> data) {
    final key = base64Url.encode(utf8.encode(data['gameKey'] as String? ?? ''));
    final added = DateTime.tryParse(
      data['dateAdded'] as String? ?? '',
    )?.millisecondsSinceEpoch;
    return 'legacy-wire:${data['id']}:$key:${added == null ? 0 : added ~/ 1000}';
  }

  static int _compareVersions(Map<String, dynamic> a, Map<String, dynamic> b) {
    final clock = (a['changeClock'] as num).toInt().compareTo(
      (b['changeClock'] as num).toInt(),
    );
    return clock != 0
        ? clock
        : (a['changeOrigin'] as String).compareTo(b['changeOrigin'] as String);
  }

  Future<Map<String, TagEntry>> _mergeIncomingTags(
    AppDatabase db,
    List<Map<String, dynamic>> games,
  ) async {
    final candidates = <String, Map<String, dynamic>>{};
    for (final game in games) {
      for (final raw
          in (game['tags'] as List<dynamic>? ?? []).whereType<Map>()) {
        final name = (raw['name'] as String? ?? '').trim();
        if (name.isEmpty) continue;
        final spec = <String, dynamic>{
          'name': name,
          'colorHex': raw['colorHex'] as String? ?? '#0078d4',
          'isSteamTag': raw['isSteamTag'] as bool? ?? false,
          'changeClock': raw['changeClock'] ?? game['changeClock'] ?? 1,
          'changeOrigin':
              raw['changeOrigin'] ?? game['changeOrigin'] ?? 'legacy',
        };
        final previous = candidates[name.toLowerCase()];
        if (previous == null ||
            _compareVersions(spec, previous) > 0 ||
            _compareVersions(spec, previous) == 0 &&
                jsonEncode([
                      spec['name'],
                      spec['colorHex'],
                      spec['isSteamTag'],
                    ]).compareTo(
                      jsonEncode([
                        previous['name'],
                        previous['colorHex'],
                        previous['isSteamTag'],
                      ]),
                    ) >
                    0) {
          candidates[name.toLowerCase()] = spec;
        }
      }
    }
    if (candidates.isEmpty) return {};
    final existing = {
      for (final tag in await db.getAllTags()) tag.name.toLowerCase(): tag,
    };
    final versions = await db.getSyncTagVersions();
    final gameVersions = await db.getSyncRecords(
      attachedTagIds: [
        for (final name in candidates.keys)
          if (existing[name] != null) existing[name]!.id,
      ],
    );
    final resolved = await db.batchGetOrCreateTags(
      candidates.values
          .map(
            (spec) => (
              name: spec['name'] as String,
              color: spec['colorHex'] as String,
              isSteamTag: spec['isSteamTag'] as bool,
            ),
          )
          .toList(),
    );
    var touched = false;
    for (final entry in candidates.entries) {
      final local = existing[entry.key];
      final candidate = entry.value;
      final version = local == null ? null : versions[local.id];
      if (version != null) {
        final compared = _compareVersions(candidate, version);
        if (compared < 0) continue;
        if (compared == 0 &&
            jsonEncode([
                  candidate['name'],
                  candidate['colorHex'],
                  candidate['isSteamTag'],
                ]).compareTo(
                  jsonEncode([local!.name, local.color, local.isSteamTag]),
                ) <=
                0) {
          continue;
        }
      }
      var tag = resolved[entry.key]!;
      final updated = tag.copyWith(
        name: candidate['name'] as String,
        color: candidate['colorHex'] as String,
        isSteamTag: candidate['isSteamTag'] as bool,
      );
      if (updated != tag) {
        await db.updateTag(updated);
        tag = updated;
      }
      await db.acceptRemoteTagVersion(
        tag.id,
        (candidate['changeClock'] as num).toInt(),
        candidate['changeOrigin'] as String,
      );
      resolved[entry.key] = tag;
      touched = true;
    }
    if (touched) await db.restoreSyncRecordVersions(gameVersions);
    return resolved;
  }

  /// Modern records converge by stable identity and deterministic logical
  /// versions. Received changes retain their version when relayed to a third
  /// device. Legacy peers still use their timestamp/conflict rules.
  Future<SyncImportResult> applyDeltaPayload(
    List<Map<String, dynamic>> gamesJson, {
    List<Map<String, dynamic>> tombstones = const [],
    DateTime? lastSyncAt,
  }) async {
    final db = getDatabase();
    if (db == null) {
      return const SyncImportResult(inserted: 0, updated: 0, conflicts: 0);
    }
    return db.transaction(() async {
      final tagEntries = await _mergeIncomingTags(db, gamesJson);
      final records = await db.getSyncRecords();
      final recordsBySync = {
        for (final record in records) record['syncId'] as String: record,
      };
      final targetIds = <int>{
        for (final record in [...gamesJson, ...tombstones])
          if (record['id'] is num) (record['id'] as num).toInt(),
        for (final record in [...gamesJson, ...tombstones])
          if (recordsBySync[record['syncId']]?['id'] is int)
            recordsBySync[record['syncId']]!['id'] as int,
        for (final record in gamesJson)
          if (!_modern(record) &&
              recordsBySync[_legacyIdentity(record)]?['id'] is int)
            recordsBySync[_legacyIdentity(record)]!['id'] as int,
      };
      final games = await db.getGamesByIds(targetIds);
      final gamesById = {for (final game in games) game.id: game};
      final tagsById = await db.getTagsForGames(
        games.map((game) => game.id).toList(),
      );
      var deleted = 0;
      var inserted = 0;
      var updated = 0;
      var conflicts = 0;
      var nextLocalId = await db.getNextGameIdForSync();
      final inserts = <GamesCompanion>[];
      final updates = <GameEntry>[];
      final tagsToSet = <int, List<int>>{};
      final remoteRecords = <Map<String, dynamic>>[];

      for (final tombstone in tombstones) {
        final modern = _modern(tombstone);
        final incomingId = (tombstone['id'] as num?)?.toInt();
        final syncId = tombstone['syncId'] as String?;
        final localRecord = modern ? recordsBySync[syncId] : null;
        var localId = modern
            ? (localRecord?['deletedAt'] == 0
                  ? (localRecord?['id'] as int?)
                  : null)
            : incomingId;
        final key = tombstone['gameKey'] as String? ?? '';
        // Version-8 tombstones have no creation date with which to recover
        // their bootstrap identity. Restrict fallback matching to those.
        if (localId == null &&
            (syncId?.startsWith('legacy-delete:') ?? false)) {
          final candidate = gamesById[incomingId];
          final candidateRecords = records.where(
            (record) => record['id'] == incomingId && record['deletedAt'] == 0,
          );
          if (candidate != null &&
              candidate.gameKey == key &&
              candidateRecords.isNotEmpty &&
              (candidateRecords.first['syncId'] as String).startsWith(
                'legacy:',
              ) &&
              _compareVersions(tombstone, candidateRecords.first) >= 0) {
            localId = candidate.id;
          }
        }
        final local = gamesById[localId];
        final deletedAt = (tombstone['deletedAt'] as num?)?.toInt() ?? 0;
        if (modern && localRecord != null) {
          final compared = _compareVersions(tombstone, localRecord);
          if (compared < 0 || compared == 0 && localRecord['deletedAt'] != 0) {
            continue;
          }
        }
        if (!modern && (incomingId == null || incomingId <= 0)) continue;
        if (!modern &&
            local != null &&
            local.updatedAt.millisecondsSinceEpoch > deletedAt) {
          conflicts++;
          continue;
        }
        if (!modern &&
            local != null &&
            key.isNotEmpty &&
            local.gameKey != key) {
          continue;
        }
        if (local != null) {
          await db.batchDeleteGameTags([local.id]);
          await (db.delete(
            db.games,
          )..where((game) => game.id.equals(local.id))).go();
          gamesById.remove(local.id);
          deleted++;
        }
        if (modern) {
          await db.acceptRemoteSyncRecord(
            syncId: syncId!,
            localGameId: localId,
            gameKey: key,
            changeClock: (tombstone['changeClock'] as num).toInt(),
            changeOrigin: tombstone['changeOrigin'] as String,
            deletedAt: deletedAt > 0 ? deletedAt : 1,
          );
          recordsBySync[syncId] = {
            ...tombstone,
            'id': localId,
            'deletedAt': deletedAt > 0 ? deletedAt : 1,
          };
        } else if (local != null) {
          await db.recordGameDeletionTombstones(
            [local.id],
            gameKeysById: {local.id: local.gameKey},
            deletedAtMillis: deletedAt,
          );
        }
      }

      // Highest version wins within a packet too, regardless of record order.
      final incomingByIdentity = <String, Map<String, dynamic>>{};
      for (final data in gamesJson) {
        final identity = _modern(data)
            ? data['syncId'] as String
            : 'wire:${data['id']}:${data['gameKey']}:${data['dateAdded']}';
        final previous = incomingByIdentity[identity];
        if (previous == null ||
            !_modern(data) ||
            _compareVersions(data, previous) > 0 ||
            _compareVersions(data, previous) == 0 &&
                (await SyncEntryFingerprint.fromPayload(data)).compareTo(
                      await SyncEntryFingerprint.fromPayload(previous),
                    ) >
                    0) {
          incomingByIdentity[identity] = data;
        }
      }
      for (final rawData in incomingByIdentity.values) {
        // A tag is shared by several games. Use its independently resolved
        // metadata when comparing records, so an older colour cannot force
        // repeated repair of an otherwise identical game.
        final data = {
          ...rawData,
          'tags': [
            for (final tag
                in (rawData['tags'] as List<dynamic>? ?? []).whereType<Map>())
              if (tagEntries[(tag['name'] as String? ?? '')
                      .trim()
                      .toLowerCase()]
                  case final TagEntry localTag)
                {
                  'name': localTag.name,
                  'colorHex': localTag.color,
                  'isSteamTag': localTag.isSteamTag,
                },
          ],
        };
        final incomingId = (data['id'] as num?)?.toInt();
        final key = (data['gameKey'] as String? ?? '').trim();
        if (key.isEmpty) continue;
        final modern = _modern(data);
        final syncId = data['syncId'] as String?;
        var localRecord = modern ? recordsBySync[syncId] : null;
        GameEntry? existing;
        if (modern) {
          if (localRecord != null && localRecord['deletedAt'] == 0) {
            existing = gamesById[localRecord['id']];
          }
          if (localRecord == null && (syncId?.startsWith('legacy:') ?? false)) {
            final candidate = gamesById[incomingId];
            final created = DateTime.tryParse(
              data['dateAdded'] as String? ?? '',
            );
            if (candidate != null &&
                candidate.gameKey == key &&
                created != null &&
                candidate.dateAdded.millisecondsSinceEpoch ~/ 1000 ==
                    created.millisecondsSinceEpoch ~/ 1000) {
              existing = candidate;
              localRecord = records.firstWhere(
                (record) =>
                    record['id'] == candidate.id && record['deletedAt'] == 0,
              );
            }
          }
          if (localRecord != null && _compareVersions(data, localRecord) < 0) {
            continue;
          }
        } else {
          localRecord = recordsBySync[_legacyIdentity(data)];
          final candidate = gamesById[incomingId];
          if (candidate != null && candidate.gameKey == key) {
            existing = candidate;
          }
          existing ??= gamesById[recordsBySync[_legacyIdentity(data)]?['id']];
        }
        final dateAdded =
            DateTime.tryParse(data['dateAdded'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final changedAt =
            DateTime.tryParse(data['updatedAt'] as String? ?? '') ?? dateAdded;
        if (!modern &&
            localRecord != null &&
            (localRecord['deletedAt'] as int? ?? 0) > 0 &&
            changedAt.millisecondsSinceEpoch <=
                (localRecord['deletedAt'] as int)) {
          continue;
        }
        final incomingHash = await SyncEntryFingerprint.fromPayload(data);
        final localHash = existing == null
            ? null
            : await SyncEntryFingerprint.fromGameEntry(
                existing,
                tagsById[existing.id] ?? [],
              );
        final sameContent = incomingHash == localHash;
        if (modern &&
            localRecord != null &&
            _compareVersions(data, localRecord) == 0) {
          if (sameContent ||
              localHash != null && incomingHash.compareTo(localHash) <= 0) {
            continue;
          }
          if (localRecord['deletedAt'] != 0) continue;
        }
        if (!modern && existing != null) {
          // Legacy packets may format timestamps differently and historically
          // omitted content metadata; keep their last-write-wins semantics.
          if (sameContent) continue;
          if (!changedAt.isAfter(existing.updatedAt)) continue;
          if (lastSyncAt != null && existing.updatedAt.isAfter(lastSyncAt)) {
            conflicts++;
            continue;
          }
        }
        if (modern &&
            existing != null &&
            !sameContent &&
            localRecord != null &&
            data['changeClock'] == localRecord['changeClock'] &&
            data['changeOrigin'] != localRecord['changeOrigin']) {
          conflicts++;
        }
        var localId = existing?.id;
        if (!sameContent) {
          if (localId == null) {
            localId =
                incomingId != null &&
                    incomingId > 0 &&
                    !gamesById.containsKey(incomingId)
                ? incomingId
                : nextLocalId;
            if (localId >= nextLocalId) nextLocalId = localId + 1;
          }
          String? persistedCover;
          if (data['coverImageFile'] is Map) {
            persistedCover = await _persistIncomingCoverImage(
              payload: Map<String, dynamic>.from(data['coverImageFile'] as Map),
            );
          }
          final cover = await _resolveTranslatedCoverImagePath(
            hasCoverImage:
                data['hasCoverImage'] as bool? ??
                (data['coverImage'] as String? ?? '').isNotEmpty,
            syncedCoverImagePath: persistedCover,
            incomingLegacyCoverPath: data['coverImage'] as String? ?? '',
            existingCoverImagePath: existing?.coverImage ?? '',
          );
          final companion = GamesCompanion(
            id: Value(localId),
            title: Value(data['title'] as String? ?? ''),
            gameKey: Value(key),
            platform: Value(data['platform'] as String? ?? 'Steam'),
            dateAdded: Value(dateAdded),
            updatedAt: Value(changedAt),
            notes: Value(data['notes'] as String? ?? ''),
            isUsed: Value(data['isUsed'] as bool? ?? false),
            coverImage: Value(cover),
            hasDeadline: Value(data['hasDeadline'] as bool? ?? false),
            deadlineDate: Value(
              DateTime.tryParse(data['deadlineDate'] as String? ?? ''),
            ),
            isDlc: Value(data['isDlc'] as bool? ?? false),
            steamAppId: Value(data['steamAppId'] as String? ?? ''),
            developer: Value(data['developer'] as String? ?? ''),
            reviewScore: Value((data['reviewScore'] as num?)?.toInt() ?? 0),
            reviewCount: Value((data['reviewCount'] as num?)?.toInt() ?? 0),
          );
          if (existing == null) {
            inserts.add(companion);
            inserted++;
          } else {
            updates.add(_entryFromCompanion(companion));
            updated++;
          }
          final rawTags = (data['tags'] as List<dynamic>? ?? [])
              .whereType<Map>()
              .toList();
          final resolvedTags = <TagEntry>[
            for (final tag in rawTags)
              if (tagEntries[(tag['name'] as String? ?? '')
                      .trim()
                      .toLowerCase()]
                  case final TagEntry entry)
                entry,
          ];
          tagsToSet[localId] = resolvedTags
              .map((tag) => tag.id)
              .toSet()
              .toList();
          gamesById[localId] = _entryFromCompanion(companion);
          tagsById[localId] = resolvedTags;
        }
        if (modern && localId != null) {
          remoteRecords.add({...data, 'id': localId, 'deletedAt': 0});
          recordsBySync[syncId!] = {...data, 'id': localId, 'deletedAt': 0};
        } else if (!modern && existing == null && localId != null) {
          final legacyId = _legacyIdentity(data);
          final record = <String, dynamic>{
            'syncId': legacyId,
            'id': localId,
            'gameKey': key,
            'changeClock': changedAt.millisecondsSinceEpoch > 0
                ? changedAt.millisecondsSinceEpoch
                : 1,
            'changeOrigin': 'legacy-wire',
            'deletedAt': 0,
          };
          remoteRecords.add(record);
          recordsBySync[legacyId] = record;
        }
      }
      if (inserts.isNotEmpty) {
        await db.batch((batch) => batch.insertAll(db.games, inserts));
      }
      await db.batchUpdateGames(updates);
      await db.batchSetTagsForGames(tagsToSet);
      await db.acceptRemoteSyncRecords(remoteRecords);
      return SyncImportResult(
        inserted: inserted,
        deleted: deleted,
        updated: updated,
        conflicts: conflicts,
      );
    });
  }

  static GameEntry _entryFromCompanion(GamesCompanion game) => GameEntry(
    id: game.id.value,
    title: game.title.value,
    gameKey: game.gameKey.value,
    platform: game.platform.value,
    dateAdded: game.dateAdded.value,
    updatedAt: game.updatedAt.value,
    notes: game.notes.value,
    isUsed: game.isUsed.value,
    coverImage: game.coverImage.value,
    hasDeadline: game.hasDeadline.value,
    deadlineDate: game.deadlineDate.value,
    isDlc: game.isDlc.value,
    steamAppId: game.steamAppId.value,
    developer: game.developer.value,
    reviewScore: game.reviewScore.value,
    reviewCount: game.reviewCount.value,
  );

  // -------------------------------------------------------------------------
  // Cover image serialisation helpers
  // -------------------------------------------------------------------------

  /// Hash the same bytes that are sent, without reading the cover again for
  /// the payload digest and entry fingerprint.
  Future<({String digest, Map<String, dynamic>? file})>
  _serializeCoverImageForTransfer({
    required String rawCoverImagePath,
    required String gameKey,
  }) async {
    final raw = rawCoverImagePath.trim();
    if (raw.isEmpty) return (digest: '', file: null);
    if (raw.startsWith('http://') ||
        raw.startsWith('https://') ||
        raw.startsWith('assets/')) {
      return (digest: raw, file: null);
    }

    File sourceFile;
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.scheme.toLowerCase() == 'file') {
      sourceFile = File.fromUri(uri);
    } else {
      sourceFile = File(raw);
    }

    if (!await sourceFile.exists()) return (digest: '', file: null);
    final bytes = await sourceFile.readAsBytes();
    final digest = 'sha256:${await SyncEntryFingerprint.hashBytes(bytes)}';
    if (bytes.isEmpty) return (digest: digest, file: null);

    final sourceName = p.basename(sourceFile.path).trim();
    final ext = p.extension(sourceFile.path).toLowerCase();
    final safeKey = gameKey.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final fileName = sourceName.isNotEmpty
        ? sourceName
        : '${safeKey.isEmpty ? 'cover' : safeKey}${ext.isEmpty ? '.img' : ext}';
    return (
      digest: digest,
      file: {'fileName': fileName, 'bytesBase64': base64Encode(bytes)},
    );
  }

  Future<String?> _persistIncomingCoverImage({
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
    final ext = p.extension(p.basename(incomingName));
    final safeName =
        '${await SyncEntryFingerprint.hashBytes(bytes)}${ext.isEmpty ? '.img' : ext}';
    final target = File(p.join(imagesDir.path, safeName));
    if (!await target.exists()) await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  Future<String> _resolveTranslatedCoverImagePath({
    required bool hasCoverImage,
    required String? syncedCoverImagePath,
    required String incomingLegacyCoverPath,
    required String existingCoverImagePath,
  }) async {
    if (!hasCoverImage) return '';

    if (syncedCoverImagePath != null &&
        syncedCoverImagePath.trim().isNotEmpty) {
      return syncedCoverImagePath.trim();
    }

    final fromIncoming = await _translateCoverImagePathForCurrentDevice(
      rawPath: incomingLegacyCoverPath,
    );
    if (fromIncoming.isNotEmpty) return fromIncoming;

    final fromExisting = await _translateCoverImagePathForCurrentDevice(
      rawPath: existingCoverImagePath,
    );
    if (fromExisting.isNotEmpty) return fromExisting;

    return '';
  }

  Future<String> _translateCoverImagePathForCurrentDevice({
    required String rawPath,
  }) async {
    final raw = rawPath.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('assets/')) return raw;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;

    final sourceFile = _fileFromRawPath(raw);
    if (sourceFile != null && await sourceFile.exists()) {
      return _copyCoverImageToManagedPath(sourceFile);
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
    if (_windowsPathPattern.hasMatch(raw) || raw.startsWith('/')) {
      return File(raw);
    }
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
    final sourcePath = (uri != null && uri.scheme.toLowerCase() == 'file')
        ? uri.path
        : rawPath;
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

  Future<String> _copyCoverImageToManagedPath(File sourceFile) async {
    final sourceCanonical = p.normalize(sourceFile.absolute.path);
    final syncDir = await _resolveManagedImagesDirectory();
    final steamDir = await _resolveSteamImagesDirectory();

    if (sourceCanonical.startsWith(p.normalize(syncDir.path)) ||
        sourceCanonical.startsWith(p.normalize(steamDir.path))) {
      return sourceFile.path;
    }

    final ext = p.extension(sourceFile.path);
    final digest = await SyncEntryFingerprint.hashBytes(
      await sourceFile.readAsBytes(),
    );
    final fileName = '$digest${ext.isEmpty ? '.img' : ext}';

    final target = File(p.join(syncDir.path, fileName));
    if (!await target.exists()) {
      await sourceFile.copy(target.path);
    }
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
