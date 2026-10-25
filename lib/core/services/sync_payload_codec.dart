/// Codec that serialises and deserialises the sync payload exchanged between
/// devices.  Extracted from [DeviceSyncService] so the logic can be tested and
/// reasoned about independently of the transport layer.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../database/database.dart';
import '../models/device_sync_models.dart';
import 'sync_entry_fingerprint.dart';
import 'sync_frames.dart';
import 'steam_service.dart';

class SyncPayloadCodec {
  SyncPayloadCodec({
    required this.getDatabase,
    this.exportSteamCache = exportSteamCacheSnapshotForSync,
    this.imagesRoot,
  });

  final AppDatabase? Function() getDatabase;
  final Future<Map<String, dynamic>> Function() exportSteamCache;

  /// Folder holding the `sync` and `steam` image folders. Defaults to the
  /// `images` folder beside the default database.
  final Future<Directory> Function()? imagesRoot;

  static final RegExp _windowsPathPattern = RegExp(r'^[a-zA-Z]:[\\/]');

  /// Digest state is shared by every codec bound to the same open database,
  /// so the background poll, manual syncs and incoming transfers reuse one
  /// computation instead of each rehashing the library.
  static final Expando<_DigestState> _digestStates = Expando();

  /// Below this many changed records hashing stays on the calling isolate;
  /// spawning a worker would cost more than it saves.
  static const int _isolateHashThreshold = 256;

  /// Hashes only journalled changes after the initial snapshot. Health checks
  /// reuse the completed digest while the database revision is unchanged.
  Future<String> getDatasetDigest() async {
    final db = getDatabase();
    if (db == null) return '';
    return _getDatasetDigest(db);
  }

  /// Record hashes folded into [count] buckets that peers compare to find
  /// the few records that differ, instead of exchanging every record's hash.
  /// Also returns the revision the hashes describe: records changed after it
  /// must be sent whatever their bucket.
  Future<({List<String> digests, int revision})> getBucketDigests(
    int count,
  ) async {
    final db = getDatabase();
    if (db == null) return (digests: List.filled(count, ''), revision: 0);
    await _getDatasetDigest(db);
    final state = _digestStates[db]!;
    return (
      digests: bucketDigests(state.hashes, count),
      revision: state.revision ?? 0,
    );
  }

  /// Number of live and deleted records the digests currently cover.
  int get hashedRecordCount {
    final db = getDatabase();
    return db == null ? 0 : _digestStates[db]?.hashes.length ?? 0;
  }

  /// About 32 records per bucket keeps both the digests and the records sent
  /// around one edit small.
  static int bucketCountFor(int records) {
    var count = 16;
    while (count < 2048 && count * 32 < records) {
      count *= 2;
    }
    return count;
  }

  /// Stable across devices and platforms: FNV-1a of the sync ID.
  static int bucketOf(String syncId, int count) {
    var hash = 0x811c9dc5;
    for (final unit in syncId.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash % count;
  }

  /// XOR of each bucket's 60-bit record-hash prefixes: order-independent,
  /// and record hashes include the sync ID, so duplicates cannot cancel out.
  static List<String> bucketDigests(Map<String, String> hashes, int count) {
    final buckets = List<int?>.filled(count, null);
    hashes.forEach((syncId, hash) {
      final bucket = bucketOf(syncId, count);
      final value = int.parse(hash.substring(0, 15), radix: 16);
      buckets[bucket] = (buckets[bucket] ?? 0) ^ value;
    });
    return [for (final value in buckets) value?.toRadixString(16) ?? ''];
  }

  /// Buckets whose digests differ; a missing remote digest always differs.
  static Set<int> differingBuckets(List<Object?> local, List<Object?> remote) =>
      {
        for (var i = 0; i < local.length; i++)
          if (i >= remote.length || local[i] != remote[i]) i,
      };

  /// `sha256:<hex>` digests of the covers stored in the managed sync image
  /// folder. Those files are content-addressed, so a peer can skip sending
  /// any cover listed here.
  Future<List<String>> getLocalCoverDigests() async =>
      (await _localCoverFiles()).keys.toList();

  Future<Map<String, String>> _localCoverFiles() async {
    final dir = await _resolveManagedImagesDirectory();
    final files = <String, String>{};
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basenameWithoutExtension(entity.path);
      if (_sha256Hex.hasMatch(name)) files['sha256:$name'] = entity.path;
    }
    return files;
  }

