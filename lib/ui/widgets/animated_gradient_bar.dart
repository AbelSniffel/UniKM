/// Animated gradient bar widget - Performance optimized
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:unikm/providers/app_providers.dart';

import 'hover_preview_card.dart';

import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';

/// Animated gradient bar with multiple animation styles.
/// Uses [Ticker] for frame-synced updates and [RepaintBoundary] for isolation.
class AnimatedGradientBar extends ConsumerStatefulWidget {
  const AnimatedGradientBar({
    super.key,
    this.theme,
    this.animationStyle = GradientAnimation.scroll,
    this.height = 4.0,
    this.width,
    this.colors,
    this.isVertical = false,
    this.isPlaying = true,
    this.autoPauseWhenNotVisible = false,
    this.optimizeForPreview = false,
    this.maxFps = 60.0,
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

  List<Color> get gradientColors => colors ?? [theme!.accent, theme!.primary];

  @override
  ConsumerState<AnimatedGradientBar> createState() =>
      _AnimatedGradientBarState();
}

class _AnimatedGradientBarState extends ConsumerState<AnimatedGradientBar>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final Key _visibilityKey;
  double _elapsed = 0.0;
  Duration _lastTime = Duration.zero;
  double _frameBudgetAccumulator = 0.0;
  double _visibleFraction = 1.0;

  static const _speeds = {
    GradientAnimation.solid: 0.0, // No animation
    GradientAnimation.scroll: 0.25,
    GradientAnimation.pulse: 0.6,
    GradientAnimation.scanner: 0.25,
    GradientAnimation.heart: 0.4,
    GradientAnimation.aurora: 0.4,
  };

  @override
  void initState() {
    super.initState();
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
    if (oldWidget.animationStyle != widget.animationStyle) {
      _lastTime = Duration.zero;
      _frameBudgetAccumulator = 0.0;
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
    final frameInterval = 1.0 / widget.maxFps;
    if (_frameBudgetAccumulator < frameInterval) return;

    final steppedDt = _frameBudgetAccumulator;
    _frameBudgetAccumulator = 0.0;
    final speed = _speeds[widget.animationStyle] ?? 0.5;
    setState(() => _elapsed += steppedDt * speed);
  }

  bool get _canAnimate {
    final speed = _speeds[widget.animationStyle] ?? 0.0;
    final visible = !widget.autoPauseWhenNotVisible || _visibleFraction > 0.02;
    final tickerMode = TickerMode.valuesOf(context);
    return speed > 0.0 && widget.isPlaying && visible && tickerMode.enabled;
  }

  void _syncTickerState() {
    if (!mounted) return;

    if (_canAnimate) {
      if (!_ticker.isActive) {
        _lastTime = Duration.zero;
        _frameBudgetAccumulator = 0.0;
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                width: widget.width ?? 6.0,
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

  Widget _painter(Color p, Color a, Color bg, bool v) => CustomPaint(
    painter: _GradientPainter(
      _elapsed,
      widget.animationStyle,
      p,
      a,
      bg,
      v,
      widget.optimizeForPreview,
    ),
    isComplex: true,
    willChange: true,
  );
}

class _GradientPainter extends CustomPainter {
  _GradientPainter(
    this.progress,
    this.style,
    this.primary,
    this.accent,
    this.bg,
    this.vert,
    this.lightweight,
  );

  final double progress;
  final GradientAnimation style;
  final Color primary, accent, bg;
  final bool vert;
  final bool lightweight;

  static final _paint = Paint()..isAntiAlias = false;

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
      case GradientAnimation.aurora:
        _aurora(canvas, rect);
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
    _paint.color = bg;
    c.drawRect(r, _paint);

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

    // Use the "other" theme color as the uniform background/ends color
    final baseEnd = accent;

    // Minimum visible alpha when "off" (to avoid a bright paused state).
    const double minOffAlpha = 0.2;

    // Middle color remains the primary
    final mid = primary;

    // Ends stay dim at minOffAlpha to create the "tunnel" look
    final baseEndDim = baseEnd.withValues(alpha: minOffAlpha);

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
      var col = Color.lerp(baseEndDim, mid, intensity) ?? baseEndDim;
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

  void _aurora(Canvas c, Rect r) {
    final len = vert ? r.height : r.width;
    final colors = <Color>[];
    final stops = <double>[];

    // Increase samples for smoother, higher-contrast bands and add a
    // high-frequency component to create narrow, darker "spots".
    final samples = lightweight ? 20 : 32;
    for (int i = 0; i <= samples; i++) {
      final t = i / samples;

      // Stationary (non-scrolling) aurora: remove the progress*t translation so
      // bands do not move left/right. Use a time-only phase to pulse in place
      // and a deterministic per-sample seed so peaks are spatially varied and
      // slowly animate without translating across the bar.
      final phasePulse =
          progress * 2.0 * math.pi * 0.45; // slow-medium in-place pulse

      // Deterministic spatial seed per sample (fract(sin(n))*large) — stable
      // across frames but different per t so peaks appear at different x.
      final seed = ((math.sin(i * 12.9898) * 43758.5453) % 1.0).abs();

      // Slow modulation using global progress so seeded peaks fade/brighten
      final slowMod =
          (math.sin(progress * 2.0 * math.pi * 0.45 + seed * 6.28318) * 0.5 +
          0.5);

      final w1 =
          math.sin(t * 2.6 * math.pi * 2 + phasePulse + seed * 1.6) * 0.5 + 0.5;
      final w2 =
          math.sin(t * 5.2 * math.pi * 2 - phasePulse * 0.55 + seed * 2.1) *
              0.5 +
          0.5;
      final w3 = math.sin(t * 12.0 * math.pi * 2 + seed * 3.7) * 0.5 + 0.5;

      // Combine waves and inject a slow, seeded amplitude so peaks remain mostly
      // stationary but vary in intensity over time (no lateral scrolling).
      var comb = (w1 * 0.55 + w2 * 0.30 + w3 * 0.15 + 0.35 * seed * slowMod)
          .clamp(0.0, 1.0);

      // Compact, behavior-preserving mapping:
      // - lows -> bg, mids -> accent (raised to primary lightness), peaks -> primary
      // - fewer/deeper dips, stronger mid-range visibility, narrow dark spots kept
      const double accentBoost = 0.65;
      const double dipSuppress = 0.60;

      final double peak = math.pow(comb, 2.4).toDouble();
      final double eased = math.min(
        1.0,
        math.max(0.0, math.pow(comb, 0.75).toDouble()),
      );

      final primaryLight = HSLColor.fromColor(primary).lightness;
      final Color accentAtPeak = HSLColor.fromColor(
        accent,
      ).withLightness(primaryLight).toColor();
      final Color midColor = Color.lerp(accent, accentAtPeak, eased)!;

      final Color colBase = Color.lerp(bg, midColor, eased)!;
      final Color col = Color.lerp(
        Color.lerp(colBase, bg, 0.18),
        primary,
        peak,
      )!;

      final double dip =
          dipSuppress * math.pow((1.0 - eased).clamp(0.0, 1.0), 1.2).toDouble();
      final double baseAlpha = ((0.10 + 0.90 * peak) * (1.0 - dip)).clamp(
        0.06,
        1.0,
      );

      final double spot = (1.0 - 0.9 * math.pow(w3, 8))
          .clamp(0.0, 1.0)
          .toDouble();
      final double boost =
          ((1.0 - (comb - 0.5).abs() * 2.0).clamp(0.0, 1.0) * accentBoost);
      final double alphaOut = (baseAlpha + boost * (1.0 - peak)).clamp(
        0.06,
        1.0,
      );

      colors.add(col.withValues(alpha: alphaOut * spot));
      stops.add(t);
    }

    _paint.shader = ui.Gradient.linear(
      Offset.zero,
      vert ? Offset(0, len) : Offset(len, 0),
      colors,
      stops,
    );
    c.drawRect(r, _paint);
  }

  Color _alpha(Color c, double a) => c.withValues(alpha: a.clamp(0.0, 1.0));

  @override
  bool shouldRepaint(covariant _GradientPainter old) =>
      old.progress != progress ||
      old.style != style ||
      old.vert != vert ||
      old.primary != primary ||
      old.accent != accent ||
      old.lightweight != lightweight;
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
  Widget build(BuildContext context) {
    return HoverPreviewCard(
      name: effect.displayName,
      theme: theme,
      isSelected: isSelected,
      onTap: onTap,
      backgroundBuilder: (context, _) {
        return Stack(
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
        );
      },
    );
  }
}
