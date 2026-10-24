import 'dart:math' as math;

import '../../core/constants/app_constants.dart';

/// Settings cards share one width across rows, including the last partial row.
/// When two cards cannot sit side by side, each card fills its row instead of
/// leaving empty space; otherwise cards share each row up to a width cap.
double settingsCardWidth({
  required double availableWidth,
  required int cardCount,
  double minimumCardWidth = kInteractionCardMinWidth,
  double maximumCardWidth = kInteractionCardMaxWidth,
  double spacing = 8,
}) {
  final fitting = ((availableWidth + spacing) / (minimumCardWidth + spacing))
      .floor();
  if (fitting < 2 || availableWidth <= kSettingsCompactLayoutBreakpoint) {
    return availableWidth;
  }
  final columns = math.max(1, math.min(cardCount, fitting));
  return math.min(
    maximumCardWidth,
    (availableWidth - spacing * (columns - 1)) / columns,
  );
}
