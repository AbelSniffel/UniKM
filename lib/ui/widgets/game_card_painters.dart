/// Custom painters and layout data classes for GameCard.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data-only helpers
// ─────────────────────────────────────────────────────────────────────────────

class CardViewOptions {
  const CardViewOptions({
    required this.showTitle,
    required this.showTitleOnNoPicture,
    required this.showPlatform,
    required this.showTags,
    required this.showTagsOnHoverOnly,
    required this.showDeadline,
    required this.showRatingsNow,
    required this.slimListView,
  });

  final bool showTitle;
  final bool showTitleOnNoPicture;
  final bool showPlatform;
  final bool showTags;
  final bool showTagsOnHoverOnly;
  final bool showDeadline;
  final bool showRatingsNow;
  final bool slimListView;
}

class ListCardLayout {
  const ListCardLayout({
    required this.useSlim,
    required this.cardHeight,
    required this.cardImageWidth,
  });

  final bool useSlim;
  final double cardHeight;
  final double cardImageWidth;

  static ListCardLayout fromOptions(CardViewOptions options) {
    final useSlim = options.slimListView;

    return ListCardLayout(
      useSlim: useSlim,
      cardHeight: useSlim ? kSlimListCardHeight : kListCardHeight,
      cardImageWidth: kListCardImageWidth,
    );
  }
}

class FetchStatusVisual {
  const FetchStatusVisual({
    required this.color,
    required this.icon,
    required this.tooltip,
  });

  final Color color;
  final Widget icon;
  final String tooltip;
}

// ─────────────────────────────────────────────────────────────────────────────
// Painters
// ─────────────────────────────────────────────────────────────────────────────

/// Paints an inward frame glow around a game card.
///
/// A horizontal [LinearGradient] (accent → primary) fills the card, then an
/// alpha mask shaped like a frame — fully opaque at the card edges, punched
/// out in the centre by a blurred inner [RRect] — is applied via [BlendMode.dstIn].
class CardGlowPainter extends CustomPainter {
  const CardGlowPainter({
    required this.accentColor,
    required this.primaryColor,
    required this.selected,
    required this.cornerRadius,
  });

  final Color accentColor;
  final Color primaryColor;
  final bool selected;
  final double cornerRadius;

  static const double _hoverAlpha = 0.85;
  static const double _selectedAlpha = 0.95;
  static const double _glowDepthFraction = 0.035;

  @override
  void paint(Canvas canvas, Size size) {
    final double alpha = selected ? _selectedAlpha : _hoverAlpha;
    final rect = Offset.zero & size;
    final double glowDepth =
        math.min(size.width, size.height) * _glowDepthFraction;
    final double blurSigma = glowDepth * 0.45;
    final double innerRadius = (cornerRadius - glowDepth * 0.4).clamp(
      0.0,
      cornerRadius,
    );

    canvas.saveLayer(
      rect,
      Paint()..color = Color.fromARGB((alpha * 255).round(), 255, 255, 255),
    );

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
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
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CardGlowPainter old) =>
      old.accentColor != accentColor ||
      old.primaryColor != primaryColor ||
      old.selected != selected ||
      old.cornerRadius != cornerRadius;
}

/// Paints a diagonal tiled "USED" watermark text pattern.
class UsedPatternPainter extends CustomPainter {
  const UsedPatternPainter({
    required this.textColor,
    required this.angleDegrees,
    required this.patternSize,
  });

  static const String _label = 'USED';
  static final Map<int, TextPainter> _textPainterCache = <int, TextPainter>{};
  static const int _maxCacheEntries = 16;

  final Color textColor;
  final double angleDegrees;
  final Size patternSize;

  TextPainter _resolveTextPainter(double fontSize) {
    final quantized = (fontSize * 2).round() / 2;
    final cacheKey = Object.hash(textColor.toARGB32(), quantized);
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
      _textPainterCache.remove(_textPainterCache.keys.first);
    }
    _textPainterCache[cacheKey] = painter;
    return painter;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final shortestSide = math.min(patternSize.width, patternSize.height);
    final fontSize = (shortestSide * 0.10).clamp(18.0, 28.0);
    final textPainter = _resolveTextPainter(fontSize);

    final textWidth = textPainter.width;
    final textHeight = textPainter.height;
    final xStep = textWidth + fontSize * 1.3;
    final yStep = textHeight + fontSize * 1.3;

    final diagonal = math.sqrt(
      patternSize.width * patternSize.width +
          patternSize.height * patternSize.height,
    );
    final angle = angleDegrees * (math.pi / 180);

    // Stable top-left anchor to avoid perceived drift during resize.
    final anchorX = patternSize.width / 2 - diagonal / 2;
    final anchorY = patternSize.height / 2 - diagonal / 2;

    final cols = (diagonal / xStep).ceil() + 2;
    final rows = (diagonal / yStep).ceil() + 2;

    for (var row = -1; row < rows; row++) {
      for (var col = -1; col < cols; col++) {
        final cx = anchorX + col * xStep + textWidth / 2;
        final cy = anchorY + row * yStep + textHeight / 2;

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
      old.patternSize != patternSize;
}

// ─────────────────────────────────────────────────────────────────────────────
// _VisibilityReveal
// ─────────────────────────────────────────────────────────────────────────────

/// Explicit visibility animation that only runs when [isVisible] changes.
///
/// Unlike AnimatedSize, this does not start a new layout animation when the
/// child changes size because of a parent resize, which keeps large card lists
/// much cheaper during nav panel collapse/expand and window resizing.
class VisibilityReveal extends StatefulWidget {
  const VisibilityReveal({
    super.key,
    required this.isVisible,
    required this.axisAlignment,
    required this.alignment,
    required this.child,
  });

  final bool isVisible;
  final double axisAlignment;
  final Alignment alignment;
  final Widget child;

  @override
  State<VisibilityReveal> createState() => _VisibilityRevealState();
}

class _VisibilityRevealState extends State<VisibilityReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;
  late final Animation<double> _opacity;

  /// The widget currently being rendered inside the transitions.
  late Widget _displayChild;

  @override
  void initState() {
    super.initState();
    _displayChild = widget.child;
    _controller = AnimationController(
      vsync: this,
      duration: kVeryFastAnimation,
      reverseDuration: kFastAnimation,
      value: widget.isVisible ? 1.0 : 0.0,
    );
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCirc,
      reverseCurve: Curves.easeInOutCirc,
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(covariant VisibilityReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible) {
      _displayChild = widget.child;
      if (oldWidget.isVisible != widget.isVisible) {
        _controller.forward();
      }
    } else if (oldWidget.isVisible != widget.isVisible) {
      _controller.reverse().whenCompleteOrCancel(() {
        if (mounted) setState(() => _displayChild = widget.child);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizeTransition(
        sizeFactor: _curve,
        axisAlignment: widget.axisAlignment,
        child: Align(
          alignment: widget.alignment,
          heightFactor: 1.0,
          child: IgnorePointer(
            ignoring: !widget.isVisible,
            child: FadeTransition(opacity: _opacity, child: _displayChild),
          ),
        ),
      ),
    );
  }
}
