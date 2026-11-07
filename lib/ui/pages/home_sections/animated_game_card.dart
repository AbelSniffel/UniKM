/// Viewport-triggered card reveals, with a short stagger for each visible batch.
/// A card whose cover is still loading waits for its picture, so each card
/// pops in on its own as soon as it is ready. A card that scrolls out of view
/// reveals again when it comes back, in either direction. While the window
/// resizes or the library scrolls fast, cards show at once instead.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../widgets/game_cover_image.dart';

/// Tracks revealed entries for one library session without keeping cards alive.
class GameCardRevealCoordinator {
  final _revealedIds = <int>{};
  final _cards = <_AnimatedGameCardState>{};
  final _unmountedIds = <int>{};
  bool _viewportCheckScheduled = false;
  Duration? _batchFrame;
  int _batchIndex = 0;
  double _scrolledSinceCheck = 0;
  double _viewportExtent = 0;
  Duration? _lastScrollCheck;
  Timer? _skipTimer;

  /// Faster than this many viewport lengths a second, cards show at once.
  static const double _fastScrollViewportsPerSecond = 21;

  /// How long fast scrolling or a resize keeps skipping reveals after its
  /// last frame. A longer gap between scroll frames starts a new scroll.
  static const Duration _settleTime = Duration(milliseconds: 150);

  bool hasRevealed(int gameId) => _revealedIds.contains(gameId);

  void markRevealed(int gameId) => _revealedIds.add(gameId);

  bool get _skipsReveals => _skipTimer?.isActive ?? false;

  /// Listens above the library and a [SizeChangedLayoutNotifier] around it.
  ///
  /// Scrolling re-arms the reveal of cards that left the view but are still
  /// kept in the scroll cache, and reveals them again when they return: a
  /// cached card keeps its last paint, so its return is found here rather
  /// than by painting. A resize shows every card at once.
  bool onNotification(Notification notification) {
    switch (notification) {
      // Only the library's own scrolling, not a scrolling row inside a card.
      case ScrollUpdateNotification(
        depth: 0,
        :final scrollDelta,
        :final metrics,
      ):
        _scrolledSinceCheck += (scrollDelta ?? 0).abs();
        _viewportExtent = metrics.viewportDimension;
        _scheduleViewportCheck();
      case SizeChangedLayoutNotification():
        // Sent during layout: cards update after it, before the reveals that
        // the frame's paint starts.
        SchedulerBinding.instance.addPostFrameCallback((_) => _skipReveals());
        return true;
    }
    return false;
  }

  /// Checks the cards once per frame, after layout has placed them at the
  /// new offset, which is also when the scroll speed is taken.
  void _scheduleViewportCheck() {
    if (_cards.isEmpty || _viewportCheckScheduled) return;
    _viewportCheckScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _viewportCheckScheduled = false;
      if (_scrolledSinceCheck > 0) _measureScrollSpeed();
      for (final card in _cards.toList()) {
        card._syncWithViewport();
      }
    });
  }

  void _measureScrollSpeed() {
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    final elapsed = now - (_lastScrollCheck ?? Duration.zero);
    final distance = _scrolledSinceCheck;
    final first = _lastScrollCheck == null;
    _lastScrollCheck = now;
    _scrolledSinceCheck = 0;
    // A single jump or the first step after a pause has no speed yet.
    if (first || elapsed > _settleTime) return;
    final perSecond =
        distance *
        Duration.microsecondsPerSecond /
        math.max(elapsed.inMicroseconds, 8000);
    if (perSecond > _fastScrollViewportsPerSecond * _viewportExtent) {
      _skipReveals();
    }
  }

  /// Many reveals at once, while resizing or scrolling fast, would lag and
  /// trail behind: cards show at once instead, including running reveals.
  void _skipReveals() {
    _skipTimer?.cancel();
    _skipTimer = Timer(_settleTime, () {});
    for (final card in _cards.toList()) {
      card._finishReveal();
    }
  }

  /// A card dropped by scrolling reveals again when it is built anew; one
  /// rebuilt in the same frame, as when filters move it, stays revealed.
  void _detach(_AnimatedGameCardState card) {
    _cards.remove(card);
    if (_cards.isEmpty) _skipTimer?.cancel();
    if (_unmountedIds.isEmpty) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        final mounted = {for (final card in _cards) card.widget.gameId};
        _revealedIds.removeAll(_unmountedIds.difference(mounted));
        _unmountedIds.clear();
      });
    }
    _unmountedIds.add(card.widget.gameId);
  }

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
}

class AnimatedGameCard extends StatefulWidget {
  const AnimatedGameCard({
    super.key,
    required this.gameId,
    required this.coordinator,
    required this.child,
    this.placeholder,
  });

  final int gameId;
  final GameCardRevealCoordinator coordinator;
  final Widget child;

  /// Holds the card's place, at its full size, until it shows, fading out
  /// as the card fades in. It animates only while the card is in view.
  final Widget? placeholder;

  @override
  State<AnimatedGameCard> createState() => _AnimatedGameCardState();
}

