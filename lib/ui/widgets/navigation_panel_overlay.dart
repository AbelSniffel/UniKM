library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';

class NavigationPanelOverlayPaint extends StatelessWidget {
  const NavigationPanelOverlayPaint({
    super.key,
    required this.theme,
    this.preview = false,
    this.isHorizontal = false,
    required this.child,
  });

  final AppThemeData theme;
  final bool preview;
  final bool isHorizontal;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (theme.navPanelOverlayStyle == NavPanelOverlayStyle.none) {
      return child;
    }

    return CustomPaint(
      painter: _NavigationPanelOverlayPainter(
        theme: theme,
        preview: preview,
        isHorizontal: isHorizontal,
      ),
      child: child,
    );
  }
}

class _NavigationPanelOverlayPainter extends CustomPainter {
  const _NavigationPanelOverlayPainter({
    required this.theme,
    required this.preview,
    this.isHorizontal = false,
  });

  final AppThemeData theme;
  final bool preview;
  final bool isHorizontal;

  /// Fixed stripe angle from vertical (30°). A fixed angle means the visual
  /// slant never changes as the navigation panel is resized or repositioned.
  static const double _kAngle = 30.0 * math.pi / 180.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    switch (theme.navPanelOverlayStyle) {
      case NavPanelOverlayStyle.none:
        return;
      case NavPanelOverlayStyle.diagonalStripes:
        _paintStripes(canvas, size);
      case NavPanelOverlayStyle.crosshatch:
        _paintStripes(canvas, size, alphaScale: 0.7);
        _paintStripes(canvas, size, clockwise: false, alphaScale: 0.7);
      case NavPanelOverlayStyle.gradient:
        _paintLinearGradient(canvas, size);
      case NavPanelOverlayStyle.hexPattern:
        _paintHexPattern(canvas, size);
      case NavPanelOverlayStyle.ripple:
        _paintRipple(canvas, size);
    }
  }

  // ── diagonal stripes at a fixed visual angle ──────────────────────────────

  void _paintStripes(
    Canvas canvas,
    Size size, {
    bool clockwise = true,
    double alphaScale = 1.0,
  }) {
    final angle = clockwise ? _kAngle : -_kAngle;
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Extent large enough so rotated stripes fill the entire panel.
    final halfDiag = math.sqrt(cx * cx + cy * cy) + 10.0;

    const stripeW = 36.0;
    const gapW = 20.0;
    const period = stripeW + gapW;

    final colors = preview
        ? <Color>[
            theme.accent.withValues(alpha: 0.24 * alphaScale),
            theme.secondary.withValues(alpha: 0.16 * alphaScale),
          ]
        : <Color>[
            theme.accent.withValues(alpha: 0.14 * alphaScale),
            theme.secondary.withValues(alpha: 0.09 * alphaScale),
          ];

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    canvas.translate(-cx, -cy);

    var x = -halfDiag;
    var i = 0;
    while (x < size.width + halfDiag) {
      canvas.drawRect(
        Rect.fromLTWH(x, -halfDiag, stripeW, size.height + halfDiag * 2),
        Paint()
          ..color = colors[i % colors.length]
          ..style = PaintingStyle.fill,
      );
      x += period;
      i++;
    }

    canvas.restore();
  }

  // ── linear gradient (axis-aligned to the panel orientation) ────────────────

  void _paintLinearGradient(Canvas canvas, Size size) {
    // Vertical panels get a top-to-bottom gradient; horizontal panels get
    // a left-to-right gradient, so the gradient always runs perpendicular
    // to the panel's long axis.
    final begin = isHorizontal ? Alignment.centerLeft : Alignment.topCenter;
    final end   = isHorizontal ? Alignment.centerRight : Alignment.bottomCenter;

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: begin,
          end: end,
          colors: [
            theme.accent.withValues(alpha: preview ? 0.36 : 0.22),
            theme.secondary.withValues(alpha: preview ? 0.26 : 0.16),
          ],
        ).createShader(Offset.zero & size),
    );
  }

  // ── hexagonal grid ────────────────────────────────────────────────────────

  /// Draws a pointy-top regular hexagon centred at [center] with circumradius
  /// [r], filling it with [fillPaint].
  void _drawHex(
    Canvas canvas,
    Offset center,
    double r,
    Paint fillPaint,
  ) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      // Pointy-top: vertex angles start at −90° and step by 60°
      final angle = -math.pi / 2 + i * (math.pi / 3);
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, fillPaint);
  }

  void _paintHexPattern(Canvas canvas, Size size) {
    // Fixed physical circumradius keeps the cell size consistent at any
    // panel dimension.
    const r = 12.0;
    const spacingScale = 1.2;
    final w = math.sqrt(3) * r * spacingScale;
    final rowStep = r * 1.5 * spacingScale;

    // Three fill colours that cycle diagonally across the grid.
    final fills = [
      Paint()
        ..color = theme.accent.withValues(alpha: preview ? 0.24 : 0.14)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
      Paint()
        ..color = theme.secondary.withValues(alpha: preview ? 0.18 : 0.10)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
      Paint()
        ..color = theme.accent.withValues(alpha: preview ? 0.10 : 0.05)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    ];

    final rowStart = -1;
    final rowEnd = (size.height / rowStep).ceil() + 1;
    final colStart = -1;
    final colEnd = (size.width / w).ceil() + 1;

    for (var row = rowStart; row <= rowEnd; row++) {
      for (var col = colStart; col <= colEnd; col++) {
        final cx = col * w + (row.isOdd ? w / 2 : 0);
        final cy = row * rowStep;
        // Diagonal stripe coloring: (row + col * 2) % 3 gives a clean
        // three-way split that never repeats on adjacent cells.
        final fillPaint = fills[(row + col * 2).abs() % 3];
        _drawHex(
          canvas,
          Offset(cx, cy),
          r,
          fillPaint,
        );
      }
    }
  }

  // ── ripple ────────────────────────────────────────────────────────────────

  void _paintRipple(Canvas canvas, Size size) {
    final origin = isHorizontal
        ? Offset(size.width / 2, size.height * 5)
        : Offset(size.width * -3, size.height / 2);

    // Farthest corner distance from origin (how far the rings must reach).
    double cornerDist(double dx, double dy) => math.sqrt(dx * dx + dy * dy);
    final maxR = [
      cornerDist(origin.dx, origin.dy),
      cornerDist(size.width - origin.dx, origin.dy),
      cornerDist(origin.dx, size.height - origin.dy),
      cornerDist(size.width - origin.dx, size.height - origin.dy),
    ].reduce(math.max) + 4.0;

    // Wide rings with generous spacing give a ripple feel similar in visual
    // weight to the diagonal stripe bands.
    const ringGap = 16.0; // gap between rings
    const strokeW = 28.0;
    final currentStrokeW = preview ? strokeW * 0.8 : strokeW;
    final ringStep = ringGap + currentStrokeW;
    final ringCount = (maxR / ringStep).ceil();

    for (var i = 1; i <= ringCount; i++) {
      final r = i * ringStep;
      // Opacity falls off smoothly from the centre outward.
      // Exponent < 1 keeps outer rings more visible.
      final t = math.pow(1.0 - (r / maxR).clamp(0.0, 1.0), 0.7) as double;
      final alpha = (preview ? 0.58 : 0.42) * t;
      if (alpha < 0.005) continue;

      canvas.drawCircle(
        origin,
        r,
        Paint()
          ..color = (i.isOdd ? theme.accent : theme.secondary)
              .withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = preview ? strokeW * 0.8 : strokeW
          ..isAntiAlias = true,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NavigationPanelOverlayPainter oldDelegate) {
    return oldDelegate.preview != preview ||
        oldDelegate.isHorizontal != isHorizontal ||
        oldDelegate.theme.accent != theme.accent ||
        oldDelegate.theme.secondary != theme.secondary ||
        oldDelegate.theme.navPanelOverlayStyle != theme.navPanelOverlayStyle;
  }
}
