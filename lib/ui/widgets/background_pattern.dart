/// The background pattern: one decorative pattern laid out across the whole
/// window, so every panel (and page) showing it lines up with the others.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';

/// Marks the window the panel pattern is laid out across: the app's content,
/// below the title bar, so edge decorations stay in view. It wraps the
/// content once; a surface outside it is a window of its own.
class const PanelPatternWindow({super.key, required final Widget child})
    extends StatelessWidget {
  static final _link = LayerLink();

  @override
  Widget build(BuildContext context) =>
      CompositedTransformTarget(link: _link, child: child);
}

/// A panel background (the navigation panel's color and pattern) that shows
/// its part of the window-wide pattern, so panels line up wherever they sit.
/// A [page] surface paints no color: it lies on the app background, which
/// the window's Scaffold already paints, and shows a much fainter pattern
/// while pages show it. A second fill there would cost a full-area layer
/// every frame.
class const PanelPatternSurface({
  super.key,
  final bool page = false,
  required final Widget child,
}) extends ConsumerWidget {
  /// How strongly every panel (the navigation panel, the library header and
  /// filter sidebar, the settings search bar and section list, and the Add
  /// Games action bars) shows the pattern, as a share of the pattern
  /// strength setting. Under it is the theme's navBackground, opaque.
  static const double panelStrength = 0.5;

  /// How much fainter the pattern is behind pages than on panels.
  static const double pageStrength = 0.4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final patternStrength = ref.watch(patternStrengthProvider);
    final showOnPage = ref.watch(pagePatternProvider);
    return _PanelPatternSurface(
      color: page ? null : theme.navBackground,
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
      recolorLater: ref.read(themeProvider.notifier).isPreviewMode,
      pattern: BackgroundPatternPainter(
        theme: theme,
        style: ref.watch(backgroundPatternProvider),
        angle: ref.watch(patternAngleProvider),
        wave: ref.watch(patternWaveProvider),
        strength: !page
            ? patternStrength * panelStrength
            : showOnPage
            ? patternStrength * pageStrength
            : 0,
      ),
      child: child,
    );
  }
}

class const _PanelPatternSurface({
  required final Color? color,
  required final BackgroundPatternPainter pattern,
  required final double pixelRatio,
  required final bool recolorLater,
  super.child,
}) extends SingleChildRenderObjectWidget {
  @override
  _RenderPanelPatternSurface createRenderObject(BuildContext context) =>
      _RenderPanelPatternSurface(color, pattern, pixelRatio, recolorLater);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPanelPatternSurface renderObject,
  ) => renderObject
    ..recolorLater = recolorLater
    ..color = color
    ..pattern = pattern
    ..pixelRatio = pixelRatio;
}

