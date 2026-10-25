/// Animated gradient bar widget - Performance optimized
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:unikm/providers/app_providers.dart';

import 'preview_card.dart';

import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';

/// Animated gradient bar with multiple animation styles.
/// Uses [Ticker] for frame-synced updates and [RepaintBoundary] for isolation.
class AnimatedGradientBar extends ConsumerStatefulWidget {
  const AnimatedGradientBar({
    super.key,
    this.theme,
    this.animationStyle = GradientAnimation.scroll,
    this.height = 48.0,
    this.width,
    this.colors,
    this.isVertical = false,
    this.isPlaying = true,
    this.autoPauseWhenNotVisible = false,
    this.optimizeForPreview = false,
    this.maxFps = 60.0,
    this.flipWaveForLeftVertical = false,
  }) : assert(
         theme != null || colors != null,
         'Either theme or colors must be provided',
       ),
       assert(maxFps > 0, 'maxFps must be > 0');

  final AppThemeData? theme;
  final GradientAnimation animationStyle;
  final double height;
  final double? width;
  final List<Color>? colors;
  final bool isVertical;
  final bool isPlaying;
  final bool autoPauseWhenNotVisible;
  final bool optimizeForPreview;
  final double maxFps;
  final bool flipWaveForLeftVertical;

  List<Color> get gradientColors => colors ?? [theme!.accent, theme!.secondary];

  @override
  ConsumerState<AnimatedGradientBar> createState() =>
      _AnimatedGradientBarState();
}

class _AnimatedGradientBarState extends ConsumerState<AnimatedGradientBar>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  late final Key _visibilityKey;
  final _elapsed = ValueNotifier<double>(0);
  bool _foreground = true;
  Duration _lastTime = Duration.zero;
  double _frameBudgetAccumulator = 0.0;
  double _unpublishedTime = 0.0;
  double _visibleFraction = 1.0;
  double _speedMultiplier = 1.0;
  _SpiralMesh? _spiralMesh;
  _HelixMesh? _helixMesh;

  static const _speeds = {
    GradientAnimation.solid: 0.0, // No animation
    GradientAnimation.scroll: 0.25,
    GradientAnimation.pulse: 0.6,
    GradientAnimation.scanner: 0.25,
    GradientAnimation.heart: 0.4,
    GradientAnimation.barberPole: 0.28,
    GradientAnimation.spiral: 0.28,
    GradientAnimation.wave: 0.35,
    GradientAnimation.helix: 0.16,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _visibilityKey = ValueKey<int>(identityHashCode(this));
    _ticker = createTicker(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTickerState();
  }

  @override
  void didUpdateWidget(covariant AnimatedGradientBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animationStyle != GradientAnimation.spiral) {
      _spiralMesh?.dispose();
      _spiralMesh = null;
    }
    if (widget.animationStyle != GradientAnimation.helix) {
      _helixMesh?.dispose();
      _helixMesh = null;
    }
    if (oldWidget.animationStyle != widget.animationStyle) {
      _lastTime = Duration.zero;
      _frameBudgetAccumulator = 0.0;
      _unpublishedTime = 0.0;
    }
    if (oldWidget.isPlaying != widget.isPlaying ||
        oldWidget.autoPauseWhenNotVisible != widget.autoPauseWhenNotVisible ||
        oldWidget.maxFps != widget.maxFps ||
        oldWidget.animationStyle != widget.animationStyle) {
      _syncTickerState();
    }
  }

  void _onTick(Duration elapsed) {
    if (!_canAnimate) return;
    if (_lastTime == Duration.zero) {
      _lastTime = elapsed;
      return;
    }

    final dt = ((elapsed - _lastTime).inMicroseconds / 1000000.0).clamp(
      0.0,
      0.1,
    );
    _lastTime = elapsed;

    _frameBudgetAccumulator += dt;
    _unpublishedTime += dt;
    final frameInterval = 1.0 / widget.maxFps;
    // Ticker timestamps have microsecond precision. Keep fractional budget
    // across frames so rounded 60 Hz ticks and faster displays stay regular.
    const roundingTolerance = 0.000001;
    if (_frameBudgetAccumulator + roundingTolerance < frameInterval) return;
    final intervals =
        ((_frameBudgetAccumulator + roundingTolerance) / frameInterval).floor();
    _frameBudgetAccumulator = math.max(
      0.0,
      _frameBudgetAccumulator - intervals * frameInterval,
    );
    // Scheduling remainder is already represented in the published elapsed
    // time; track unpublished time separately to avoid advancing it twice.
    final steppedDt = _unpublishedTime;
    _unpublishedTime = 0.0;
    final speed = _speeds[widget.animationStyle] ?? 0.5;
    _elapsed.value += steppedDt * speed * _speedMultiplier;
  }

  bool get _canAnimate {
    final speed = _speeds[widget.animationStyle] ?? 0.0;
    final visible = !widget.autoPauseWhenNotVisible || _visibleFraction > 0.02;
    final tickerMode = TickerMode.valuesOf(context);
    return _foreground &&
        speed > 0.0 &&
        widget.isPlaying &&
        visible &&
        tickerMode.enabled;
  }

  void _syncTickerState() {
    if (!mounted) return;

    if (_canAnimate) {
      if (!_ticker.isActive) {
        _lastTime = Duration.zero;
        _frameBudgetAccumulator = 0.0;
        _unpublishedTime = 0.0;
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncTickerState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _elapsed.dispose();
    _spiralMesh?.dispose();
    _helixMesh?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _speedMultiplier = ref.watch(gradientAnimationSpeedProvider).multiplier;
    var colors = widget.gradientColors;
    final swap = ref.watch(swapGradientColorsProvider);
    if (swap && colors.length >= 2) {
      colors = [colors[1], colors[0], ...colors.skip(2)];
    }

    final primary = colors.isNotEmpty ? colors[0] : Colors.blue;
    final accent = colors.length > 1 ? colors[1] : primary;
    final bg = widget.theme?.surface ?? Colors.black;

    final painted = RepaintBoundary(
      child: widget.isVertical
          ? LayoutBuilder(
              builder: (_, c) => SizedBox(
                width:
                    widget.width ??
                    (c.maxWidth.isFinite ? c.maxWidth : widget.height),
                height: c.maxHeight.isFinite ? c.maxHeight : widget.height,
                child: _painter(primary, accent, bg, true),
              ),
            )
          : LayoutBuilder(
              builder: (_, c) => SizedBox(
                height: widget.height,
                width:
                    widget.width ??
                    (c.maxWidth.isFinite ? c.maxWidth : widget.width),
                child: _painter(primary, accent, bg, false),
              ),
            ),
    );

    if (!widget.autoPauseWhenNotVisible) return painted;

    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: (info) {
        final nextVisibleFraction = info.visibleFraction;
        if ((nextVisibleFraction - _visibleFraction).abs() < 0.01) return;
        _visibleFraction = nextVisibleFraction;
        _syncTickerState();
      },
      child: painted,
    );
  }

  Widget _painter(Color p, Color a, Color bg, bool v) {
    if (widget.animationStyle == GradientAnimation.spiral &&
        (_spiralMesh == null ||
            !_spiralMesh!.matches(p, a, widget.optimizeForPreview))) {
      _spiralMesh?.dispose();
      _spiralMesh = _SpiralMesh(p, a, widget.optimizeForPreview);
    }
    if (widget.animationStyle == GradientAnimation.helix &&
        (_helixMesh == null ||
            !_helixMesh!.matches(p, a, widget.optimizeForPreview))) {
      _helixMesh?.dispose();
      _helixMesh = _HelixMesh(p, a, widget.optimizeForPreview);
    }
    return CustomPaint(
      painter: _GradientPainter(
        _elapsed,
        widget.animationStyle,
        p,
        a,
        bg,
        v,
        widget.optimizeForPreview,
        widget.flipWaveForLeftVertical,
        _spiralMesh,
        _helixMesh,
        MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0,
      ),
      isComplex:
          widget.animationStyle != GradientAnimation.barberPole &&
          widget.animationStyle != GradientAnimation.solid,
      willChange:
          widget.animationStyle != GradientAnimation.solid && widget.isPlaying,
    );
  }
}

