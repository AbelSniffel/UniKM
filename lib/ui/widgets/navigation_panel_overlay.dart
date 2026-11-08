/// The background pattern: one decorative pattern laid out across the whole
/// window, so every panel (and page) showing it lines up with the others.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';

/// Marks the window the panel pattern is laid out across. It wraps the app
/// once; without it, surfaces place the pattern from their own position.
class PanelPatternWindow extends StatelessWidget {
  const PanelPatternWindow({super.key, required this.child});

  final Widget child;

  static final _link = LayerLink();

  @override
  Widget build(BuildContext context) =>
      CompositedTransformTarget(link: _link, child: child);
}

/// A panel background (the navigation panel's color and pattern) that shows
/// its part of the window-wide pattern, so panels line up wherever they sit.
/// A [page] surface has the app background instead, and a much fainter
/// pattern while pages show it.
class PanelPatternSurface extends ConsumerWidget {
  const PanelPatternSurface({
    super.key,
    this.page = false,
    this.strength = 1,
    required this.child,
  });

  final bool page;

  /// How strongly a panel shows the pattern, relative to the navigation
  /// panel; it applies whether or not pages show the pattern too.
  final double strength;
  final Widget child;

  /// How much fainter the pattern is behind pages than on panels.
  static const double pageStrength = 0.3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(effectiveThemeProvider);
    final patternStrength = ref.watch(patternStrengthProvider);
    final showOnPage = ref.watch(pagePatternProvider);
    return _PanelPatternSurface(
      color: page ? theme.background : theme.navBackground,
      pattern: BackgroundPatternPainter(
        theme: theme,
        angle: ref.watch(patternAngleProvider),
        wave: ref.watch(patternWaveProvider),
        strength: !page
            ? patternStrength * strength
            : showOnPage
            ? patternStrength * pageStrength
            : 0,
      ),
      windowSize: MediaQuery.sizeOf(context),
      child: child,
    );
  }
}

class _PanelPatternSurface extends SingleChildRenderObjectWidget {
  const _PanelPatternSurface({
    required this.color,
    required this.pattern,
    required this.windowSize,
    super.child,
  });

  final Color color;
  final BackgroundPatternPainter pattern;
  final Size windowSize;

  @override
  _RenderPanelPatternSurface createRenderObject(BuildContext context) =>
      _RenderPanelPatternSurface(color, pattern, windowSize);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPanelPatternSurface renderObject,
  ) => renderObject
    ..color = color
    ..pattern = pattern
    ..windowSize = windowSize;
}

/// Records the pattern around the surface once, in window coordinates, and
/// lets the compositor pin it to the window: moving the surface never
/// repaints it, and hover repaints inside the panel reuse the recording.
class _RenderPanelPatternSurface extends RenderProxyBox {
  _RenderPanelPatternSurface(this._color, this._pattern, this._windowSize);

  /// Extra pattern recorded around the surface, so small moves reuse it.
  static const double _margin = 64;
  static final _surfaces = <_RenderPanelPatternSurface>{};
  static bool _watchingFrames = false;

