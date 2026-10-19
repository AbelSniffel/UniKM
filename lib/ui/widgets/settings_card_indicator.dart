import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Decorative card controls; the surrounding card owns taps and semantics.
class SettingsCardIndicator extends StatelessWidget {
  const SettingsCardIndicator({
    super.key,
    required this.theme,
    required this.value,
    required this.enabled,
  });

  static const double extent = 28;
  static const Size size = Size(32, extent);

  final AppThemeData theme;
  final bool value;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final lit = value && enabled;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 140);
    final offColor = Color.lerp(theme.background, theme.textSecondary, 0.25)!;
    return SizedBox.fromSize(
      size: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: lit ? 1 : 0),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (context, activation, _) {
          final color = Color.lerp(offColor, theme.accent, activation)!;
          return DecoratedBox(
            key: const ValueKey('settings-card-state-square'),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(theme.cornerRadius),
              ),
              boxShadow: activation > 0
                  ? [
                      BoxShadow(
                        color: theme.accent.withValues(
                          alpha: 0.62 * activation,
                        ),
                        blurRadius: 8,
                      ),
                      BoxShadow(
                        color: theme.accent.withValues(
                          alpha: 0.24 * activation,
                        ),
                        blurRadius: 14,
                      ),
                    ]
                  : const [],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(theme.cornerRadius),
              ),
              child: CustomPaint(
                painter: _RetroStatusPainter(
                  activation: activation,
                  cornerRadius: theme.cornerRadius,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Static display texture and soft inner shadows; only state changes animate.
class _RetroStatusPainter extends CustomPainter {
  const _RetroStatusPainter({
    required this.activation,
    required this.cornerRadius,
  });

  final double activation;
  final double cornerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final scanline = Paint()
      ..color = Colors.black.withValues(alpha: 0.06 + 0.045 * activation);
    for (var y = 2.0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 0.8), scanline);
    }
    final phosphor = Paint()
      ..color = Colors.white.withValues(alpha: 0.03 + 0.07 * activation);
    for (var y = 3.0; y < size.height; y += 4) {
      for (var x = 3.0; x < size.width; x += 4) {
        canvas.drawRect(Rect.fromLTWH(x, y, 0.7, 0.7), phosphor);
      }
    }
    final rect = Offset.zero & size;
    final outline = BorderRadius.only(
      topRight: Radius.circular(cornerRadius),
      bottomLeft: Radius.circular(cornerRadius),
    ).toRRect(rect).scaleRadii();
    final wall = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect.inflate(16))
      ..addRRect(outline.shift(const Offset(2, -2)));
    canvas.drawPath(
      wall,
      Paint()
        ..color = Colors.black.withValues(
          alpha: (0.22 + 0.16 * activation) * 0.95,
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
    );
    final r = outline.trRadiusX;
    if (r > 0) {
      final corner = Rect.fromLTWH(size.width - r, 0, r, r);
      canvas.saveLayer(corner, Paint());
      canvas.drawRect(
        corner,
        Paint()
          ..shader = SweepGradient(
            center: Alignment.bottomLeft,
            startAngle: math.pi * 1.5,
            endAngle: math.pi * 2,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: (0.09 + 0.19 * activation) * 0.95),
              Colors.transparent,
            ],
          ).createShader(corner),
      );
      canvas.drawRect(
        corner,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = const RadialGradient(
            center: Alignment.bottomLeft,
            radius: 2,
            colors: [Colors.transparent, Colors.white],
            stops: [0.5, 1],
          ).createShader(corner),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_RetroStatusPainter oldDelegate) =>
      oldDelegate.activation != activation ||
      oldDelegate.cornerRadius != cornerRadius;
}
