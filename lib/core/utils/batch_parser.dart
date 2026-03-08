import '../constants/platform_patterns.dart';

/// Result from parsing a batch line
class ParsedBatchEntry {
  ParsedBatchEntry({
    required this.title,
    required this.key,
    required this.platform,
  });

  final String title;
  final String key;
  final String platform;

  @override
  String toString() =>
      'ParsedBatchEntry(title: $title, key: $key, platform: $platform)';
}

/// Parse multiline batch text into title/key/platform
List<ParsedBatchEntry> parseBatchText(
  String text, {
  String defaultPlatform = 'Steam',
}) {
  final games = <ParsedBatchEntry>[];
  if (text.isEmpty) return games;

  final gameKeyPattern = RegExp(
    r'[A-Za-z0-9]{4,6}(?:-[A-Za-z0-9]{4,6}){1,5}',
    caseSensitive: false,
  );
  final titleTrailing = RegExp(r'[\s:;\-,|]+$');

  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    String? title;
    String? key;

    final keyMatch = gameKeyPattern.firstMatch(line);
    if (keyMatch != null) {
      key = keyMatch.group(0)!.trim();
      final titlePart = line.substring(0, keyMatch.start).trim();
      title = titlePart.replaceAll(titleTrailing, '').trim();
      if (title.isEmpty) title = 'Unknown Game';
    } else if (line.contains('\t')) {
      final parts = line.split('\t');
      if (parts.length >= 2) {
        title = parts[0].trim();
        key = parts.sublist(1).join('\t').trim();
      }
    } else if (line.contains(' | ')) {
      final parts = line.split(' | ');
      if (parts.length >= 2) {
        title = parts[0].trim();
        key = parts.sublist(1).join(' | ').trim();
      }
    } else {
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        key = parts.last.trim();
        title = parts.sublist(0, parts.length - 1).join(' ').trim();
        title = title.replaceAll(titleTrailing, '').trim();
      }
    }

    if (key != null && key.isNotEmpty) {
      final detected = PlatformDetector.detectPlatform(key);
      final platform = detected != GamePlatform.other
          ? detected.displayName
          : defaultPlatform;
      games.add(
        ParsedBatchEntry(
          title: title ?? 'Unknown Game',
          key: key,
          platform: platform,
        ),
      );
    }
  }

  return games;
}