  final _clip = LayerHandle<ClipRectLayer>();
  final _follower = LayerHandle<FollowerLayer>();
  ui.Picture? _recording;
  Rect? _recordedArea;

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  BackgroundPatternPainter _pattern;
  set pattern(BackgroundPatternPainter value) {
    if (!value.shouldRepaint(_pattern)) return;
    final wasVisible = _pattern.isVisible;
    _pattern = value;
    _clearRecording();
    if (wasVisible != value.isVisible) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  Size _windowSize;
  set windowSize(Size value) {
    if (value == _windowSize) return;
    _windowSize = value;
    _clearRecording();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _pattern.isVisible;

  // An opaque panel, like the colored box it replaces.
  @override
  bool hitTestSelf(Offset position) => true;

  /// This surface's bounds in window coordinates.
  Rect get _area =>
      MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size);

  bool _covers(Rect area) {
    final recorded = _recordedArea;
    return recorded != null &&
        recorded.left <= area.left &&
        recorded.top <= area.top &&
        recorded.right >= area.right &&
        recorded.bottom >= area.bottom;
  }

  void _clearRecording() {
    _recording?.dispose();
    _recording = null;
    _recordedArea = null;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _surfaces.add(this);
    if (_watchingFrames) return;
    _watchingFrames = true;
    // A surface moved by an ancestor's layer is not repainted, so check
    // after every frame that its recording still covers it.
    final scheduler = SchedulerBinding.instance;
    scheduler.addPersistentFrameCallback(
      (_) => scheduler.addPostFrameCallback((_) {
        for (final surface in _surfaces) {
          if (surface._recording != null &&
              surface.hasSize &&
              !surface._covers(surface._area)) {
            surface.markNeedsPaint();
          }
        }
      }),
    );
  }

  @override
  void detach() {
    _surfaces.remove(this);
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    _follower.layer = null;
    _clearRecording();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.canvas.drawRect(offset & size, Paint()..color = _color);
    if (_pattern.isVisible) {
      final area = _area;
      if (!_covers(area)) {
        _clearRecording();
        final recorded = area.inflate(_margin);
        final recorder = ui.PictureRecorder();
        _pattern.paintArea(Canvas(recorder), _windowSize, recorded);
        _recording = recorder.endRecording();
        _recordedArea = recorded;
      }
      _clip.layer = context.pushClipRect(true, offset, Offset.zero & size, (
        context,
        offset,
      ) {
        final follower = _follower.layer ??= FollowerLayer(
          link: PanelPatternWindow._link,
        );
        // Without the window marker, place the window's origin from this
        // surface's own position instead.
        follower.unlinkedOffset = offset - area.topLeft;
        context.pushLayer(
          follower,
          (context, _) => context.canvas.drawPicture(_recording!),
          Offset.zero,
        );
      }, oldLayer: _clip.layer);
    } else {
      _clip.layer = null;
      _follower.layer = null;
    }
    super.paint(context, offset);
  }
}

/// Paints the theme's background pattern style. Surfaces draw their area of
/// a window-sized pattern with [paintArea]; as a [CustomPainter] it fills a
/// preview card on its own.
class BackgroundPatternPainter extends CustomPainter {
  const BackgroundPatternPainter({
    required this.theme,
    this.angle = DefaultSettings.patternAngle,
    this.wave = DefaultSettings.patternWave,
    this.strength = 1,
    this.preview = false,
  });

  final AppThemeData theme;

  /// Degrees clockwise: the stripes' slant from vertical, and the direction
  /// the gradient runs, across the stripes. Fixed to the pattern, so it
  /// never changes as panels resize or move.
  final int angle;

  /// How the Lines style sways: 0 straight, 0.5 smooth waves, 1 zigzag.
  final double wave;

  /// Scales every color's opacity, from the pattern strength setting.
  final double strength;

  /// Stronger colors for small preview cards.
  final bool preview;

  bool get isVisible =>
      strength > 0 && theme.navPanelOverlayStyle != NavPanelOverlayStyle.none;

  /// [color] at [alpha], scaled by [strength].
  Color _tone(Color color, double alpha) =>
      color.withValues(alpha: (alpha * strength).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) =>
      paintArea(canvas, size, Offset.zero & size);

  /// Draws the part of a [size]-sized pattern inside [area].
  void paintArea(Canvas canvas, Size size, Rect area) {
    if (area.isEmpty) return;
    switch (theme.navPanelOverlayStyle) {
      case NavPanelOverlayStyle.none:
        return;
      case NavPanelOverlayStyle.gradient:
        _paintGradient(canvas, size, area);
      case NavPanelOverlayStyle.diagonalStripes:
        _paintStripes(canvas, area, sway: wave > 0 ? _sway : null);
      case NavPanelOverlayStyle.crosshatch:
        // Keeps its own slant: the angle would fold its two sets together.
        _paintStripes(canvas, area, degrees: 30, alphaScale: 0.7);
        _paintStripes(canvas, area, degrees: -30, alphaScale: 0.7);
      case NavPanelOverlayStyle.dots:
        _paintDots(canvas, area);
      case NavPanelOverlayStyle.cubes:
        _paintCubes(canvas, area);
    }
  }

