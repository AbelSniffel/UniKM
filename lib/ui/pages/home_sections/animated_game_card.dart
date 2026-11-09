/// Viewport-triggered card reveals. A card is there from the start, at the
/// size it grows from, with its cover still in its loading tone. It grows to
/// full size as its cover fades in, so a cover never appears suddenly on a
/// card that is already shown. While it does, the card is drawn from still
/// images of itself, so growing costs image draws, not a live card's text and
/// overlays redrawn at each scale. The cards of the first load or a new layout
/// reveal together; cards scrolled into view cascade in, with a short stagger
/// for each visible batch, a whole grid row at a time.
/// A card whose cover is still loading waits for its picture, so each card
/// pops in on its own as soon as it is ready. A card that scrolls out of view
/// reveals again when it comes back, in either direction. While the window
/// resizes, cards show at once instead. A list whose cards do not
/// [GameCardRevealCoordinator.scrollReveals], like the slim list, reveals only
/// with its layout: the first scroll shows what is waiting, and the cards it
/// brings in are plain, so a long fling costs no more than the cards do.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../widgets/game_cover_image.dart';

/// Tracks revealed entries for one library session without keeping cards alive.
class GameCardRevealCoordinator {
  GameCardRevealCoordinator({this.scrollReveals = true});

  /// Whether cards scrolled into view reveal. If not, only the cards built
  /// before the first scroll do.
  final bool scrollReveals;
  bool _scrolledOn = false;
  final _revealedIds = <int>{};
  final _cards = <_AnimatedGameCardState>{};
  final _unmountedIds = <int>{};
  bool _viewportCheckScheduled = false;
  Duration? _batchFrame;
  int _batchIndex = 0;

  /// This frame's stagger step for each row top, so a grid row reveals as
  /// one; a list row holds a single card.
  final _batchRows = <double, int>{};
  bool _scrolled = false;

  /// The frame of the last viewport check after the library scrolled.
  Duration? _lastScrollCheck;
  Timer? _skipTimer;

  /// How long a resize keeps skipping reveals after its last frame, and how
  /// long after a scroll step the library still counts as scrolling.
  static const Duration _settleTime = Duration(milliseconds: 150);

  bool hasRevealed(int gameId) => _revealedIds.contains(gameId);

  /// Whether [gameId]'s card starts out shown: it was shown before, or
  /// reveals are being skipped, as while the window resizes.
  bool startsShown(int gameId) {
    if (_skipsReveals) markRevealed(gameId);
    return hasRevealed(gameId);
  }

  void markRevealed(int gameId) => _revealedIds.add(gameId);

  bool get _skipsReveals => _skipTimer?.isActive ?? false;

  /// Whether a card built now reveals, rather than being a plain card.
  bool get _reveals => scrollReveals || !_scrolledOn;

  /// Listens above the library and a [SizeChangedLayoutNotifier] around it.
  ///
  /// Scrolling re-arms the reveal of cards that left the view but are still
  /// kept in the scroll cache, and reveals them again when they return: a
  /// cached card keeps its last paint, so its return is found here rather
  /// than by painting. A resize shows every card at once.
  bool onNotification(Notification notification) {
    switch (notification) {
      // Only the library's own scrolling, not a scrolling row inside a card.
      case ScrollUpdateNotification(depth: 0, :final scrollDelta):
        if (!scrollReveals) {
          if ((scrollDelta ?? 0) != 0) _endLayoutReveal();
          return false;
        }
        _scrolled |= (scrollDelta ?? 0) != 0;
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
  /// new offset.
  void _scheduleViewportCheck() {
    if (_cards.isEmpty || _viewportCheckScheduled) return;
    _viewportCheckScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _viewportCheckScheduled = false;
      if (_scrolled) {
        _scrolled = false;
        _lastScrollCheck = SchedulerBinding.instance.currentFrameTimeStamp;
      }
      for (final card in _cards.toList()) {
        card._syncWithViewport();
      }
    });
  }

  /// The first scroll of a list that reveals only with its layout: what waits
  /// shows at once, and from now on cards are plain and no longer checked.
  void _endLayoutReveal() {
    if (_scrolledOn) return;
    _scrolledOn = true;
    _skipReveals(all: true);
    _cards.clear();
  }

  /// The window is resizing: every card shows at once, even one still out of
  /// view. Called before the frame builds, so a card the new size brings into
  /// view is never drawn at its starting size on the frame before its reveal
  /// would be found skipped.
  void onWindowResize() => _skipReveals(all: true);

