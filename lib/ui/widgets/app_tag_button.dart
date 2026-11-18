import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/button_depth.dart';
import '../../models/game.dart';
import 'app_action_button.dart';
import 'settings_card_inset.dart';

/// A tag chip, looking and reacting as an [AppActionButton] toggle does,
/// with the tag's category color.
///
/// Lists show hundreds of these, so it is not built from the button's
/// widgets (about 80 a chip) but painted by one render object: label, status
/// mark, lighting and inset. The chip keeps Flutter's own [Material] for its
/// outline, label color fade and ink (surface, hover, focus and press
/// highlights and the theme's splash), and [Focus] and [Actions] for the
/// keyboard. Read-only chips ([onTap] null) show as on and take no input.
class AppTagButton extends StatefulWidget {
  const AppTagButton({
    super.key,
    required this.tag,
    required this.theme,
    this.isSelected = false,
    this.onTap,
    this.deleteOnTap = false,
  });

  final Tag tag;
  final AppThemeData theme;
  final bool isSelected;
  final VoidCallback? onTap;

  /// A custom tag's mark turns into a cross while hovered.
  final bool deleteOnTap;

  @override
  State<AppTagButton> createState() => _AppTagButtonState();
}

/// A value easing to its latest target as [TweenAnimationBuilder] does; its
/// controller is made on the first change that takes time.
class _Ease<T extends Object> {
  _Ease(this._end, this.curve);

  final Curve curve;
  T _end;
  Tween<T>? _tween;
  AnimationController? _controller;

  T get value => _controller == null
      ? _end
      : _tween!.transform(curve.transform(_controller!.value));

  void to(T end, Duration duration, TickerProvider vsync, VoidCallback tick) {
    if (end == _end) return;
    if (_controller == null && duration == Duration.zero) {
      _end = end;
      return tick();
    }
    _tween = Tween<T>(begin: value, end: end);
    _end = end;
    (_controller ??= AnimationController(vsync: vsync)..addListener(tick))
      ..duration = duration
      ..forward(from: 0);
  }

  void dispose() => _controller?.dispose();
}

