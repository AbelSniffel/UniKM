import 'package:flutter/material.dart';

/// A short outward glow that never paints underneath a translucent card.
class CardSelectionGlow extends StatelessWidget {
  const CardSelectionGlow({
    super.key,
    required this.selected,
    required this.color,
    required this.borderRadius,
    required this.child,
  });

  final bool selected;
  final Color color;
  final double borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: selected
        ? _CardSelectionGlowPainter(color: color, radius: borderRadius)
        : null,
    child: child,
  );
}

class _CardSelectionGlowPainter extends CustomPainter {
  const _CardSelectionGlowPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).scaleRadii();
    // Blur one continuous rounded shape instead of antialiased rings, which
    // overlap unevenly around corners. The cutout keeps all ink outside.
    const extent = 7.0;
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect((Offset.zero & size).inflate(extent))
      ..addRRect(outline);
    canvas.save();
    canvas.clipPath(outside);
    canvas.drawRRect(
      outline.inflate(1),
      Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CardSelectionGlowPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
