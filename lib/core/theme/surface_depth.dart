import 'package:material_ui/material_ui.dart';

/// Shared, subtle raised lighting for groupboxes, title bars and tab buttons.
abstract final class SurfaceDepth {
  /// [surface] lit by [highlight]: the top of the [gradient], and the flat
  /// fill of group boxes' headers.
  static Color top(Color surface, {double highlight = 0.10}) =>
      Color.lerp(surface, Colors.white, highlight)!;

  static LinearGradient gradient(Color surface, {double highlight = 0.10}) =>
      LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          top(surface, highlight: highlight),
          surface,
          Color.lerp(surface, Colors.black, 0.10)!,
        ],
        stops: const [0, 0.45, 1],
      );

  static BoxShadow shadow({required bool isDark}) => BoxShadow(
    color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.10),
    blurRadius: 4,
    offset: const Offset(0, 2),
  );
}
