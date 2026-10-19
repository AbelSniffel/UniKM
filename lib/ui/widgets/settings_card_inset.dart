import 'package:flutter/material.dart';

/// Recessed lighting for active settings cards, with an optional raised rest
/// state for toggle buttons. All shading stays inside the
/// live card outline, so layout, hit testing, and child ink remain unchanged.
class SettingsCardInset extends StatelessWidget {
  const SettingsCardInset({
    super.key,
    required this.active,
    required this.borderRadius,
    required this.surfaceColor,
    required this.child,
    this.raisedWhenInactive = false,
    this.overlay,
    this.shadeOverlay = true,
  });

  final bool active;
  final double borderRadius;
  final Color surfaceColor;
  final bool raisedWhenInactive;
  final Widget child;

  /// Decorative overlay, sharing the card bounds and ignoring pointer events.
  final Widget? overlay;

  /// Lit indicators can sit above the depth lighting instead of being dimmed.
  final bool shadeOverlay;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(
      end: active
          ? 1
          : raisedWhenInactive
          ? -1
          : 0,
    ),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 140),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (context, depth, child) {
      final painter = depth != 0
          ? _SettingsCardInsetPainter(
              radius: borderRadius,
              depth: depth,
              surfaceColor: surfaceColor,
            )
          : null;
      if (overlay == null) {
        return CustomPaint(foregroundPainter: painter, child: child);
      }
      return Stack(
        children: [
          child!,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: shadeOverlay ? null : painter,
                foregroundPainter: shadeOverlay ? painter : null,
                child: overlay,
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _SettingsCardInsetPainter extends CustomPainter {
  const _SettingsCardInsetPainter({
    required this.radius,
    required this.depth,
    required this.surfaceColor,
  });

  final double radius;
  final double depth;
  final Color surfaceColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final outline = RRect.fromRectAndRadius(
      rect,
      Radius.circular(radius),
    ).scaleRadii();
    canvas.save();
    canvas.clipRRect(outline);

    final hsl = HSLColor.fromColor(surfaceColor);
    final nearBlack =
        (1 - hsl.saturation) * ((0.10 - hsl.lightness) / 0.10).clamp(0.0, 1.0);
    final brightness = surfaceColor.computeLuminance();
    final shadow = Color.lerp(surfaceColor, Colors.black, 0.9)!;
    final light = Color.lerp(surfaceColor, Colors.white, 0.72)!;
    final recessed = depth > 0;
    final strength = depth.abs();
    final shadowStrength = strength * 0.95;

    // Keep colored surfaces close to their own tone. Only nearly black,
    // neutral backgrounds need a small lift to make the inner shadow visible.
    if (recessed) {
      canvas.drawRRect(
        outline,
        Paint()
          ..color = Colors.black.withValues(
            alpha: 0.045 * (1 - nearBlack) * strength,
          ),
      );
      if (nearBlack > 0) {
        canvas.drawRRect(
          outline,
          Paint()
            ..color = Colors.white.withValues(
              alpha: 0.022 * nearBlack * strength,
            ),
        );
      }
    } else {
      canvas.drawRRect(
        outline,
        Paint()
          ..color = light.withValues(
            alpha: (0.028 + 0.012 * nearBlack) * strength,
          ),
      );
    }

    // The bottom remains a hinge. The upper walls catch shadows when pressed
    // inward, or light when raised; both taper equally down the sides.
    canvas.saveLayer(rect, Paint());
    _paintRecessWall(
      canvas,
      outline,
      reach: 3,
      sideInset: 2.5,
      color: recessed
          ? shadow.withValues(
              alpha: (0.16 - 0.07 * brightness) * shadowStrength,
            )
          : light.withValues(alpha: (0.015 + 0.01 * brightness) * strength),
      sigma: 5.5,
    );
    _paintRecessWall(
      canvas,
      outline,
      reach: 5,
      sideInset: 2,
      color: recessed
          ? shadow.withValues(
              alpha: (0.62 - 0.32 * brightness) * shadowStrength,
            )
          : light.withValues(
              alpha: (0.07 + 0.12 * brightness + 0.01 * nearBlack) * strength,
            ),
      sigma: 3.5,
    );
    // Fade after blurring so the shadow cannot spill onto the bottom lip.
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            Colors.white,
            Colors.transparent,
            Colors.transparent,
          ],
          stops: [0, 0.12, 0.8, 1],
        ).createShader(rect),
    );
    canvas.restore();
    _paintBottomLip(
      canvas,
      rect,
      reach: 1.5,
      color: recessed
          ? light.withValues(
              alpha: (0.12 + 0.08 * brightness + 0.02 * nearBlack) * strength,
            )
          : shadow.withValues(
              alpha: (0.42 - 0.18 * brightness) * shadowStrength,
            ),
      sigma: 2,
    );
    canvas.restore();
  }

  void _paintRecessWall(
    Canvas canvas,
    RRect outline, {
    required double reach,
    required double sideInset,
    required Color color,
    required double sigma,
  }) {
    final wall = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(outline.outerRect.inflate(24))
      ..addRRect(outline.deflate(sideInset).shift(Offset(0, reach)));
    canvas.drawPath(
      wall,
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
    );
  }

  void _paintBottomLip(
    Canvas canvas,
    Rect rect, {
    required double reach,
    required Color color,
    required double sigma,
  }) {
    // The bottom lip anchors the pivot with light when recessed, shade when raised.
    final wall = rect.inflate(24);
    canvas.drawRect(
      Rect.fromLTRB(wall.left, rect.bottom - reach, wall.right, wall.bottom),
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
    );
  }

  @override
  bool shouldRepaint(_SettingsCardInsetPainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.depth != depth ||
      oldDelegate.surfaceColor != surfaceColor;
}