  static final RegExp _sha256Hex = RegExp(r'^[0-9a-f]{64}$');

  /// Long record loops pause this often so the UI can draw frames; awaiting
  /// only completed futures never returns control to the event loop.
  static const int _yieldEvery = 250;

  static Future<void> _yieldToUi() => Future<void>.delayed(Duration.zero);

  /// Must not be awaited from inside a database transaction: the refresh reads
  /// in its own transaction and would wait on the caller's forever.
  Future<String> _getDatasetDigest(AppDatabase db) {
    final state = _digestStates[db] ??= _DigestState();
    return state.inFlight ??= _refreshDigest(
      db,
      state,
    ).whenComplete(() => state.inFlight = null);
  }

  Future<String> _refreshDigest(AppDatabase db, _DigestState state) async {
    final snapshot = await db.transaction(() async {
      final revision = await db.getLocalSyncRevision();
      final origin = await db.getSyncDatabaseOrigin();
      if (state.origin == origin &&
          state.revision == revision &&
          state.digest != null) {
        return null;
      }
      final reset =
          state.origin != origin ||
          state.revision == null ||
          revision < state.revision!;
      final records = await db.getSyncRecords(
        sinceRevision: reset ? 0 : state.revision!,
      );
      final games = await db.getGamesByIds([
        for (final record in records)
          if (record['deletedAt'] == 0 && record['id'] is int)
            record['id'] as int,
      ]);
      return (
        revision: revision,
        origin: origin,
        reset: reset,
        records: records,
        games: games,
        tags: await db.getTagsForGames(games.map((game) => game.id).toList()),
        tagVersions: await db.getSyncTagVersions(),
        // Identity adoption can remove the prior sync record without changing
        // any game fields. Prune metadata-only removals without rehashing the
        // unchanged rows in the library.
        currentIds: reset ? null : await db.getSyncRecordIds(),
      );
    });
    if (snapshot == null) return state.digest!;

    final records = snapshot.records;
    final games = snapshot.games;
    final tags = snapshot.tags;
    final tagVersions = snapshot.tagVersions;
    final ({Map<String, String?> hashes, Map<String, CoverStamp> covers})
    hashed;
    if (records.length < _isolateHashThreshold) {
      hashed = _hashRecords(records, games, tags, tagVersions, null);
    } else {
      hashed = await _hashRecordsInBackground(
        records,
        games,
        tags,
        tagVersions,
        Map.of(SyncEntryFingerprint.coverCache),
      );
      SyncEntryFingerprint.coverCache.addAll(hashed.covers);
    }

    if (snapshot.reset) state.hashes.clear();
    hashed.hashes.forEach((syncId, hash) {
      if (hash == null) {
        state.hashes.remove(syncId);
      } else {
        state.hashes[syncId] = hash;
      }
    });
    final currentIds = snapshot.currentIds;
    if (currentIds != null) {
      state.hashes.removeWhere((id, _) => !currentIds.contains(id));
    }
    final entries = [
      for (final entry in state.hashes.entries) '${entry.key}:${entry.value}',
    ]..sort();
    state
      ..revision = snapshot.revision
      ..origin = snapshot.origin
      ..digest = SyncEntryFingerprint.hashBytes(
        utf8.encode(entries.join('\n')),
      );
    return state.digest!;
  }

  /// Kept static so the worker closure captures only these arguments.
  static Future<({Map<String, String?> hashes, Map<String, CoverStamp> covers})>
  _hashRecordsInBackground(
    List<Map<String, dynamic>> records,
    List<GameEntry> games,
    Map<int, List<TagEntry>> tags,
    Map<int, Map<String, dynamic>> tagVersions,
    Map<String, CoverStamp> coverCache,
  ) => Isolate.run(
    () => _hashRecords(records, games, tags, tagVersions, coverCache),
  );

