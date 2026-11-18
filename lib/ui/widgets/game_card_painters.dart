/// The library cards' glow and USED watermark, drawn once into images.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// Paints an inward frame glow around a game card.
///
/// A horizontal [LinearGradient] (accent → primary) fills the card, then an
/// alpha mask shaped like a frame — fully opaque at the card edges, punched
/// out in the centre by a blurred inner [RRect] — is applied via [BlendMode.dstIn].
///
/// That takes two offscreen layers and a blur, the same again on every frame
/// for every glowing card. It is drawn once into an image, shared by every
/// card of the same size, and each paint only draws that image.
class CardGlowPainter extends CustomPainter {
  const CardGlowPainter({
    required this.accentColor,
    required this.primaryColor,
    required this.cornerRadius,
    this.hover,
    this.devicePixelRatio = 1.0,
  }) : super(repaint: hover);

  final Color accentColor;
  final Color primaryColor;
  final double cornerRadius;

  /// How far the hover glow has faded in. A selected card has none: its glow
  /// shows in full.
  final Animation<double>? hover;

  /// The pixel density the glow's image is drawn at.
  final double devicePixelRatio;

  static const double _hoverAlpha = 0.85;
  static const double _selectedAlpha = 0.95;
  static const double _glowDepthFraction = 0.035;

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = hover == null ? _selectedAlpha : _hoverAlpha * hover!.value;
    if (alpha <= 0 || size.isEmpty) return;
    final image = _CardGlowImages.of(this, size);
    canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()
        ..color = Color.fromRGBO(255, 255, 255, alpha)
        ..filterQuality = FilterQuality.low,
    );
  }

  /// Draws the glow itself, at full strength.
  void _paintGlow(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final double glowDepth =
        math.min(size.width, size.height) * _glowDepthFraction;
    final double blurSigma = glowDepth * 0.45;
    final double innerRadius = (cornerRadius - glowDepth * 0.4).clamp(
      0.0,
      cornerRadius,
    );

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [accentColor, primaryColor],
        ).createShader(rect),
    );

    canvas.saveLayer(rect, Paint()..blendMode = BlendMode.dstIn);
    canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawRRect(
      RRect.fromLTRBR(
        glowDepth,
        glowDepth,
        size.width - glowDepth,
        size.height - glowDepth,
        Radius.circular(innerRadius),
      ),
      Paint()
        ..blendMode = BlendMode.dstOut
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma)
        ..color = const Color(0xFFFFFFFF),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CardGlowPainter old) =>
      old.accentColor != accentColor ||
      old.primaryColor != primaryColor ||
      old.cornerRadius != cornerRadius ||
      old.hover != hover ||
      old.devicePixelRatio != devicePixelRatio;
}

/// The glow images drawn so far, the latest few.
abstract final class _CardGlowImages {
  static final _images = <(Color, Color, double, Size, double), ui.Image>{};

  static ui.Image of(CardGlowPainter painter, Size size) {
    final ratio = painter.devicePixelRatio;
    final key = (
      painter.accentColor,
      painter.primaryColor,
      painter.cornerRadius,
      size,
      ratio,
    );
    final cached = _images[key];
    if (cached != null) return cached;
    if (_images.length >= 6) _images.remove(_images.keys.first)?.dispose();
    final width = (size.width * ratio).ceil();
    final height = (size.height * ratio).ceil();
    final recorder = ui.PictureRecorder();
    painter._paintGlow(
      Canvas(recorder)..scale(width / size.width, height / size.height),
      size,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    return _images[key] = image;
  }
}

/// Paints a diagonal tiled "USED" watermark text pattern.
///
/// The pattern is many rotated text runs, which cost the same again on every
/// frame. It is drawn once into an image, shared by every card that needs the
/// same one, and each paint only draws that image.
class UsedPatternPainter extends CustomPainter {
  const UsedPatternPainter({
    required this.textColor,
    required this.angleDegrees,
    required this.patternSize,
    this.tileToCanvas = false,
    this.devicePixelRatio = 1.0,
  });

  static const String _label = 'USED';
  static final _textPainterCache = <(Color, double), TextPainter>{};
  static const int _maxCacheEntries = 16;

  final Color textColor;
  final double angleDegrees;
  final Size patternSize;
  final bool tileToCanvas;