  // ── stripes and dots at the pattern angle ─────────────────────────────────

  /// Rotates [canvas] by [degrees] around the pattern origin and returns
  /// [area]'s bounds in the rotated space, so rows and columns stay fixed to
  /// the pattern however the area changes.
  static Rect _rotate(Canvas canvas, Rect area, double degrees) {
    final radians = degrees * math.pi / 180;
    final cosine = math.cos(radians);
    final sine = math.sin(radians);
    final corners = [
      for (final point in [
        area.topLeft,
        area.topRight,
        area.bottomLeft,
        area.bottomRight,
      ])
        Offset(
          point.dx * cosine + point.dy * sine,
          -point.dx * sine + point.dy * cosine,
        ),
    ];
    canvas.clipRect(area);
    canvas.rotate(radians);
    return Rect.fromLTRB(
      corners.map((point) => point.dx).reduce(math.min),
      corners.map((point) => point.dy).reduce(math.min) - 1,
      corners.map((point) => point.dx).reduce(math.max),
      corners.map((point) => point.dy).reduce(math.max) + 1,
    );
  }

  /// The lines' sideways sway along their length: growing into smooth waves
  /// by [wave] 0.5, then sharpening into a zigzag by 1. Its corners fall on
  /// the 6 px sampling grid.
  double _sway(double y) {
    final smooth = math.sin(y * math.pi / 60);
    final sharp = 2 / math.pi * math.asin(smooth);
    final sharpness = math.max(wave * 2 - 1, 0);
    return 12 * math.min(wave * 2, 1) * (smooth + (sharp - smooth) * sharpness);
  }

  /// The stripes' accent and secondary tones.
  List<Color> _stripeColors([double alphaScale = 1]) {
    final (accent, secondary) = preview ? (0.24, 0.16) : (0.14, 0.09);
    return [
      _tone(theme.accent, accent * alphaScale),
      _tone(theme.secondary, secondary * alphaScale),
    ];
  }

  void _paintStripes(
    Canvas canvas,
    Rect area, {
    double? degrees,
    double alphaScale = 1.0,
    double Function(double y)? sway,
  }) {
    const stripeW = 36.0;
    const period = stripeW + 20;
    final colors = _stripeColors(alphaScale);
    canvas.save();
    final bounds = _rotate(canvas, area, degrees ?? angle.toDouble());
    // Swaying stripes move sideways along their length. Samples sit on a
    // fixed grid, so a larger area draws the same curves.
    const step = 6.0;
    final ys = [
      if (sway != null)
        for (
          var y = (bounds.top / step).floor() * step;
          y <= bounds.bottom + step;
          y += step
        )
          y,
    ];
    for (
      var index = (bounds.left / period).floor();
      index <= (bounds.right / period).ceil();
      index++
    ) {
      final paint = Paint()..color = colors[index % colors.length];
      final left = index * period;
      if (sway == null) {
        canvas.drawRect(
          Rect.fromLTRB(left, bounds.top, left + stripeW, bounds.bottom),
          paint,
        );
        continue;
      }
      canvas.drawPath(
        Path()..addPolygon([
          for (final y in ys) Offset(left + sway(y), y),
          for (final y in ys.reversed) Offset(left + stripeW + sway(y), y),
        ], true),
        paint,
      );
    }
    canvas.restore();
  }

  void _paintDots(Canvas canvas, Rect area) {
    // Staggered rows of dots along the angle, cycling large accent, medium
    // secondary and small faint accent dots, each size drawn as one path.
    const gap = 30.0;
    const radii = [10.0, 7.0, 4.5];
    final paths = [Path(), Path(), Path()];
    canvas.save();
    final bounds = _rotate(canvas, area, angle.toDouble());
    for (
      var row = (bounds.top / gap).floor() - 1;
      row * gap < bounds.bottom + gap;
      row++
    ) {
      final layer = row % 3;
      final shift = row.isOdd ? gap / 2 : 0;
      for (
        var col = (bounds.left / gap).floor() - 1;
        col * gap < bounds.right + gap;
        col++
      ) {
        paths[layer].addOval(
          Rect.fromCircle(
            center: Offset(col * gap + shift, row * gap),
            radius: radii[layer],
          ),
        );
      }
    }
    _fillLayers(
      canvas,
      paths,
      preview ? const [0.34, 0.26, 0.2] : const [0.2, 0.15, 0.12],
    );
    canvas.restore();
  }

