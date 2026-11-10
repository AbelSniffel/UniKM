import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import 'background_pattern.dart';

/// The same gradient and background pattern at any preview-card size. Every
/// theme shows the background pattern setting.
class ThemePreviewBackground extends ConsumerWidget {
  const ThemePreviewBackground({super.key, required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) => CustomPaint(
    painter: _PreviewBackdrop(
      theme,
      ref.watch(backgroundPatternProvider),
      MediaQuery.devicePixelRatioOf(context),
    ),
  );
}

/// Draws the gradient and pattern from an image of them, made once. The
/// pattern's glows are blurs, and Impeller draws a picture again on every
/// frame, so a menu with a dozen previews would blur them all while it
/// opens or slides.
class _PreviewBackdrop extends CustomPainter {
  const _PreviewBackdrop(this.theme, this.style, this.ratio);

  final AppThemeData theme;
  final NavPanelOverlayStyle style;
  final double ratio;

  /// The latest images, by what they show.
  static final _images = <Record, ui.Image>{};

  ui.Image _image(Size size) {
    final key = (
      theme.background,
      theme.accent,
      theme.secondary,
      theme.isDark,
      style,
      size,
      ratio,
    );
    // Hits move to the end, so the oldest image is the first.
    final cached = _images.remove(key);
    if (cached != null) return _images[key] = cached;
    if (_images.length >= 32) _images.remove(_images.keys.first)?.dispose();
    final bounds = Offset.zero & size;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(ratio)
      ..drawRect(
        bounds,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [theme.background, theme.accent, theme.secondary],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(bounds),
      );
    BackgroundPatternPainter(
      theme: theme,
      style: style,
      preview: true,
    ).paint(canvas, size);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      (size.width * ratio).ceil(),
      (size.height * ratio).ceil(),
    );
    picture.dispose();
    return _images[key] = image;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final image = _image(size);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_PreviewBackdrop old) =>
      old.theme != theme || old.style != style || old.ratio != ratio;
}
