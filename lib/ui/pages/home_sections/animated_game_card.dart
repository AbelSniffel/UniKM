/// Viewport-triggered card reveals, with a short stagger for each visible batch.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// Tracks revealed entries for one library session without keeping cards alive.
class GameCardRevealCoordinator {
  final _revealedIds = <int>{};
  Duration? _batchFrame;
  int _batchIndex = 0;
  double? _lastScrollPixels;
  bool _scrollingTowardEnd = true;

  bool hasRevealed(int gameId) => _revealedIds.contains(gameId);

  void markRevealed(int gameId) => _revealedIds.add(gameId);

  Duration reveal(int gameId) {
    markRevealed(gameId);
    final frame = SchedulerBinding.instance.currentFrameTimeStamp;
    if (_batchFrame != frame) {
      _batchFrame = frame;
      _batchIndex = 0;
    }
    // Restart the stagger for newly visible batches, even deep in the library.
    // A fast scroll never accumulates a long queue of delayed reveals.
    final delay = Duration(milliseconds: _batchIndex.clamp(0, 7) * 22);
    _batchIndex++;
    return delay;
  }

  /// The edge a revealed card grows from. Scrolling down brings cards in at
  /// the bottom, so they grow up from their bottom edge; scrolling up brings
  /// them in at the top, so they grow down from their top edge. The direction
  /// comes from the offset itself because `userScrollDirection` is already
  /// idle again after a mouse-wheel step.
  Alignment growthAlignment(ScrollPosition? position) {
    if (position != null && position.hasPixels) {
      final pixels = position.pixels;
      final last = _lastScrollPixels;
      if (last != null && pixels != last) _scrollingTowardEnd = pixels > last;
      _lastScrollPixels = pixels;
    }
    return _scrollingTowardEnd ? Alignment.bottomCenter : Alignment.topCenter;
  }
}

class AnimatedGameCard extends StatefulWidget {
  const AnimatedGameCard({
    super.key,
    required this.gameId,
    required this.coordinator,
    required this.child,
  });

  final int gameId;
  final GameCardRevealCoordinator coordinator;
  final Widget child;

  @override
  State<AnimatedGameCard> createState() => _AnimatedGameCardState();
}

class _AnimatedGameCardState extends State<AnimatedGameCard>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    duration: const Duration(milliseconds: 220),
    value: widget.coordinator.hasRevealed(widget.gameId) ? 1 : 0,
    vsync: this,
  );
  late final _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  bool _started = false;
  Timer? _startTimer;
  Alignment _growFrom = Alignment.bottomCenter;

  static const double _startScale = 0.88;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _showImmediately();
  }

  @override
  void didUpdateWidget(AnimatedGameCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gameId != widget.gameId ||
        oldWidget.coordinator != widget.coordinator) {
      _startTimer?.cancel();
      _started = false;
      _controller.value = widget.coordinator.hasRevealed(widget.gameId) ? 1 : 0;
      if (MediaQuery.disableAnimationsOf(context)) _showImmediately();
    }
  }

  void _showImmediately() {
    _startTimer?.cancel();
    _started = true;
    widget.coordinator.markRevealed(widget.gameId);
    _controller.value = 1;
  }

  void _startReveal() {
    if (!mounted || _started || _controller.isCompleted) return;
    _started = true;
    _growFrom = widget.coordinator.growthAlignment(
      Scrollable.maybeOf(context)?.position,
    );
    final delay = widget.coordinator.reveal(widget.gameId);
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      _startTimer = Timer(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _RevealOnPaint(
    key: ValueKey((widget.coordinator, widget.gameId)),
    onPaint: _startReveal,
    child: AnimatedBuilder(
      animation: _animation,
      // Grow out from the middle horizontally, anchored at the edge the
      // card scrolled in from.
      builder: (context, child) => Opacity(
        opacity: _animation.value,
        child: Transform.scale(
          scale: _startScale + (1 - _startScale) * _animation.value,
          alignment: _growFrom,
          child: child,
        ),
      ),
      child: widget.child,
    ),
  );
}

/// Slivers paint only entries intersecting their viewport. Listening to their
/// first paint avoids starting animations for the offscreen scroll cache, and
/// needs no visibility polling or per-card scroll listeners.
class _RevealOnPaint extends SingleChildRenderObjectWidget {
  const _RevealOnPaint({
    super.key,
    required this.onPaint,
    required super.child,
  });

  final VoidCallback onPaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRevealOnPaint(onPaint);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRevealOnPaint renderObject,
  ) {
    renderObject.onPaint = onPaint;
  }
}

class _RenderRevealOnPaint extends RenderProxyBox {
  _RenderRevealOnPaint(this.onPaint);

  VoidCallback onPaint;
  bool _scheduled = false;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (_scheduled) return;
    // A list row's bottom spacing can intersect the viewport while its card
    // is still outside it. Check the card itself before claiming its reveal.
    final viewport = RenderAbstractViewport.maybeOf(this);
    if (viewport != null) {
      final bounds = MatrixUtils.transformRect(
        getTransformTo(viewport),
        Offset.zero & size,
      );
      if (!bounds.overlaps(viewport.paintBounds)) return;
    }
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) onPaint();
    });
  }
}
