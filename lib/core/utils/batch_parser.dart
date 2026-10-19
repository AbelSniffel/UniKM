import '../constants/platform_patterns.dart';

final RegExp _titleTrailing = RegExp(r'[\s:;\-,|]+$');

/// Parsed values and source offsets shared by batch import and its inline editor.
class BatchLineParts {
  const BatchLineParts({
    required this.title,
    required this.key,
    required this.titleEnd,
    required this.keyStart,
  });

  final String title;
  final String key;
  final int titleEnd;
  final int keyStart;
}

BatchLineParts? parseBatchLine(String raw) {
  final line = raw.trim();
  if (line.isEmpty || line.startsWith('#')) return null;
  final parts = _parseBatchLine(line);
  if (parts == null) return null;
  final leading = raw.length - raw.trimLeft().length;
  return BatchLineParts(
    title: parts.title,
    key: parts.key,
    titleEnd: parts.titleEnd + leading,
    keyStart: parts.keyStart + leading,
  );
}

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

  for (final raw in text.split('\n')) {
    final parsed = parseBatchLine(raw);
    if (parsed != null && parsed.key.isNotEmpty) {
      final detected = PlatformDetector.detectPlatform(parsed.key);
      final platform = detected != GamePlatform.other
          ? detected.displayName
          : defaultPlatform;
      games.add(
        ParsedBatchEntry(
          title: parsed.title,
          key: parsed.key,
          platform: platform,
        ),
      );
    }
  }

  return games;
}

BatchLineParts? _parseBatchLine(String line) {
  final explicit =
      _trySplitFixedSeparator(line) ?? _trySplitValidatedSeparator(line);
  if (explicit != null) {
    return explicit;
  }

  final trailing = _extractTrailingKey(line);
  if (trailing != null) {
    final title = _cleanTitle(line.substring(0, trailing.start));
    return BatchLineParts(
      title: title.isEmpty ? 'Unknown Game' : title,
      key: trailing.group(0)!.trim(),
      titleEnd: title.length,
      keyStart: trailing.start,
    );
  }

  return null;
}

BatchLineParts? _trySplitFixedSeparator(String line) {
  BatchLineParts? fallback;

  for (final separator in ['\t', ' | ', '|']) {
    var index = line.lastIndexOf(separator);
    while (index > 0) {
      final title = _cleanTitle(line.substring(0, index));
      final key = line.substring(index + separator.length).trim();
      if (title.isEmpty || key.isEmpty) {
        index = line.lastIndexOf(separator, index - 1);
        continue;
      }

      final candidate = BatchLineParts(
        title: title,
        key: key,
        titleEnd: title.length,
        keyStart: line.length - key.length,
      );
      if (_looksLikeRecognizedKey(key)) {
        return candidate;
      }
      fallback ??= candidate;
      index = line.lastIndexOf(separator, index - 1);
    }
  }

  return fallback;
}

BatchLineParts? _trySplitValidatedSeparator(String line) {
  for (final separator in [':', ' - ']) {
    var index = line.lastIndexOf(separator);
    while (index > 0) {
      final title = _cleanTitle(line.substring(0, index));
      final key = line.substring(index + separator.length).trim();
      if (title.isNotEmpty && _looksLikeRecognizedKey(key)) {
        return BatchLineParts(
          title: title,
          key: key,
          titleEnd: title.length,
          keyStart: line.length - key.length,
        );
      }
      index = line.lastIndexOf(separator, index - 1);
    }
  }

  return null;
}

RegExpMatch? _extractTrailingKey(String line) {
  for (final pattern in PlatformDetector.trailingKeyPatterns) {
    final match = pattern.firstMatch(line);
    if (match == null) continue;

    final start = match.start;
    // A matching suffix inside a longer token is not a complete game key.
    if (start > 0 &&
        (_isWordCharacter(line.codeUnitAt(start - 1)) ||
            line.codeUnitAt(start - 1) == 45)) {
      continue;
    }

    return match;
  }

  return null;
}

bool _looksLikeRecognizedKey(String value) {
  if (value.isEmpty) return false;
  return _extractTrailingKey(value)?.start == 0;
}

String _cleanTitle(String value) {
  return value.trim().replaceAll(_titleTrailing, '').trim();
}

bool _isWordCharacter(int codeUnit) {
  return (codeUnit >= 48 && codeUnit <= 57) ||
      (codeUnit >= 65 && codeUnit <= 90) ||
      (codeUnit >= 97 && codeUnit <= 122);
}
