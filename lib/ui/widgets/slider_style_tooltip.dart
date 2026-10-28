import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_slider_theme.dart';

/// Shows [message] above [child] in the theme sliders' value bubble while a
/// mouse hovers it, or briefly after a touch.
class SliderStyleTooltip extends StatefulWidget {
  const SliderStyleTooltip({
    super.key,
    required this.message,
    required this.child,
    this.color,
  });

  final String message;
  final Widget child;

  /// The bubble's fill instead of the sliders' accent; its label turns
  /// black on light fills to stay readable.
  final Color? color;

  @override
  State<SliderStyleTooltip> createState() => _SliderStyleTooltipState();
}

class _SliderStyleTooltipState extends State<SliderStyleTooltip>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  late final AnimationController _controller;
  late final CurvedAnimation _scale;
  Timer? _touchHide;

  // The mouse leaves a region as it is removed, after it can no longer
  // animate.
  bool _active = true;

  @override
  void initState() {
    super.initState();
    // The slider's value indicator timing and curve.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.fastOutSlowIn);
  }

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void deactivate() {
    _active = false;
    super.deactivate();
  }

  @override
  void dispose() {
    _touchHide?.cancel();
    _scale.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _show() {
    _touchHide?.cancel();
    _portal.show();
    _controller.forward();
  }

  void _hide() {
    if (!_active) return;
    _controller.reverse().then((_) {
      if (mounted && _controller.isDismissed) _portal.hide();
    });
  }

  @override
  Widget build(BuildContext context) {
    final themed = SliderTheme.of(context);
    final color = widget.color;
    final sliderTheme = color == null
        ? themed
        : themed.copyWith(
            valueIndicatorColor: color,
            valueIndicatorTextStyle:
                (themed.valueIndicatorTextStyle ?? const TextStyle()).copyWith(
                  // White text unless it falls below 3:1 contrast.
                  color: color.computeLuminance() > 0.3
                      ? Colors.black
                      : Colors.white,
                ),
          );
    // Sliders cap their label's text scale at 1.3.
    final textScale =
        MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3).scale(14) /
        14;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (overlayContext) => AnimatedBuilder(
        animation: _scale,
        builder: (_, _) => _ValueBubble(
          target: context.findRenderObject()! as RenderBox,
          label: widget.message,
          scale: _scale.value,
          sliderTheme: sliderTheme,
          textScale: textScale,
          textDirection: Directionality.of(context),
        ),
      ),
      child: MouseRegion(
        onEnter: (_) => _show(),
        onExit: (_) => _hide(),
        child: Listener(
          onPointerDown: (event) {
            if (event.kind != PointerDeviceKind.mouse) _show();
          },
          onPointerUp: (event) {
            if (event.kind == PointerDeviceKind.mouse) return;
            _touchHide = Timer(const Duration(milliseconds: 1500), _hide);
          },
          child: widget.child,
        ),
      ),
    );
  }
}

/// Paints the slider value indicator over the overlay, its tip just above
/// the top centre of [target].
class _ValueBubble extends LeafRenderObjectWidget {
  const _ValueBubble({
    required this.target,
    required this.label,
    required this.scale,
    required this.sliderTheme,
    required this.textScale,
    required this.textDirection,
  });

  final RenderBox target;
  final String label;
  final double scale;
  final SliderThemeData sliderTheme;
  final double textScale;
  final TextDirection textDirection;

  @override
  _RenderValueBubble createRenderObject(BuildContext context) =>
      _RenderValueBubble(this);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderValueBubble renderObject,
  ) => renderObject
    ..bubble = this
    ..markNeedsPaint();
}

class _RenderValueBubble extends RenderBox {
  _RenderValueBubble(this.bubble);

  _ValueBubble bubble;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    final target = bubble.target;
    if (!target.attached || !target.hasSize) return;
    final shape =
        bubble.sliderTheme.valueIndicatorShape ??
        const DropSliderValueIndicatorShape();
    // The pointer's tip sits just above the target.
    final tipGap = shape is AppSliderValueIndicatorShape
        ? AppSliderValueIndicatorShape.tipGap - 3
        : 14.0;
    final center =
        globalToLocal(
          target.localToGlobal(target.size.topCenter(Offset.zero)),
        ) +
        Offset(0, tipGap);
    final label = TextPainter(
      text: TextSpan(
        text: bubble.label,
        style: bubble.sliderTheme.valueIndicatorTextStyle,
      ),
      textDirection: bubble.textDirection,
      textScaler: TextScaler.linear(bubble.textScale),
    )..layout();
    shape.paint(
      context,
      offset + center,
      activationAnimation: AlwaysStoppedAnimation(bubble.scale),
      enableAnimation: kAlwaysCompleteAnimation,
      isDiscrete: false,
      labelPainter: label,
      parentBox: this,
      sliderTheme: bubble.sliderTheme,
      textDirection: bubble.textDirection,
      value: 0,
      textScaleFactor: bubble.textScale,
      sizeWithOverflow: size,
    );
    label.dispose();
  }
}
