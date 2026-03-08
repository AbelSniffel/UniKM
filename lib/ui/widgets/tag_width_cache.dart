/// Static cache for tag text width measurements to avoid recreating TextPainter
/// objects on every layout pass. Uses remove + re-insert LRU semantics: Dart's
/// built-in Map is an insertion-ordered LinkedHashMap, so both cache-hit
/// promotion and LRU eviction are O(1) without any extra data structure.
library;

import 'package:flutter/material.dart';

class TagWidthCache {
  static const _maxCacheSize = 500;

  // Dart's Map literal creates a LinkedHashMap that preserves insertion order.
  // remove + re-insert on a cache hit bumps the entry to the MRU end in O(1),
  // replacing the previous O(n) _accessOrder List scan.
  static final _cache = <String, double>{};

  /// Generate cache key from text + style properties.
  static String _cacheKey(String text, TextStyle style, double textScale) {
    return '${text}_${style.fontSize}_${style.fontWeight?.value ?? 0}_$textScale';
  }

  /// Measure text width with O(1) LRU caching.
  static double measureTextWidth(
    String text,
    TextStyle style,
    TextDirection direction,
    TextScaler textScaler,
  ) {
    final scale = textScaler.scale(1.0);
    final key = _cacheKey(text, style, scale);

    final cached = _cache[key];
    if (cached != null) {
      // Promote to MRU end in O(1): remove then re-insert.
      _cache.remove(key);
      _cache[key] = cached;
      return cached;
    }

    // Evict the LRU entry (first key in LinkedHashMap = oldest) in O(1).
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }

    // Measure and insert at the MRU end.
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: direction,
      textScaler: textScaler,
    )..layout();

    final width = painter.width;
    _cache[key] = width;
    return width;
  }
}