/// Records the pattern around the surface once, in window coordinates, and
/// lets the compositor pin it to the window: moving the surface never
/// repaints it, and hover repaints inside the panel reuse the recording.
/// The recording draws [_PatternTiles], so a surface that grows, as in a
/// window resize, only draws the tiles it newly reaches.
///
/// While [recolorLater] (a live theme preview), a change of the pattern's
/// colors alone keeps the recording until the colors have rested for
/// [_recolorDelay]: redrawing every tile on each step of a color drag halved
/// the frame rate on a weak GPU.
class _RenderPanelPatternSurface(
  var Color? _color,
  var BackgroundPatternPainter _pattern,
  var double _pixelRatio,
  var bool _recolorLater,
) extends RenderProxyBox {
  /// Extra pattern recorded around the surface, so small moves reuse it.
  static const double _margin = 64;
  static final _surfaces = <_RenderPanelPatternSurface>{};
  static bool _watchingFrames = false;

  /// Surfaces showing pattern colors a preview has since changed.
  static final _stale = <_RenderPanelPatternSurface>{};
  static Timer? _recolorTimer;
  static const _recolorDelay = Duration(milliseconds: 150);

  static void _recolorStale() {
    _recolorTimer = null;
    for (final surface in [..._stale]) {
      surface
        .._clearRecording()
        ..markNeedsPaint();
    }
  }

  /// Links nothing, for a surface outside any [PanelPatternWindow].
  static final _alone = LayerLink();

  final _clip = LayerHandle<ClipRectLayer>();
  final _follower = LayerHandle<FollowerLayer>();
  ui.Picture? _recording;
  List<Record> _tiles = const [];
  Rect? _recordedArea;
  Size? _recordedWindow;

  /// The [PanelPatternWindow] this surface sits in, found when it attaches.
  RenderLeaderLayer? _window;

  set recolorLater(bool value) {
    if (value == _recolorLater) return;
    _recolorLater = value;
    if (!value && _stale.contains(this)) {
      _clearRecording();
      markNeedsPaint();
    }
  }

  // Painted under the recording, whose tiles hold only the pattern; a page
  // surface has none.
  set color(Color? value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  set pattern(BackgroundPatternPainter value) {
    if (!value.shouldRepaint(_pattern)) return;
    final wasVisible = _pattern.isVisible;
    final recolor =
        _recolorLater && _recording != null && value.sameShapes(_pattern);
    _pattern = value;
    if (recolor) {
      _stale.add(this);
      _recolorTimer?.cancel();
      _recolorTimer = Timer(_recolorDelay, _recolorStale);
      return;
    }
    _clearRecording();
    if (wasVisible != value.isVisible) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  set pixelRatio(double value) {
    if (value == _pixelRatio) return;
    _pixelRatio = value;
    _clearRecording();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _pattern.isVisible;

  // An opaque panel, like the colored box it replaces.
  @override
  bool hitTestSelf(Offset position) => true;

  /// This surface's bounds in window coordinates.
  Rect get _area => _window == null
      ? Offset.zero & size
      : MatrixUtils.transformRect(getTransformTo(_window), Offset.zero & size);

  Size get _windowSize => _window?.size ?? size;

  bool _covers(Rect area) {
    final recorded = _recordedArea;
    return recorded != null &&
        _recordedWindow == _windowSize &&
        recorded.left <= area.left &&
        recorded.top <= area.top &&
        recorded.right >= area.right &&
        recorded.bottom >= area.bottom;
  }

  void _clearRecording() {
    if (_stale.remove(this) && _stale.isEmpty) {
      _recolorTimer?.cancel();
      _recolorTimer = null;
    }
    _PatternTiles.release(_tiles);
    _tiles = const [];
    _recording?.dispose();
    _recording = null;
    _recordedArea = null;
    _recordedWindow = null;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _window = null;
    for (var node = parent; node != null; node = node.parent) {
      if (node is RenderLeaderLayer && node.link == PanelPatternWindow._link) {
        _window = node;
        break;
      }
    }
    _surfaces.add(this);
    if (_watchingFrames) return;
    _watchingFrames = true;
    // A surface moved by an ancestor's layer is not repainted, so check
    // after every frame that its recording still covers it. This runs after
    // the frame's paint, so frames with no recorded pattern skip the check.
    final scheduler = SchedulerBinding.instance;
    scheduler.addPersistentFrameCallback((_) {
      if (!_surfaces.any((surface) => surface._recording != null)) return;
      scheduler.addPostFrameCallback((_) {
        for (final surface in _surfaces) {
          if (surface._recording != null &&
              surface.hasSize &&
              !surface._covers(surface._area)) {
            surface.markNeedsPaint();
          }
        }
      });
    });
  }

  @override
  void detach() {
    _surfaces.remove(this);
    _window = null;
    // Redrawn in its current colors if it attaches again.
    if (_stale.contains(this)) _clearRecording();
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
    if (_color case final color?) {
      context.canvas.drawRect(offset & size, Paint()..color = color);
    }
    if (_pattern.isVisible) {
      final area = _area;
      if (!_covers(area)) {
        final recorded = area.inflate(_margin);
        final recorder = ui.PictureRecorder();
        // Hold the new tiles before letting go of the old, to keep shared ones.
        final tiles = _PatternTiles.paint(
          Canvas(recorder),
          _pattern,
          _windowSize,
          recorded,
          _pixelRatio,
        );
        _clearRecording();
        _recording = recorder.endRecording();
        _tiles = tiles;
        _recordedArea = recorded;
        _recordedWindow = _windowSize;
      }
      _clip.layer = context.pushClipRect(true, offset, Offset.zero & size, (
        context,
        offset,
      ) {
        final follower = (_follower.layer ??= FollowerLayer(link: _alone))
          ..link = _window == null ? _alone : PanelPatternWindow._link
          // Outside a window, the surface is its own window.
          ..unlinkedOffset = offset - area.topLeft;
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

/// Squares of a pattern, drawn once into images that every surface showing
/// them shares. A square is a whole number of physical pixels, placed on
/// physical pixels, and holds only the pattern: a surface paints its color
/// under it, so a color change keeps the tiles.
abstract final class _PatternTiles {
  /// A tile's side, in physical pixels.
  static const _side = 512;

  /// Tiles no surface holds that are kept for the next one to ask.
  static const _spare = 48;

  static final _images = <Record, ui.Image>{};
  static final _holders = <Record, int>{};

  /// Unheld tiles, the longest unheld first.
  static final _unheld = <Record>{};
  static final _paint = Paint()..filterQuality = FilterQuality.none;

  /// Draws [pattern] over [area] of a [window]-sized pattern and returns
  /// the tiles it holds, for [release].
  static List<Record> paint(
    Canvas canvas,
    BackgroundPatternPainter pattern,
    Size window,
    Rect area,
    double pixelRatio,
  ) {
    final held = <Record>[];
    final extent = _side / pixelRatio;
    final anchored = pattern._anchored(window);
    canvas
      ..save()
      ..scale(1 / pixelRatio);
    for (var y = (area.top / extent).floor(); y * extent < area.bottom; y++) {
      for (var x = (area.left / extent).floor(); x * extent < area.right; x++) {
        final tile = Rect.fromLTWH(x * extent, y * extent, extent, extent);
        // Only tiles reaching something placed in the window follow its size.
        final key = (
          pattern._key,
          pixelRatio,
          x,
          y,
          anchored.any(tile.overlaps) ? window : pattern._scope(window, tile),
        );
        _holders[key] = (_holders[key] ?? 0) + 1;
        _unheld.remove(key);
        held.add(key);
        canvas.drawImage(
          _images[key] ??= _draw(pattern, window, tile, pixelRatio),
          tile.topLeft * pixelRatio,
          _paint,
        );
      }
    }
    canvas.restore();
    return held;
  }

  static ui.Image _draw(
    BackgroundPatternPainter pattern,
    Size window,
    Rect tile,
    double pixelRatio,
  ) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(pixelRatio)
      ..translate(-tile.left, -tile.top);
    pattern.paintArea(canvas, window, tile);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(_side, _side);
    picture.dispose();
    return image;
  }

  /// Lets go of [tiles]; those no surface holds any more wait as spares.
  static void release(List<Record> tiles) {
    for (final key in tiles) {
      final holders = _holders[key]! - 1;
      if (holders > 0) {
        _holders[key] = holders;
      } else {
        _holders.remove(key);
        _unheld.add(key);
      }
    }
    while (_unheld.length > _spare) {
      final oldest = _unheld.first;
      _unheld.remove(oldest);
      _images.remove(oldest)!.dispose();
    }
  }
}

/// Paints a background pattern [style] in the theme's colors. Surfaces draw
/// their area of a window-sized pattern with [paintArea]; as a
/// [CustomPainter] it fills a preview card on its own.
class const BackgroundPatternPainter({
  required final AppThemeData theme,
  required final NavPanelOverlayStyle style,

  /// Degrees clockwise: the stripes' slant from vertical. Fixed to the
  /// pattern, so it never changes as panels resize or move.
  final int angle = DefaultSettings.patternAngle,

  /// How the Lines style sways: 0 straight, 0.5 smooth waves, 1 zigzag.
  final double wave = DefaultSettings.patternWave,

  /// Scales every color's opacity, from the pattern strength setting.
  final double strength = 1,

  /// Stronger colors for small preview cards.
  final bool preview = false,
}) extends CustomPainter {
  bool get isVisible => strength > 0 && style != NavPanelOverlayStyle.none;

  /// [color] at [alpha], scaled by [strength].
  Color _tone(Color color, double alpha) =>
      color.withValues(alpha: (alpha * strength).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) =>
      paintArea(canvas, size, Offset.zero & size);

  /// Draws the part of a [size]-sized pattern inside [area].
  void paintArea(Canvas canvas, Size size, Rect area) {
    if (area.isEmpty) return;
    switch (style) {
      case NavPanelOverlayStyle.none:
        return;
      case NavPanelOverlayStyle.diagonalStripes:
        _paintStripes(canvas, area, sway: wave > 0 ? _sway : null);
      case NavPanelOverlayStyle.crosshatch:
        // Keeps its own slant: the angle would fold its two sets together.
        _paintStripes(canvas, area, degrees: 30, alphaScale: 0.7);
        _paintStripes(canvas, area, degrees: -30, alphaScale: 0.7);
      case NavPanelOverlayStyle.stars:
        _paintStars(canvas, area);
      case NavPanelOverlayStyle.halloween:
        _paintHalloween(canvas, Offset.zero & size, area);
      case NavPanelOverlayStyle.christmas:
        _paintChristmas(canvas, Offset.zero & size, area);
        _paintLights(canvas, Offset.zero & size, area);
    }
  }

  /// What [tile] depends on in the window, away from [_anchored]: Christmas
  /// has stars down to half its height and snow down to three quarters.
  Object _scope(Size window, Rect tile) =>
      style == NavPanelOverlayStyle.christmas
      ? (tile.top < window.height * 0.5, tile.top < window.height * 0.75)
      : 0;

  /// Where the pattern is placed in the [window] rather than fixed to its
  /// origin, with room for glows and for the scattered shapes kept clear.
  List<Rect> _anchored(Size window) {
    final shortest = window.shortestSide;
    switch (style) {
      case NavPanelOverlayStyle.halloween:
        // The webs, the scratch, and the bats left out around them.
        final reach = math.min(280.0, shortest * 0.6);
        final claw = math.min(220.0, shortest * 0.42);
        return [
          Rect.fromCircle(center: Offset(window.width, 0), radius: reach + 76),
          Rect.fromCircle(center: Offset.zero, radius: reach * 0.6 + 76),
          Rect.fromCircle(
            center: window.center(Offset.zero),
            radius: claw + 96,
          ),
        ];
      case NavPanelOverlayStyle.christmas:
        // The trees with their topper's glow, the lights' last bulbs, and
        // the lines the stars and the snow stop at.
        final size = math.min(window.height * 0.55, 420.0) / 1.95;
        return [
          Rect.fromLTRB(
            window.width / 2 - size * 1.75 - 8,
            window.height - size * 2.3 - 20,
            window.width / 2 + size * 1.75 + 8,
            window.height,
          ),
          Rect.fromLTRB(window.width - 48, 0, window.width, 40),
          for (final share in const [0.5, 0.75])
            Rect.fromLTRB(
              double.negativeInfinity,
              window.height * share - 24,
              double.infinity,
              window.height * share + 24,
            ),
        ];
      default:
        return const [];
    }
  }

  // ── stripes at the pattern angle, and stars ────────────────────────────────

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
    final paints = [
      for (final color in _stripeColors(alphaScale)) Paint()..color = color,
    ];
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
    // Every stripe sways alike, so each sample's sway is worked out once.
    final sways = [for (final y in ys) sway!(y)];
    for (
      var index = (bounds.left / period).floor();
      index <= (bounds.right / period).ceil();
      index++
    ) {
      final paint = paints[index % paints.length];
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
          for (final (i, y) in ys.indexed) Offset(left + sways[i], y),
          for (var i = ys.length - 1; i >= 0; i--)
            Offset(left + stripeW + sways[i], ys[i]),
        ], true),
        paint,
      );
    }
    canvas.restore();
  }

  /// Scatters shapes over a [cell]-sized jittered grid: each cell holds at
  /// most one, at a random spot inside it, and cells past the [filled] share
  /// stay empty, so no rows or columns show. [add] gets each shape's tier (0
  /// the largest, picked by the cumulative [odds], the rest the last tier),
  /// center, radius (its tier's, shrunk by up to the [vary] share) and a
  /// steady random turn from -1 to 1. Cells reach one past each side of
  /// [area], so glows cross a surface's edge, and every surface places the
  /// same shapes.
  static void _scatter(
    Rect area, {
    required double cell,
    required List<double> radii,
    required List<double> odds,
    required void Function(int tier, Offset center, double radius, double turn)
    add,
    double filled = 0.75,
    double vary = 0,
  }) {
    for (
      var row = (area.top / cell).floor() - 1;
      row * cell < area.bottom + cell;
      row++
    ) {
      for (
        var col = (area.left / cell).floor() - 1;
        col * cell < area.right + cell;
        col++
      ) {
        if (_noise(col, row, 0) >= filled) continue;
        final size = _noise(col, row, 1);
        var tier = odds.indexWhere((odd) => size < odd);
        if (tier < 0) tier = radii.length - 1;
        final radius = radii[tier] * (1 - vary * _noise(col, row, 5));
        // Anywhere a shape clears its cell's edges, so neighbours never touch.
        final inset = radius + 2;
        final room = cell - 2 * inset;
        add(
          tier,
          Offset(
            col * cell + inset + _noise(col, row, 2) * room,
            row * cell + inset + _noise(col, row, 3) * room,
          ),
          radius,
          _noise(col, row, 4) * 2 - 1,
        );
      }
    }
  }

  /// The large, medium and small shapes' strengths.
  List<double> get _tierAlphas =>
      preview ? const [0.6, 0.38, 0.24] : const [0.4, 0.24, 0.14];

  /// A soft halo of [path], blurred by [blur], for drawing under it.
  void _glow(
    Canvas canvas,
    Path path,
    Color color,
    double alpha,
    double blur,
  ) => canvas.drawPath(
    path,
    Paint()
      ..color = _tone(color, alpha)
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
  );

  /// [points] in units of [radius] around [center], turned by [turn] radians.
  static List<Offset> _shape(
    Offset center,
    double radius,
    double turn,
    List<(double, double)> points,
  ) {
    final (cosine, sine) = (math.cos(turn), math.sin(turn));
    return [
      for (final (x, y) in points)
        center + Offset(x * cosine - y * sine, x * sine + y * cosine) * radius,
    ];
  }

  void _paintStars(Canvas canvas, Rect area) {
    // Large accent, medium secondary and small faint accent four-pointed
    // stars, each one path; the larger glow, the largest most.
    final paths = [Path(), Path(), Path()];
    _scatter(
      area,
      cell: 40,
      radii: const [12, 8, 4.5],
      odds: const [0.15, 0.5],
      add: (tier, center, radius, _) => _addStar(paths[tier], center, radius),
    );
    final alphas = _tierAlphas;
    _glow(canvas, paths[0], theme.accent, alphas[0] * 1.2, 8);
    _glow(canvas, paths[1], theme.secondary, alphas[1] * 0.6, 3.5);
    _fillLayers(canvas, paths, alphas);
  }

  void _paintHalloween(Canvas canvas, Rect window, Rect area) {
    // A large cobweb in the top-right corner with a spider on it, a smaller
    // one in the top-left corner, one huge glowing claw scratch across the
    // middle, and a few bats of very different sizes around them.
    final silk = Path();
    final spiders = Path();
    final legs = Path();
    final corner = window.topRight;
    final reach = math.min(280.0, window.shortestSide * 0.6);
    _addWeb(silk, corner, const Offset(-1, 1), reach);
    final small = reach * 0.6;
    _addWeb(silk, window.topLeft, const Offset(1, 1), small);
    final spider = (window.shortestSide * 0.05).clamp(3.0, 7.0);
    // Partway out along the web's middle spoke.
    _addSpider(
      spiders,
      legs,
      corner + const Offset(-1, 1) * (reach * 0.42 / math.sqrt2),
      spider,
    );
    final scratches = Path();
    final claw = math.min(220.0, window.shortestSide * 0.42);
    _addScratch(scratches, window.center, claw, -0.45);
    final bats = Path();
    _scatter(
      area,
      cell: 130,
      radii: const [34],
      odds: const [],
      vary: 0.6,
      filled: 0.32,
      add: (_, center, radius, turn) {
        // None in the webs or on the scratch.
        if ((center - corner).distance < reach + radius ||
            (center - window.topLeft).distance < small + radius ||
            (center - window.center).distance < claw * 0.8 + radius) {
          return;
        }
        bats.addPolygon(_shape(center, radius, turn * 0.35, _bat), true);
      },
    );
    final [large, medium, _] = _tierAlphas;
    // The silk passes behind the spiders.
    canvas
      ..save()
      ..clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(area.inflate(1))
          ..addPath(spiders, Offset.zero),
      )
      ..drawPath(
        silk,
        Paint()
          ..color = _tone(theme.textPrimary, medium * 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      )
      ..restore();
    final dark = _tone(theme.secondary, large);
    canvas
      ..drawPath(
        legs,
        Paint()
          ..color = dark
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round,
      )
      ..drawPath(spiders, Paint()..color = dark)
      ..drawPath(bats, Paint()..color = dark);
    // Glowing: lighter than the accent on a dark background, the accent
    // itself on a light one.
    final light = theme.isDark
        ? Color.lerp(theme.accent, Colors.white, 0.6)!
        : theme.accent;
    _glow(canvas, scratches, light, large * 1.6, 4 + claw * 0.04);
    canvas.drawPath(scratches, Paint()..color = _tone(light, large * 2.2));
  }

  /// A cobweb from [corner], reaching [reach] into the window towards
  /// [into]: spokes fanning across the corner, joined by rings that sag
  /// towards it between them.
  static void _addWeb(Path silk, Offset corner, Offset into, double reach) {
    const spokes = 7;
    const rings = 7;
    Offset at(int spoke, double distance) {
      final angle = spoke / (spokes - 1) * math.pi / 2;
      return corner +
          Offset(into.dx * math.cos(angle), into.dy * math.sin(angle)) *
              distance;
    }

    for (var spoke = 0; spoke < spokes; spoke++) {
      final end = at(spoke, reach);
      silk
        ..moveTo(corner.dx, corner.dy)
        ..lineTo(end.dx, end.dy);
    }
    for (var ring = 1; ring <= rings; ring++) {
      final distance = reach * ring / rings;
      final start = at(0, distance);
      silk.moveTo(start.dx, start.dy);
      for (var spoke = 1; spoke < spokes; spoke++) {
        final from = at(spoke - 1, distance);
        final to = at(spoke, distance);
        final sag = corner + ((from + to) / 2 - corner) * 0.88;
        silk.quadraticBezierTo(sag.dx, sag.dy, to.dx, to.dy);
      }
    }
  }

  /// A spider of [radius] at [center]: a round body with its head above in
  /// [body], and four bent legs a side in [legs].
  static void _addSpider(Path body, Path legs, Offset center, double radius) {
    body
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..addOval(
        Rect.fromCircle(
          center: center.translate(0, -radius * 1.25),
          radius: radius * 0.6,
        ),
      );
    for (final side in const [-1.0, 1.0]) {
      for (var leg = 0; leg < 4; leg++) {
        final root = center.translate(
          side * radius * 0.6,
          (leg - 2) * radius * 0.55,
        );
        final knee = root.translate(
          side * radius * 1.1,
          -radius * (0.7 - leg * 0.35),
        );
        final foot = knee.translate(side * radius * 0.5, radius * 0.9);
        legs
          ..moveTo(root.dx, root.dy)
          ..lineTo(knee.dx, knee.dy)
          ..lineTo(foot.dx, foot.dy);
      }
    }
  }

  /// A claw scratch of [radius] at [center], turned by [turn] radians:
  /// three thin curved slivers, the left one middling, the middle one the
  /// longest and the right one the shortest.
  static void _addScratch(
    Path path,
    Offset center,
    double radius,
    double turn,
  ) {
    for (final (x, length) in const [(-0.3, 0.8), (0.0, 1.0), (0.3, 0.6)]) {
      final [start, out, end, back] = _shape(center, radius, turn, [
        (x - 0.1, -length),
        (x + 0.18, 0),
        (x + 0.1, length),
        (x + 0.1, 0),
      ]);
      path
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(out.dx, out.dy, end.dx, end.dy)
        ..quadraticBezierTo(back.dx, back.dy, start.dx, start.dy)
        ..close();
    }
  }

  void _paintChristmas(Canvas canvas, Rect window, Rect area) {
    // A big tree standing on the middle of the window's bottom edge with a
    // glowing star on top, two smaller trees just behind it, one a side,
    // and snowflakes and glowing tiny stars scattered in front of them.
    final size = math.min(window.height * 0.55, 420.0) / 1.95;
    final middle = window.center.dx;
    // A tree of [size] standing on the bottom edge at [x].
    Path tree(double x, double size) {
      final path = Path();
      final center = Offset(x, window.bottom - size * 0.95);
      for (final part in _tree) {
        path.addPolygon(_shape(center, size, 0, part), true);
      }
      return path;
    }

    final bigTree = tree(middle, size);
    // Their lowest tiers just tucked behind the big tree's.
    final side = size * 0.72;
    final apart = (0.82 + 0.82 * 0.72 - 0.3) * size;
    final sideTrees = Path.combine(
      PathOperation.difference,
      tree(middle - apart, side)
        ..addPath(tree(middle + apart, side), Offset.zero),
      bigTree,
    );
    final topper = Path();
    _addStar(topper, Offset(middle, window.bottom - size * 1.95), size * 0.16);
    final flakes = Path();
    final stars = Path();
    _scatter(
      area,
      cell: 56,
      radii: const [16, 5],
      odds: const [0.3],
      vary: 0.5,
      add: (tier, center, radius, turn) {
        // Clear of the lights along the top, and in the upper part of the
        // window: stars in its top half, snow in its top three quarters.
        if (center.dy - radius < window.top + 24) return;
        final reach = window.top + window.height * (tier > 0 ? 0.5 : 0.75);
        if (center.dy > reach) return;
        if (tier > 0) {
          _addStar(stars, center, radius);
          return;
        }
        // Six arms, each forked partway out, at a random turn.
        for (var arm = 0; arm < 6; arm++) {
          final angle = (turn + arm * 2) * math.pi / 6;
          final tip = center + Offset.fromDirection(angle, radius);
          final fork = center + Offset.fromDirection(angle, radius * 0.55);
          flakes
            ..moveTo(center.dx, center.dy)
            ..lineTo(tip.dx, tip.dy);
          for (final side in const [-1, 1]) {
            final end =
                fork +
                Offset.fromDirection(angle + side * math.pi / 4, radius * 0.32);
            flakes
              ..moveTo(fork.dx, fork.dy)
              ..lineTo(end.dx, end.dy);
          }
        }
      },
    );
    final [large, medium, _] = _tierAlphas;
    canvas
      ..drawPath(
        sideTrees,
        Paint()..color = _tone(theme.secondary, medium * 0.6),
      )
      ..drawPath(bigTree, Paint()..color = _tone(theme.secondary, medium * 1.4))
      ..drawPath(
        flakes,
        Paint()
          ..color = _tone(theme.accent, large)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
    _glow(canvas, stars, theme.accent, medium * 1.4, 3);
    canvas.drawPath(stars, Paint()..color = _tone(theme.accent, medium * 1.3));
    _glow(canvas, topper, theme.accent, large * 1.5, 4 + size * 0.06);
    canvas.drawPath(topper, Paint()..color = theme.accent);
  }

  /// String lights along the window's top edge: a wire sagging between
  /// hooks, with glowing bulbs hanging from it, alternately accent and
  /// secondary.
  void _paintLights(Canvas canvas, Rect window, Rect area) {
    // Only while their glow can reach the area.
    if (area.top > window.top + 40) return;
    const span = 56.0;
    const sag = 9.0;
    Offset at(double x) =>
        window.topLeft +
        Offset(x, 2 + sag * math.sin(math.pi * (x % span) / span));
    final wire = Path()..moveTo(at(0).dx, at(0).dy);
    for (var x = 4.0; x <= window.width; x += 4) {
      wire.lineTo(at(x).dx, at(x).dy);
    }
    // Every half span, at the hooks and the dips, clear of the corners.
    final sockets = Path();
    final bulbs = [Path(), Path()];
    for (var bulb = 1; bulb * span / 2 < window.width - 12; bulb++) {
      final hook = at(bulb * span / 2);
      sockets.addRect(
        Rect.fromCenter(center: hook.translate(0, 2), width: 4, height: 3),
      );
      bulbs[bulb % 2].addOval(
        Rect.fromCenter(center: hook.translate(0, 7), width: 6, height: 9),
      );
    }
    final [large, _, small] = _tierAlphas;
    canvas.drawPath(
      wire,
      Paint()
        ..color = _tone(theme.textPrimary, small * 2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawPath(
      sockets,
      Paint()..color = _tone(theme.textPrimary, small * 3),
    );
    for (final (index, color) in [theme.accent, theme.secondary].indexed) {
      _glow(canvas, bulbs[index], color, large * 1.4, 5);
      canvas.drawPath(bulbs[index], Paint()..color = _tone(color, large * 2));
    }
  }

  // Shapes in units of their radius, y down.

  /// A bat with its wings spread, their lower edges scalloped.
  static const _bat = [
    (0.12, -0.28), (0.35, -0.39), (0.65, -0.59), (1.0, -0.39), //
    (0.86, 0.0), (0.74, -0.11), (0.6, 0.14), (0.46, 0.0), (0.3, 0.25),
    (0.14, 0.17), (0.0, 0.42), (-0.14, 0.17), (-0.3, 0.25), (-0.46, 0.0),
    (-0.6, 0.14), (-0.74, -0.11), (-0.86, 0.0), (-1.0, -0.39), //
    (-0.65, -0.59), (-0.35, -0.39), (-0.12, -0.28), (-0.1, -0.59),
    (-0.04, -0.36), (0.04, -0.36), (0.1, -0.59),
  ];

  /// A Christmas tree's three tiers and trunk, wound alike so they join.
  static const _tree = [
    [(0.0, -1.0), (0.42, -0.38), (-0.42, -0.38)],
    [(0.0, -0.66), (0.62, 0.12), (-0.62, 0.12)],
    [(0.0, -0.3), (0.82, 0.62), (-0.82, 0.62)],
    [(-0.14, 0.62), (0.14, 0.62), (0.14, 0.95), (-0.14, 0.95)],
  ];

  /// Adds a four-pointed star of [radius] at [center], its sides curving in.
  static void _addStar(Path path, Offset center, double radius) {
    final pinch = radius * 0.16;
    final tips = [
      center.translate(0, -radius),
      center.translate(radius, 0),
      center.translate(0, radius),
      center.translate(-radius, 0),
    ];
    final bends = [
      center.translate(pinch, -pinch),
      center.translate(pinch, pinch),
      center.translate(-pinch, pinch),
      center.translate(-pinch, -pinch),
    ];
    path.moveTo(tips[0].dx, tips[0].dy);
    for (var i = 0; i < 4; i++) {
      final tip = tips[(i + 1) % 4];
      path.quadraticBezierTo(bends[i].dx, bends[i].dy, tip.dx, tip.dy);
    }
    path.close();
  }

  /// A steady value in [0, 1) for grid cell ([x], [y]), one per [salt]: the
  /// same wherever and however much of the pattern an area draws.
  static double _noise(int x, int y, int salt) {
    var hash =
        (x * 0x27d4eb2d + y * 0x165667b1 + salt * 0x9e3779b1) & 0xffffffff;
    hash = ((hash ^ (hash >> 15)) * 0x85ebca6b) & 0xffffffff;
    hash = ((hash ^ (hash >> 13)) * 0xc2b2ae35) & 0xffffffff;
    return (hash ^ (hash >> 16)) / 0x100000000;
  }

  /// Fills each of [paths] with its accent, secondary or faint accent tone,
  /// so a page-sized area stays three draw calls.
  void _fillLayers(Canvas canvas, List<Path> paths, List<double> alphas) {
    final colors = [theme.accent, theme.secondary, theme.accent];
    for (var i = 0; i < 3; i++) {
      canvas.drawPath(paths[i], Paint()..color = _tone(colors[i], alphas[i]));
    }
  }

  /// Everything the drawing depends on.
  Record get _key => (
    preview,
    strength,
    angle,
    wave,
    theme.accent,
    theme.secondary,
    // Halloween's silk and glow and Christmas's wire follow it.
    theme.isDark,
    style,
  );

  /// Whether this draws the same shapes as [other], only in other colors.
  bool sameShapes(BackgroundPatternPainter other) =>
      (preview, strength, angle, wave, style) ==
      (other.preview, other.strength, other.angle, other.wave, other.style);

  @override
  bool shouldRepaint(covariant BackgroundPatternPainter oldDelegate) =>
      oldDelegate._key != _key;
}