  /// Many reveals at once, while resizing, would lag and trail behind: cards
  /// show at once instead, including running reveals.
  void _skipReveals({bool all = false}) {
    _skipTimer?.cancel();
    _skipTimer = Timer(_settleTime, () {});
    for (final card in _cards.toList()) {
      card._finishReveal(all: all);
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

  /// Starts [gameId]'s reveal, returning how long it waits first. Cards at
  /// the same [row], their top in the viewport, wait as long.
  Duration reveal(int gameId, {double? row}) {
    markRevealed(gameId);
    final frame = SchedulerBinding.instance.currentFrameTimeStamp;
    // Only cards brought in while the library scrolls cascade in. The
    // viewport check that follows a scroll runs before this frame's reveals.
    final lastScroll = _lastScrollCheck;
    if (lastScroll == null || frame - lastScroll > _settleTime) {
      return Duration.zero;
    }
    if (_batchFrame != frame) {
      _batchFrame = frame;
      _batchIndex = 0;
      _batchRows.clear();
    }
    // Restart the stagger for newly visible batches, even deep in the library.
    // A fast scroll never accumulates a long queue of delayed reveals.
    final step = row == null
        ? _batchIndex++
        : _batchRows[row] ??= _batchIndex++;
    return Duration(milliseconds: step.clamp(0, 7) * 22);
  }
}

class AnimatedGameCard extends StatefulWidget {
  const AnimatedGameCard({
    super.key,
    required this.gameId,
    required this.coordinator,
    required this.child,
    this.coverWidth = double.infinity,
  });

  final int gameId;
  final GameCardRevealCoordinator coordinator;
  final Widget child;

  /// How much of the card's left side its cover covers: all of it by
  /// default, none for a row without a cover.
  final double coverWidth;

  /// How far the card of [element], an [AnimatedGameCard]'s, has revealed,
  /// from 0 (at its starting size, cover hidden) to 1.
  @visibleForTesting
  static double debugRevealOf(Element element) {
    final state = (element as StatefulElement).state as _AnimatedGameCardState;
    return state._plain ? 1 : state._animation.value;
  }

  /// Whether the card of [element] was last drawn from still images of itself
  /// rather than as the live card.
  @visibleForTesting
  static bool debugDrawsStills(Element element) {
    final state = (element as StatefulElement).state as _AnimatedGameCardState;
    return !state._plain && state._popIn.drawsStills;
  }

  @override
  State<AnimatedGameCard> createState() => _AnimatedGameCardState();
}

class _AnimatedGameCardState extends State<AnimatedGameCard>
    with SingleTickerProviderStateMixin
    implements CoverLoadListener {
  late final _controller = AnimationController(
    duration: const Duration(milliseconds: 200),
    value: widget.coordinator.startsShown(widget.gameId) ? 1 : 0,
    vsync: this,
  );
  late final _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final _scale = _animation.drive(Tween(begin: _startScale, end: 1.0));

  late final _popIn = _PopIn(_animation);
  static final _noSnapshot = SnapshotController();

  /// A pointer over or pressing the card: it must react at once, so the card
  /// is drawn live from then on.
  bool _pointerOver = false;
  bool _started = false;

  /// A card built after a layout-only reveal ended: just its child, with
  /// nothing to reveal or check.
  late bool _plain;

  /// In view, waiting for or running its reveal.
  bool _visible = false;
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
    _plain = !widget.coordinator._reveals;
    if (!_plain) widget.coordinator._cards.add(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_plain && MediaQuery.disableAnimationsOf(context)) _showImmediately();
  }

  @override
  void didUpdateWidget(AnimatedGameCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gameId == widget.gameId &&
        oldWidget.coordinator == widget.coordinator) {
      return;
    }
    oldWidget.coordinator._cards.remove(this);
    // A new coordinator, as a layout switch brings, reveals the card anew.
    if (_plain) _plain = !widget.coordinator._reveals;
    if (_plain) return;
    widget.coordinator._cards.add(this);
    _reset(widget.coordinator.startsShown(widget.gameId) ? 1 : 0);
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
    _popIn
      ..live = _pointerOver
      ..clear();
    _controller.value = value;
    final box = context.findRenderObject();
    if (box is _RenderRevealOnPaint) box.rearm();
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

  /// Shows a card that is waiting for or running its reveal at once, or any
  /// card not yet shown with [all].
  void _finishReveal({bool all = false}) {
    if (mounted && !_controller.isCompleted && (all || _started || _visible)) {
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
    final box = context.findRenderObject() as _RenderRevealOnPaint?;
    final delay = widget.coordinator.reveal(
      widget.gameId,
      row: box?.viewportTop,
    );
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
    if (!_plain) {
      widget.coordinator._detach(this);
      _startTimer?.cancel();
      _coverTimer?.cancel();
      _popIn.dispose();
      _animation.dispose();
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_plain) return widget.child;
    _popIn
      ..coverWidth = widget.coverWidth
      ..pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return _RevealOnPaint(
      key: ValueKey((widget.coordinator, widget.gameId)),
      onPaint: _onVisible,
      // Grows from the card's centre, like an app opening, from the loading
      // card it already is, its cover fading in.
      child: ScaleTransition(
        scale: _scale,
        child: MouseRegion(
          opaque: false,
          onEnter: (_) {
            _pointerOver = true;
            _popIn.live = true;
          },
          onExit: (_) => _pointerOver = false,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _popIn.live = true,
            child: SnapshotWidget(
              controller: _noSnapshot,
              painter: _popIn,
              child: CoverLoadScope(listener: this, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws a card from still images of it until it has fully revealed: the card
/// as it waits, with its cover still loading, and the card with its cover in,
/// fading in over the first as the reveal runs. Each is taken once, at the
/// device's pixel ratio, so growing costs image draws, where the live card,
/// scaled, would redraw all its text and overlays at every scale. Revealed, or
/// touched by a pointer, the card paints as itself.
class _PopIn extends SnapshotPainter {
  _PopIn(this.reveal) {
    reveal.addListener(notifyListeners);
  }

  final Animation<double> reveal;

  /// How much of the card's left side its cover covers. The two images differ
  /// only there, so only there the second is drawn: a translucent background
  /// elsewhere would show through twice.
  double coverWidth = double.infinity;
  double pixelRatio = 1;

  /// Whether the last paint drew the still images.
  bool drawsStills = false;
  bool _live = false;
  ui.Image? _waiting, _covered;
  final _paint = Paint()..filterQuality = FilterQuality.low;

  set live(bool value) {
    if (value == _live) return;
    _live = value;
    notifyListeners();
  }

  void clear() {
    _waiting?.dispose();
    _covered?.dispose();
    _waiting = _covered = null;
  }

  @override
  void dispose() {
    reveal.removeListener(notifyListeners);
    clear();
    super.dispose();
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset,
    Size size,
    PaintingContextCallback painter,
  ) {
    final progress = reveal.value;
    drawsStills = progress < 1 && !_live;
    if (!drawsStills) {
      clear();
      return painter(context, offset);
    }
    // The child painted into a layer of its own, as a SnapshotWidget does.
    ui.Image capture() {
      final layer = OffsetLayer();
      final imageContext = PaintingContext(layer, Offset.zero & size);
      painter(imageContext, Offset.zero);
      // ignore: invalid_use_of_protected_member
      imageContext.stopRecordingIfNeeded();
      final image = layer.toImageSync(
        Offset.zero & size,
        pixelRatio: pixelRatio,
      );
      layer.dispose();
      return image;
    }

    _waiting ??= capture();
    final cover = Size(math.min(coverWidth, size.width), size.height);
    if (progress > 0 && !cover.isEmpty) _covered ??= capture();
    context.canvas.drawImageRect(
      _waiting!,
      Offset.zero & (size * pixelRatio),
      offset & size,
      _paint..color = const Color(0xFF000000),
    );
    if (_covered != null) {
      context.canvas.drawImageRect(
        _covered!,
        Offset.zero & (cover * pixelRatio),
        offset & cover,
        _paint..color = Color.fromRGBO(0, 0, 0, progress),
      );
    }
  }

  @override
  void paintSnapshot(
    PaintingContext context,
    Offset offset,
    Size size,
    ui.Image image,
    Size sourceSize,
    double pixelRatio,
  ) {}

  @override
  bool shouldRepaint(SnapshotPainter oldPainter) => false;
}

/// Slivers paint only entries intersecting their viewport. Listening to their
/// first paint avoids starting animations for the offscreen scroll cache, and
/// needs no visibility polling or per-card scroll listeners. A re-armed card
/// shrinks back and hides its cover, which repaints it on its return.
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

  Rect _boundsIn(RenderAbstractViewport viewport) =>
      MatrixUtils.transformRect(getTransformTo(viewport), Offset.zero & size);

  /// The top of this card in its viewport, to whole pixels: the cards of a
  /// grid row share it.
  double? get viewportTop {
    final viewport = attached && hasSize
        ? RenderAbstractViewport.maybeOf(this)
        : null;
    return viewport == null ? null : _boundsIn(viewport).top.roundToDouble();
  }

  /// A list row's bottom spacing can intersect the viewport while its card
  /// is still outside it, so this checks the card itself.
  bool get inViewport {
    if (!attached || !hasSize) return false;
    final viewport = RenderAbstractViewport.maybeOf(this);
    return viewport == null ||
        _boundsIn(viewport).overlaps(viewport.paintBounds);
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
