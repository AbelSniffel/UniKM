import 'dart:math' as math;

import '../../core/constants/app_constants.dart';

/// Settings cards share one width across rows, including the last partial row.
/// Compact layouts use the available width; desktop cards have a width cap.
double settingsCardWidth({
  required double availableWidth,
  required int cardCount,
  double minimumCardWidth = kInteractionCardMinWidth,
  double maximumCardWidth = kInteractionCardMaxWidth,
  double spacing = 8,
}) {
  final columns = math.max(
    1,
    math.min(
      cardCount,
      ((availableWidth + spacing) / (minimumCardWidth + spacing)).floor(),
    ),
  );
  return availableWidth <= kSettingsCompactLayoutBreakpoint
      ? availableWidth
      : math.min(
          maximumCardWidth,
          (availableWidth - spacing * (columns - 1)) / columns,
        );
}