class _AnimatedGameCardState extends State<AnimatedGameCard>
    with SingleTickerProviderStateMixin
    implements CoverLoadListener {
  late final _controller = AnimationController(
    duration: const Duration(milliseconds: 200),
    value: widget.coordinator.hasRevealed(widget.gameId) ? 1 : 0,
    vsync: this,
  );
  late final _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final _placeholderFade = ReverseAnimation(_animation);
  bool _started = false;

  /// In view, waiting for or running its reveal.
  final _inView = ValueNotifier(false);
  bool get _visible => _inView.value;
  set _visible(bool value) => _inView.value = value;
  Timer? _startTimer;
  Timer? _coverTimer;
  final _loadingCovers = <Object>{};

  static const double _startScale = 0.9;

  /// A slow or unreachable cover never keeps its card hidden for long.
  static const Duration _maxCoverWait = Duration(seconds: 2);

  /// Hidden and waiting to come into view.
  bool get _armed => !_visible && !_started && _controller.value == 0;

  @override
  void initState() {
    super.initState();
    widget.coordinator._cards.add(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _showImmediately();
  }

  @override
  void didUpdateWidget(AnimatedGameCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gameId == widget.gameId &&
        oldWidget.coordinator == widget.coordinator) {
      return;
    }
    oldWidget.coordinator._cards.remove(this);
    widget.coordinator._cards.add(this);
    _reset(widget.coordinator.hasRevealed(widget.gameId) ? 1 : 0);
    if (MediaQuery.disableAnimationsOf(context)) {
      _showImmediately();
    } else {
      // A kept card may reuse its last paint: find it in view instead.
      widget.coordinator._scheduleViewportCheck();
    }
  }

  void _reset(double value) {
    _startTimer?.cancel();
    _coverTimer?.cancel();
    _started = _visible = false;
    _controller.value = value;
    (context.findRenderObject() as _RenderRevealOnPaint?)?.rearm();
  }

  /// Hides a shown card that is fully outside the viewport, and reveals a
  /// hidden one that is back in it.
  void _syncWithViewport() {
    if (!mounted || MediaQuery.disableAnimationsOf(context)) return;
    final box = context.findRenderObject();
    if (box is! _RenderRevealOnPaint) return;
    if (box.inViewport) {
      _onVisible();
    } else if (!_armed) {
      widget.coordinator._revealedIds.remove(widget.gameId);
      _reset(0);
    }
  }

  /// Shows a card that is waiting for or running its reveal at once.
  void _finishReveal() {
    if (mounted && !_controller.isCompleted && (_started || _visible)) {
      _showImmediately();
    }
  }

  void _showImmediately() {
    _startTimer?.cancel();
    _coverTimer?.cancel();
    _started = true;
    widget.coordinator.markRevealed(widget.gameId);
    _controller.value = 1;
  }

  @override
  void coverLoading(Object cover) => _loadingCovers.add(cover);

  @override
  void coverSettled(Object cover) {
    if (!_loadingCovers.remove(cover) || _loadingCovers.isNotEmpty) return;
    // Reports arrive while the tree builds or unmounts.
    if (_visible && !_started) _startRevealNextFrame();
  }

  /// The stagger is per frame, so a reveal from a report or timer starts
  /// with the next one.
  void _startRevealNextFrame() {
    SchedulerBinding.instance.addPostFrameCallback((_) => _startReveal());
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _onVisible() {
    if (!mounted || !_armed) return;
    _visible = true;
    if (widget.coordinator._skipsReveals) {
      _showImmediately();
    } else if (_loadingCovers.isEmpty) {
      _startReveal();
    } else {
      _coverTimer = Timer(_maxCoverWait, _startRevealNextFrame);
    }
  }

  void _startReveal() {
    if (!mounted || _started || _controller.isCompleted) return;
    _started = true;
    _coverTimer?.cancel();
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
    widget.coordinator._detach(this);
    _startTimer?.cancel();
    _coverTimer?.cancel();
    _inView.dispose();
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _RevealOnPaint(
    key: ValueKey((widget.coordinator, widget.gameId)),
    onPaint: _onVisible,
    child: AnimatedBuilder(
      animation: _animation,
      // Fade in while growing from the card's centre, like an app opening.
      // A hidden card paints nothing; the card's own repaint boundary keeps
      // its contents from repainting while it scales.
      builder: (context, child) {
        final card = Opacity(
          opacity: _animation.value,
          child: Transform.scale(
            scale: _startScale + (1 - _startScale) * _animation.value,
            child: child,
          ),
        );
        final placeholder = widget.placeholder;
        if (placeholder == null) return card;
        return Stack(
          fit: StackFit.passthrough,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: _animation.value == 1
                  ? const SizedBox.shrink()
                  // Out of view, its animation pauses.
                  : ValueListenableBuilder(
                      valueListenable: _inView,
                      builder: (context, inView, child) =>
                          TickerMode(enabled: inView, child: child!),
                      child: FadeTransition(
                        opacity: _placeholderFade,
                        child: placeholder,
                      ),
                    ),
            ),
            card,
          ],
        );
      },
      child: CoverLoadScope(listener: this, child: widget.child),
    ),
  );
}

/// Slivers paint only entries intersecting their viewport. Listening to their
/// first paint avoids starting animations for the offscreen scroll cache, and
/// needs no visibility polling or per-card scroll listeners. A re-armed card
/// faded out to nothing, which repaints it on its return.
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
  ) => renderObject.onPaint = onPaint;
}

class _RenderRevealOnPaint extends RenderProxyBox {
  _RenderRevealOnPaint(this.onPaint);

  VoidCallback onPaint;
  bool _scheduled = false;

  void rearm() => _scheduled = false;

  /// A list row's bottom spacing can intersect the viewport while its card
  /// is still outside it, so this checks the card itself.
  bool get inViewport {
    if (!attached || !hasSize) return false;
    final viewport = RenderAbstractViewport.maybeOf(this);
    if (viewport == null) return true;
    final bounds = MatrixUtils.transformRect(
      getTransformTo(viewport),
      Offset.zero & size,
    );
    return bounds.overlaps(viewport.paintBounds);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (_scheduled || !inViewport) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) onPaint();
    });
  }
}
