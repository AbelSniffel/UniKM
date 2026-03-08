/// Title cleaning and similarity scoring utilities for Steam game matching
///
/// Extracted from steam_service.dart to allow independent testing and reuse.
library;

import 'dart:math' as math;

/// Clean a title for searching: remove edition words, punctuation, collapse spaces
String cleanTitleForSearch(String title) {
  var clean = title.trim();

  // Remove common edition suffixes (case insensitive)
  final editionPatterns = [
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
  for (final p in editionPatterns) {
    clean = clean.replaceAll(p, '');
  }

  // Remove parenthetical content
  clean = clean.replaceAll(RegExp(r'\s*\([^)]*\)\s*'), ' ');

  // Remove special characters but keep alphanumeric, numbers and spaces
  clean = clean.replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ');
  // Collapse multiple spaces
  clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
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
  final weightsB = <double>[];

  double tokenMatchWeight = 0.0;

  bool hasNumberA = false;
  bool hasNumberB = false;

  final numRe = RegExp(r'^\d+$');
  final romanRe = RegExp(r'^[ivxlcdm]+$', caseSensitive: false);

  for (final t in tokensA) {
    double w = t.length.toDouble();
    if (numRe.hasMatch(t)) {
      w += 3.0; // number tokens are very important
      hasNumberA = true;
    } else if (romanRe.hasMatch(t)) {
      w += 2.0; // roman numerals matter
    }
    weightsA.add(w);
    totalWeightA += w;
  }
  for (final t in tokensB) {
    double w = t.length.toDouble();
    if (numRe.hasMatch(t)) {
      w += 3.0;
      hasNumberB = true;
    } else if (romanRe.hasMatch(t)) {
      w += 2.0;
    }
    weightsB.add(w);
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
    final numsA = tokensA.where((t) => numRe.hasMatch(t)).toSet();
    final numsB = tokensB.where((t) => numRe.hasMatch(t)).toSet();
    if (numsA.intersection(numsB).isNotEmpty) {
      combined = math.min(1.0, combined + 0.12);
    }
  }

  return combined.clamp(0.0, 1.0);
}

/// Levenshtein distance between two strings.
int _levenshteinDistance(String a, String b) {
  final m = a.length;
  final n = b.length;

  if (m == 0) return n;
  if (n == 0) return m;

  final d = List.generate(m + 1, (_) => List.filled(n + 1, 0));

  for (var i = 1; i <= m; i++) {
    d[i][0] = i;
  }
  for (var j = 1; j <= n; j++) {
    d[0][j] = j;
  }

  for (var i = 1; i <= m; i++) {
    for (var j = 1; j <= n; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      d[i][j] = [
        d[i - 1][j] + 1,
        d[i][j - 1] + 1,
        d[i - 1][j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
  }

  return d[m][n];
}
