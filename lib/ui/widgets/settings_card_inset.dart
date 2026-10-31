import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Recessed lighting for active settings cards, with an optional raised rest
/// state for toggle buttons. All shading stays inside the
/// live card outline, so layout, hit testing, and child ink remain unchanged.
class SettingsCardInset extends StatelessWidget {
  /// One shared shadow strength for settings cards and compact toggle surfaces.
  static const defaultDepthStrength = 0.5;

  const SettingsCardInset({
    super.key,
    required this.active,
    required this.borderRadius,
    required this.surfaceColor,
    required this.child,
    this.raisedWhenInactive = false,
    this.overlay,
    this.shadeOverlay = true,
    this.depthStrength = defaultDepthStrength,
    this.cacheRaster = false,
  }) : assert(depthStrength >= 0 && depthStrength <= 1);

  final bool active;
  final double borderRadius;
  final Color surfaceColor;
  final bool raisedWhenInactive;
  final Widget child;

  /// Decorative overlay, sharing the card bounds and ignoring pointer events.
  final Widget? overlay;

  /// Lit indicators can sit above the depth lighting instead of being dimmed.
  final bool shadeOverlay;

  /// Scales the depth lighting while preserving its shape and blur.
  final double depthStrength;

  /// Draws the settled lighting from a shared image instead of blurring it
  /// per paint. For small, numerous surfaces such as tag chips, where a
  /// scrolling list would otherwise blur every newly mounted chip.
  final bool cacheRaster;

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
      // Only the settled lighting is cached; animating depths paint directly.
      final painter = depth == 0 || depthStrength <= 0
          ? null
          : cacheRaster && depth.abs() == 1
          ? _CachedInsetPainter(
              radius: borderRadius,
              depth: depth * depthStrength,
              surfaceColor: surfaceColor,
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            )
          : _SettingsCardInsetPainter(
              radius: borderRadius,
              depth: depth * depthStrength,
              surfaceColor: surfaceColor,
            );
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

/// Paints [_SettingsCardInsetPainter] from one small image per lighting, cut
/// into nine slices so it fits any width. The lighting only varies within
/// [_slice] of the sides, so the middle stretches without a visible seam.
class _CachedInsetPainter extends CustomPainter {
  const _CachedInsetPainter({
    required this.radius,
    required this.depth,
    required this.surfaceColor,
    required this.devicePixelRatio,
  });

  final double radius;
  final double depth;
  final Color surfaceColor;
  final double devicePixelRatio;

  /// Logical width of each side slice, past the blur of the side lighting.
  static const _slice = 20.0;
  static const _stretch = 8.0;
  static const _maxImages = 24;
  static final _images = <(double, double, double, int, double), ui.Image>{};

  ui.Image _image(double height) {
    final key = (
      height,
      radius,
      depth,
      surfaceColor.toARGB32(),
      devicePixelRatio,
    );
    final cached = _images.remove(key);
    if (cached != null) return _images[key] = cached;
    const width = _slice * 2 + _stretch;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    _SettingsCardInsetPainter(
      radius: radius,
      depth: depth,
      surfaceColor: surfaceColor,
    ).paint(canvas, Size(width, height));
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      (width * devicePixelRatio).ceil(),
      (height * devicePixelRatio).ceil(),
    );
    picture.dispose();
    if (_images.length >= _maxImages) {
      _images.remove(_images.keys.first)?.dispose();
    }
    return _images[key] = image;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (size.width < _slice * 2 + 1) {
      return _SettingsCardInsetPainter(
        radius: radius,
        depth: depth,
        surfaceColor: surfaceColor,
      ).paint(canvas, size);
    }
    final image = _image(size.height);
    final scale = devicePixelRatio;
    canvas
      ..save()
      ..scale(1 / scale);
    canvas.drawImageNine(
      image,
      Rect.fromLTRB(
        _slice * scale,
        image.height / 2 - 1,
        (_slice + _stretch) * scale,
        image.height / 2 + 1,
      ),
      Rect.fromLTWH(0, 0, size.width * scale, size.height * scale),
      Paint()..filterQuality = FilterQuality.low,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CachedInsetPainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.depth != depth ||
      oldDelegate.surfaceColor != surfaceColor ||
      oldDelegate.devicePixelRatio != devicePixelRatio;
}
