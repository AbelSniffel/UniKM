library;

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../database/database.dart';

/// Portable content hashes: local row IDs, filesystem paths, tag ordering,
/// timezone formatting and sub-second precision are not shared state.
class SyncEntryFingerprint {
  SyncEntryFingerprint._();

  static final Sha256 _sha256 = Sha256();

  static Future<String> fromGameEntry(
    GameEntry game,
    List<TagEntry> tags,
  ) async {
    return fromPayload({
      'title': game.title,
      'gameKey': game.gameKey,
      'platform': game.platform,
      'dateAdded': game.dateAdded.toIso8601String(),
      'updatedAt': game.updatedAt.toIso8601String(),
      'notes': game.notes,
      'isUsed': game.isUsed,
      'coverDigest': await coverIdentity(game.coverImage),
      'hasDeadline': game.hasDeadline,
      'deadlineDate': game.deadlineDate?.toIso8601String(),
      'isDlc': game.isDlc,
      'steamAppId': game.steamAppId,
      'developer': game.developer,
      'reviewScore': game.reviewScore,
      'reviewCount': game.reviewCount,
      'tags': tags
          .map(
            (tag) => {
              'name': tag.name,
              'colorHex': tag.color,
              'isSteamTag': tag.isSteamTag,
            },
          )
          .toList(growable: false),
    });
  }

  static Future<String> coverIdentity(String rawPath) async {
    final raw = rawPath.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') ||
        raw.startsWith('https://') ||
        raw.startsWith('assets/')) {
      return raw;
    }
    try {
      final uri = Uri.tryParse(raw);
      final file = uri?.scheme == 'file' ? File.fromUri(uri!) : File(raw);
      if (!await file.exists()) return '';
      return 'sha256:${await hashBytes(await file.readAsBytes())}';
    } on FileSystemException {
      return '';
    }
  }

  static Future<String> fromPayload(Map<String, dynamic> input) async {
    var coverDigest = input['coverDigest'] as String?;
    final coverFile = input['coverImageFile'];
    if (coverDigest == null &&
        coverFile is Map &&
        coverFile['bytesBase64'] is String) {
      try {
        coverDigest =
            'sha256:${await hashBytes(base64Decode(coverFile['bytesBase64'] as String))}';
      } on FormatException {
        coverDigest = '';
      }
    }
    coverDigest ??= await coverIdentity(input['coverImage'] as String? ?? '');
    final tags =
        (input['tags'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map(
              (tag) => <String, dynamic>{
                'name': (tag['name'] as String? ?? '').trim(),
                'colorHex': (tag['colorHex'] as String? ?? '#0078d4')
                    .trim()
                    .toLowerCase(),
                'isSteamTag': tag['isSteamTag'] as bool? ?? false,
              },
            )
            .toList()
          ..sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
    return hashBytes(
      utf8.encode(
        jsonEncode({
          'title': input['title'] as String? ?? '',
          'gameKey': input['gameKey'] as String? ?? '',
          'platform': input['platform'] as String? ?? 'Steam',
          'dateAdded': _time(input['dateAdded']),
          'updatedAt': _time(input['updatedAt']),
          'notes': input['notes'] as String? ?? '',
          'isUsed': input['isUsed'] as bool? ?? false,
          'coverDigest': coverDigest,
          'hasDeadline': input['hasDeadline'] as bool? ?? false,
          'deadlineDate': _time(input['deadlineDate']),
          'isDlc': input['isDlc'] as bool? ?? false,
          'steamAppId': input['steamAppId'] as String? ?? '',
          'developer': input['developer'] as String? ?? '',
          'reviewScore': (input['reviewScore'] as num?)?.toInt() ?? 0,
          'reviewCount': (input['reviewCount'] as num?)?.toInt() ?? 0,
          'tags': tags,
        }),
      ),
    );
  }

  static int? _time(dynamic value) {
    final time = value is String ? DateTime.tryParse(value) : null;
    return time == null ? null : time.millisecondsSinceEpoch ~/ 1000;
  }

  static Future<String> hashBytes(List<int> bytes) async {
    final hash = await _sha256.hash(bytes);
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