class _GradientPainter extends CustomPainter {
  _GradientPainter(
    this.animation,
    this.style,
    this.primary,
    this.accent,
    this.bg,
    this.vert,
    this.lightweight,
    this.flipWaveForLeftVertical,
    this.spiralMesh,
    this.helixMesh,
    this.pixelRatio,
  ) : super(repaint: animation);

  final ValueNotifier<double> animation;
  double get progress => animation.value;
  final GradientAnimation style;
  final Color primary, accent, bg;
  final bool vert;
  final bool lightweight;
  final bool flipWaveForLeftVertical;
  final _SpiralMesh? spiralMesh;
  final _HelixMesh? helixMesh;
  final double pixelRatio;

  final _paint = Paint()..isAntiAlias = false;

  // Heart and Scanner share the exact same translucent resting color.
  late final _restingColor = accent.withValues(alpha: 0.2);

  // Wave and Helix reveal the surrounding background through their gaps.
  late final _translucentBackground = Paint()
    ..color = bg.withValues(alpha: 0.52);

  late final _barberPoleColors = [
    Color.lerp(primary, accent, 0.5)!,
    primary,
    primary,
    accent,
    accent,
    Color.lerp(primary, accent, 0.5)!,
  ];
  final _barberPolePaint = Paint();
  (double, double)? _barberPoleScale;

  void _cacheBarberPoleShader(double pitch) {
    final scale = (pitch, pixelRatio);
    if (_barberPoleScale == scale) return;
    // A subpixel fringe filters both diagonal seams, including the repeated
    // tile boundary. The shader only changes on resize or display-scale changes.
    final halfFringe = 0.75 * math.sqrt2 / (pitch * pixelRatio) / 2;
    _barberPolePaint.shader = ui.Gradient.linear(
      Offset.zero,
      const Offset(0.5, 0.5),
      _barberPoleColors,
      [0, halfFringe, 0.5 - halfFringe, 0.5 + halfFringe, 1 - halfFringe, 1],
      TileMode.repeated,
    );
    _barberPoleScale = scale;
  }

  // A cached cross-axis reflection rounds the pole without blur or layers.
  late final _barberPoleShadePaint = Paint()
    ..shader = ui.Gradient.linear(
      Offset.zero,
      const Offset(0, 1),
      [
        Colors.black.withValues(alpha: 0.28),
        Colors.transparent,
        Colors.white.withValues(alpha: 0.07),
        Colors.transparent,
        Colors.black.withValues(alpha: 0.28),
      ],
      const [0, 0.22, 0.42, 0.7, 1],
    );

