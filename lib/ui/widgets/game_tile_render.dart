/// The render object behind [GameTile]: a library card laid out and painted
/// in one place, with the animations of its reveal, hover, selection, fetch
/// status and chips. It draws what a card of widgets would, so a card needs
/// no widgets, elements or layers of its own.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart'
    show
        MouseTrackerAnnotation,
        PointerEnterEventListener,
        PointerExitEventListener;
import 'package:material_ui/material_ui.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/color_utils.dart';
import '../../models/game.dart';
import '../../providers/app_providers.dart' show GameFetchStatus;
import '../pages/home_sections/game_card_reveal.dart' show RevealViewportBox;
import 'game_card_badges.dart';
import 'game_card_painters.dart';
import 'game_card_tags.dart';
import 'game_cover_image.dart';
import 'platform_icon.dart';

enum GameTileDesign() {
  grid,
  list,
  slim,
}

/// Where the tile's widgets sit: tooltips over its chips, a fetch spinner.
enum GameTileSlot() {
  newChip,
  deadline,
  rating,
  platform,
  fetch,
  selected,
  spinner,
}

/// How the tile's texts and icons are styled, as [Text] and [Icon] would be
/// at its place in the tree.
typedef GameTileText = ({
  TextStyle style,
  TextScaler scaler,
  Locale? locale,
  TextHeightBehavior? heightBehavior,
  TextWidthBasis widthBasis,
  bool bold,
  IconThemeData icons,
  double pixelRatio,
});

/// What a tile shows, as its state last built it. [titleVisible]: a grid
/// card shows its title without a cover, or with a broken one. [images]: how
/// the cover resolves, as an [Image] here would. [showTags]: a list card has
/// a tag row, shown while [tagsVisible] (it may show only while hovered).
typedef GameTileData = ({
  GameTileDesign design,
  Game game,
  AppThemeData theme,
  GameTileText text,
  bool hovered,
  bool selected,
  bool showNew,
  bool showPlatform,
  bool showRatings,
  bool showDeadline,
  GameFetchStatus? fetchStatus,
  bool titleVisible,
  ImageConfiguration images,
  bool showTags,
  bool tagsVisible,
});

class const GameTileBox({
  super.key,
  required final GameTileData data,
  required final TickerProvider vsync,
  required final ValueChanged<PointerEvent> onPointer,
  required final PointerEnterEventListener onEnter,
  required final PointerExitEventListener onExit,

  /// Called after the frame in which the cover failed to load.
  required final VoidCallback onCoverError,

  /// Told while the cover loads, as [GameCoverImage] tells its scope.
  final CoverLoadListener? coverListener,

  /// How far the card has revealed, if it reveals, and what to call when it
  /// is first painted in view.
  final Animation<double>? reveal,
  final VoidCallback? onRevealPaint,
  super.children,
}) extends MultiChildRenderObjectWidget {
  @override
  RenderGameTile createRenderObject(BuildContext context) {
    final tile = RenderGameTile(data: data, vsync: vsync);
    updateRenderObject(context, tile);
    return tile;
  }

  @override
  void updateRenderObject(BuildContext context, RenderGameTile renderObject) =>
      renderObject
        ..data = data
        ..onPointer = onPointer
        ..onEnter = onEnter
        ..onExit = onExit
        ..onCoverError = onCoverError
        ..coverListener = coverListener
        ..reveal = reveal
        ..onRevealPaint = onRevealPaint;
}

/// Places [child] over one of the tile's chips, or where its spinner spins.
class const GameTileSlotWidget({
  super.key,
  required final GameTileSlot slot,
  required super.child,
}) extends ParentDataWidget<GameTileParentData> {
  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as GameTileParentData;
    if (data.slot == slot) return;
    data.slot = slot;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => GameTileBox;
}

class GameTileParentData extends ContainerBoxParentData<RenderBox> {
  GameTileSlot? slot;
}

/// A badge: a decorated box and what is drawn in it, at [offset] in the card.
class _Chip(
  final Size size,
  final BoxDecoration decoration,
  final List<(TextPainter, Offset)> contents, {
  final GameTileSlot? slot,
}) {
  Offset offset = Offset.zero;

  Rect get rect => offset & size;

  void paint(Canvas canvas, Offset origin) {
    _paintDecoration(canvas, origin + offset & size, decoration);
    for (final (painter, at) in contents) {
      _paintText(canvas, painter, origin + offset + at);
    }
  }
}

/// Paints [painter] as a [Text]'s paragraph: clipped to its box once its
/// text runs past its lines.
void _paintText(Canvas canvas, TextPainter painter, Offset at, [Size? box]) {
  final size = box ?? painter.size;
  final clip = painter.didExceedMaxLines || size.width < painter.width;
  if (clip) {
    canvas
      ..save()
      ..clipRect(at & size);
  }
  painter.paint(canvas, at);
  if (clip) canvas.restore();
}

/// Where [Center] puts a [child] in [area].
Offset _center(Rect area, Size child) =>
    area.topLeft +
    Offset(
      (area.width - child.width) / 2.0,
      (area.height - child.height) / 2.0,
    );

void _paintDecoration(Canvas canvas, Rect rect, Decoration decoration) {
  final painter = decoration.createBoxPainter();
  painter.paint(
    canvas,
    rect.topLeft,
    ImageConfiguration(size: rect.size, textDirection: TextDirection.ltr),
  );
  painter.dispose();
}

/// Saves [canvas] scaled by [scale] about [center].
void _scaleAbout(Canvas canvas, Offset center, double scale) => canvas
  ..save()
  ..translate(center.dx, center.dy)
  ..scale(scale)
  ..translate(-center.dx, -center.dy);

/// Starts a layer at [alpha] unless it is opaque; whether it did, to restore.
bool _fadeLayer(Canvas canvas, int alpha, [Rect? bounds]) {
  if (alpha >= 255) return false;
  canvas.saveLayer(bounds, Paint()..color = Color.fromARGB(alpha, 0, 0, 0));
  return true;
}

/// A fetch status overlay fading in or out, as [AnimatedSwitcher] fades them.
typedef _Fade = ({GameFetchStatus status, AnimationController controller});

