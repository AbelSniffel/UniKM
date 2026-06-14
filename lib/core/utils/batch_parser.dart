import '../constants/platform_patterns.dart';

final List<_KeyPattern> _trailingKeyPatterns = [
  _KeyPattern(RegExp(r'https?://\S+$', caseSensitive: false)),
  _KeyPattern(
    RegExp(
      r'[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}$',
      caseSensitive: false,
    ),
  ),
  _KeyPattern(RegExp(r'[A-F0-9]{32}$', caseSensitive: false)),
  _KeyPattern(
    RegExp(
      r'[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$',
      caseSensitive: false,
    ),
  ),
  _KeyPattern(
    RegExp(
      r'[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$',
      caseSensitive: false,
    ),
  ),
  _KeyPattern(
    RegExp(r'[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$', caseSensitive: false),
  ),
  _KeyPattern(
    RegExp(
      r'[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$',
      caseSensitive: false,
    ),
  ),
  _KeyPattern(
    RegExp(r'[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$', caseSensitive: false),
  ),
  _KeyPattern(
    RegExp(r'[A-Z0-9]{8,16}$', caseSensitive: false),
    allowAdjacentTitleText: false,
  ),
];

final RegExp _titleTrailing = RegExp(r'[\s:;\-,|]+$');

class _KeyPattern {
  const _KeyPattern(this.pattern, {this.allowAdjacentTitleText = true});

  final RegExp pattern;
  final bool allowAdjacentTitleText;
}

class _ParsedLineParts {
  const _ParsedLineParts({required this.title, required this.key});

  final String title;
  final String key;
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
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    final parsed = _parseBatchLine(line);
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

_ParsedLineParts? _parseBatchLine(String line) {
  final explicit =
      _trySplitFixedSeparator(line) ?? _trySplitValidatedSeparator(line);
  if (explicit != null) {
    return explicit;
  }

  final trailing = _extractTrailingKey(line);
  if (trailing != null) {
    final title = _cleanTitle(line.substring(0, trailing.start));
    return _ParsedLineParts(
      title: title.isEmpty ? 'Unknown Game' : title,
      key: trailing.group(0)!.trim(),
    );
  }

  return null;
}

_ParsedLineParts? _trySplitFixedSeparator(String line) {
  _ParsedLineParts? fallback;

  for (final separator in ['\t', ' | ', '|']) {
    var index = line.lastIndexOf(separator);
    while (index > 0) {
      final title = _cleanTitle(line.substring(0, index));
      final key = line.substring(index + separator.length).trim();
      if (title.isEmpty || key.isEmpty) {
        index = line.lastIndexOf(separator, index - 1);
        continue;
      }

      final candidate = _ParsedLineParts(title: title, key: key);
      if (_looksLikeRecognizedKey(key)) {
        return candidate;
      }
      fallback ??= candidate;
      index = line.lastIndexOf(separator, index - 1);
    }
  }

  return fallback;
}

_ParsedLineParts? _trySplitValidatedSeparator(String line) {
  for (final separator in [':', ' - ']) {
    var index = line.lastIndexOf(separator);
    while (index > 0) {
      final title = _cleanTitle(line.substring(0, index));
      final key = line.substring(index + separator.length).trim();
      if (title.isNotEmpty && _looksLikeRecognizedKey(key)) {
        return _ParsedLineParts(title: title, key: key);
      }
      index = line.lastIndexOf(separator, index - 1);
    }
  }

  return null;
}

RegExpMatch? _extractTrailingKey(String line) {
  for (final keyPattern in _trailingKeyPatterns) {
    final match = keyPattern.pattern.firstMatch(line);
    if (match == null) continue;

    final start = match.start;
    if (start > 0 &&
        !keyPattern.allowAdjacentTitleText &&
        _isWordCharacter(line.codeUnitAt(start - 1))) {
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