  // Idle fractions for painter-level animations (pulse/heart). Kept local to
  // the painter so drawing logic doesn't depend on State implementation.
  static const _idleFraction = {
    GradientAnimation.pulse: 0.5,
    GradientAnimation.heart: 0.5,
  };

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    switch (style) {
      case GradientAnimation.solid:
        _solid(canvas, rect);
      case GradientAnimation.scroll:
        _scroll(canvas, rect);
      case GradientAnimation.pulse:
        _pulse(canvas, rect);
      case GradientAnimation.scanner:
        _scanner(canvas, rect);
      case GradientAnimation.heart:
        _heart(canvas, rect);
      case GradientAnimation.barberPole:
        _barberPole(canvas, rect);
      case GradientAnimation.spiral:
        _spiral(canvas, rect);
      case GradientAnimation.wave:
        _wave(canvas, rect);
      case GradientAnimation.helix:
        _helix(canvas, rect);
    }
  }

  void _solid(Canvas c, Rect r) {
    // True solid color - just the primary color, no gradient
    _paint.shader = null;
    _paint.color = primary;
    c.drawRect(r, _paint);
  }

  void _scroll(Canvas c, Rect r) {
    final p = progress % 1.0;
    final len = vert ? r.height : r.width;
    // Remove the background bands so the scroll only transitions between
    // `primary` and `accent`. Keep TileMode.repeated so the motion remains
    // continuous.
    _paint.shader = ui.Gradient.linear(
      vert ? Offset(0, len * (-1 + p * 2)) : Offset(len * (-1 + p * 2), 0),
      vert ? Offset(0, len * (1 + p * 2)) : Offset(len * (1 + p * 2), 0),
      [primary, accent, primary],
      [0.0, 0.5, 1.0],
      TileMode.repeated,
    );
    c.drawRect(r, _paint);
  }

  void _pulse(Canvas c, Rect r) {
    // Pulse should start from a true "off" state, then rise to a peak and
    // return to off before the idle pause. Use a cosine-based hump so
    // activeT==0 maps to alpha==minAlpha.
    final idle = _idleFraction[GradientAnimation.pulse] ?? 0.0;
    final period = 1.0 + idle; // active (1.0) + idle
    final t = progress % period;

    // Minimum visible alpha when "off". Set to 0.0 for fully off start.
    const double minAlpha = 0.2;

    if (t >= 1.0) {
      // idle — show the resting (off) alpha
      final alpha = minAlpha;
      _paint.shader = ui.Gradient.linear(
        Offset.zero,
        vert ? Offset(0, r.height) : Offset(r.width, 0),
        // Flipped: ends use accent, center uses primary
        [_alpha(accent, alpha), _alpha(primary, alpha), _alpha(accent, alpha)],
        [0.0, 0.5, 1.0],
      );
      c.drawRect(r, _paint);
      return;
    }

    // active portion (map t -> 0..1). Use (1 - cos(2πt)) / 2 to create a
    // single symmetric hump that starts/ends at 0 and peaks at 0.5.
    final activeT = (t / 1.0).clamp(0.0, 1.0);
    final hump = (1.0 - math.cos(activeT * math.pi * 2)) / 2.0; // 0..1..0
    final alpha = minAlpha + hump * (1.0 - minAlpha);

    _paint.shader = ui.Gradient.linear(
      Offset.zero,
      vert ? Offset(0, r.height) : Offset(r.width, 0),
      // Flipped: ends use accent, center uses primary
      [_alpha(accent, alpha), _alpha(primary, alpha), _alpha(accent, alpha)],
      [0.0, 0.5, 1.0],
    );
    c.drawRect(r, _paint);
  }

  // Scanner effect — single integrated profile: a 20px primary front band
  // followed by a smooth trailing glow. Center travels off-screen so the
  // effect enters/exits gradually.
  void _scanner(Canvas c, Rect r) {
    _paint.shader = null;
    _paint.color = _restingColor;
    c.drawRect(r, _paint);
    // Shader colors carry their own alpha; do not multiply the beam by the
    // resting background's opacity.
    _paint.color = Colors.white;

    final len = vert ? r.height : r.width;
    if (len <= 0) return;

    // Movement timing
    const double speedMult = 1.5;
    final double cycle = (progress * speedMult) % 2.0;
    final bool movingRight = cycle < 1.0;
    final double halfCycle = movingRight ? cycle : (cycle - 1.0);

    // Per-direction phase: pause (invisible) -> move -> fade-out.
    // This adds a small delay before each outbound/return sweep.
    const pauseFrac = 0.22;
    const moveFrac = 0.62;
    const fadeFrac = 1.0 - pauseFrac - moveFrac;

    double phasePos;
    double amplitude;
    if (halfCycle < pauseFrac) {
      phasePos = 0.0;
      amplitude = 0.0;
    } else if (halfCycle < pauseFrac + moveFrac) {
      phasePos = (halfCycle - pauseFrac) / moveFrac;
      amplitude = 1.0;
    } else {
      phasePos = 1.0;
      final fadeProgress = (halfCycle - pauseFrac - moveFrac) / fadeFrac;
      amplitude = (1.0 - fadeProgress).clamp(0.0, 1.0);
    }

    if (amplitude <= 0.01) return;

    // Overshoot so center can be off-screen and enter smoothly
    const double overshoot = 0.15;
    final double extendedRange = 1.0 + 2.0 * overshoot;
    final double basePos = (phasePos * extendedRange) - overshoot;
    final double renderPos = movingRight
        ? basePos
        : (1.0 + overshoot) - (phasePos * extendedRange);

    // Compact sampled profile avoids edge clamping artifacts and keeps tail
    // correctly on the trailing side when direction flips.
    final frontBand = (20.0 / len).clamp(0.0, 0.45);
    final frontFeather = (6.0 / len).clamp(0.0, 0.2);
    final trailLen = (0.95 * (0.65 + 0.35 * amplitude)).clamp(0.10, 1.0);
    final headCore = (2.0 / len).clamp(0.002, 0.03);
    final trailCore = (trailLen - frontBand).clamp(0.001, 1.0);
    final center = renderPos;
    final dir = movingRight ? 1.0 : -1.0;

    double smooth01(double x) {
      final t = x.clamp(0.0, 1.0);
      return t * t * (3.0 - 2.0 * t);
    }

    final samples = lightweight
        ? (len.clamp(36.0, 72.0) + (amplitude > 0.7 ? 8.0 : 0.0)).round()
        : (len.clamp(96.0, 168.0) + (amplitude > 0.7 ? 20.0 : 0.0)).round();
    final stops = <double>[];
    final colors = <Color>[];
    for (int i = 0; i <= samples; i++) {
      final t = i / samples;
      final signed = (t - center) * dir; // >0 ahead, <0 behind
      final ahead = signed > 0.0 ? signed : 0.0;
      final behind = signed < 0.0 ? -signed : 0.0;

      double intensity = 0.0;
      double mix = 0.0;

      if (signed.abs() <= headCore) {
        intensity = 1.0;
        mix = 0.0;
      } else if (behind > headCore && behind <= frontBand) {
        intensity = 1.0;
        mix = 0.0;
      } else if (behind > frontBand && behind <= trailLen) {
        final u = ((behind - frontBand) / trailCore).clamp(0.0, 1.0);
        final decay = math.exp(-3.2 * u * u);
        final endFade = 1.0 - smooth01(u);
        intensity = (decay * endFade).clamp(0.0, 1.0);
        mix = math.pow(u, 0.72).toDouble();
      } else if (ahead > headCore && ahead <= frontFeather) {
        intensity = (1.0 - smooth01(ahead / frontFeather)) * 0.22;
        mix = 0.0;
      }

      final alpha = (intensity * amplitude).clamp(0.0, 1.0);
      final color = Color.lerp(primary, accent, mix) ?? primary;
      stops.add(t);
      colors.add(color.withValues(alpha: alpha));
    }

    _paint.shader = ui.Gradient.linear(
      Offset.zero,
      vert ? Offset(0, len) : Offset(len, 0),
      colors,
      stops,
    );
    c.drawRect(r, _paint);
  }

  // Heart: expands from middle, fills quickly, contracts, dissipates
  void _heart(Canvas c, Rect r) {
    // Sonnet-style heart: center glow that breathes, with dim ends.
    final len = vert ? r.height : r.width;
    if (len <= 0) return;

    // phase 0..1 where 0 is trough (dim) and 1 is peak (bright)
    final phase = progress * math.pi * 2.0;
    // Smoother wave: (sin + 1)/2 is standard 0..1 sine.
    // Pow(2.5) makes the "beat" (peak) sharper and the "rest" (trough) flatter and wider.
    final raw = (math.sin(phase) + 1.0) / 2.0;
    final p = math.pow(raw, 2.5).toDouble();

    // Middle color remains the primary
    final mid = primary;

    // Dim ends share Scanner's translucent resting color.
    final baseEndDim = _restingColor;

    // Radius grows with phase: expands at peak, contracts at rest
    final radius = (0.05 + p * 1.2).clamp(0.01, 1.5);

    final colors = <Color>[];
    final stops = <double>[];
    final samples = lightweight ? 20 : 32;
    for (int i = 0; i <= samples; i++) {
      final t = i / samples;
      final dist = (t - 0.5).abs() / 0.5; // 0..1 (0 at center, 1 at edges)

      double intensity;
      if (radius <= 0) {
        intensity = 0.0;
      } else {
        // Calculate glow falloff from center
        // 1.0 at center, drops to 0 at radius
        final rawInt = 1.0 - (dist / radius);
        intensity = rawInt.clamp(0.0, 1.0);

        // Smoothstep for softer edges
        intensity = intensity * intensity * (3 - 2 * intensity);

        // Modulate intensity by the beat pulse `p`.
        // At rest (p=0), intensity becomes 0, blending fully to baseEndDim (off color).
        intensity *= p;
      }

      // Interpolate between the dim background and the bright middle
      final col = Color.lerp(baseEndDim, mid, intensity) ?? baseEndDim;
      colors.add(col);
      stops.add(t);
    }

    _paint.shader = ui.Gradient.linear(
      vert ? Offset(0, -len) : Offset(-len, 0),
      vert ? Offset(0, 0) : Offset(0, 0),
      colors,
      stops,
      TileMode.mirror,
    );
    c.drawRect(r, _paint);
  }

  void _barberPole(Canvas c, Rect r) {
    _paintOriented(c, r, (canvas, size) {
      // Physical-pixel pitch keeps the diagonals at 45 degrees in wide,
      // and vertical bars. TileMode draws every stripe in one operation.
      final pitch = (size.height * 2.4).clamp(28.0, 110.0);
      _cacheBarberPoleShader(pitch);
      final phase = progress % 1.0;
      // Move the canvas rather than recreating the stripe shader each frame.
      canvas.save();
      canvas.translate(phase * pitch, 0);
      canvas.scale(pitch);
      canvas.drawRect(
        Rect.fromLTWH(-phase, 0, size.width / pitch, size.height / pitch),
        _barberPolePaint,
      );
      canvas.restore();

      // Stretch only the reflection's cross axis; its shader stays cached
      // through every frame and resize. No path generation or pixel sampling.
      canvas.save();
      canvas.scale(1, size.height);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, 1),
        _barberPoleShadePaint,
      );
      canvas.restore();
    });
  }

  void _spiral(Canvas c, Rect r) {
    final mesh = spiralMesh;
    if (mesh == null) return;
    c.save();
    c.clipRect(r);
    _paintOriented(c, r, (canvas, size) {
      // A rotating cylindrical helix projects to a longitudinal phase shift.
      // The cached curved boundaries and ridge lighting supply its 3D depth.
      final pitch = math.max(size.height * 2.4, 28.0);
      canvas.scale(pitch, size.height);
      final phase = progress % 1.0;
      canvas.translate(phase, 0);
      final vertices = mesh.verticesFor(pitch, size.height, pixelRatio);
      // Repeat the cached geometry at its original pitch, clipping overscan
      // where tiles meet so their edge shading is painted only once.
      for (
        var start = 0.0;
        start < size.width / pitch;
        start += _SpiralMesh.turns
      ) {
        canvas.save();
        canvas.clipRect(
          Rect.fromLTWH(start - phase, 0, _SpiralMesh.turns.toDouble(), 1),
          doAntiAlias: false,
        );
        canvas.translate(start, 0);
        canvas.drawVertices(vertices, BlendMode.dst, _paint);
        canvas.restore();
      }
    });
    c.restore();
  }

  void _wave(Canvas c, Rect r) {
    _paintOriented(c, r, (canvas, size) {
      if (vert && flipWaveForLeftVertical) {
        canvas.translate(size.width, size.height);
        canvas.rotate(math.pi);
      }

      canvas.drawRect(Offset.zero & size, _translucentBackground);

      final layerColors = <Color>[
        accent.withValues(alpha: 0.72),
        Color.lerp(primary, accent, 0.45)!.withValues(alpha: 0.62),
        primary.withValues(alpha: 0.55),
      ];
      final baseHeights = <double>[0.48, 0.62, 0.78];
      final xDrift = <double>[0.05, 0.09, 0.14];
      final yDrift = <double>[0.05, 0.07, 0.10];
      final frequencies = <double>[2.25, 1.85, 1.4];
      final secondaryFrequencies = <double>[4.3, 3.6, 2.9];
      final phases = <double>[3.4, 2.1, 0.9];

      for (var layerIndex = 0; layerIndex < layerColors.length; layerIndex++) {
        _drawWaveLayer(
          canvas,
          size,
          color: layerColors[layerIndex],
          baseHeightFactor: baseHeights[layerIndex],
          amplitude: math.max(size.height * (0.24 - (layerIndex * 0.03)), 1.0),
          secondaryAmplitude: math.max(
            size.height * (0.08 - (layerIndex * 0.01)),
            0.45,
          ),
          xDriftFactor: xDrift[layerIndex],
          yDriftFactor: yDrift[layerIndex],
          frequency: frequencies[layerIndex],
          secondaryFrequency: secondaryFrequencies[layerIndex],
          phase: phases[layerIndex],
        );
      }
    });
  }

  void _helix(Canvas c, Rect r) {
    final mesh = helixMesh;
    if (mesh == null) return;
    c.save();
    c.clipRect(r);
    _paintOriented(c, r, (canvas, size) {
      canvas.save();
      canvas.scale(size.width, size.height);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 1, 1), _translucentBackground);
      canvas.restore();
      final pitch = math.max(size.height * 2, 28.0);
      canvas.scale(pitch, size.height);
      // Rotation shifts the helix along its axis; each ribbon also sways and
      // breathes independently, preserving the half-turn crossing order.
      final phase = progress % 1.0;
      canvas.translate(phase, 0);
      final tileCount = (size.width / pitch / _HelixMesh.turns).ceil();
      mesh.retainTiles(tileCount);
      for (var tile = 0; tile < tileCount; tile++) {
        final start = tile * _HelixMesh.turns.toDouble();
        canvas.save();
        canvas.clipRect(
          Rect.fromLTWH(start - phase, 0, _HelixMesh.turns.toDouble(), 1),
          doAntiAlias: false,
        );
        canvas.translate(start, 0);
        canvas.drawVertices(
          mesh.verticesForTile(tile, pitch, size.height, pixelRatio, progress),
          BlendMode.dst,
          _paint,
        );
        canvas.restore();
      }
    });
    c.restore();
  }

  void _paintOriented(
    Canvas canvas,
    Rect rect,
    void Function(Canvas, Size) painter,
  ) {
    if (!vert) {
      painter(canvas, rect.size);
      return;
    }

    canvas.save();
    canvas.translate(0, rect.height);
    canvas.rotate(-math.pi / 2);
    painter(canvas, Size(rect.height, rect.width));
    canvas.restore();
  }

  void _drawWaveLayer(
    Canvas canvas,
    Size size, {
    required Color color,
    required double baseHeightFactor,
    required double amplitude,
    required double secondaryAmplitude,
    required double xDriftFactor,
    required double yDriftFactor,
    required double frequency,
    required double secondaryFrequency,
    required double phase,
  }) {
    final path = Path();
    // Keep wavelength, drift and sampling anchored to the cross axis.
    // Changing the length only adds or removes samples of the same curve.
    final span = math.max(size.height * 8, 160.0);
    final overscan = span * 0.18;
    final xDrift = math.sin((progress * 1.4) + phase) * (span * xDriftFactor);
    final yDrift =
        math.cos((progress * 1.1) + (phase * 1.7)) *
        (size.height * yDriftFactor);
    final baseY = (size.height * baseHeightFactor) + yDrift;
    final step = math.max(span / (lightweight ? 18 : 28), 6.0);

    final crestPath = Path();
    var started = false;
    path.moveTo(-overscan, size.height * 1.18);
    for (double x = -overscan; x <= size.width + overscan; x += step) {
      final t = (x + xDrift) / span;
      final wave = math.sin(
        (t * frequency * math.pi * 2) + (progress * 2.3) + phase,
      );
      final detail = math.sin(
        (t * secondaryFrequency * math.pi * 2) -
            (progress * 3.1) +
            (phase * 0.65),
      );
      final y = baseY + (wave * amplitude) + (detail * secondaryAmplitude);
      path.lineTo(x, y.clamp(-size.height * 0.35, size.height * 1.12));
      if (!started) {
        crestPath.moveTo(x, y);
        started = true;
      } else {
        crestPath.lineTo(x, y);
      }
    }
    path.lineTo(size.width + overscan, size.height * 1.18);
    path.close();

    final fillPaint = Paint()
      ..isAntiAlias = true
      ..color = color;
    canvas.drawPath(path, fillPaint);

    final crestPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = color.withValues(alpha: color.a * 0.42);
    canvas.drawPath(crestPath, crestPaint);
  }

  Color _alpha(Color c, double a) => c.withValues(alpha: a.clamp(0.0, 1.0));

  @override
  bool shouldRepaint(covariant _GradientPainter old) =>
      old.progress != progress ||
      old.style != style ||
      old.vert != vert ||
      old.primary != primary ||
      old.accent != accent ||
      old.bg != bg ||
      old.lightweight != lightweight ||
      old.pixelRatio != pixelRatio ||
      old.flipWaveForLeftVertical != flipWaveForLeftVertical;
}

