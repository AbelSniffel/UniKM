/// Title cleaning and similarity scoring utilities for Steam game matching
///
/// Extracted from steam_service.dart to allow independent testing and reuse.
library;

import 'dart:math' as math;

final _editionPatterns = [
  RegExp(
    r'\s*(GOTY|Game of the Year|Deluxe|Premium|Gold|Complete|Enhanced|Remastered?|Definitive|Ultimate|Special|Collectors?|Anniversary)\s*Edition',
    caseSensitive: false,
  ),
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

final _parentheticalPattern = RegExp(r'\s*\([^)]*\)\s*');
final _specialCharacterPattern = RegExp(r'[^a-zA-Z0-9\s]');
final _whitespacePattern = RegExp(r'\s+');
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
  clean = clean.replaceAll(_parentheticalPattern, ' ');

  // Remove special characters but keep alphanumeric, numbers and spaces
  clean = clean.replaceAll(_specialCharacterPattern, ' ');
  // Collapse multiple spaces
  clean = clean.replaceAll(_whitespacePattern, ' ').trim();
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

  double totalWeightA = 0.0;
  double totalWeightB = 0.0;
  final weightsA = <double>[];

  double tokenMatchWeight = 0.0;

  bool hasNumberA = false;
  bool hasNumberB = false;

  for (final t in tokensA) {
    double w = t.length.toDouble();
    if (_numberPattern.hasMatch(t)) {
      w += 3.0; // number tokens are very important
      hasNumberA = true;
    } else if (_romanPattern.hasMatch(t)) {
      w += 2.0; // roman numerals matter
    }
    weightsA.add(w);
    totalWeightA += w;
  }
  for (final t in tokensB) {
    double w = t.length.toDouble();
    if (_numberPattern.hasMatch(t)) {
      w += 3.0;
      hasNumberB = true;
    } else if (_romanPattern.hasMatch(t)) {
      w += 2.0;
    }
    totalWeightB += w;
  }

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
    final numsA = tokensA.where((t) => _numberPattern.hasMatch(t)).toSet();
    final numsB = tokensB.where((t) => _numberPattern.hasMatch(t)).toSet();
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
