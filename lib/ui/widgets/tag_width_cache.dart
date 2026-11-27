/// Static cache for tag text width measurements to avoid recreating TextPainter
/// objects on every layout pass. Dart's Map keeps insertion order, so moving
/// a hit to the end and evicting the first key make it an O(1) LRU.
library;

import 'package:material_ui/material_ui.dart';

class TagWidthCache {
  static const _maxCacheSize = 500;

  static final _cache =
      <(String, TextStyle, TextDirection, TextScaler, Locale?), double>{};

  /// [text]'s width on one line.
  static double measureTextWidth(
    String text,
    TextStyle style,
    TextDirection direction,
    TextScaler textScaler, {
    Locale? locale,
  }) {
    final key = (text, style, direction, textScaler, locale);

    final cached = _cache.remove(key);
    if (cached != null) return _cache[key] = cached;
    if (_cache.length >= _maxCacheSize) _cache.remove(_cache.keys.first);
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: direction,
      textScaler: textScaler,
      locale: locale,
    )..layout();

    final width = painter.width;
    painter.dispose();
    _cache[key] = width;
    return width;
  }
}