/// Shared topology and reused motion buffers with stable crossing order.
/// State owns the current native mesh and releases replaced buffers.
class _HelixMesh {
  _HelixMesh(
    this.primary,
    this.accent,
    this.lightweight, {
    int turnOffset = 0,
  }) {
    _source = turnOffset == 0
        ? (lightweight ? _previewGeometry : _geometry)
        : _HelixGeometry(lightweight ? 18 : 32, turnOffset: turnOffset);
    _colors = Int32List(_source.shades.length);
    for (var i = 0; i < _colors.length; i++) {
      final (first, highlight, shadow, edge) = _source.shades[i];
      final lit = Color.lerp(
        first ? primary : accent,
        Colors.white,
        highlight,
      )!;
      _colors[i] = Color.lerp(
        lit,
        Colors.black,
        shadow,
      )!.withValues(alpha: edge ? 0 : 1).toARGB32();
    }
  }

  static const turns = 6;
  static final _geometry = _HelixGeometry(32);
  static final _previewGeometry = _HelixGeometry(18);
  final Color primary;
  final Color accent;
  final bool lightweight;
  late final _HelixGeometry _source;
  late final Int32List _colors;
  ui.Vertices? _vertices;
  Float32List? _positions;
  Float64List? _edgeFeathers;
  final _motionWeights = Float64List(8);
  final _widthWeights = Float64List(12);
  final _positionWeights = Float64List(12);
  final _tiles = <int, _HelixMesh>{};
  (double, double, double)? _scale;
  double? _motion;

