import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Expanding ink whose radius follows a button that resizes during the gesture.
class LiveSizeInkRipple extends InteractiveInkFeature {
  LiveSizeInkRipple({
    required super.controller,
    required super.referenceBox,
    required super.color,
    required this.position,
    required this.textDirection,
    this.rectCallback,
    this.borderRadius,
    this.radius,
    super.customBorder,
    super.onRemoved,
  }) {
    _expansion = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: controller.vsync,
    )..addListener(controller.markNeedsPaint);
    _opacity =
        AnimationController(
            value: 1,
            duration: const Duration(milliseconds: 350),
            vsync: controller.vsync,
          )
          ..addListener(controller.markNeedsPaint)
          ..addStatusListener((status) {
            if (status == AnimationStatus.dismissed) dispose();
          });
    controller.addInkFeature(this);
    _expansion.forward();
  }

  static const splashFactory = _LiveSizeInkRippleFactory();

  final Offset position;
  final TextDirection textDirection;
  final RectCallback? rectCallback;
  final BorderRadius? borderRadius;
  final double? radius;
  late final AnimationController _expansion;
  late final AnimationController _opacity;

  @override
  void confirm() {
    _expansion.duration = const Duration(milliseconds: 250);
    _expansion.forward();
    _opacity.reverse();
  }

  @override
  void cancel() => _opacity.reverse(from: _opacity.value);

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    final rect = rectCallback?.call() ?? Offset.zero & referenceBox.size;
    final targetRadius =
        radius ??
        [
          rect.topLeft,
          rect.topRight,
          rect.bottomLeft,
          rect.bottomRight,
        ].map((corner) => (corner - position).distance).reduce(math.max);
    paintInkCircle(
      canvas: canvas,
      transform: transform,
      paint: Paint()..color = color.withValues(alpha: color.a * _opacity.value),
      center: position,
      radius: targetRadius * Curves.easeOut.transform(_expansion.value),
      textDirection: textDirection,
      customBorder: customBorder,
      borderRadius: borderRadius ?? BorderRadius.zero,
      clipCallback: () => rect,
    );
  }

  @override
  void dispose() {
    _expansion.dispose();
    _opacity.dispose();
    super.dispose();
  }
}

class _LiveSizeInkRippleFactory extends InteractiveInkFeatureFactory {
  const _LiveSizeInkRippleFactory();

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) => LiveSizeInkRipple(
    controller: controller,
    referenceBox: referenceBox,
    position: position,
    color: color,
    textDirection: textDirection,
    rectCallback: rectCallback,
    borderRadius: borderRadius,
    customBorder: customBorder,
    radius: radius,
    onRemoved: onRemoved,
  );
}