  /// Pure function so it can run on a worker isolate. A `null` hash marks a
  /// record whose game row disappeared without a tombstone.
  static ({Map<String, String?> hashes, Map<String, CoverStamp> covers})
  _hashRecords(
    List<Map<String, dynamic>> records,
    List<GameEntry> games,
    Map<int, List<TagEntry>> tags,
    Map<int, Map<String, dynamic>> tagVersions,
    Map<String, CoverStamp>? coverCache,
  ) {
    if (coverCache != null) SyncEntryFingerprint.coverCache.addAll(coverCache);
    final byId = {for (final game in games) game.id: game};
    final hashes = <String, String?>{};
    for (final record in records) {
      final syncId = record['syncId'] as String;
      final game = byId[record['id']];
      final deleted = (record['deletedAt'] as int) > 0;
      if (!deleted && game == null) {
        hashes[syncId] = null;
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
          : SyncEntryFingerprint.fromGameEntry(game!, gameTags);
      final signature = jsonEncode([
        syncId,
        record['changeClock'],
        record['changeOrigin'],
        content,
        tagSignatures,
      ]);
      // 128 bits is ample to detect a changed record; the full digest below
      // still covers the whole manifest.
      hashes[syncId] = SyncEntryFingerprint.hashBytes(
        utf8.encode(signature),
      ).substring(0, 32);
    }
    return (hashes: hashes, covers: SyncEntryFingerprint.coverCache);
  }

  /// Builds the records to send to a peer: everything changed after
  /// [sinceRevision], or with [onlyBuckets] just the records in buckets whose
  /// digests differ from the peer's (plus any changed after those digests
  /// were taken). Covers the peer lists in [peerCovers] are not sent again.
  Future<Map<String, dynamic>> buildDeltaPayload({
    required String syncRevisionId,
    String? deviceName,
    bool includeSteamCache = true,
    int sinceRevision = 0,
    ({int count, Set<int> buckets, int hashedRevision})? onlyBuckets,
    Set<String> peerCovers = const {},
  }) async {
    final db = getDatabase();
    if (db == null) {
      return {
        'syncProtocol': supportedDeviceSyncProtocol,
        'syncRevisionId': syncRevisionId,
        'localRevision': 0,
        'dbTimestampMillis': 0,
        'games': const <Map<String, dynamic>>[],
        'tombstones': const <Map<String, dynamic>>[],
      };
    }
    // Hash outside the transaction below (see [_getDatasetDigest]).
    final contentDigest = await _getDatasetDigest(db);
    // The cursor and records describe the same snapshot. A later edit must
    // never fall behind a checkpoint for an earlier payload.
    final snapshot = await db.transaction(() async {
      final snapshotRevision = await db.getLocalSyncRevision();
      var records = await db.getSyncRecords(
        sinceRevision: onlyBuckets == null ? sinceRevision : 0,
      );
      if (onlyBuckets case (
        :final count,
        :final buckets,
        :final hashedRevision,
      )) {
        records = records
            .where(
              (record) =>
                  (record['localRevision'] as int) > hashedRevision ||
                  buckets.contains(bucketOf(record['syncId'] as String, count)),
            )
            .toList(growable: false);
      }
      final liveById = <int, Map<String, dynamic>>{
        for (final record in records)
          if (record['deletedAt'] == 0 && record['id'] is int)
            record['id'] as int: record,
      };
      final changed = await db.getGamesByIds(liveById.keys);
      return (
        revision: snapshotRevision,
        records: records,
        liveById: liveById,
        changed: changed,
        tags: await db.getTagsForGames(changed.map((g) => g.id).toList()),
        tagVersions: await db.getSyncTagVersions(),
        dbTimestampMillis: await db.getSyncDbTimestampMillis(),
      );
    });

    final serialized = <Map<String, dynamic>>[];
    final coverFiles = <String, String>{};
    var processed = 0;
    for (final game in snapshot.changed) {
      if (++processed % _yieldEvery == 0) await _yieldToUi();
      final record = snapshot.liveById[game.id]!;
      final gameTags = snapshot.tags[game.id] ?? const <TagEntry>[];
      final coverDigest = SyncEntryFingerprint.coverIdentity(game.coverImage);
      if (coverDigest.startsWith('sha256:') &&
          !peerCovers.contains(coverDigest)) {
        coverFiles.putIfAbsent(coverDigest, () => game.coverImage.trim());
      }
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
        'coverDigest': coverDigest,
        'hasDeadline': game.hasDeadline,
        'deadlineDate': game.deadlineDate?.toUtc().toIso8601String(),
        'isDlc': game.isDlc,
        'steamAppId': game.steamAppId,
        'developer': game.developer,
        'reviewScore': game.reviewScore,
        'reviewCount': game.reviewCount,
        'tags': gameTags
            .map(
              (tag) => {
                'name': tag.name,
                'colorHex': tag.color,
                'isSteamTag': tag.isSteamTag,
                ...?snapshot.tagVersions[tag.id],
              },
            )
            .toList(growable: false),
      });
    }
    return {
      'syncProtocol': supportedDeviceSyncProtocol,
      'syncRevisionId': syncRevisionId,
      'localRevision': snapshot.revision,
      'dbTimestampMillis': snapshot.dbTimestampMillis,
      'contentDigest': contentDigest,
      if (deviceName != null && deviceName.isNotEmpty) 'deviceName': deviceName,
      if (includeSteamCache) 'steamCache': await exportSteamCache(),
      'games': serialized,
      'covers': await _readCoversForTransfer(coverFiles),
      'tombstones': snapshot.records
          .where((record) => (record['deletedAt'] as int) > 0)
          .toList(growable: false),
    };
  }

  /// Reads covers on a worker isolate. A cover whose bytes no longer match
  /// its cached digest is dropped; the receiver keeps its own copy.
  static Future<List<SyncCover>> _readCoversForTransfer(
    Map<String, String> pathsByDigest,
  ) async {
    if (pathsByDigest.isEmpty) return const [];
    return Isolate.run(() {
      final covers = <SyncCover>[];
      pathsByDigest.forEach((digest, raw) {
        try {
          final file = SyncEntryFingerprint.coverFile(raw);
          final bytes = file.readAsBytesSync();
          if (bytes.isEmpty ||
              SyncEntryFingerprint.coverDigest(bytes) != digest) {
            return;
          }
          covers.add(
            SyncCover(
              digest: digest,
              fileName: p.basename(file.path),
              bytes: bytes,
            ),
          );
        } on FileSystemException {
          // Missing covers are simply not sent.
        }
      });
      return covers;
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

  /// Breaks version ties between tag specs deterministically.
  static String _tagSignature(Map<String, dynamic> spec) =>
      jsonEncode([spec['name'], spec['colorHex'], spec['isSteamTag']]);

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
        final compared = previous == null
            ? 1
            : _compareVersions(spec, previous);
        if (compared > 0 ||
            compared == 0 &&
                _tagSignature(spec).compareTo(_tagSignature(previous!)) > 0) {
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
            _tagSignature(candidate).compareTo(
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
  ///
  /// [covers] is the payload's deduplicated `digest → file` map. A record
  /// whose cover is not in it reuses the copy this device already stores.
  Future<SyncImportResult> applyDeltaPayload(
    List<Map<String, dynamic>> gamesJson, {
    List<Map<String, dynamic>> tombstones = const [],
    DateTime? lastSyncAt,
    Map<String, SyncCover> covers = const {},
  }) async {
    final db = getDatabase();
    if (db == null) {
      return const SyncImportResult(inserted: 0, updated: 0, conflicts: 0);
    }
    // Listed only when a record needs a cover, so cover-free payloads never
    // touch the image folder.
    Map<String, String>? localCovers;
    Future<String?> coverForDigest(String digest) async {
      final storedCovers = localCovers ??= await _localCoverFiles();
      final stored = storedCovers[digest];
      if (stored != null) return stored;
      final cover = covers[digest];
      if (cover == null) return null;
      final path = await _persistIncomingCoverImage(cover);
      if (path != null) storedCovers[digest] = path;
      return path;
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
                SyncEntryFingerprint.fromPayload(
                      data,
                    ).compareTo(SyncEntryFingerprint.fromPayload(previous)) >
                    0) {
          incomingByIdentity[identity] = data;
        }
      }
      var processed = 0;
      for (final rawData in incomingByIdentity.values) {
        if (++processed % _yieldEvery == 0) await _yieldToUi();
        // A tag is shared by several games. Use its independently resolved
        // metadata when comparing records, so an older colour cannot force
        // repeated repair of an otherwise identical game.
        final resolvedTags = <TagEntry>[
          for (final tag
              in (rawData['tags'] as List<dynamic>? ?? []).whereType<Map>())
            if (tagEntries[(tag['name'] as String? ?? '').trim().toLowerCase()]
                case final TagEntry localTag)
              localTag,
        ];
        final data = {
          ...rawData,
          'tags': [
            for (final tag in resolvedTags)
              {
                'name': tag.name,
                'colorHex': tag.color,
                'isSteamTag': tag.isSteamTag,
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
        final incomingHash = SyncEntryFingerprint.fromPayload(data);
        final localHash = existing == null
            ? null
            : SyncEntryFingerprint.fromGameEntry(
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
          final coverDigest = data['coverDigest'] as String? ?? '';
          final persistedCover = coverDigest.startsWith('sha256:')
              ? await coverForDigest(coverDigest)
              : null;
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

  /// Stores a received cover under its content address. Bytes that do not
  /// match the digest they were sent under are discarded.
  Future<String?> _persistIncomingCoverImage(SyncCover cover) async {
    final bytes = cover.bytes;
    if (bytes.isEmpty ||
        SyncEntryFingerprint.coverDigest(bytes) != cover.digest) {
      return null;
    }
    final imagesDir = await _resolveManagedImagesDirectory();
    final ext = p.extension(p.basename(cover.fileName.trim()));
    final safeName =
        '${SyncEntryFingerprint.hashBytes(bytes)}${ext.isEmpty ? '.img' : ext}';
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
    final synced = syncedCoverImagePath?.trim() ?? '';
    if (synced.isNotEmpty) return synced;
    final fromIncoming = await _translateCoverImagePathForCurrentDevice(
      incomingLegacyCoverPath,
    );
    if (fromIncoming.isNotEmpty) return fromIncoming;
    return _translateCoverImagePathForCurrentDevice(existingCoverImagePath);
  }

  /// Returns '' when the cover cannot be found on this device.
  Future<String> _translateCoverImagePathForCurrentDevice(
    String rawPath,
  ) async {
    final raw = rawPath.trim();
    if (raw.isEmpty) return '';
    if (SyncEntryFingerprint.isAddressedCover(raw)) return raw;
    final sourceFile = _fileFromRawPath(raw);
    if (sourceFile != null && await sourceFile.exists()) {
      return _copyCoverImageToManagedPath(sourceFile);
    }
    return (await _findManagedImageByName(raw))?.path ?? '';
  }

  File? _fileFromRawPath(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.scheme.toLowerCase() == 'file') {
      return File.fromUri(uri);
    }
    // Legacy support for cross-platform paths (basename extraction only).
    if (_windowsPathPattern.hasMatch(raw) ||
        raw.startsWith('/') ||
        !kIsWeb && Platform.isWindows && raw.startsWith('\\\\')) {
      return File(raw);
    }
    return null;
  }

  Future<File?> _findManagedImageByName(String rawPath) async {
    final uri = Uri.tryParse(rawPath);
    final sourcePath = (uri != null && uri.scheme.toLowerCase() == 'file')
        ? uri.path
        : rawPath;
    // Covers synced from another OS keep that OS's path separators.
    final fileName = _windowsPathPattern.hasMatch(sourcePath)
        ? p.windows.basename(sourcePath)
        : p.basename(sourcePath);
    if (fileName.trim().isEmpty) return null;

    for (final folder in const ['sync', 'steam']) {
      final file = File(
        p.join((await _imagesDirectory(folder)).path, fileName),
      );
      if (await file.exists()) return file;
    }
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
    final digest = SyncEntryFingerprint.hashBytes(
      await sourceFile.readAsBytes(),
    );
    final fileName = '$digest${ext.isEmpty ? '.img' : ext}';

    final target = File(p.join(syncDir.path, fileName));
    if (!await target.exists()) await sourceFile.copy(target.path);
    return target.path;
  }

  // Resolved once: the default lookup goes through a platform channel and
  // codecs are created per sync, so it is shared. An injected root is cached
  // per codec instead, keeping separate devices in one process apart.
  static final Map<String, Future<Directory>> _defaultImageDirectories = {};
  final Map<String, Future<Directory>> _imageDirectories = {};

  Future<Directory> _resolveManagedImagesDirectory() =>
      _imagesDirectory('sync');

  Future<Directory> _resolveSteamImagesDirectory() => _imagesDirectory('steam');

  Future<Directory> _imagesDirectory(String name) {
    final cache = imagesRoot == null
        ? _defaultImageDirectories
        : _imageDirectories;
    return cache[name] ??= () async {
      try {
        final root =
            await imagesRoot?.call() ??
            Directory(
              p.join(p.dirname(await AppDatabase.getDatabasePath()), 'images'),
            );
        final imagesDir = Directory(p.join(root.path, name));
        if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
        return imagesDir;
      } catch (_) {
        // Retry on the next call instead of caching the failure.
        cache.remove(name);
        rethrow;
      }
    }();
  }
}

class _DigestState {
  int? revision;
  String? origin;
  String? digest;

  /// `syncId → record hash`, the manifest peers compare.
  final Map<String, String> hashes = {};
  Future<String>? inFlight;
}