  ui.Vertices verticesFor(
    double pitch,
    double height,
    double pixelRatio,
    double progress,
  ) {
    final scale = (pitch, height, pixelRatio);
    if (_positions == null || _scale != scale) {
      _positions = Float32List.fromList(_source.positions);
      final feathers = Float64List(_source.rows.length);
      final slopeScale = math.pow(0.29 * math.pi * 2 * height / pitch, 2);
      for (var row = 0; row < _source.rows.length; row++) {
        final sine = _source.rows[row].$3;
        feathers[row] =
            0.75 *
            math.sqrt(1 + slopeScale * (1 - sine * sine)) /
            (height * pixelRatio);
      }
      _edgeFeathers = feathers;
      _scale = scale;
      _motion = null;
    }
    // Two- and three-beat sways share a seamless four-rotation cycle. The
    // native upload runs only when motion/size changes, including on resume.
    final motion = progress % 4.0;
    if (_vertices == null || _motion != motion) {
      for (var ribbon = 0; ribbon < 2; ribbon++) {
        final phase =
            motion * math.pi * (ribbon == 0 ? 1.0 : 1.5) +
            (ribbon == 0 ? 0.4 : 1.7);
        final offset = ribbon * 4;
        _motionWeights[offset] =
            (ribbon == 0 ? 0.025 : 0.022) * math.sin(phase);
        _motionWeights[offset + 1] = 0.017 * math.cos(phase);
        _motionWeights[offset + 2] = 0.006 * math.cos(phase * 2);
        _motionWeights[offset + 3] = 0.006 * math.sin(phase * 2);
        final rotation = progress % 1.0;
        _source.profiles[ribbon].writeWeights(
          _widthWeights,
          ribbon,
          rotation,
          phase,
        );
        _source.motionProfiles[ribbon].writeWeights(
          _positionWeights,
          ribbon,
          rotation,
          -phase,
        );
      }
      final positions = _positions!;
      for (var row = 0; row < _source.rows.length; row++) {
        final (offset, center, sine, sine2, cosine2, ribbon) =
            _source.rows[row];
        final weight = ribbon * 4;
        var sway =
            sine * _motionWeights[weight] +
            _motionWeights[weight + 1] +
            sine2 * _motionWeights[weight + 2] +
            cosine2 * _motionWeights[weight + 3];
        var noise = 0.0;
        for (var band = 0; band < _HelixRandomProfile.bands; band++) {
          final basis = row * 6 + band * 2;
          final coefficient = ribbon * 6 + band * 2;
          noise +=
              _source.widthBasis[basis] * _widthWeights[coefficient] +
              _source.widthBasis[basis + 1] * _widthWeights[coefficient + 1];
          sway +=
              0.018 *
              (_source.motionBasis[basis] * _positionWeights[coefficient] +
                  _source.motionBasis[basis + 1] *
                      _positionWeights[coefficient + 1]);
        }
        // The normalized noise is bounded: this smooth range needs no hard
        // clipping that would introduce corners in the changing outline.
        final factor = 1.325 + noise * 0.475;
        final width = (_source.positions[offset] - center).abs() * factor;
        // Keep the fringe near one physical pixel as the ribbon broadens,
        // with a solid core preserved when a randomized section is thin.
        final feather = math.min(_edgeFeathers![row], width * 0.38);
        for (var column = 0; column < _HelixGeometry.ridges.length; column++) {
          final edge =
              column == 0 || column == _HelixGeometry.ridges.length - 1;
          positions[offset + column * 2] =
              center +
              sway +
              _HelixGeometry.ridges[column] * (width - (edge ? 0 : feather));
        }
      }
      _vertices?.dispose();
      _vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        positions,
        colors: _colors,
        indices: _source.indices,
      );
      _motion = motion;
    }
    return _vertices!;
  }

  ui.Vertices verticesForTile(
    int tile,
    double pitch,
    double height,
    double pixelRatio,
    double progress,
  ) {
    final mesh = tile == 0
        ? this
        : _tiles.putIfAbsent(
            tile,
            () => _HelixMesh(
              primary,
              accent,
              lightweight,
              turnOffset: tile * turns,
            ),
          );
    return mesh.verticesFor(pitch, height, pixelRatio, progress);
  }

  void retainTiles(int count) {
    for (final tile in _tiles.keys.where((tile) => tile >= count).toList()) {
      _tiles.remove(tile)!.dispose();
    }
  }

  bool matches(Color p, Color a, bool preview) =>
      primary == p && accent == a && lightweight == preview;

  void dispose() {
    for (final tile in _tiles.values) {
      tile.dispose();
    }
    _tiles.clear();
    _vertices?.dispose();
    _vertices = null;
    _positions = null;
    _edgeFeathers = null;
    _motion = null;
  }
}