class _AppTagButtonState extends State<AppTagButton>
    with TickerProviderStateMixin {
  /// Hovered, pressed and focused.
  final _states = <WidgetState>{};
  final _focus = FocusNode();
  late final _tap = TapGestureRecognizer(debugOwner: this)
    ..onTapDown = ((details) => _startSplash(details.globalPosition))
    ..onTap = (() => _endPress(tapped: true))
    ..onTapCancel = (() => _endPress(tapped: false));
  late final _actions = <Type, Action<Intent>>{
    ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: _activate),
    ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
      onInvoke: _activate,
    ),
  };

  // The ink, on the chip's Material, as the button's InkWell made it.
  BuildContext? _boxContext;
  _RenderTagChip? _box;
  InkDecoration? _surface;
  final _highlights = <WidgetState, InkHighlight>{};
  final _splashes = <InteractiveInkFeature>{};
  InteractiveInkFeature? _splash;
  Timer? _activation;

  // Material's outline and label fades snap to a new theme, as
  // ButtonThemeSync makes them.
  ThemeData? _materialTheme;
  bool _snapTheme = false;

  final _surfaceAlpha = _Ease<double>(0, Curves.easeOutCubic);
  final _depth = _Ease<double>(0, Curves.easeOutCubic);
  final _inset = _Ease<double>(0, Curves.easeOutCubic);
  // The mark's size; the label slides over to make room for it.
  final _shown = _Ease<double>(0, Curves.easeInOutCubic);
  final _mark = _Ease<Offset>(Offset.zero, Curves.easeInOutCubic);

  bool get _readOnly => widget.onTap == null;
  bool get _selected => _readOnly || widget.isSelected;
  bool get _idle => !_selected && _states.isEmpty;
  Color get _accent =>
      widget.tag.isSteamTag ? widget.theme.accent : widget.theme.secondary;
  bool get _deleteOnHover =>
      widget.deleteOnTap && !widget.tag.isSteamTag && !_readOnly;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_highlightModeChanged);
    // The first targets show without easing.
    _retarget(Duration.zero, Duration.zero);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context);
    if (_materialTheme != null && !identical(theme, _materialTheme)) {
      _snap();
    }
    _materialTheme = theme;
  }

  @override
  void didUpdateWidget(AppTagButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.theme != widget.theme) _snap();
    if (_readOnly) {
      _states.clear();
      _clearInk();
    }
  }

  void _snap() {
    if (_snapTheme) return;
    _snapTheme = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _snapTheme = false);
    });
  }

  @override
  void deactivate() {
    _clearInk();
    _surface?.dispose();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    if (_box != null) _mountInk(_boxContext!, _box!);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_highlightModeChanged);
    _activation?.cancel();
    _tap.dispose();
    _focus.dispose();
    for (final ease in [_surfaceAlpha, _depth, _inset, _shown, _mark]) {
      ease.dispose();
    }
    super.dispose();
  }

  // Ink and states, as InkWell keeps them.

  /// The chip's surface, under every highlight and splash.
  void _mountInk(BuildContext context, _RenderTagChip box) {
    _boxContext = context;
    _box = box;
    _surface = InkDecoration(
      decoration: _surfaceDecoration,
      configuration: createLocalImageConfiguration(context),
      controller: Material.of(context),
      referenceBox: box,
      onRemoved: () => _surface = null,
    );
  }

  BoxDecoration get _surfaceDecoration => BoxDecoration(
    color: widget.theme.background.withValues(alpha: _surfaceAlpha.value),
    borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
  );

  void _clearInk() {
    for (final ink in [..._splashes, ..._highlights.values]) {
      ink.dispose();
    }
    _splash = null;
    _highlights.clear();
    _activation?.cancel();
  }

  RoundedRectangleBorder get _shape => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
  );

  Color _overlay(WidgetState state) {
    final theme = Theme.of(context);
    return switch (state) {
      WidgetState.pressed => theme.splashColor,
      WidgetState.hovered => theme.hoverColor,
      _ => theme.focusColor,
    };
  }

  void _setState(WidgetState state, bool on) {
    if (_states.contains(state) == on) return;
    setState(() => on ? _states.add(state) : _states.remove(state));
  }

  void _highlight(WidgetState state, bool on) {
    if (state != WidgetState.focused) _setState(state, on);
    final highlight = _highlights[state];
    if (on == (highlight != null && highlight.active)) return;
    if (!on) return highlight!.deactivate();
    if (highlight != null) return highlight.activate();
    final box = _boxContext;
    if (box == null) return;
    late final InkHighlight created;
    _highlights[state] = created = InkHighlight(
      controller: Material.of(box),
      referenceBox: _box!,
      color: _overlay(state),
      customBorder: _shape,
      onRemoved: () {
        if (identical(_highlights[state], created)) _highlights.remove(state);
      },
      textDirection: Directionality.of(box),
      fadeDuration: state == WidgetState.pressed
          ? const Duration(milliseconds: 200)
          : const Duration(milliseconds: 50),
    );
  }

  void _hover(bool on) {
    if (!_readOnly || !on) _highlight(WidgetState.hovered, on);
  }

  void _highlightModeChanged(FocusHighlightMode mode) {
    if (mounted) setState(_updateFocusHighlight);
  }

  void _updateFocusHighlight() {
    final hasFocus = _states.contains(WidgetState.focused);
    final show = switch (FocusManager.instance.highlightMode) {
      FocusHighlightMode.touch => false,
      FocusHighlightMode.traditional =>
        switch (MediaQuery.maybeNavigationModeOf(context)) {
          NavigationMode.traditional || null => !_readOnly && hasFocus,
          NavigationMode.directional => hasFocus,
        },
    };
    _highlight(WidgetState.focused, show);
  }

  void _focusChanged(bool hasFocus) {
    _setState(WidgetState.focused, hasFocus);
    _updateFocusHighlight();
  }

  void _startSplash(Offset globalPosition) {
    final context = _boxContext;
    if (context == null) return;
    _setState(WidgetState.pressed, true);
    late final InteractiveInkFeature splash;
    splash = Theme.of(context).splashFactory.create(
      controller: Material.of(context),
      referenceBox: _box!,
      position: _box!.globalToLocal(globalPosition),
      color: _overlay(WidgetState.pressed),
      containedInkWell: true,
      customBorder: _shape,
      onRemoved: () {
        _splashes.remove(splash);
        if (identical(_splash, splash)) _splash = null;
      },
      textDirection: Directionality.of(context),
    );
    _splashes.add(splash);
    _splash?.cancel();
    _splash = splash;
    _highlight(WidgetState.pressed, true);
  }

  /// A tap spreads the splash and calls [AppTagButton.onTap], a cancel fades
  /// it; the press shows a little longer when [hold] (from the keyboard).
  void _endPress({required bool tapped, bool hold = false}) {
    tapped ? _splash?.confirm() : _splash?.cancel();
    _splash = null;
    void release() => _highlight(WidgetState.pressed, false);
    hold
        ? _activation = Timer(const Duration(milliseconds: 100), release)
        : release();
    if (!tapped || widget.onTap == null) return;
    Feedback.forTap(context);
    widget.onTap!();
  }

  /// Enter or space: a splash from the middle, then the tap.
  void _activate([Intent? _]) {
    _activation?.cancel();
    final box = _box;
    if (box == null || !box.hasSize) return;
    _startSplash(box.localToGlobal(box.paintBounds.center));
    _endPress(tapped: true, hold: true);
  }

  void _tick() => _box?.markNeedsPaint();

  void _tickSurface() => _surface?.decoration = _surfaceDecoration;

  /// Eases each part toward the chip's states, as the button's animated
  /// builders did.
  void _retarget(Duration surface, Duration status) {
    final idle = _idle;
    _surfaceAlpha.to(idle ? 0 : 0.65, surface, this, _tickSurface);
    _depth.to(
      _selected || idle
          ? 0
          : _states.contains(WidgetState.pressed)
          ? -0.45
          : 1,
      surface,
      this,
      _tick,
    );
    _inset.to(
      _selected ? 1 : 0,
      surface == Duration.zero
          ? Duration.zero
          : const Duration(milliseconds: 140),
      this,
      _tick,
    );
    if (_readOnly) return;
    final hovered = _states.contains(WidgetState.hovered);
    _shown.to(idle ? 0 : 1, status, this, _tick);
    _mark.to(
      Offset(_selected ? 1 : 0, _deleteOnHover && hovered ? 1 : 0),
      status,
      this,
      _tick,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final still = MediaQuery.disableAnimationsOf(context);
    _retarget(
      still ? Duration.zero : const Duration(milliseconds: 110),
      still ? Duration.zero : const Duration(milliseconds: 120),
    );
    _tickSurface();
    // As InkWell keeps its ink in step with the theme and the shape.
    final shape = _shape;
    for (final MapEntry(key: state, value: highlight) in _highlights.entries) {
      highlight
        ..color = _overlay(state)
        ..customBorder = shape;
    }
    for (final splash in _splashes) {
      splash.customBorder = shape;
    }
    _splash?.color = _overlay(WidgetState.pressed);
    final focused = _states.contains(WidgetState.focused);
    final foreground = _selected ? _accent : theme.textPrimary;
    return RepaintBoundary(
      child: Semantics(
        container: true,
        button: !_readOnly,
        enabled: _readOnly ? null : true,
        label: widget.tag.name,
        onTap: _readOnly ? null : _activate,
        child: Actions(
          actions: _actions,
          child: Focus(
            focusNode: _focus,
            canRequestFocus: !_readOnly,
            onFocusChange: _focusChanged,
            child: Material(
              type: MaterialType.button,
              color: Colors.transparent,
              borderOnForeground: false,
              // As a button with a background builder clips.
              clipBehavior: Clip.antiAlias,
              animationDuration: _snapTheme
                  ? Duration.zero
                  : kThemeChangeDuration,
              textStyle: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: foreground),
              shape: shape.copyWith(
                side: _idle
                    ? BorderSide.none
                    : BorderSide(
                        color: focused ? _accent : theme.border,
                        width: focused ? 1.5 : 1,
                      ),
              ),
              child: _TagChipBox(state: this),
            ),
          ),
        ),
      ),
    );
  }
}