  // ── gradient across the pattern ───────────────────────────────────────────

  void _paintGradient(Canvas canvas, Size size, Rect area) {
    // From one edge of the whole pattern, fading out by the opposite one,
    // in the pattern angle's direction.
    final radians = angle * math.pi / 180;
    final (x, y) = (math.cos(radians), math.sin(radians));
    final end = Alignment(x, y) / math.max(x.abs(), y.abs());
    canvas.drawRect(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: -end,
          end: end,
          colors: [
            _tone(theme.accent, preview ? 0.55 : 0.36),
            _tone(theme.secondary, preview ? 0.32 : 0.2),
            _tone(theme.secondary, 0),
          ],
        ).createShader(Offset.zero & size),
    );
  }

  // ── cubes ────────────────────────────────────────────────────

  /// Pointy-top hexagon corners around the origin, from the top clockwise.
  static List<Offset> _hexCorners(double r) => [
    for (var i = 0; i < 6; i++)
      Offset.fromDirection(-math.pi / 2 + i * (math.pi / 3), r),
  ];

  /// Calls [cell] with the center of each hexagon of a grid [w] wide per
  /// cell and [rowStep] per row, odd rows shifted half a cell, over [area].
  static void _hexGrid(
    Rect area,
    double w,
    double rowStep,
    void Function(int row, int col, Offset center) cell,
  ) {
    final rowEnd = (area.bottom / rowStep).ceil() + 1;
    final colEnd = (area.right / w).ceil() + 1;
    for (var row = (area.top / rowStep).floor() - 1; row <= rowEnd; row++) {
      for (var col = (area.left / w).floor() - 1; col <= colEnd; col++) {
        cell(
          row,
          col,
          Offset(col * w + (row.isOdd ? w / 2 : 0), row * rowStep),
        );
      }
    }
  }

  /// Fills each of [paths] with its accent, secondary or faint accent tone,
  /// so a page-sized area stays three draw calls.
  void _fillLayers(Canvas canvas, List<Path> paths, List<double> alphas) {
    final colors = [theme.accent, theme.secondary, theme.accent];
    for (var i = 0; i < 3; i++) {
      canvas.drawPath(paths[i], Paint()..color = _tone(colors[i], alphas[i]));
    }
  }

  void _paintCubes(Canvas canvas, Rect area) {
    // Touching hexagons, each split into a top, right and left rhombus lit
    // differently, read as stacked cubes.
    const r = 26.0;
    final v = _hexCorners(r);
    final faces = [
      [v[5], v[0], v[1]],
      [v[1], v[2], v[3]],
      [v[3], v[4], v[5]],
    ];
    final paths = [Path(), Path(), Path()];
    _hexGrid(area, math.sqrt(3) * r, r * 1.5, (row, col, center) {
      for (final (index, face) in faces.indexed) {
        paths[index].addPolygon([
          center,
          for (final corner in face) center + corner,
        ], true);
      }
    });
    _fillLayers(
      canvas,
      paths,
      preview ? const [0.28, 0.18, 0.06] : const [0.18, 0.11, 0.03],
    );
  }

  @override
  bool shouldRepaint(covariant BackgroundPatternPainter oldDelegate) =>
      oldDelegate.preview != preview ||
      oldDelegate.strength != strength ||
      oldDelegate.angle != angle ||
      oldDelegate.wave != wave ||
      oldDelegate.theme.accent != theme.accent ||
      oldDelegate.theme.secondary != theme.secondary ||
      oldDelegate.theme.navPanelOverlayStyle != theme.navPanelOverlayStyle;
}
