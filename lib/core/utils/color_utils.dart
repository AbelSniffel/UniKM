/// Shared color parsing and conversion utilities
/// 
/// Consolidates duplicate color logic from app_theme.dart, settings_page.dart,
/// and game.dart into a single source of truth.
library;

import 'package:flutter/material.dart';

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

/// Get a contrasting text color (black or white) for the given [color].
Color contrastColor(Color color) {
  return color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
}

/// Blend two colors together by [amount] (0.0 = color1, 1.0 = color2).
Color blendColors(Color color1, Color color2, double amount) {
  return Color.lerp(color1, color2, amount)!;
}