/// The painted chip, under the chip's [Material].
class _TagChipBox extends LeafRenderObjectWidget {
  const _TagChipBox({required this.state});

  final _AppTagButtonState state;

  @override
  _RenderTagChip createRenderObject(BuildContext context) {
    final box = _RenderTagChip(state);
    updateRenderObject(context, box);
    state._mountInk(context, box);
    return box;
  }

  @override
  void updateRenderObject(BuildContext context, _RenderTagChip box) {
    // As a Text in the button's label.
    final defaults = DefaultTextStyle.of(context);
    box
      ..label = TextSpan(
        text: state.widget.tag.name,
        style: MediaQuery.boldTextOf(context)
            ? defaults.style.merge(const TextStyle(fontWeight: FontWeight.bold))
            : defaults.style,
      )
      ..text = (
        direction: Directionality.of(context),
        scaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        heightBehavior:
            defaults.textHeightBehavior ??
            DefaultTextHeightBehavior.maybeOf(context),
        widthBasis: defaults.textWidthBasis,
      )
      ..look = (
        theme: state.widget.theme,
        accent: state._accent,
        readOnly: state._readOnly,
        ratio: MediaQuery.devicePixelRatioOf(context),
      );
  }
}

/// The label's settings besides its span, as a Text takes them.
typedef _TextSettings = ({
  TextDirection direction,
  TextScaler scaler,
  Locale? locale,
  TextHeightBehavior? heightBehavior,
  TextWidthBasis widthBasis,
});

/// What painting reads from the chip besides its eases: the theme, the tag's
/// color, read-only (no mark, so a narrower chip) and the pixel ratio of the
/// cached inset.
typedef _Look = ({
  AppThemeData theme,
  Color accent,
  bool readOnly,
  double ratio,
});