class _HelixGeometry {
  _HelixGeometry(int segments, {int turnOffset = 0}) {
    final points = <double>[];
    final triangles = <int>[];
    final lighting = <(bool, double, double, bool)>[];
    final bases = <double>[];
    final motionBases = <double>[];
    profiles = [
      _HelixRandomProfile(0x48454c49),
      _HelixRandomProfile(0x52494242),
    ];
    motionProfiles = [
      _HelixRandomProfile(0x53574159, gentle: true),
      _HelixRandomProfile(0x464c4558, gentle: true),
    ];
    rows = <(int, double, double, double, double, int)>[];
    // Overscan both ends so phase shifts cannot expose missing ribbon tiles.
    for (var half = -5; half <= _HelixMesh.turns * 2 + 1; half++) {
      final front = half.isOdd ? 0 : 1;
      for (final ribbon in [1 - front, front]) {
        final start = lighting.length;
        for (var row = 0; row <= segments; row++) {
          final x = 0.25 + half * 0.5 + row / segments * 0.5;
          final angle = x * math.pi * 2 + ribbon * math.pi;
          final sine = math.sin(angle);
          final cosine = math.cos(angle);
          final center = 0.5 + 0.29 * sine;
          rows.add((
            points.length + 1,
            center,
            sine,
            math.sin(angle * 2),
            math.cos(angle * 2),
            ribbon,
          ));
          // Continue random profiles in world coordinates across mesh tiles.
          final worldX = x + turnOffset;
          for (final frequency in profiles[ribbon].frequencies) {
            final spatialPhase = worldX * frequency * math.pi * 2;
            bases.addAll([math.sin(spatialPhase), math.cos(spatialPhase)]);
          }
          for (final frequency in motionProfiles[ribbon].frequencies) {
            final spatialPhase = worldX * frequency * math.pi * 2;
            motionBases.addAll([
              math.sin(spatialPhase),
              math.cos(spatialPhase),
            ]);
          }
          // Broad narrowing keeps the outer turn convex: even a smooth
          // but steep width change can overpower the centerline's curvature
          // and create a dent. Randomized width is applied separately.
          final width = (0.072 + 0.050 * cosine * cosine) * 1.5;
          final facing = (cosine + 1) * 0.5;
          for (var column = 0; column < ridges.length; column++) {
            final ridge = ridges[column];
            final edge = column == 0 || column == ridges.length - 1;
            points.add(x);
            points.add(center + ridge * width);
            final reflection = (1 - (ridge - sine * 0.3).abs() / 0.8).clamp(
              0.0,
              1.0,
            );
            final highlight = reflection * (0.08 + facing * 0.20);
            final shadow = (1 - facing) * 0.30 + ridge * ridge * 0.13;
            lighting.add((ribbon == 0, highlight, shadow, edge));
          }
        }
        for (var row = 0; row < segments; row++) {
          for (var column = 0; column < ridges.length - 1; column++) {
            final a = start + row * ridges.length + column;
            final b = a + ridges.length;
            triangles.addAll([a, b, a + 1, a + 1, b, b + 1]);
          }
        }
      }
    }
    positions = Float32List.fromList(points);
    indices = Uint16List.fromList(triangles);
    shades = lighting;
    widthBasis = Float64List.fromList(bases);
    motionBasis = Float64List.fromList(motionBases);
  }

