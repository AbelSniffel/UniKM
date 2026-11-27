/// Shared color parsing and conversion utilities.
library;

import 'package:material_ui/material_ui.dart';

/// Parse a hex color string (e.g. '#FF5733' or 'FF5733') into a [Color].
/// Returns [fallback] if parsing fails.
Color parseHexColor(String hex, {Color fallback = const Color(0xFF0078D4)}) {
  try {
    final clean = hex.replaceFirst('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  } catch (_) {
    return fallback;
  }
}

/// Convert a [Color] to a hex string like '#RRGGBB'.
String colorToHex(Color color) {
  final argb = color.toARGB32();
  return '#${argb.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}

/// Text for a [color] fill: white, unless white falls below WCAG's 3:1
/// contrast (the minimum for bold text and icons) on it, then black.
///
/// White's contrast is 1.05 / (luminance + 0.05), so 3:1 at a luminance of
/// 0.3: saturated accents keep white, pale ones such as lime get black.
Color contrastColor(Color color) =>
    color.computeLuminance() > 0.3 ? Colors.black : Colors.white;

/// Blend two colors together by [amount] (0.0 = color1, 1.0 = color2).
Color blendColors(Color color1, Color color2, double amount) =>
    Color.lerp(color1, color2, amount)!;