class _RenderTagChip extends RenderBox implements MouseTrackerAnnotation {
  _RenderTagChip(this.state);

  final _AppTagButtonState state;
  final _painter = TextPainter(maxLines: 1, ellipsis: '…');

  _Look? _look;
  set look(_Look value) {
    if (value == _look) return;
    value.readOnly != _look?.readOnly ? markNeedsLayout() : markNeedsPaint();
    _look = value;
  }

  // Compared as given: the painter keeps no scaling when handed the system's,
  // which then no longer equals what it was handed.
  _TextSettings? _text;
  set text(_TextSettings value) {
    if (value == _text) return;
    _text = value;
    _painter
      ..textDirection = value.direction
      ..textScaler = value.scaler
      ..locale = value.locale
      ..textHeightBehavior = value.heightBehavior
      ..textWidthBasis = value.widthBasis;
    markNeedsLayout();
  }

  static const _padding = AppActionButton.toggleHorizontalPadding;
  static const _status = AppActionButton.statusSize;
  static const _statusRoom = _status + AppActionButton.statusSpacing;

  set label(TextSpan value) {
    final old = _painter.text;
    final change = old?.compareTo(value) ?? RenderComparison.layout;
    if (change == RenderComparison.identical) return;
    _painter.text = value;
    change.index >= RenderComparison.layout.index
        ? markNeedsLayout()
        : markNeedsPaint();
  }

  bool get _showsStatus => !_look!.readOnly;

  @override
  bool get isRepaintBoundary => true;

  // Where the label row sits, from layout.
  double _rowTop = 0;
  double _rowHeight = 0;
  bool _clipText = false;

  @override
  void performLayout() {
    // As the button's Padding, Align and Row(s) lay out its label: the mark
    // keeps its room, the label takes what is left and ellipsizes.
    final status = _showsStatus ? _statusRoom : 0.0;
    _painter.layout(
      maxWidth: math.max(0.0, constraints.maxWidth - _padding * 2 - status),
    );
    final textSize = _painter.size;
    _rowHeight = math.max(textSize.height, _showsStatus ? _status : 0);
    final inner = math.max(32.0 - 14, _rowHeight);
    _rowTop = 7 + (inner - _rowHeight) / 2;
    _clipText = _painter.didExceedMaxLines;
    size = constraints.constrain(
      Size(textSize.width + _padding * 2 + status, inner + 14),
    );
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent && !state._readOnly) {
      state._tap.addPointer(event);
    }
  }

  @override
  MouseCursor get cursor =>
      state._readOnly ? MouseCursor.defer : SystemMouseCursors.click;

  @override
  PointerEnterEventListener? get onEnter =>
      state._readOnly ? null : (_) => state._hover(true);

  @override
  PointerExitEventListener? get onExit =>
      (_) => state._hover(false);

  @override
  bool get validForMouseTracker => attached;

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final theme = _look!.theme;
    void painter(CustomPainter? painter) {
      if (painter == null) return;
      canvas
        ..save()
        ..translate(offset.dx, offset.dy);
      painter.paint(canvas, size);
      canvas.restore();
    }

    // Raised lighting under the label, the inset over it.
    final depth = state._depth.value;
    if (depth != 0) {
      painter(ButtonDepthPainter(depth, true, state._shape, _text!.direction));
    }

    final shown = _showsStatus ? state._shown.value : 1.0;
    const hiddenShift = _statusRoom / 2;
    final textOffset =
        offset +
        Offset(
          _padding + (1 - shown) * hiddenShift,
          _rowTop + (_rowHeight - _painter.height) / 2,
        );
    if (_clipText) {
      canvas
        ..save()
        ..clipRect(textOffset & _painter.size);
    }
    _painter.paint(canvas, textOffset);
    if (_clipText) canvas.restore();

    if (_showsStatus && shown != 0) {
      final mark = state._mark.value;
      final box =
          offset +
              Offset(
                _padding + _painter.width + AppActionButton.statusSpacing,
                _rowTop + (_rowHeight - _status) / 2,
              ) &
          const Size.square(_status);
      canvas
        ..save()
        ..translate(box.center.dx, box.center.dy)
        ..scale(shown)
        ..translate(-box.center.dx, -box.center.dy)
        ..translate(box.left, box.top);
      ToggleIndicatorPainter(
        progress: mark.dx,
        deleteProgress: mark.dy,
        color: Color.lerp(
          theme.textHint,
          _look!.accent,
          math.max(mark.dx, mark.dy),
        )!,
      ).paint(canvas, box.size);
      canvas.restore();
    }

    painter(
      SettingsCardInset.painterFor(
        depth: state._inset.value,
        radius: theme.cornerRadius,
        surfaceColor: theme.background,
        devicePixelRatio: _look!.ratio,
      ),
    );
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }
}
