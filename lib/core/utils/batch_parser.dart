import '../constants/platform_patterns.dart';

final RegExp _titleTrailing = RegExp(r'[\s:;\-,|]+$');

/// Parsed values and source offsets shared by batch import and its inline editor.
class BatchLineParts {
  const BatchLineParts({
    required this.title,
    required this.key,
    required this.titleEnd,
    required this.keyStart,
    this.keyEnd,
    this.dateStart,
    this.deadline,
  });

  final String title;
  final String key;
  final int titleEnd;
  final int keyStart;

  /// Where the key ends when a deadline date follows it; otherwise the key
  /// runs to the end of the line.
  final int? keyEnd;

  /// Where the trailing deadline date starts, when the line has one.
  final int? dateStart;

  /// The deadline written after the key, as a local date.
  final DateTime? deadline;
}

BatchLineParts? parseBatchLine(String raw) {
  final line = raw.trim();
  if (line.isEmpty || line.startsWith('#')) return null;
  final leading = raw.length - raw.trimLeft().length;
  // A trailing date is a deadline only when the text before it still holds
  // a title and key; otherwise it stays part of the line as before.
  if (_trailingDate(line) case (:final start, :final dateStart, :final date)) {
    final rest = line.substring(0, start);
    final parts = _parseBatchLine(rest);
    if (parts != null && parts.key.isNotEmpty) {
      return BatchLineParts(
        title: parts.title,
        key: parts.key,
        titleEnd: parts.titleEnd + leading,
        keyStart: parts.keyStart + leading,
        keyEnd: rest.length + leading,
        dateStart: dateStart + leading,
        deadline: date,
      );
    }
  }
  final parts = _parseBatchLine(line);
  if (parts == null) return null;
  return BatchLineParts(
    title: parts.title,
    key: parts.key,
    titleEnd: parts.titleEnd + leading,
    keyStart: parts.keyStart + leading,
  );
}

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

const _month =
    r'(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|'
    r'aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?';
const _day = r'(\d{1,2})(?:st|nd|rd|th)?';

/// A date ending the line: "May 6, 2027", "6 May 2027" or "2027-05-06",
/// optionally in parentheses. It must be set apart by a space (around an
/// optional "-", "|" or ","), so a key that merely contains a date stays whole.
final _trailingDatePattern = RegExp(
  r'(?:\s+[-|,]?\s*|[-|,]\s+|(?<=\s)(?=\())\(?'
  '(?:$_month\\s+$_day,?\\s+(\\d{4})|$_day\\s+$_month,?\\s+(\\d{4})|'
  r'(\d{4})[-/.](\d{1,2})[-/.](\d{1,2}))\)?\s*$',
  caseSensitive: false,
);

/// Where a trailing date's separator and the date itself start, and the
/// date, when [line] ends with a real calendar date.
({int start, int dateStart, DateTime date})? _trailingDate(String line) {
  final match = _trailingDatePattern.firstMatch(line);
  if (match == null || match.start == 0) return null;
  int? number(int group) => int.tryParse(match.group(group) ?? '');
  int? month(int group) =>
      _months[match.group(group)?.substring(0, 3).toLowerCase()];
  final (year, monthValue, day) = match.group(3) != null
      ? (number(3), month(1), number(2))
      : match.group(6) != null
      ? (number(6), month(5), number(4))
      : (number(7), number(8), number(9));
  if (year == null || monthValue == null || day == null) return null;
  final date = DateTime(year, monthValue, day);
  // Reject dates such as February 30 that DateTime would roll over.
  if (date.month != monthValue || date.day != day) return null;
  final text = match.group(0)!;
  final dateOffset = text.indexOf(RegExp(r'[\p{L}\d(]', unicode: true));
  return (start: match.start, dateStart: match.start + dateOffset, date: date);
}

/// Result from parsing a batch line
class ParsedBatchEntry {
  ParsedBatchEntry({
    required this.title,
    required this.key,
    required this.platform,
    this.deadline,
  });

  final String title;
  final String key;
  final String platform;

  /// A deadline written on the line itself; it takes precedence over the
  /// batch's shared deadline for this entry only.
  final DateTime? deadline;

  @override
  String toString() =>
      'ParsedBatchEntry(title: $title, key: $key, platform: $platform, '
      'deadline: $deadline)';
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
          deadline: parsed.deadline,
        ),
      );
    }
  }

  return games;
}

BatchLineParts? _parseBatchLine(String line) {
  final explicit =
      _trySplitFixedSeparator(line) ?? _trySplitValidatedSeparator(line);
  if (explicit != null) return explicit;

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
      if (_looksLikeRecognizedKey(key)) return candidate;
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

String _cleanTitle(String value) =>
    value.trim().replaceAll(_titleTrailing, '').trim();

bool _isWordCharacter(int codeUnit) =>
    (codeUnit >= 48 && codeUnit <= 57) ||
    (codeUnit >= 65 && codeUnit <= 90) ||
    (codeUnit >= 97 && codeUnit <= 122);