  static const ridges = [-1.0, -1.0, -0.7, 0.0, 0.7, 1.0, 1.0];
  late final Float32List positions;
  late final Uint16List indices;
  late final List<(bool, double, double, bool)> shades;
  late final List<(int, double, double, double, double, int)> rows;
  late final List<_HelixRandomProfile> profiles;
  late final List<_HelixRandomProfile> motionProfiles;
  late final Float64List widthBasis;
  late final Float64List motionBasis;
}

/// Stable random spatial frequencies/phases create different, smooth width
/// and motion profiles without per-frame random sampling.
class _HelixRandomProfile {
  _HelixRandomProfile(int seed, {bool gentle = false}) {
    final random = math.Random(seed);
    frequencies = [
      0.35 + random.nextDouble() * 0.20,
      0.78 + random.nextDouble() * 0.24,
      1.35 + random.nextDouble() * 0.40,
    ];
    if (gentle) {
      for (var i = 0; i < bands; i++) {
        frequencies[i] *= 0.6;
      }
    }
    phases = List.generate(bands, (_) => random.nextDouble() * math.pi * 2);
    weights = [
      0.60 + random.nextDouble() * 0.08,
      0.24 + random.nextDouble() * 0.05,
      0.12 + random.nextDouble() * 0.04,
    ];
    final sum = weights.reduce((a, b) => a + b);
    for (var i = 0; i < bands; i++) {
      weights[i] /= sum;
    }
  }

  void writeWeights(
    Float64List output,
    int ribbon,
    double rotation,
    double phase,
  ) {
    for (var band = 0; band < bands; band++) {
      // Keep the random fields anchored across rotation wraps; temporal
      // phases retain a seamless loop while each ribbon moves independently.
      final angle =
          phases[band] +
          rotation * math.pi * 2 * frequencies[band] +
          phase * (band + 1) * (band == 1 ? -1 : 1);
      final offset = ribbon * 6 + band * 2;
      output[offset] = weights[band] * math.cos(angle);
      output[offset + 1] = weights[band] * math.sin(angle);
    }
  }

  static const bands = 3;
  late final List<double> frequencies;
  late final List<double> phases;
  late final List<double> weights;
}

