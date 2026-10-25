library;

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';

import '../database/database.dart';

/// A cover digest remembered for a file whose size and modification time
/// have not changed since it was hashed.
typedef CoverStamp = ({int size, int modifiedMillis, String digest});

/// Portable content hashes: local row IDs, filesystem paths, tag ordering,
/// timezone formatting and sub-second precision are not shared state.
///
/// Everything here is synchronous so it can run inside a background isolate.
class SyncEntryFingerprint {
  SyncEntryFingerprint._();

  static const DartSha256 _sha256 = DartSha256();

  /// Cover digests for this isolate, keyed by the raw cover path. Many games
  /// share one cover, and the files rarely change, so hashing each file once
  /// keeps database comparison from re-reading every image on each pass.
  static final Map<String, CoverStamp> coverCache = {};

  static String fromGameEntry(
    GameEntry game,
    List<TagEntry> tags, {
    String? coverDigest,
  }) => fromPayload({
    'title': game.title,
    'gameKey': game.gameKey,
    'platform': game.platform,
    'dateAdded': game.dateAdded.toIso8601String(),
    'updatedAt': game.updatedAt.toIso8601String(),
    'notes': game.notes,
    'isUsed': game.isUsed,
    'coverDigest': coverDigest ?? coverIdentity(game.coverImage),
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

  /// Remote and bundled covers are identified by their address, not bytes.
  static bool isAddressedCover(String raw) =>
      raw.startsWith('http://') ||
      raw.startsWith('https://') ||
      raw.startsWith('assets/');

  /// The local file for a stored cover path or `file:` URI.
  static File coverFile(String raw) {
    final uri = Uri.tryParse(raw);
    return uri != null && uri.scheme.toLowerCase() == 'file'
        ? File.fromUri(uri)
        : File(raw);
  }

  /// Content-addressed cover identity shared on the wire and on disk.
  static String coverDigest(List<int> bytes) => 'sha256:${hashBytes(bytes)}';

  static String coverIdentity(String rawPath) {
    final raw = rawPath.trim();
    if (raw.isEmpty) return '';
    if (isAddressedCover(raw)) return raw;
    try {
      final file = coverFile(raw);
      final stat = file.statSync();
      if (stat.type != FileSystemEntityType.file) return '';
      final modified = stat.modified.millisecondsSinceEpoch;
      final cached = coverCache[raw];
      if (cached != null &&
          cached.size == stat.size &&
          cached.modifiedMillis == modified) {
        return cached.digest;
      }
      final digest = coverDigest(file.readAsBytesSync());
      coverCache[raw] = (
        size: stat.size,
        modifiedMillis: modified,
        digest: digest,
      );
      return digest;
    } on FileSystemException {
      return '';
    }
  }

  static String fromPayload(Map<String, dynamic> input) {
    final coverDigest =
        input['coverDigest'] as String? ??
        coverIdentity(input['coverImage'] as String? ?? '');
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
            // Preserve the wire ordering while encoding each tag only once.
            .map((tag) => (encoded: jsonEncode(tag), value: tag))
            .toList()
          ..sort((a, b) => a.encoded.compareTo(b.encoded));
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
          'tags': tags.map((tag) => tag.value).toList(growable: false),
        }),
      ),
    );
  }

  static int? _time(dynamic value) {
    final time = value is String ? DateTime.tryParse(value) : null;
    return time == null ? null : time.millisecondsSinceEpoch ~/ 1000;
  }

  static String hashBytes(List<int> bytes) {
    final digest = _sha256.hashSync(bytes).bytes;
    final buffer = StringBuffer();
    for (final b in digest) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
