library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../database/database.dart';

class SyncEntryFingerprint {
  SyncEntryFingerprint._();

  static final Sha256 _sha256 = Sha256();

  static Future<String> fromGameEntry(
    GameEntry game,
    List<TagEntry> tags,
  ) async {
    final normalized = _normalizePayload(
      <String, dynamic>{
        'id': game.id,
        'title': game.title,
        'gameKey': game.gameKey,
        'platform': game.platform,
        'dateAdded': game.dateAdded.toUtc().toIso8601String(),
        'updatedAt': game.updatedAt.toUtc().toIso8601String(),
        'notes': game.notes,
        'isUsed': game.isUsed,
        'coverImage': game.coverImage,
        'hasDeadline': game.hasDeadline,
        'deadlineDate': game.deadlineDate?.toUtc().toIso8601String(),
        'isDlc': game.isDlc,
        'steamAppId': game.steamAppId,
        'developer': game.developer,
        'reviewScore': game.reviewScore,
        'reviewCount': game.reviewCount,
        'tags': tags
            .map(
              (t) => <String, dynamic>{
                'name': t.name,
                'colorHex': t.color,
                'isSteamTag': t.isSteamTag,
              },
            )
            .toList(growable: false),
      },
    );

    return _hashNormalized(normalized);
  }

  static Future<String> fromPayload(
    Map<String, dynamic> gamePayload,
  ) async {
    final normalized = _normalizePayload(<String, dynamic>{
      'id': gamePayload['id'],
      'title': gamePayload['title'],
      'gameKey': gamePayload['gameKey'],
      'platform': gamePayload['platform'],
      'dateAdded': gamePayload['dateAdded'],
      'updatedAt': gamePayload['updatedAt'],
      'notes': gamePayload['notes'],
      'isUsed': gamePayload['isUsed'],
      'coverImage': gamePayload['coverImage'],
      'hasDeadline': gamePayload['hasDeadline'],
      'deadlineDate': gamePayload['deadlineDate'],
      'isDlc': gamePayload['isDlc'],
      'steamAppId': gamePayload['steamAppId'],
      'developer': gamePayload['developer'],
      'reviewScore': gamePayload['reviewScore'],
      'reviewCount': gamePayload['reviewCount'],
      'tags': gamePayload['tags'] ?? const <dynamic>[],
    });

    return _hashNormalized(normalized);
  }

  static Future<String> _hashNormalized(Map<String, dynamic> normalized) async {
    final bytes = utf8.encode(jsonEncode(normalized));
    final hash = await _sha256.hash(bytes);
    final digest = hash.bytes;
    final buffer = StringBuffer();
    for (final b in digest) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static Map<String, dynamic> _normalizePayload(Map<String, dynamic> input) {
    final tagsRaw = (input['tags'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .map(
          (tag) => <String, dynamic>{
            'name': (tag['name'] as String?)?.trim() ?? '',
            'colorHex': (tag['colorHex'] as String?)?.trim() ?? '#0078d4',
            'isSteamTag': (tag['isSteamTag'] as bool?) ?? false,
          },
        )
        .toList(growable: false)
      ..sort((a, b) {
        final byName = (a['name'] as String).compareTo(b['name'] as String);
        if (byName != 0) return byName;
        final byColor =
            (a['colorHex'] as String).compareTo(b['colorHex'] as String);
        if (byColor != 0) return byColor;
        final aSteam = (a['isSteamTag'] as bool) ? 1 : 0;
        final bSteam = (b['isSteamTag'] as bool) ? 1 : 0;
        return aSteam.compareTo(bSteam);
      });

    return <String, dynamic>{
      'id': (input['id'] as num?)?.toInt(),
      'title': (input['title'] as String?) ?? '',
      'gameKey': (input['gameKey'] as String?) ?? '',
      'platform': (input['platform'] as String?) ?? 'Steam',
      'dateAdded': (input['dateAdded'] as String?) ?? '',
      'updatedAt': (input['updatedAt'] as String?) ?? '',
      'notes': (input['notes'] as String?) ?? '',
      'isUsed': (input['isUsed'] as bool?) ?? false,
      'coverImage': (input['coverImage'] as String?) ?? '',
      'hasDeadline': (input['hasDeadline'] as bool?) ?? false,
      'deadlineDate': (input['deadlineDate'] as String?),
      'isDlc': (input['isDlc'] as bool?) ?? false,
      'steamAppId': (input['steamAppId'] as String?) ?? '',
      'developer': (input['developer'] as String?) ?? '',
      'reviewScore': (input['reviewScore'] as int?) ?? 0,
      'reviewCount': (input['reviewCount'] as int?) ?? 0,
      'tags': tagsRaw,
    };
  }
}