class RenderGameTile({
  required var GameTileData _data,
  required final TickerProvider vsync,
}) extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, GameTileParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, GameTileParentData>,
        RevealViewportBox
    implements MouseTrackerAnnotation {
  /// Its callbacks are set as [GameTileBox] updates it.
  this {
    _selectTo(_data.selected, animate: false);
    _switchFetch(null, _data.fetchStatus);
    for (final fade in [..._fades, ..._fetchIcons]) {
      fade.controller.value = 1;
    }
    _tintTo = _tintFor(_data);
    _tagsShown = _data.tagsVisible;
  }

  late ValueChanged<PointerEvent> onPointer;
  @override
  late PointerEnterEventListener onEnter;
  @override
  late PointerExitEventListener onExit;
  late VoidCallback onCoverError;
  CoverLoadListener? coverListener;

  GameTileData get data => _data;
  set data(GameTileData value) {
    if (identical(value, _data)) return;
    final old = _data;
    _data = value;
    if (value.text != old.text) _clearTexts();
    hover(value.hovered);
    if (value.selected != old.selected) _selectTo(value.selected);
    if (value.fetchStatus != old.fetchStatus) {
      _switchFetch(old.fetchStatus, value.fetchStatus);
    }
    _tintTowards(_tintFor(value));
    if (value.tagsVisible != _tagsShown) {
      // Only a list card has a tag row to reveal.
      value.design == GameTileDesign.list
          ? _revealTags(value.tagsVisible)
          : _tagsShown = value.tagsVisible;
    }
    if (value.game.title != old.game.title) markNeedsSemanticsUpdate();
    markNeedsLayout();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = _data.game.title
      ..textDirection = TextDirection.ltr;
  }

  // ── Animations, made when first needed ─────────────────────────────────────

  AnimationController _controller(Duration duration) =>
      AnimationController(duration: duration, vsync: vsync)
        ..addListener(markNeedsPaint);

  /// The hover zoom and glow.
  AnimationController? _hover;
  CurvedAnimation? _hoverCurve;
  double get _hoverValue => _hoverCurve?.value ?? 0;

  bool _hovered = false;

  /// Zooms the card in or out, unless it already is.
  void hover(bool hovered) {
    if (hovered == _hovered) return;
    _hovered = hovered;
    final hover = _hover ??= _controller(const Duration(milliseconds: 180));
    _hoverCurve ??= CurvedAnimation(
      parent: hover,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    hovered ? hover.forward() : hover.reverse();
  }

  /// The selection overlay; a card built selected shows it at once.
  AnimationController? _selection;
  CurvedAnimation? _selectionCurve;

  void _selectTo(bool selected, {bool animate = true}) {
    if (_selection == null && !selected) return;
    final selection = _selection ??= _controller(kMediumAnimation);
    _selectionCurve ??= CurvedAnimation(
      parent: selection,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    if (!animate) {
      selection.value = selected ? 1 : 0;
    } else {
      selected ? selection.forward() : selection.reverse();
    }
  }

  /// The slim row's accent tint, eased as an [AnimatedContainer] eases it.
  AnimationController? _tintController;
  CurvedAnimation? _tintCurve;
  Color? _tintFrom, _tintTo;
  Color? get _tint => _tintCurve == null
      ? _tintTo
      : Color.lerp(_tintFrom, _tintTo, _tintCurve!.value);

  Color? _tintFor(GameTileData d) => d.design != GameTileDesign.slim
      ? null
      : d.theme.accent.withValues(
          alpha: d.selected
              ? (d.hovered ? 0.80 : 0.65)
              : (d.hovered ? 0.40 : 0.0),
        );

  void _tintTowards(Color? tint) {
    if (tint == _tintTo) return;
    _tintFrom = _tint;
    _tintTo = tint;
    final controller = _tintController ??= _controller(kFastAnimation);
    _tintCurve ??= CurvedAnimation(parent: controller, curve: Curves.easeOut);
    controller.forward(from: 0);
  }

  /// The fetch status overlays, oldest first, faded as an [AnimatedSwitcher]
  /// fades its children: the one shown when the card is built is not.
  final _fades = <_Fade>[];

  /// The slim fetch chip's icons, switched as an [AnimatedSwitcher] with a
  /// scale and fade would switch them: the old one shrinks and fades as the
  /// new one grows in. A chip just shown shows its icon at once.
  final _fetchIcons = <_Fade>[];

  /// Fades [fades] out and a new one of [status] in over [duration].
  void _crossFade(
    List<_Fade> fades,
    GameFetchStatus? status,
    Duration duration,
  ) {
    for (final fade in fades) {
      fade.controller.reverse();
    }
    if (status == null) return;
    final controller = _controller(duration);
    final fade = (status: status, controller: controller);
    controller.addStatusListener((animation) {
      if (!animation.isDismissed) return;
      fades.remove(fade);
      controller.dispose();
      markNeedsPaint();
    });
    fades.add(fade);
    controller.forward();
  }

  void _switchFetch(GameFetchStatus? from, GameFetchStatus? to) {
    _crossFade(_fades, to, kFastAnimation);
    if (_data.design != GameTileDesign.slim) return;
    if (from == null || to == null) {
      for (final icon in _fetchIcons) {
        icon.controller.dispose();
      }
      _fetchIcons.clear();
    }
    _crossFade(_fetchIcons, to, kVeryFastAnimation);
    if (from == null) _fetchIcons.lastOrNull?.controller.value = 1;
  }

  /// The slim row's selection and fetch chips grow in and shrink away, as an
  /// [AnimatedSize] around them does.
  AnimationController? _extrasController;
  CurvedAnimation? _extrasCurve;
  bool _hasExtrasBox = false;
  Size _extrasFrom = Size.zero, _extrasTo = Size.zero;
  Size get _extrasSize => _extrasCurve == null
      ? _extrasTo
      : Size.lerp(_extrasFrom, _extrasTo, _extrasCurve!.value)!;

  /// The value the last layout used: a change made by layout itself, as it
  /// starts the animation, needs no other.
  double _extrasLaidOut = 1;

  void _resizeExtras(Size target) {
    _extrasFrom = _extrasSize;
    _extrasTo = target;
    final controller = _extrasController ??=
        AnimationController(duration: kFastAnimation, vsync: vsync)
          ..addListener(() {
            if (_extrasController!.value != _extrasLaidOut) markNeedsLayout();
          });
    _extrasCurve ??= CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubic,
    );
    _extrasLaidOut = 0;
    controller.forward(from: 0);
  }

  /// The list card's tag row, revealed and hidden as a [SizeTransition] and
  /// a fade would: it grows up from the bottom, fading in, faster than it
  /// goes.
  AnimationController? _tagsController;
  CurvedAnimation? _tagsSize, _tagsOpacity;
  bool _tagsShown = true;

  void _revealTags(bool visible) {
    _tagsShown = visible;
    final controller = _tagsController ??= _controller(kVeryFastAnimation)
      ..reverseDuration = kFastAnimation
      ..value = visible ? 0 : 1;
    _tagsSize ??= CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCirc,
      reverseCurve: Curves.easeInOutCirc,
    );
    _tagsOpacity ??= CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
    );
    visible ? controller.forward() : controller.reverse();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _reveal?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _reveal?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    clearStills();
    _setCoverStream(null);
    _coverSettle?.cancel();
    _clearTexts();
    for (final controller in [
      _hover,
      _selection,
      _tintController,
      _extrasController,
      _tagsController,
      for (final fade in [..._fades, ..._fetchIcons]) fade.controller,
    ]) {
      controller?.dispose();
    }
    super.dispose();
  }

  // ── Cover ──────────────────────────────────────────────────────────────────

  // The cover as GameCoverImage shows it: decoded at its width in steps of
  // 128 device pixels, a width held while the card resizes, the last picture
  // kept while a new decode loads, over the placeholder until its first
  // frame, and its loading told to [coverListener].
  ImageStream? _coverStream;
  ImageInfo? _cover;
  String _coverRaw = '';
  (String, int)? _coverKey;

  /// The current stream has shown a frame, or failed.
  bool _coverLoaded = false;
  bool _coverFailed = false;
  bool _coverReported = false;
  int? _heldDecodeWidth;
  Timer? _coverSettle;
  late final _coverStreamListener = ImageStreamListener(
    _onCover,
    onError: _onCoverError,
  );

  /// GameCoverImage's held decode width: never more than one step too small.
  int _decodeWidth(int needed) {
    _coverSettle?.cancel();
    final held = _heldDecodeWidth;
    if (held == null || needed == held || needed > held + 128) {
      return _heldDecodeWidth = needed;
    }
    _coverSettle = Timer(const Duration(milliseconds: 150), () {
      _heldDecodeWidth = null;
      markNeedsLayout();
    });
    return held;
  }

  void _layoutCover(double width) {
    final game = _data.game;
    final raw = game.hasCoverImage ? game.coverImage.trim() : '';
    if (raw != _coverRaw) {
      // Another picture, as another Image: none of the last one is kept.
      _setCoverStream(null);
      _cover?.dispose();
      _cover = null;
      _coverFailed = false;
      _coverRaw = raw;
    }
    if (raw.isEmpty) return;
    final cacheWidth = _decodeWidth(
      GameCoverImage.decodeWidth(
        width.isFinite ? width : 640.0,
        _data.text.pixelRatio,
      ),
    );
    final key = (raw, cacheWidth);
    if (key == _coverKey) return;
    _coverKey = key;
    final provider = raw.startsWith('http')
        ? ResizeImage.resizeIfNeeded(
            cacheWidth,
            null,
            CachedNetworkImageProvider(raw),
          )
        : GameCoverImage.localProvider(raw, cacheWidth);
    _setCoverStream(provider.resolve(_data.images));
  }

  void _setCoverStream(ImageStream? stream) {
    if (stream != null && stream.key == _coverStream?.key) return;
    _coverStream?.removeListener(_coverStreamListener);
    _coverStream = stream;
    _coverLoaded = false;
    if (stream == null) {
      _coverKey = null;
      _reportCover(loading: false);
      return;
    }
    stream.addListener(_coverStreamListener);
    if (!_coverLoaded) _reportCover(loading: true);
  }

  void _reportCover({required bool loading}) {
    if (loading == _coverReported) return;
    _coverReported = loading;
    loading
        ? coverListener?.coverLoading(this)
        : coverListener?.coverSettled(this);
  }

  void _onCover(ImageInfo info, bool synchronousCall) {
    _cover?.dispose();
    _cover = info;
    _coverLoaded = true;
    _coverFailed = false;
    _reportCover(loading: false);
    markNeedsPaint();
  }

  void _onCoverError(Object error, StackTrace? stackTrace) {
    _coverLoaded = _coverFailed = true;
    _reportCover(loading: false);
    markNeedsPaint();
    SchedulerBinding.instance.addPostFrameCallback((_) => onCoverError());
  }

  /// The placeholder, with the picture over it once it has one.
  void _paintCover(Canvas canvas, Rect rect) {
    final cover = _coverFailed ? null : _cover;
    if (cover == null || !_coverLoaded) {
      // GameCoverImage's placeholder: its tone, a controller in the middle.
      canvas.drawRect(rect, Paint()..color = _data.theme.cardCoverPlaceholder);
      final (icon, inBox) = _placeholderIcon!;
      icon.paint(canvas, _center(rect, const Size.square(48)) + inBox);
    }
    if (cover == null) return;
    paintImage(
      canvas: canvas,
      rect: rect,
      image: cover.image,
      debugImageLabel: cover.debugLabel,
      scale: cover.scale,
      fit: BoxFit.cover,
      // CachedNetworkImage's default, and Image's.
      filterQuality: _coverRaw.startsWith('http')
          ? FilterQuality.low
          : FilterQuality.medium,
    );
  }

  (TextPainter, Offset)? _placeholderIcon;

  // ── Text ───────────────────────────────────────────────────────────────────

  var _texts = <Object, TextPainter>{};
  var _usedTexts = <Object, TextPainter>{};

  void _clearTexts() {
    for (final painter in _texts.values) {
      painter.dispose();
    }
    _texts = {};
  }

  /// The painter of a [Text] of [text] in [style], laid out as the [Text]'s
  /// paragraph would be between [minWidth] and [maxWidth].
  TextPainter _text(
    String text,
    TextStyle style, {
    int? maxLines,
    double minWidth = 0,
    double maxWidth = double.infinity,
  }) {
    final env = _data.text;
    var effective = env.style.merge(style);
    if (env.bold) {
      effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final painter = _cached(
      (text, effective, maxLines),
      () => TextPainter(
        text: TextSpan(text: text, style: effective),
        textDirection: TextDirection.ltr,
        textScaler: env.scaler,
        maxLines: maxLines,
        ellipsis: maxLines == null ? null : '…',
        locale: env.locale,
        textWidthBasis: env.widthBasis,
        textHeightBehavior: env.heightBehavior,
      ),
    );
    return painter..layout(minWidth: minWidth, maxWidth: maxWidth);
  }

  /// The painter kept for [key], or a new one, used by this layout.
  TextPainter _cached(Object key, TextPainter Function() create) =>
      _usedTexts[key] ??= _texts.remove(key) ?? create();

  /// The glyph of an [Icon] of [icon]: centred in a [size] square unless it
  /// is a [FaIcon]'s, which sizes itself.
  (TextPainter, Offset) _icon(
    IconData icon,
    double size,
    Color color, {
    bool square = true,
    double? maxWidth,
  }) {
    final icons = _data.text.icons;
    final opacity = icons.opacity ?? 1.0;
    final style = TextStyle(
      fontVariations: [
        if (icons.fill != null) FontVariation('FILL', icons.fill!),
        if (icons.weight != null) FontVariation('wght', icons.weight!),
        if (icons.grade != null) FontVariation('GRAD', icons.grade!),
        if (icons.opticalSize != null)
          FontVariation('opsz', icons.opticalSize!),
      ],
      inherit: false,
      color: opacity == 1.0
          ? color
          : color.withValues(alpha: color.a * opacity),
      fontSize: size,
      fontFamily: icon.fontFamily,
      package: icon.fontPackage,
      fontFamilyFallback: icon.fontFamilyFallback,
      shadows: icons.shadows,
      height: 1.0,
      leadingDistribution: TextLeadingDistribution.even,
    );
    final painter = _cached(
      (icon.codePoint, style),
      () => TextPainter(
        text: TextSpan(text: String.fromCharCode(icon.codePoint), style: style),
        textDirection: TextDirection.ltr,
        locale: _data.text.locale,
      ),
    );
    painter.layout(maxWidth: square ? size : maxWidth ?? double.infinity);
    return (
      painter,
      square
          ? Offset((size - painter.width) / 2, (size - painter.height) / 2)
          : Offset.zero,
    );
  }

  // ── Chips, as GameCardBadges builds them ───────────────────────────────────

  BorderRadius _radius(double extent) =>
      GameCardBadges.chipBorderRadius(_data.theme, extent);

  /// A text chip [height] tall.
  _Chip _labelChip(
    String label,
    Color color,
    Color textColor, {
    double height = 26,
    GameTileSlot? slot,
  }) {
    final text = _text(
      label,
      TextStyle(
        color: textColor,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        decoration: TextDecoration.none,
      ),
    );
    return _Chip(
      Size(text.width + 12, height),
      BoxDecoration(
        color: color.withValues(alpha: 0.95),
        borderRadius: _radius(20.0),
      ),
      [(text, Offset(6, (height - text.height) / 2))],
      slot: slot,
    );
  }

  _Chip _newChip({double height = 26}) => _labelChip(
    'NEW',
    _data.theme.secondary,
    _data.theme.onSecondaryText,
    height: height,
    slot: GameTileSlot.newChip,
  );

  _Chip _dlcChip({double height = 26}) => _labelChip(
    'DLC',
    _data.theme.accent,
    _data.theme.primaryButtonText,
    height: height,
  );

  /// A square chip around [icon], a glyph of its own size when it is not
  /// [square].
  _Chip _squareChip(
    Color color,
    double size,
    (TextPainter, Offset) icon, {
    double? iconBox,
    GameTileSlot? slot,
  }) {
    final (painter, inBox) = icon;
    final box = iconBox == null
        ? Size(painter.width, painter.height)
        : Size.square(iconBox);
    return _Chip(
      Size.square(size),
      BoxDecoration(color: color, borderRadius: _radius(size)),
      [
        (
          painter,
          Offset((size - box.width) / 2, (size - box.height) / 2) + inBox,
        ),
      ],
      slot: slot,
    );
  }

  _Chip _platformChip(double size) {
    final theme = _data.theme;
    final platform = _data.game.platformEnum;
    return _squareChip(
      theme.baseSecondary.withValues(alpha: kGameCardChipBackgroundAlpha),
      size,
      _icon(
        platformIconFor(platform).data,
        platformIconSizeFor(platform, minHeight: size),
        theme.onSecondaryText,
        square: false,
        maxWidth: size,
      ),
      slot: GameTileSlot.platform,
    );
  }

  /// The rating chip: as tall as [minHeight], or its icon and [padding].
  _Chip _ratingChip({
    required EdgeInsets padding,
    double? minHeight,
    BorderRadius? borderRadius,
  }) {
    final rating = GameCardBadges.ratingInfo(_data.theme, _data.game);
    final icon = _icon(rating.icon, 18, contrastColor(rating.fill));
    final size = Size(
      18 + padding.horizontal,
      minHeight ?? 18 + padding.vertical,
    );
    return _Chip(
      size,
      BoxDecoration(
        color: rating.fill.withValues(alpha: 0.95),
        borderRadius: borderRadius ?? _radius(minHeight ?? kBadgeHeight),
      ),
      [
        (
          icon.$1,
          Offset((size.width - 18) / 2, (size.height - 18) / 2) + icon.$2,
        ),
      ],
      slot: GameTileSlot.rating,
    );
  }

  /// The deadline chip, as [GameCardBadges.deadlineBadge]: its icon alone,
  /// or icon and text.
  _Chip _deadlineChip({bool iconOnly = false}) {
    final deadline = GameCardBadges.deadlineInfo(
      _data.theme,
      _data.game.deadlineDate,
    );
    final color = deadline.color.withValues(
      alpha: kGameCardChipBackgroundAlpha,
    );
    final foreground = contrastColor(deadline.color);
    final icon = _icon(deadline.icon, 18, foreground);
    if (iconOnly || deadline.iconOnly) {
      return _squareChip(
        color,
        kBadgeHeight,
        icon,
        iconBox: 18,
        slot: GameTileSlot.deadline,
      );
    }
    final text = _text(
      deadline.text,
      TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.w600),
    );
    // A row of icon, gap and text, at least as tall as the badge's inside.
    final rowHeight = math.max(kBadgeHeight - 8, math.max(18.0, text.height));
    return _Chip(
      Size(18 + 6 + text.width + 16, rowHeight + 8),
      BoxDecoration(color: color, borderRadius: _radius(kBadgeHeight)),
      [
        (icon.$1, Offset(8, 4 + (rowHeight - 18) / 2) + icon.$2),
        (text, Offset(8 + 18 + 6, 4 + (rowHeight - text.height) / 2)),
      ],
      slot: GameTileSlot.deadline,
    );
  }

  /// A fetch status's colour, and its icon and the icon's colour; the
  /// spinner slot spins in place of the icon while the game is fetched.
  (Color, IconData?, Color?) _fetchVisual(GameFetchStatus status) {
    final theme = _data.theme;
    return switch (status) {
      GameFetchStatus.waiting => (
        theme.secondary,
        Icons.schedule,
        theme.onSecondaryText,
      ),
      GameFetchStatus.processing => (theme.background, null, null),
      GameFetchStatus.done => (Colors.green, Icons.check, Colors.white),
      GameFetchStatus.error => (
        theme.secondary,
        Icons.error,
        theme.onSecondaryText,
      ),
    };
  }

  /// The slim row's fetch status chip; its icons are [_fetchIcons].
  _Chip _slimFetchChip(GameFetchStatus status) => _Chip(
    const Size.square(kBadgeHeight),
    BoxDecoration(
      // The spinner sits on the card itself; the other states keep their fill.
      color: status == GameFetchStatus.processing
          ? Colors.transparent
          : _fetchVisual(status).$1,
      borderRadius: _radius(kBadgeHeight),
    ),
    const [],
    slot: GameTileSlot.fetch,
  );

  /// The icons of [_fetchIcons], by status, laid out [size] square.
  var _fetchIconPainters = <GameFetchStatus, (TextPainter, Offset)>{};

  // ── Layout ─────────────────────────────────────────────────────────────────

  /// Everything placed by the last layout: chips under the overlays, and
  /// over them.
  var _under = <_Chip>[];
  var _chips = <_Chip>[];
  TextPainter? _title;
  Offset _titleOffset = Offset.zero;
  Size _titleBox = Size.zero;

  /// The slim row's extra chips and the box they grow in.
  var _extras = <_Chip>[];
  Rect _extrasBox = Rect.zero;
  Rect _fetchIconBox = Rect.zero;
  Rect? _spinnerRect;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! GameTileParentData) {
      child.parentData = GameTileParentData();
    }
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    _usedTexts = {};
    _chips = [];
    _under = [];
    _tagBadges = [];
    _extras = [];
    _spinnerRect = null;
    switch (_data.design) {
      case GameTileDesign.slim:
        _layoutSlim();
      case GameTileDesign.grid:
        _layoutGrid();
      case GameTileDesign.list:
        _layoutList();
    }
    // Painters no longer shown go.
    for (final painter in _texts.values) {
      painter.dispose();
    }
    _texts = _usedTexts;
    _usedTexts = {};
    _layoutSlots();
  }

  void _layoutSlots() {
    final rects = <GameTileSlot, Rect>{
      for (final chip in [..._under, ..._chips, ..._extras])
        if (chip.slot != null) chip.slot!: chip.rect,
      GameTileSlot.spinner: ?_spinnerRect,
    };
    var child = firstChild;
    while (child != null) {
      final parentData = child.parentData! as GameTileParentData;
      final rect = rects[parentData.slot] ?? Rect.zero;
      child.layout(BoxConstraints.tight(rect.size));
      parentData.offset = rect.topLeft;
      child = parentData.nextSibling;
    }
  }

  void _layoutSlim() {
    final d = _data;
    final game = d.game;
    final iconSize = platformIconSizeFor(
      game.platformEnum,
      minHeight: kBadgeHeight,
    );
    final base = [
      if (d.showNew) _newChip(height: kBadgeHeight),
      if (d.showDeadline && game.hasDeadline) _deadlineChip(iconOnly: true),
      if (game.isDlc) _dlcChip(height: kBadgeHeight),
      if (d.showRatings && game.reviewCount > 0)
        _ratingChip(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          minHeight: kBadgeHeight,
        ),
      if (d.showPlatform) _platformChip(kBadgeHeight),
    ];
    _fetchIconPainters = {
      for (final icon in _fetchIcons)
        if (_fetchVisual(icon.status) case (_, final data?, final color?))
          icon.status: _icon(data, iconSize, color),
    };
    final extras = [
      if (d.fetchStatus case final status?) _slimFetchChip(status),
      if (d.selected)
        _squareChip(
          d.theme.accent,
          kBadgeHeight,
          _icon(Icons.check, iconSize, d.theme.onAccentText),
          iconBox: iconSize,
          slot: GameTileSlot.selected,
        ),
    ];

    // The box the extras grow in exists while the row has any chip.
    final hasBox = base.isNotEmpty || extras.isNotEmpty;
    final target = extras.isEmpty
        ? Size.zero
        : Size(
            extras.fold(0.0, (sum, chip) => sum + chip.size.width) +
                6.0 * (extras.length - 1),
            kBadgeHeight,
          );
    if (!hasBox) {
      _hasExtrasBox = false;
    } else if (!_hasExtrasBox) {
      _hasExtrasBox = true;
      _extrasFrom = _extrasTo = target;
      _extrasLaidOut = 1;
      _extrasController?.value = 1;
    } else if (target != _extrasTo) {
      _resizeExtras(target);
    }
    _extrasLaidOut = _extrasController?.value ?? 1;
    final box = hasBox
        ? BoxConstraints.loose(const Size(double.infinity, 32))
              .constrain(_extrasSize)
        : Size.zero;

    // A row of the title, then the chips, 10 in from the sides, 6 from the
    // top and bottom, each centred on its height.
    const row = Rect.fromLTWH(10, 6, 0, 32);
    final rowWidth = size.width - 20;
    final separator = extras.isNotEmpty && base.isNotEmpty ? 6.0 : 0.0;
    final trailingWidth =
        base.fold(0.0, (sum, chip) => sum + chip.size.width) +
        6.0 * math.max(0, base.length - 1) +
        separator +
        (hasBox ? box.width : 0);
    final trailingHeight = math.max(
      base.isEmpty ? 0.0 : kBadgeHeight,
      hasBox ? box.height : 0,
    );
    final titleWidth = math.max(0.0, rowWidth - trailingWidth);
    final title = _title = _text(
      game.title,
      TextStyle(
        color: d.theme.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      maxLines: 1,
      minWidth: titleWidth,
      maxWidth: titleWidth,
    );
    _titleBox = Size(titleWidth, title.height);
    _titleOffset = Offset(row.left, row.top + (row.height - title.height) / 2);

    var x = row.left + titleWidth;
    final top = row.top + (row.height - trailingHeight) / 2;
    for (final (i, chip) in base.indexed) {
      if (i > 0) x += 6;
      chip.offset = Offset(x, top + (trailingHeight - chip.size.height) / 2);
      x += chip.size.width;
    }
    _chips = base;
    x += separator;
    _extrasBox = Offset(x, top + (trailingHeight - box.height) / 2) & box;
    // Right-aligned and centred in their box, which clips them.
    var extraX = _extrasBox.right - target.width;
    for (final chip in extras) {
      chip.offset = Offset(
        extraX,
        _extrasBox.top + (_extrasBox.height - chip.size.height) / 2,
      );
      extraX += chip.size.width + 6;
      if (chip.slot == GameTileSlot.fetch) {
        final icon = Size.square(iconSize);
        _fetchIconBox = _center(chip.rect, icon) & icon;
        final spinner = Size.square((iconSize - 3.0).clamp(10.0, iconSize));
        _spinnerRect = _center(_fetchIconBox, spinner) & spinner;
      }
    }
    _extras = extras;
  }

  /// The cover's placeholder, the selection check, and the fetch overlays'
  /// status icons and spinner, over the cover [imageWidth] wide or the card.
  void _layoutOverlays(double? imageWidth) {
    final theme = _data.theme;
    _placeholderIcon = _icon(
      Icons.videogame_asset_outlined,
      48,
      theme.textHint,
    );
    _selectionCheck = _icon(
      Icons.check,
      _data.text.icons.size ?? 24,
      theme.onAccentText,
    );
    final area = _overImage(Offset.zero & size, imageWidth);
    _fetchIconPainters = {
      for (final fade in _fades)
        if (_fetchVisual(fade.status) case (_, final data?, final color?))
          fade.status: _icon(data, kSelectionIndicatorSize, color),
    };
    _spinnerRect =
        _center(area, const Size.square(kSelectionIndicatorSize)) &
        const Size.square(kSelectionIndicatorSize);
  }

  /// The grid card: the cover, NEW top left, deadline and title
  /// bottom left, platform, rating and DLC top right.
  void _layoutGrid() {
    final d = _data;
    final game = d.game;
    _layoutCover(size.width);
    _layoutOverlays(null);
    final chips = [if (d.showNew) _newChip()..offset = const Offset(5, 5)];

    // Deadline over title, 8 in from the sides and the bottom.
    final bottom = [
      if (d.showDeadline && game.hasDeadline) _deadlineChip(),
      if (d.titleVisible) _titleChip(math.max(0.0, size.width - 32)),
    ];
    var y =
        size.height -
        8 -
        bottom.fold(0.0, (sum, chip) => sum + chip.size.height) -
        (bottom.length > 1 ? 4 : 0);
    for (final chip in bottom) {
      chip.offset = Offset(8, y);
      y += chip.size.height + 4;
    }
    chips.addAll(bottom);

    // 5 in from the top right.
    final (right, width) = _sideChips();
    _placeColumn(right, Offset(size.width - 5 - width, 5), width);
    _chips = [...chips, ...right];
  }

  /// The top right chips, platform, rating and DLC, and the width of the
  /// column they make.
  (List<_Chip>, double) _sideChips() {
    final d = _data;
    final chips = [
      if (d.showPlatform) _platformChip(kPlatformBadgeHeight),
      // Under the platform chip it is a pill as tall as its icon.
      if (d.showRatings && d.game.reviewCount > 0)
        _ratingChip(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minHeight: d.showPlatform ? null : kBadgeHeight,
          borderRadius: d.showPlatform ? _radius(20.0) : null,
        ),
      if (d.game.isDlc) _dlcChip(),
    ];
    return (
      chips,
      chips.fold(0.0, (width, chip) => math.max(width, chip.size.width)),
    );
  }

  /// Stacks [chips] down from [topLeft], 4 apart, each centred in [width].
  void _placeColumn(List<_Chip> chips, Offset topLeft, double width) {
    var y = topLeft.dy;
    for (final (i, chip) in chips.indexed) {
      if (i > 0) y += 4;
      chip.offset = Offset(topLeft.dx + (width - chip.size.width) / 2, y);
      y += chip.size.height;
    }
  }

  /// The list card: the cover on the left, NEW over it and the
  /// deadline at its bottom; right of it the title, the tag row at the
  /// bottom, and platform, rating and DLC down the right.
  void _layoutList() {
    final d = _data;
    final game = d.game;
    _layoutCover(kListCardImageWidth);
    _layoutOverlays(kListCardImageWidth);
    _under = [if (d.showNew) _newChip()..offset = const Offset(5, 5)];
    if (d.showDeadline && game.hasDeadline) {
      final deadline = _deadlineChip();
      _chips.add(
        deadline..offset = Offset(8, size.height - 8 - deadline.size.height),
      );
    }
    // The pane right of the cover, 8 in; the chips' column at its right, 5
    // from the title's.
    _pane = Rect.fromLTWH(
      kListCardImageWidth + 8,
      8,
      math.max(0.0, size.width - kListCardImageWidth - 16),
      math.max(0.0, size.height - 16),
    );
    final (side, sideWidth) = _sideChips();
    final columnWidth = side.isEmpty
        ? _pane.width
        : math.max(0.0, _pane.width - sideWidth - kElementHSpacing);
    _placeColumn(
      side,
      _pane.topLeft + Offset(columnWidth + kElementHSpacing, 0),
      sideWidth,
    );
    _chips.addAll(side);
    final title = _title = _text(
      game.title,
      TextStyle(
        color: d.theme.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      // Two lines still leave room for the tag row.
      maxLines: 2,
      maxWidth: columnWidth,
    );
    _titleOffset = _pane.topLeft;
    _titleBox = title.size;
    _tagsWidth = columnWidth;
    if (d.showTags && game.tags.isNotEmpty && (_tagsShown || _tagsShowing)) {
      _layoutTags(columnWidth);
    }
  }

  bool get _tagsShowing => (_tagsController?.value ?? 0) > 0;

  /// The list card's content pane, and its tag row's badges, its height and
  /// width.
  Rect _pane = Rect.zero;
  var _tagBadges = <_Chip>[];
  double _tagsHeight = 0;
  double _tagsWidth = 0;

  /// The tag row: as many tags as fit, in one badge, and a badge counting
  /// the rest, measured at [width] in steps of 8.
  void _layoutTags(double width) {
    final d = _data;
    final tags = d.game.tags;
    final color = tags.first.isSteamTag ? d.theme.accent : d.theme.secondary;
    final fit = fitTagLabels(
      [for (final tag in tags) tag.name],
      (width / 8).floorToDouble() * 8,
      d.text.style.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      d.text.scaler,
      TextDirection.ltr,
      d.text.locale,
    );
    final style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: contrastColor(color),
    );
    _Chip badge(String text, double maxWidth) {
      final painter = _text(
        text,
        style,
        maxLines: 1,
        maxWidth: math.max(0.0, maxWidth - kTagBadgePadding.horizontal),
      );
      // At least the badge's height inside its padding, the text centred.
      final inner = math.max(
        kBadgeHeight - kTagBadgePadding.vertical,
        painter.height,
      );
      return _Chip(
        Size(painter.width + kTagBadgePadding.horizontal, inner + 8),
        BoxDecoration(
          color: color.withValues(alpha: kGameCardChipBackgroundAlpha),
          borderRadius: _radius(kBadgeHeight),
        ),
        [(painter, Offset(8, 4 + (inner - painter.height) / 2))],
      );
    }

    // The count badge takes its own width; the label gets the rest.
    final count = fit.count.isEmpty || fit.label.isEmpty
        ? null
        : badge(fit.count, double.infinity);
    final gap = count == null ? 0.0 : kTagBadgeGap;
    final badges = [
      if (fit.label.isNotEmpty)
        badge(fit.label, width - gap - (count?.size.width ?? 0)),
      ?count,
      if (fit.label.isEmpty && fit.count.isNotEmpty) badge(fit.count, width),
    ];
    final height = badges.fold(
      0.0,
      (height, chip) => math.max(height, chip.size.height),
    );
    var x = 0.0;
    for (final chip in badges) {
      chip.offset = Offset(x, (height - chip.size.height) / 2);
      x += chip.size.width + gap;
    }
    _tagBadges = badges;
    _tagsHeight = 6 + height;
  }

  /// The title chip, its text at most [maxWidth] wide.
  _Chip _titleChip(double maxWidth) {
    final text = _text(
      _data.game.title,
      const TextStyle(fontWeight: FontWeight.w600),
      maxLines: 2,
      maxWidth: maxWidth,
    );
    return _Chip(
      Size(text.width + 16, text.height + 8),
      BoxDecoration(
        color: _data.theme.background.withValues(alpha: 0.75),
        borderRadius: _radius(kBadgeHeight),
      ),
      [(text, const Offset(8, 4))],
    );
  }

  // ── Paint ──────────────────────────────────────────────────────────────────

  /// Paints the spinner slot, if there is one; the canvas to go on with.
  Canvas _paintSpinner(PaintingContext context, Offset offset) {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final parentData = child.parentData! as GameTileParentData;
      if (parentData.slot == GameTileSlot.spinner) {
        context.paintChild(child, offset + parentData.offset);
      }
    }
    return context.canvas;
  }

  /// The USED watermark over [rect], laid out for a card [patternSize].
  void _paintUsedPattern(
    Canvas canvas,
    Rect rect,
    Color color,
    Size patternSize, {
    bool tileToCanvas = false,
  }) {
    canvas
      ..save()
      ..translate(rect.left, rect.top);
    UsedPatternPainter(
      textColor: color,
      angleDegrees: -35,
      patternSize: patternSize,
      tileToCanvas: tileToCanvas,
      devicePixelRatio: _data.text.pixelRatio,
    ).paint(canvas, rect.size);
    canvas.restore();
  }

  /// The hover shadow of the card's shell.
  List<BoxShadow>? _hoverShadow(double t, double alpha) => t > 0.001
      ? [
          BoxShadow(
            color: _data.theme.accent.withValues(alpha: t * alpha),
            blurRadius: t * 12,
            spreadRadius: t * 2,
          ),
        ]
      : null;

  // ── Reveal ─────────────────────────────────────────────────────────────────

  // The card's reveal: it grows from 90% about its
  // centre, drawn from still images of itself, the card as it waited (its
  // cover still loading) and the card with its cover in, whose cover fades
  // in over the first. Stills cost image draws, where the live card, scaled,
  // would redraw its text and overlays at every scale. Revealed, or touched
  // by a pointer, it paints as itself.
  Animation<double>? _reveal;
  set reveal(Animation<double>? value) {
    if (identical(value, _reveal)) return;
    if (attached) _reveal?.removeListener(markNeedsPaint);
    _reveal = value;
    if (attached) value?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  /// A pointer is on the card, or was during its reveal: it is drawn live.
  bool _revealLive = false;
  set revealLive(bool value) {
    if (value == _revealLive) return;
    _revealLive = value;
    markNeedsPaint();
  }

  ui.Image? _waiting, _covered;
  final _stillPaint = Paint()..filterQuality = FilterQuality.low;

  /// Whether the last paint drew the still images.
  bool get drawsStills => _drawsStills;
  bool _drawsStills = false;

  void clearStills() {
    _waiting?.dispose();
    _covered?.dispose();
    _waiting = _covered = null;
  }

  /// The card painted into a layer of its own, at the device's pixel ratio.
  ui.Image _still() {
    final layer = OffsetLayer();
    final context = PaintingContext(layer, Offset.zero & size);
    _paintCard(context, Offset.zero);
    // ignore: invalid_use_of_protected_member
    context.stopRecordingIfNeeded();
    final image = layer.toImageSync(
      Offset.zero & size,
      pixelRatio: _data.text.pixelRatio,
    );
    layer.dispose();
    return image;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final progress = _reveal?.value ?? 1;
    _drawsStills = progress < 1 && !_revealLive;
    if (progress >= 1) {
      clearStills();
      _paintCard(context, offset);
    } else {
      // ScaleTransition's: 0.9 to 1, about the centre.
      _scaleAbout(
        context.canvas,
        offset + size.center(Offset.zero),
        0.9 + (1.0 - 0.9) * progress,
      );
      if (!_drawsStills) {
        clearStills();
        _paintCard(context, offset);
      } else {
        // The two stills differ only in the cover, so only it is drawn
        // twice: a translucent background would show through twice.
        final ratio = _data.text.pixelRatio;
        final cover = Size(
          math.min(switch (_data.design) {
            GameTileDesign.grid => double.infinity,
            GameTileDesign.list => kListCardImageWidth,
            GameTileDesign.slim => 0.0,
          }, size.width),
          size.height,
        );
        _waiting ??= _still();
        if (progress > 0 && !cover.isEmpty) _covered ??= _still();
        context.canvas.drawImageRect(
          _waiting!,
          Offset.zero & (size * ratio),
          offset & size,
          _stillPaint..color = const Color(0xFF000000),
        );
        if (_covered case final covered?) {
          context.canvas.drawImageRect(
            covered,
            Offset.zero & (cover * ratio),
            offset & cover,
            _stillPaint..color = Color.fromRGBO(0, 0, 0, progress),
          );
        }
      }
      context.canvas.restore();
    }
    revealPainted();
  }

  void _paintCard(PaintingContext context, Offset offset) {
    // Zoomed about its centre while hovered.
    final scale =
        1.0 +
        _hoverValue *
            switch (_data.design) {
              GameTileDesign.grid => 0.015,
              GameTileDesign.list => 0.006,
              GameTileDesign.slim => 0.012,
            };
    final zoomed = scale != 1.0;
    if (zoomed) {
      _scaleAbout(context.canvas, offset + size.center(Offset.zero), scale);
    }
    switch (_data.design) {
      case GameTileDesign.slim:
        _paintSlim(context, offset);
      case GameTileDesign.grid:
        _paintGrid(context, offset);
      case GameTileDesign.list:
        _paintList(context, offset);
    }
    if (zoomed) context.canvas.restore();
  }

  void _paintGrid(PaintingContext context, Offset offset) {
    final d = _data;
    final theme = d.theme;
    final rect = offset & size;
    final radius = BorderRadius.circular(theme.cornerRadius);
    final canvas = context.canvas;
    _paintDecoration(
      canvas,
      rect,
      BoxDecoration(
        borderRadius: radius,
        boxShadow: _hoverShadow(_hoverValue, 0.2),
      ),
    );
    // On fractional pixels a bright cover bleeds through the dark USED tint
    // along the card's edges: a used card's layers are clipped together.
    final used = d.game.isUsed;
    canvas
      ..save()
      ..clipRRect(radius.toRRect(rect));
    if (used) canvas.saveLayer(rect, Paint());
    _paintCover(canvas, rect);
    if (used) {
      // A pixel past the edges, which the clip trims.
      final tint = rect.inflate(1);
      canvas.drawRect(tint, Paint()..color = theme.gridUsedOverlay);
      _paintUsedPattern(
        canvas,
        tint,
        Colors.white.withValues(alpha: 0.24),
        const Size(kGridCardWidth, kGridCardHeight),
      );
    }
    // The glow, over the USED pattern so a used card glows as brightly.
    canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    CardGlowPainter(
      accentColor: theme.accent,
      primaryColor: theme.secondary,
      cornerRadius: theme.cornerRadius,
      hover: d.selected ? null : _hoverCurve ?? kAlwaysDismissedAnimation,
      devicePixelRatio: d.text.pixelRatio,
    ).paint(canvas, size);
    canvas.restore();
    _paintSelection(context, rect);
    _paintFetchOverlays(context, offset, rect);
    for (final chip in _chips) {
      chip.paint(context.canvas, offset);
    }
    if (used) context.canvas.restore();
    context.canvas.restore();
  }

  /// A [Container]'s child area inside the overlays' 3 px border: over
  /// the cover of a list card ([imageWidth]), or the whole card.
  Rect _overImage(Rect rect, double? imageWidth) {
    final inner = rect.deflate(3);
    return imageWidth == null
        ? inner
        : Rect.fromLTWH(inner.left, inner.top, imageWidth, inner.height);
  }

  /// The selection overlay: a tint and frame, a check in the middle.
  void _paintSelection(
    PaintingContext context,
    Rect rect, {
    double? imageWidth,
  }) {
    final t = (_selectionCurve?.value ?? 0).clamp(0.0, 1.0);
    if (t <= 0) return;
    final theme = _data.theme;
    final canvas = context.canvas;
    _paintDecoration(canvas, rect, theme.selectionOverlayDecoration(t));
    final side = 18 + 18 * t;
    final box =
        _center(_overImage(rect, imageWidth), Size.square(side)) &
        Size.square(side);
    _paintDecoration(
      canvas,
      box,
      BoxDecoration(
        color: theme.accent.withValues(alpha: t),
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        boxShadow: t > 0.01
            ? [
                BoxShadow(
                  color: theme.accent.withValues(alpha: 0.28 * t),
                  blurRadius: 12 * t,
                  spreadRadius: t,
                ),
              ]
            : null,
      ),
    );
    final alpha = Color.getAlphaFromOpacity(t);
    if (alpha == 0) return;
    // The check, an Icon of the theme's size fitted into its box, faded.
    final (check, inBox) = _selectionCheck!;
    final iconSize = _data.text.icons.size ?? 24;
    final at = box.topLeft + Offset(4 + 4 * t, 4 + 4 * t);
    final faded = _fadeLayer(canvas, alpha);
    _scaleAbout(canvas, at, (10 + 10 * t) / iconSize);
    check.paint(canvas, at + inBox);
    canvas.restore();
    if (faded) canvas.restore();
  }

  (TextPainter, Offset)? _selectionCheck;

  /// The fetch status overlays, each a tint, a frame and a status
  /// icon in a box, fading in and out.
  void _paintFetchOverlays(
    PaintingContext context,
    Offset offset,
    Rect rect, {
    double? imageWidth,
  }) {
    final theme = _data.theme;
    for (final fade in _fades) {
      final alpha = Color.getAlphaFromOpacity(fade.controller.value);
      if (alpha == 0) continue;
      var canvas = context.canvas;
      final faded = _fadeLayer(canvas, alpha);
      final status = fade.status;
      final (color, _, _) = _fetchVisual(status);
      _paintDecoration(
        canvas,
        rect,
        BoxDecoration(
          color: color.withValues(
            alpha: status == GameFetchStatus.done ? 0.32 : 0.28,
          ),
          border: Border.all(
            color: status == GameFetchStatus.processing
                ? Colors.transparent
                : color,
            width: 3,
          ),
          borderRadius: BorderRadius.circular(theme.cornerRadius),
        ),
      );
      final box =
          _center(
            _overImage(rect, imageWidth),
            const Size.square(kSelectionIndicatorSize + 16),
          ) &
          const Size.square(kSelectionIndicatorSize + 16);
      _paintDecoration(
        canvas,
        box,
        BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(theme.cornerRadius),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.45),
              blurRadius: 14,
              spreadRadius: 2,
            ),
          ],
        ),
      );
      if (status == GameFetchStatus.processing) {
        canvas = _paintSpinner(context, offset);
      } else if (_fetchIconPainters[status] case (final icon, final inBox)) {
        icon.paint(canvas, box.topLeft + const Offset(8, 8) + inBox);
      }
      if (faded) canvas.restore();
    }
  }

  void _paintList(PaintingContext context, Offset offset) {
    final d = _data;
    final theme = d.theme;
    final rect = offset & size;
    final radius = BorderRadius.circular(theme.cornerRadius);
    final canvas = context.canvas;
    final colors = d.selected
        ? theme.listCardSelectedGradient
        : d.hovered
        ? theme.listCardHoverGradient
        : theme.listCardDefaultGradient;
    _paintDecoration(
      canvas,
      rect,
      BoxDecoration(
        gradient: LinearGradient(
          transform: GradientRotation(25 * math.pi / 180),
          colors: [theme.background, colors[1], colors[0]],
          stops: const [0.10, 0.5, 1.0],
        ),
        boxShadow: _hoverShadow(_hoverValue, 0.18),
        borderRadius: radius,
      ),
    );
    final cover = Rect.fromLTWH(
      offset.dx,
      offset.dy,
      kListCardImageWidth,
      size.height,
    );
    canvas
      ..save()
      ..clipRRect(
        BorderRadius.horizontal(left: Radius.circular(theme.cornerRadius))
            .toRRect(cover),
      );
    _paintCover(canvas, cover);
    canvas.restore();
    if (d.game.isUsed) {
      canvas
        ..save()
        ..clipRRect(radius.toRRect(rect))
        ..drawRect(rect, Paint()..color = theme.usedOverlay);
      // The pattern only depends on the card's height.
      _paintUsedPattern(
        canvas,
        rect,
        Colors.white.withValues(alpha: 0.24),
        const Size.fromHeight(kListCardHeight),
      );
      canvas.restore();
    }
    for (final chip in _under) {
      chip.paint(canvas, offset);
    }
    _paintSelection(context, rect, imageWidth: kListCardImageWidth);
    _paintFetchOverlays(context, offset, rect, imageWidth: kListCardImageWidth);
    _paintText(context.canvas, _title!, offset + _titleOffset, _titleBox);
    _paintTags(context.canvas, offset);
    for (final chip in _chips) {
      chip.paint(context.canvas, offset);
    }
  }

  /// The tag row at the bottom of the pane, as much of it as has grown in,
  /// faded as much.
  void _paintTags(Canvas canvas, Offset offset) {
    if (_tagBadges.isEmpty) return;
    final controller = _tagsController;
    final grown = controller == null ? 1.0 : _tagsSize!.value;
    final alpha = controller == null
        ? 255
        : Color.getAlphaFromOpacity(_tagsOpacity!.value);
    if (grown <= 0 || alpha == 0) return;
    final shown = _tagsHeight * grown;
    final bottom = offset.dy + _pane.bottom;
    // Two ClipRects' hard edges.
    canvas
      ..save()
      ..clipRect(
        Rect.fromLTWH(
          offset.dx + _pane.left,
          bottom - shown,
          _tagsWidth,
          shown,
        ),
        doAntiAlias: false,
      );
    final faded = _fadeLayer(canvas, alpha);
    final origin = Offset(offset.dx + _pane.left, bottom - _tagsHeight + 6);
    for (final chip in _tagBadges) {
      chip.paint(canvas, origin);
    }
    if (faded) canvas.restore();
    canvas.restore();
  }

  void _paintSlim(PaintingContext context, Offset offset) {
    final d = _data;
    var canvas = context.canvas;
    final rect = offset & size;
    final theme = d.theme;
    _paintDecoration(
      canvas,
      rect,
      BoxDecoration(
        color: theme.surface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.zero,
      ),
    );
    if (d.game.isUsed) {
      canvas.drawRect(rect, Paint()..color = theme.slimUsedOverlay);
      _paintUsedPattern(
        canvas,
        rect,
        theme.textPrimary.withValues(alpha: 0.18),
        const Size.fromHeight(kSlimListCardHeight),
        tileToCanvas: true,
      );
    }
    final tint = _tint;
    if (tint != null && tint.a > 0) {
      canvas.drawRect(rect, Paint()..color = tint);
    }
    for (final fade in _fades) {
      final alpha = Color.getAlphaFromOpacity(fade.controller.value);
      if (alpha == 0) continue;
      final faded = _fadeLayer(canvas, alpha, rect);
      canvas.drawRect(
        rect,
        Paint()
          ..color = _fetchVisual(fade.status).$1.withValues(
            alpha: fade.status == GameFetchStatus.done ? 0.24 : 0.44,
          ),
      );
      if (faded) canvas.restore();
    }

    _paintText(canvas, _title!, offset + _titleOffset, _titleBox);

    for (final chip in _chips) {
      chip.paint(canvas, offset);
    }
    if (_extras.isNotEmpty) {
      // A ClipRect's hard edge.
      canvas
        ..save()
        ..clipRect(_extrasBox.shift(offset), doAntiAlias: false);
      for (final chip in _extras) {
        chip.paint(canvas, offset);
      }
      _paintFetchIcons(context, offset);
      context.canvas.restore();
    }
  }

  /// Each of [_fetchIcons] scaled and faded about its box's centre.
  void _paintFetchIcons(PaintingContext context, Offset offset) {
    final box = _fetchIconBox.shift(offset);
    for (final icon in _fetchIcons) {
      final value = icon.controller.value;
      final alpha = Color.getAlphaFromOpacity(value);
      if (alpha == 0) continue;
      var canvas = context.canvas;
      _scaleAbout(canvas, box.center, value);
      final faded = _fadeLayer(canvas, alpha);
      if (icon.status == GameFetchStatus.processing) {
        canvas = _paintSpinner(context, offset);
      } else if (_fetchIconPainters[icon.status] case (final glyph, final at)) {
        glyph.paint(canvas, box.topLeft + at);
      }
      if (faded) canvas.restore();
      canvas.restore();
    }
  }

  /// The chip with a tooltip at [position], if any.
  GameTileSlot? tooltipSlotAt(Offset position) {
    for (final chip in [..._under, ..._chips, ..._extras]) {
      if (chip.slot != null && chip.rect.contains(position)) return chip.slot;
    }
    return null;
  }

  // ── Input ──────────────────────────────────────────────────────────────────

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent ||
        event is PointerMoveEvent ||
        event is PointerUpEvent ||
        event is PointerCancelEvent) {
      onPointer(event);
    }
  }

  @override
  MouseCursor get cursor => MouseCursor.defer;

  @override
  bool get validForMouseTracker => attached;
}
