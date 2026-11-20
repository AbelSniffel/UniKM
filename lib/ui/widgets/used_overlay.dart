import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import 'game_card_painters.dart';

/// Shared Used tint and watermark for library cards and cover previews.
class const UsedOverlay({
  super.key,
  required final Size patternSize,
  final bool tileToCanvas = false,
  final bool gridView = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: tileToCanvas
              ? context.appTheme.slimUsedOverlay
              : gridView
              ? context.appTheme.gridUsedOverlay
              : context.appTheme.usedOverlay,
        ),
        CustomPaint(
          painter: UsedPatternPainter(
            textColor:
                (tileToCanvas ? context.appTheme.textPrimary : Colors.white)
                    .withValues(alpha: tileToCanvas ? 0.18 : 0.24),
            angleDegrees: -35,
            patternSize: patternSize,
            tileToCanvas: tileToCanvas,
            devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
          ),
          isComplex: true,
          child: const SizedBox.expand(),
        ),
      ],
    ),
  );
}
