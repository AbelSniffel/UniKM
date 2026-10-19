import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// Shared geometry for every slider, including color-gradient tracks.
SliderThemeData buildAppSliderTheme({
  required Color accent,
  required Color disabledColor,
  required Color indicatorTextColor,
  required double cornerRadius,
}) => SliderThemeData(
  trackHeight: kSliderTrackHeight,
  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
  trackShape: AppSliderTrackShape(cornerRadius: cornerRadius),
  thumbShape: AppSliderThumbShape(cornerRadius: cornerRadius),
  overlayShape: AppSliderOverlayShape(cornerRadius: cornerRadius),
  activeTrackColor: accent,
  inactiveTrackColor: accent.withValues(alpha: 0.22),
  disabledActiveTrackColor: disabledColor.withValues(alpha: 0.35),
  disabledInactiveTrackColor: disabledColor.withValues(alpha: 0.15),
  thumbColor: accent,
  disabledThumbColor: disabledColor.withValues(alpha: 0.5),
  overlayColor: accent.withValues(alpha: 0.14),
  tickMarkShape: AppSliderTickMarkShape(cornerRadius: cornerRadius),
  activeTickMarkColor: indicatorTextColor.withValues(alpha: 0.55),
  inactiveTickMarkColor: accent.withValues(alpha: 0.65),
  valueIndicatorColor: accent,
  valueIndicatorTextStyle: TextStyle(
    color: indicatorTextColor,
    fontWeight: FontWeight.w600,
  ),
);

RRect _handleRect(Offset center, double cornerRadius, {double gap = 0}) {
  final size = kSliderHandleSize + gap * 2;
  final radius = cornerRadius == 0
      ? 0.0
      : math.min(cornerRadius + gap, size / 2);
  return RRect.fromRectAndRadius(
    Rect.fromCenter(center: center, width: size, height: size),
    Radius.circular(radius),
  );
}

class AppSliderThumbShape extends SliderComponentShape {
  const AppSliderThumbShape({required this.cornerRadius, this.outlineColor});
  final double cornerRadius;
  final Color? outlineColor;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size(kSliderHandleSize, kSliderHandleSize);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final color = Color.lerp(
      sliderTheme.disabledThumbColor,
      sliderTheme.thumbColor,
      enableAnimation.value,
    )!;
    context.canvas.drawRRect(
      _handleRect(center, cornerRadius),
      Paint()..color = color,
    );
    final glow = Color.lerp(color, Colors.black, 0.35)!;
    // A bounded set of narrow inset strokes gives a smooth inner glow
    // without a blur, offscreen layer, or painting outside the handle.
    const steps = 10;
    const depth = kSliderHandleSize / 4;
    const stepWidth = depth / steps;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stepWidth;
    for (var i = 0; i < steps; i++) {
      final fade = 1 - (i + 0.5) / steps;
      paint.color = glow.withValues(
        alpha: glow.a * 0.65 * fade * fade * enableAnimation.value,
      );
      context.canvas.drawRRect(
        _handleRect(center, cornerRadius).deflate((i + 0.5) * stepWidth),
        paint,
      );
    }
    if (outlineColor case final outline?) {
      // Keep the selected color visible even when it matches the surface.
      // This edge stays inside the handle and follows its corner geometry.
      context.canvas.drawRRect(
        _handleRect(center, cornerRadius).deflate(1),
        Paint()
          ..color = outline.withValues(
            alpha: outline.a * (0.4 + 0.6 * enableAnimation.value),
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }
}

class AppSliderOverlayShape extends SliderComponentShape {
  const AppSliderOverlayShape({required this.cornerRadius});
  final double cornerRadius;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(
    kSliderHandleSize + kSliderHandleGap * 2,
    kSliderHandleSize + kSliderHandleGap * 2,
  );

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final color = sliderTheme.overlayColor!;
    context.canvas.drawRRect(
      _handleRect(center, cornerRadius, gap: kSliderHandleGap),
      Paint()
        ..color = color.withValues(alpha: color.a * activationAnimation.value),
    );
  }
}

class AppSliderTickMarkShape extends SliderTickMarkShape {
  const AppSliderTickMarkShape({required this.cornerRadius});
  final double cornerRadius;
  static const size = 4.0;

  @override
  Size getPreferredSize({
    required SliderThemeData sliderTheme,
    required bool isEnabled,
  }) => const Size(size, size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    required bool isEnabled,
    required TextDirection textDirection,
  }) {
    // Tick marks are drawn after the track. Keep every mark out of the cutout,
    // including nearby steps on a densely divided slider.
    if (_handleRect(
      thumbCenter,
      cornerRadius,
      gap: kSliderHandleGap + size / 2,
    ).contains(center)) {
      return;
    }
    final active = textDirection == TextDirection.ltr
        ? center.dx < thumbCenter.dx
        : center.dx > thumbCenter.dx;
    final color = Color.lerp(
      active
          ? sliderTheme.disabledActiveTickMarkColor
          : sliderTheme.disabledInactiveTickMarkColor,
      active
          ? sliderTheme.activeTickMarkColor
          : sliderTheme.inactiveTickMarkColor,
      enableAnimation.value,
    )!;
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: size, height: size),
        Radius.circular(math.min(cornerRadius, size / 2)),
      ),
      Paint()..color = color,
    );
  }
}

/// A wide transparent cutout makes the handle clear on solid and HSV tracks.
class AppSliderTrackShape extends SliderTrackShape {
  const AppSliderTrackShape({required this.cornerRadius, this.colors});

  final double cornerRadius;
  final List<Color>? colors;

  // Flutter gives discrete tick marks a half-track-height inset. Opt into
  // that same positioning for the handle, even with square theme corners.
  @override
  bool get isRounded => true;

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    // Reserve the thumb's half-width inside the RenderBox rather than putting
    // it in external padding. The entire endpoint handle remains draggable.
    final inset = math.min(kSliderHandleSize / 2, parentBox.size.width / 2);
    final height = sliderTheme.trackHeight ?? kSliderTrackHeight;
    return Rect.fromLTWH(
      offset.dx + inset,
      offset.dy + (parentBox.size.height - height) / 2,
      math.max(0, parentBox.size.width - inset * 2),
      height,
    );
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (rect.isEmpty) return;
    final canvas = context.canvas;
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(math.min(cornerRadius, rect.height / 2)),
    );
    final visibleTrack = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect.inflate(kSliderHandleSize + kSliderHandleGap))
      ..addRRect(_handleRect(thumbCenter, cornerRadius, gap: kSliderHandleGap));
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.clipPath(visibleTrack);
    if (colors != null) {
      canvas.drawRect(
        rect,
        Paint()..shader = LinearGradient(colors: colors!).createShader(rect),
      );
    } else {
      final active = Color.lerp(
        sliderTheme.disabledActiveTrackColor,
        sliderTheme.activeTrackColor,
        enableAnimation.value,
      )!;
      final inactive = Color.lerp(
        sliderTheme.disabledInactiveTrackColor,
        sliderTheme.inactiveTrackColor,
        enableAnimation.value,
      )!;
      canvas.drawRect(rect, Paint()..color = inactive);
      final dx = thumbCenter.dx.clamp(rect.left, rect.right);
      canvas.drawRect(
        textDirection == TextDirection.ltr
            ? Rect.fromLTRB(rect.left, rect.top, dx, rect.bottom)
            : Rect.fromLTRB(dx, rect.top, rect.right, rect.bottom),
        Paint()..color = active,
      );
    }
    canvas.restore();
  }
}
