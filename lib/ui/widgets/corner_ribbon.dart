import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The filled diagonal corner ribbon shared by library and cover cards.
class CornerRibbon extends StatelessWidget {
  const CornerRibbon({
    super.key,
    required this.label,
    required this.color,
    required this.textColor,
    this.bandHeight = 22.5,
    this.bandWidth = 130,
    this.offset = 9,
  });

  final String label;
  final Color color;
  final Color textColor;
  final double bandHeight;
  final double bandWidth;
  final double offset;

  @override
  Widget build(BuildContext context) {
    final center = offset + bandHeight / 2 / math.sqrt2;
    final extent = 2 * center + bandHeight / math.sqrt2;
    final content = SizedBox(
      width: extent,
      height: extent,
      child: Stack(
        children: [
          Positioned(
            left: center - bandWidth / 2,
            top: center - bandHeight / 2,
            child: Transform.rotate(
              angle: -math.pi / 4,
              child: SizedBox(
                width: bandWidth,
                height: bandHeight,
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return ClipPath(
      clipper: const _CornerRibbonClipper(),
      child: ColoredBox(color: color, child: content),
    );
  }
}

class _CornerRibbonClipper extends CustomClipper<Path> {
  const _CornerRibbonClipper();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width, 0)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(_CornerRibbonClipper oldClipper) => false;
}