  /// The pixel density the pattern's image is drawn at.
  final double devicePixelRatio;

  TextPainter _resolveTextPainter(double fontSize) {
    final quantized = (fontSize * 2).round() / 2;
    final cacheKey = (textColor, quantized);
    final cached = _textPainterCache[cacheKey];
    if (cached != null) return cached;

    final painter = TextPainter(
      text: TextSpan(
        text: _label,
        style: TextStyle(
          color: textColor,
          fontSize: quantized,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    if (_textPainterCache.length >= _maxCacheEntries) {
      _textPainterCache.remove(_textPainterCache.keys.first)?.dispose();
    }
    _textPainterCache[cacheKey] = painter;
    return painter;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawImageRect(
      _UsedPatternImages.of(this, size),
      Offset.zero & (size * devicePixelRatio),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  /// Draws the tiles themselves, in the card's own coordinates.
  void _paintTiles(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // Card height defines the text size; resizing its width must not change
    // either the glyphs or their spacing.
    final fontSize = tileToCanvas
        ? 12.5
        : (patternSize.height * 0.10).clamp(18.0, 28.0);
    final textPainter = _resolveTextPainter(fontSize);

    final textWidth = textPainter.width;
    final textHeight = textPainter.height;
    final xStep = textWidth + fontSize * 1.3;
    final yStep = textHeight + fontSize * 1.3;

    if (tileToCanvas) {
      final compactXStep = textWidth + fontSize * 1.6;
      // Keep each complete diagonal word centered in the slim row rather
      // than straddling its top and bottom edges in staggered rows.
      final cy = size.height / 2;
      for (var col = 0; col * compactXStep < size.width; col++) {
        final cx = textWidth / 2 + fontSize * 0.5 + col * compactXStep;
        canvas.save();
        canvas.translate(cx, cy);
        canvas.rotate(angleDegrees * (math.pi / 180));
        textPainter.paint(canvas, Offset(-textWidth / 2, -textHeight / 2));
        canvas.restore();
      }
      canvas.restore();
      return;
    }

    final angle = angleDegrees * (math.pi / 180);

    // Fixed card-local coordinates: resizing reveals or hides columns without
    // shifting any of the text already on screen.
    final cols = (size.width / xStep).ceil() + 2;
    final rows = (size.height / yStep).ceil() + 2;

    for (var row = -1; row < rows; row++) {
      for (var col = -1; col < cols; col++) {
        final cx = col * xStep + textWidth / 2;
        final cy = row * yStep + textHeight / 2;

        canvas.save();
        canvas.translate(cx, cy);
        canvas.rotate(angle);
        textPainter.paint(canvas, Offset(-textWidth / 2, -textHeight / 2));
        canvas.restore();
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant UsedPatternPainter old) =>
      old.textColor != textColor ||
      old.angleDegrees != angleDegrees ||
      old.patternSize != patternSize ||
      old.tileToCanvas != tileToCanvas ||
      old.devicePixelRatio != devicePixelRatio;
}

/// The watermark images drawn so far, the latest few.
abstract final class _UsedPatternImages {
  static final _images =
      <(Color, double, bool, double, Size, double), ui.Image>{};

  static ui.Image of(UsedPatternPainter painter, Size size) {
    // The pattern is fixed to the card's top left, so widths round up to 256
    // and heights to 64, and resizing a card keeps its image. A compact row
    // centres its words in its exact height.
    final canvasSize = Size(
      (size.width / 256).ceil() * 256,
      painter.tileToCanvas ? size.height : (size.height / 64).ceil() * 64,
    );
    final ratio = painter.devicePixelRatio;
    final key = (
      painter.textColor,
      painter.angleDegrees,
      painter.tileToCanvas,
      painter.patternSize.height,
      canvasSize,
      ratio,
    );
    final cached = _images[key];
    if (cached != null) return cached;
    if (_images.length >= 6) _images.remove(_images.keys.first)?.dispose();
    final recorder = ui.PictureRecorder();
    painter._paintTiles(Canvas(recorder)..scale(ratio), canvasSize);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      (canvasSize.width * ratio).ceil(),
      (canvasSize.height * ratio).ceil(),
    );
    picture.dispose();
    return _images[key] = image;
  }
}
