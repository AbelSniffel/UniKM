/// Title cleaning and similarity scoring utilities for Steam game matching
///
/// Extracted from steam_service.dart to allow independent testing and reuse.
library;

import 'dart:math' as math;

/// A trailing "(kind) Edition" such as "GOTY Edition" or "Deluxe Edition".
final editionSuffixPattern = RegExp(
  r'\s*(GOTY|Game of the Year|Deluxe|Premium|Gold|Complete|Enhanced|Remastered?|Definitive|Ultimate|Special|Collectors?|Anniversary)\s*Edition',
  caseSensitive: false,
);

final _editionPatterns = [
  editionSuffixPattern,
  RegExp(r'\s*[-:]?\s*Deluxe\s*(Edition)?', caseSensitive: false),
  RegExp(
    r'\s*[-:]?\s*(GOTY|Game of the Year)\s*(Edition)?',
    caseSensitive: false,
  ),
  RegExp(r'\s*[-:]?\s*Definitive\s*(Edition)?', caseSensitive: false),
  RegExp(r'\s*[-:]?\s*Ultimate\s*(Edition)?', caseSensitive: false),
  RegExp(r'\s*[-:]?\s*Gold\s*(Edition)?', caseSensitive: false),
  RegExp(r'\s*[-:]?\s*Complete\s*(Edition)?', caseSensitive: false),
  RegExp(r'\s*[-:]?\s*Remaster(ed)?', caseSensitive: false),
];

final parentheticalPattern = RegExp(r'\s*\([^)]*\)\s*');
final _specialCharacterPattern = RegExp(r'[^a-zA-Z0-9\s]');
final whitespacePattern = RegExp(r'\s+');
final _numberPattern = RegExp(r'^\d+$');
final _romanPattern = RegExp(r'^[ivxlcdm]+$', caseSensitive: false);

/// Clean a title for searching: remove edition words, punctuation, collapse spaces
String cleanTitleForSearch(String title) {
  var clean = title.trim();

  // Remove common edition suffixes (case insensitive)
  for (final p in _editionPatterns) {
    clean = clean.replaceAll(p, '');
  }

  // Remove parenthetical content
  clean = clean.replaceAll(parentheticalPattern, ' ');

  // "Tales & Tactics" and "Tales And Tactics" are the same name.
  clean = clean.replaceAll('&', ' and ');

  // Remove special characters but keep alphanumeric, numbers and spaces
  clean = clean.replaceAll(_specialCharacterPattern, ' ');
  // Collapse multiple spaces
  clean = clean.replaceAll(whitespacePattern, ' ').trim();
  return clean;
}

/// Token-weighted similarity scoring combining token matches and Levenshtein ratio
double weightedSimilarity(String a, String b) {
  final sa = cleanTitleForSearch(a).toLowerCase();
  final sb = cleanTitleForSearch(b).toLowerCase();

  if (sa.isEmpty || sb.isEmpty) return 0.0;
  if (sa == sb) return 1.0;

  final tokensA = sa.split(' ');
  final tokensB = sb.split(' ');

  // Number tokens weigh most, then roman numerals, then by length.
  double weight(String t) =>
      t.length +
      (_numberPattern.hasMatch(t)
          ? 3.0
          : _romanPattern.hasMatch(t)
          ? 2.0
          : 0.0);
  final weightsA = tokensA.map(weight).toList();
  final totalWeightA = weightsA.fold(0.0, (sum, w) => sum + w);
  final totalWeightB = tokensB.map(weight).fold(0.0, (sum, w) => sum + w);
  final hasNumberA = tokensA.any(_numberPattern.hasMatch);
  final hasNumberB = tokensB.any(_numberPattern.hasMatch);

  double tokenMatchWeight = 0.0;

  // Exact token matches weighted by token weight
  for (var i = 0; i < tokensA.length; i++) {
    final ta = tokensA[i];
    for (var j = 0; j < tokensB.length; j++) {
      final tb = tokensB[j];
      if (ta == tb) {
        tokenMatchWeight += weightsA[i];
        break;
      }
      // Also consider prefix match for longer tokens (e.g., 'tropico' vs 'tropico3')
      if (ta.length > 3 && tb.contains(ta)) {
        tokenMatchWeight += weightsA[i] * 0.8;
        break;
      }
    }
  }

  final denom = math.max(totalWeightA, totalWeightB);
  final tokenScore = denom > 0
      ? (tokenMatchWeight / denom).clamp(0.0, 1.0)
      : 0.0;

  // Levenshtein-based ratio
  double lev = 0.0;
  {
    final longer = sa.length > sb.length ? sa : sb;
    final shorter = sa.length > sb.length ? sb : sa;
    if (longer.isNotEmpty) {
      if (longer.contains(shorter)) {
        lev = shorter.length / longer.length;
      } else {
        final distance = _levenshteinDistance(sa, sb);
        lev = (longer.length - distance) / longer.length;
      }
    }
    lev = lev.clamp(0.0, 1.0);
  }

  // Combine scores, favoring token matches
  var combined = (tokenScore * 0.7) + (lev * 0.3);

  // Boost if both have the same numeric token
  if (hasNumberA && hasNumberB) {
    final numsA = tokensA.where(_numberPattern.hasMatch).toSet();
    final numsB = tokensB.where(_numberPattern.hasMatch).toSet();
    if (numsA.intersection(numsB).isNotEmpty) {
      combined = math.min(1.0, combined + 0.12);
    }
  }

  return combined.clamp(0.0, 1.0);
}

/// Levenshtein distance between two strings.
int _levenshteinDistance(String a, String b) {
  // Keep only the preceding and current rows, with the shorter title as
  // columns: O(min(a.length, b.length)) space instead of a full matrix.
  final longer = a.length >= b.length ? a : b;
  final shorter = a.length >= b.length ? b : a;
  if (shorter.isEmpty) return longer.length;

  var previous = List<int>.generate(shorter.length + 1, (i) => i);
  var current = List<int>.filled(shorter.length + 1, 0);
  for (var i = 1; i <= longer.length; i++) {
    current[0] = i;
    for (var j = 1; j <= shorter.length; j++) {
      final cost = longer.codeUnitAt(i - 1) == shorter.codeUnitAt(j - 1)
          ? 0
          : 1;
      current[j] = math.min(
        math.min(previous[j] + 1, current[j - 1] + 1),
        previous[j - 1] + cost,
      );
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[shorter.length];
}
