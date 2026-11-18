/// How a list card's tags fit its tag row.
library;

import 'package:material_ui/material_ui.dart';

import 'tag_width_cache.dart';

/// A tag badge's padding, and the gap between the tag and count badges.
const kTagBadgePadding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);
const kTagBadgeGap = 4.0;

/// The most of [names] that fit in [width] as one badge, joined by dots, and
/// a `+N` badge counting the rest, measured in [style].
({String label, String count}) fitTagLabels(
  List<String> names,
  double width,
  TextStyle style,
  TextScaler scaler,
  TextDirection direction,
  Locale? locale,
) {
  double measure(String text) => TagWidthCache.measureTextWidth(
    text,
    style,
    direction,
    scaler,
    locale: locale,
  );
  final separatorWidth = measure(' · ');
  double countWidth(int count) =>
      measure('+$count') + kTagBadgePadding.horizontal;
  var bestCount = 0;
  var textWidth = 0.0;
  for (var i = 0; i < names.length; i++) {
    textWidth += measure(names[i]) + (i == 0 ? 0 : separatorWidth);
    final labelWidth = textWidth + kTagBadgePadding.horizontal;
    // Once the prefix alone exceeds the width, no later prefix can fit.
    // Do not stop just because the count badge doesn't fit: a final small
    // tag may fit while removing the count badge altogether.
    if (labelWidth > width) break;
    final remaining = names.length - i - 1;
    if (labelWidth +
            (remaining == 0 ? 0 : kTagBadgeGap + countWidth(remaining)) <=
        width) {
      bestCount = i + 1;
    }
  }
  return (
    label: names.take(bestCount).join(' · '),
    count: bestCount == names.length ? '' : '+${names.length - bestCount}',
  );
}
