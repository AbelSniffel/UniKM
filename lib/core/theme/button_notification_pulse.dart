import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A center-out notification wave that tints the surface and foreground together.
class ButtonNotificationPulse extends StatefulWidget {
  const ButtonNotificationPulse({
    super.key,
    required this.enabled,
    required this.color,
    required this.borderRadius,
    required this.child,
  });

  final bool enabled;
  final Color color;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  State<ButtonNotificationPulse> createState() =>
      _ButtonNotificationPulseState();
}

class _ButtonNotificationPulseState extends State<ButtonNotificationPulse>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant ButtonNotificationPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (widget.enabled &&
        !_reducedMotion &&
        TickerMode.valuesOf(context).enabled) {
      final controller = _controller ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2500),
      );
      if (!controller.isAnimating) controller.repeat();
    } else {
      _controller?.stop();
      _controller?.value = 0;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final decoration = _PulseDecoration(
      progress: _controller ?? const AlwaysStoppedAnimation(0.0),
      color: widget.color,
      borderRadius: widget.borderRadius,
      reducedMotion: _reducedMotion,
    );
    return Ink(
      decoration: decoration,
      child: _PulseContent(decoration: decoration, child: widget.child),
    );
  }
}

class _PulseDecoration extends Decoration {
  const _PulseDecoration({
    required this.progress,
    required this.color,
    required this.borderRadius,
    required this.reducedMotion,
  });

  final Animation<double> progress;
  final Color color;
  final BorderRadius borderRadius;
  final bool reducedMotion;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _PulsePainter(this, onChanged);

  double get opacity {
    if (reducedMotion) return 1;
    if (progress.value >= 0.54) return 0;
    // Expand for 900 ms, fade for 450 ms, then rest until the 2.5-second repeat.
    final phase = progress.value / 0.36;
    return (phase / 0.1).clamp(0.0, 1.0) *
        (1 - Curves.easeOut.transform(((phase - 1) / 0.5).clamp(0.0, 1.0)));
  }

  void paint(Canvas canvas, Rect bounds, {bool foreground = false}) {
    final strength = opacity;
    if (strength <= 0 || bounds.isEmpty) return;
    final scale = reducedMotion
        ? 1.0
        : Curves.easeOut.transform((progress.value / 0.36).clamp(0.0, 1.0));
    final pulseBounds = Rect.fromCenter(
      center: bounds.center,
      width: bounds.width * scale,
      height: bounds.height * scale,
    );
    final alpha = foreground
        ? (reducedMotion ? 0.35 : 0.85)
        : (reducedMotion ? 0.22 : 0.32);
    canvas.save();
    canvas.clipRRect(borderRadius.toRRect(bounds));
    canvas.drawRRect(
      (borderRadius * scale).toRRect(pulseBounds),
      Paint()
        ..color = color.withValues(alpha: alpha * strength)
        ..blendMode = foreground ? BlendMode.srcATop : BlendMode.srcOver,
    );
    canvas.restore();
  }
}

class _PulsePainter extends BoxPainter {
  _PulsePainter(this.decoration, super.onChanged) {
    decoration.progress.addListener(_repaint);
  }

  final _PulseDecoration decoration;

  void _repaint() => onChanged?.call();

  @override
  void dispose() {
    decoration.progress.removeListener(_repaint);
    super.dispose();
  }

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size != null) decoration.paint(canvas, offset & size);
  }
}

class _PulseContent extends SingleChildRenderObjectWidget {
  const _PulseContent({required this.decoration, required super.child});

  final _PulseDecoration decoration;

  @override
  _RenderPulseContent createRenderObject(BuildContext context) =>
      _RenderPulseContent(decoration);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPulseContent renderObject,
  ) {
    renderObject.decoration = decoration;
  }
}

class _RenderPulseContent extends RenderProxyBox {
  _RenderPulseContent(this._decoration);

  _PulseDecoration _decoration;

  set decoration(_PulseDecoration value) {
    if (attached) _decoration.progress.removeListener(markNeedsPaint);
    _decoration = value;
    if (attached) _decoration.progress.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _decoration.progress.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _decoration.progress.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_decoration.opacity <= 0) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    // Isolate foreground alpha, including composited/fading labels, so the
    // color shift affects glyphs and icons without tinting empty button space.
    layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (context, offset) {
        super.paint(context, offset);
        _decoration.paint(context.canvas, offset & size, foreground: true);
      },
      clipBehavior: Clip.antiAliasWithSaveLayer,
      oldLayer: layer as ClipRectLayer?,
    );
  }
}
