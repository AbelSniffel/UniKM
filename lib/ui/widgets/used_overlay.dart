import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'game_card_painters.dart';

/// Shared Used tint and watermark for library cards and cover previews.
class UsedOverlay extends StatelessWidget {
  const UsedOverlay({
    super.key,
    required this.theme,
    required this.patternSize,
    this.tileToCanvas = false,
    this.gridView = false,
  });

  final AppThemeData theme;
  final Size patternSize;
  final bool tileToCanvas;
  final bool gridView;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: tileToCanvas
              ? theme.slimUsedOverlay
              : gridView
              ? theme.gridUsedOverlay
              : theme.usedOverlay,
        ),
        CustomPaint(
          painter: UsedPatternPainter(
            textColor: (tileToCanvas ? theme.textPrimary : Colors.white)
                .withValues(alpha: tileToCanvas ? 0.18 : 0.24),
            angleDegrees: -35,
            patternSize: patternSize,
            tileToCanvas: tileToCanvas,
          ),
          isComplex: true,
          willChange: false,
          child: const SizedBox.expand(),
        ),
      ],
    ),
  );
}