/// Fixed, shared projection geometry with a palette-specific native mesh.
/// State owns the native resource so theme changes and unmounting release it.
class _SpiralMesh {
  _SpiralMesh(this.primary, this.accent, this.lightweight) {
    _source = lightweight ? _previewGeometry : _geometry;
    _colors = Int32List(_source.shading.length);
    final seamColor = Color.lerp(primary, accent, 0.5)!;
    for (var i = 0; i < _colors.length; i++) {
      final (usePrimary, highlight, shadow, seam) = _source.shading[i];
      final base = seam ? seamColor : (usePrimary ? primary : accent);
      final lit = Color.lerp(base, Colors.white, highlight)!;
      _colors[i] = Color.lerp(lit, Colors.black, shadow)!.toARGB32();
    }
  }

  static const turns = 6;
  static final _geometry = _SpiralGeometry(20, const [
    0,
    0,
    .04,
    .2,
    .45,
    .7,
    .96,
    1,
    1,
  ]);
  static final _previewGeometry = _SpiralGeometry(12, const [
    0,
    0,
    .06,
    .45,
    .94,
    1,
    1,
  ]);
  final Color primary;
  final Color accent;
  final bool lightweight;
  late final _SpiralGeometry _source;
  late final Int32List _colors;
  ui.Vertices? _vertices;
  (double, double, double)? _scale;

  ui.Vertices verticesFor(double pitch, double height, double pixelRatio) {
    // About one physical pixel normal to each curved edge. Only resizing or
    // a DPI change adjusts geometry; rotation keeps the same native mesh.
    final scale = (pitch, height, pixelRatio);
    if (_vertices == null || _scale != scale) {
      final positions = Float32List.fromList(_source.positions);
      final feathers = [
        for (final slope in _source.edgeSlopes)
          (0.65 *
                  math.sqrt(1 + math.pow(slope * pitch / height, 2)) /
                  (pitch * pixelRatio))
              .clamp(0.0, 0.12),
      ];
      for (final (offset, weight, row) in _source.edgeInsets) {
        positions[offset] += weight * feathers[row];
      }
      _vertices?.dispose();
      _vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        positions,
        colors: _colors,
        indices: _source.indices,
      );
      _scale = scale;
    }
    return _vertices!;
  }

  bool matches(Color p, Color a, bool preview) =>
      primary == p && accent == a && lightweight == preview;

  void dispose() {
    _vertices?.dispose();
    _vertices = null;
  }
}

class _SpiralGeometry {
  _SpiralGeometry(int rows, List<double> ridgeStops) {
    final points = <double>[];
    final triangles = <int>[];
    final shades = <(bool, double, double, bool)>[];
    final insets = <(int, double, int)>[];
    edgeSlopes = List.generate(rows + 1, (row) {
      final angle = -math.pi / 2 + row / rows * math.pi;
      final facing = math.max(math.cos(angle), math.sin(math.pi / (rows * 2)));
      return 1 / (math.pi * facing);
    }, growable: false);
    // Two leading turns cover the phase shift plus the projected helix bow.
    // One leading turn leaves the left edge uncovered near the cycle's end.
    for (var turn = -2; turn <= _SpiralMesh.turns + 1; turn++) {
      for (var ribbon = 0; ribbon < 2; ribbon++) {
        final start = shades.length;
        for (var row = 0; row <= rows; row++) {
          final angle = -math.pi / 2 + row / rows * math.pi;
          final facing = math.cos(angle).clamp(0.0, 1.0);
          final y = (math.sin(angle) + 1) * 0.5;
          for (var column = 0; column < ridgeStops.length; column++) {
            final ridge = ridgeStops[column];
            if (column > 0 && column < ridgeStops.length - 1) {
              // Keep the inner ridge points ordered as the edge fringe widens
              // near the cylinder's ends, where its projected slope is steep.
              insets.add((points.length, 1 - ridge * 2, row));
            }
            final x = turn + ribbon * .5 + ridge * .5 + angle / (math.pi * 2);
            points.addAll([x, y]);
            final raised = math.sin(ridge * math.pi);
            final highlight = raised * facing * .26;
            final shadow = (1 - facing) * .38 + (1 - raised) * .14;
            final seam = column == 0 || column == ridgeStops.length - 1;
            shades.add((ribbon == 0, highlight, shadow, seam));
          }
        }
        final columns = ridgeStops.length;
        for (var row = 0; row < rows; row++) {
          for (var column = 0; column < columns - 1; column++) {
            final a = start + row * columns + column;
            final b = a + columns;
            triangles.addAll([a, a + 1, b, a + 1, b + 1, b]);
          }
        }
      }
    }
    positions = Float32List.fromList(points);
    indices = Uint16List.fromList(triangles);
    shading = shades;
    edgeInsets = insets;
  }

  late final Float32List positions;
  late final Uint16List indices;
  late final List<(bool, double, double, bool)> shading;
  late final List<(int, double, int)> edgeInsets;
  late final List<double> edgeSlopes;
}

/// Preview widget for gradient effects in settings
class GradientEffectPreview extends StatelessWidget {
  const GradientEffectPreview({
    super.key,
    required this.effect,
    required this.theme,
    this.isSelected = false,
    this.isPlaying = true,
    this.onTap,
  });

  final GradientAnimation effect;
  final AppThemeData theme;
  final bool isSelected;
  final bool isPlaying;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => PreviewCard(
    name: effect.displayName,
    theme: theme,
    isSelected: isSelected,
    onTap: onTap,
    backgroundBuilder: (context, _) => Stack(
      children: [
        // base surface and animated gradient
        Container(color: theme.surface),
        Positioned.fill(
          child: AnimatedGradientBar(
            theme: theme,
            animationStyle: effect,
            isPlaying: isPlaying,
            autoPauseWhenNotVisible: true,
            optimizeForPreview: true,
            maxFps: 60,
          ),
        ),
      ],
    ),
  );
}
