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

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../widgets/game_cover_image.dart';
import '../../widgets/game_tile.dart';
import '../../widgets/game_tile_render.dart';

/// Tracks revealed entries for one library session without keeping cards alive.
class GameCardRevealCoordinator {
  GameCardRevealCoordinator({this.scrollReveals = true});

  /// Whether cards scrolled into view reveal. If not, only the cards built
  /// before the first scroll do.
  final bool scrollReveals;
  bool _scrolledOn = false;
  final _revealedIds = <int>{};
  final _cards = <GameCardReveal>{};
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
  void _detach(GameCardReveal card) {
    _cards.remove(card);
    if (_cards.isEmpty) _skipTimer?.cancel();
    if (_unmountedIds.isEmpty) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        final mounted = {for (final card in _cards) card._revealId};
        _revealedIds.removeAll(_unmountedIds.difference(mounted));
        _unmountedIds.clear();
      });
    }
    _unmountedIds.add(card._revealId);
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

/// A library card's reveal: when it starts, what it waits for, and how far
/// it has run, for the card to draw from [revealAnimation].
mixin GameCardReveal on State<GameTile>, TickerProvider
    implements CoverLoadListener {
  /// The card's render object, which draws the reveal and tells when it is
  /// painted in view.
  RenderGameTile? get tile => switch (context.findRenderObject()) {
    final RenderGameTile tile => tile,
    _ => null,
  };

  /// Whether the card was last drawn from still images of itself.
  bool get drawsStills => tile?.drawsStills ?? false;

  bool _controllerMade = false;
  late final revealController = () {
    _controllerMade = true;
    return AnimationController(
      duration: const Duration(milliseconds: 200),
      value: _coordinator!.startsShown(_revealId) ? 1 : 0,
      vsync: this,
    );
  }();
  late final revealAnimation = CurvedAnimation(
    parent: revealController,
    curve: Curves.easeOutCubic,
  );

  int get _revealId => widget.gameId;
  GameCardRevealCoordinator? get _coordinator => widget.coordinator;

  /// A pointer over or pressing the card: it must react at once, so the card
  /// is drawn live from then on.
  bool pointerOver = false;
  bool _started = false;

  /// A card that does not reveal, or one built after a layout-only reveal
  /// ended: just itself, with nothing to reveal or check.
  late bool revealPlain;

  /// In view, waiting for or running its reveal.
  bool _visible = false;
  Timer? _startTimer;
  Timer? _coverTimer;
  final _loadingCovers = <Object>{};

  /// A slow or unreachable cover never keeps its card hidden for long.
  static const Duration _maxCoverWait = Duration(seconds: 2);

  /// Hidden and waiting to come into view.
  bool get _armed => !_visible && !_started && revealController.value == 0;

  @override
  void initState() {
    super.initState();
    final coordinator = _coordinator;
    revealPlain = coordinator == null || !coordinator._reveals;
    if (!revealPlain) coordinator!._cards.add(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!revealPlain && MediaQuery.disableAnimationsOf(context)) {
      _showImmediately();
    }
  }

  @override
  void didUpdateWidget(GameTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.coordinator;
    final coordinator = _coordinator;
    if (oldWidget.gameId == _revealId && old == coordinator) return;
    old?._cards.remove(this);
    // A new coordinator, as a layout switch brings, reveals the card anew.
    if (revealPlain) {
      revealPlain = coordinator == null || !coordinator._reveals;
    } else if (coordinator == null) {
      _startTimer?.cancel();
      _coverTimer?.cancel();
      revealPlain = true;
    }
    if (revealPlain) return;
    coordinator!._cards.add(this);
    _reset(coordinator.startsShown(_revealId) ? 1 : 0);
    if (MediaQuery.disableAnimationsOf(context)) {
      _showImmediately();
    } else {
      // A kept card may reuse its last paint: find it in view instead.
      coordinator._scheduleViewportCheck();
    }
  }

  void _reset(double value) {
    _startTimer?.cancel();
    _coverTimer?.cancel();
    _started = _visible = false;
    // Armed again: no stills, and drawn live only while a pointer is on it.
    tile
      ?..revealLive = pointerOver
      ..clearStills();
    revealController.value = value;
    tile?.rearm();
  }

  /// Hides a shown card that is fully outside the viewport, and reveals a
  /// hidden one that is back in it.
  void _syncWithViewport() {
    if (!mounted || MediaQuery.disableAnimationsOf(context)) return;
    final box = tile;
    if (box == null) return;
    if (box.inViewport) {
      revealVisible();
    } else if (!_armed) {
      _coordinator!._revealedIds.remove(_revealId);
      _reset(0);
    }
  }

  /// Shows a card that is waiting for or running its reveal at once, or any
  /// card not yet shown with [all].
  void _finishReveal({bool all = false}) {
    if (mounted &&
        !revealController.isCompleted &&
        (all || _started || _visible)) {
      _showImmediately();
    }
  }

  void _showImmediately() {
    _startTimer?.cancel();
    _coverTimer?.cancel();
    _started = true;
    _coordinator?.markRevealed(_revealId);
    revealController.value = 1;
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

  /// The card was painted in view: it reveals, once its cover is ready.
  void revealVisible() {
    if (!mounted || revealPlain || !_armed) return;
    _visible = true;
    if (_coordinator!._skipsReveals) {
      _showImmediately();
    } else if (_loadingCovers.isEmpty) {
      _startReveal();
    } else {
      _coverTimer = Timer(_maxCoverWait, _startRevealNextFrame);
    }
  }

  void _startReveal() {
    if (!mounted || revealPlain || _started || revealController.isCompleted) {
      return;
    }
    _started = true;
    _coverTimer?.cancel();
    final delay = _coordinator!.reveal(_revealId, row: tile?.viewportTop);
    if (delay == Duration.zero) {
      revealController.forward();
    } else {
      _startTimer = Timer(delay, () {
        if (mounted) revealController.forward();
      });
    }
  }

  @override
  void dispose() {
    if (!revealPlain) _coordinator?._detach(this);
    _startTimer?.cancel();
    _coverTimer?.cancel();
    if (_controllerMade) {
      revealAnimation.dispose();
      revealController.dispose();
    }
    super.dispose();
  }
}

/// A card's render object that tells when the card is painted in view.
/// Slivers paint only entries intersecting their viewport: listening to the
/// first paint there avoids starting animations for the offscreen scroll
/// cache, and needs no visibility polling or per-card scroll listeners. A
/// re-armed card shrinks back and hides its cover, which repaints it on its
/// return.
mixin RevealViewportBox on RenderBox {
  /// Called after the frame in which the card was first painted in view.
  VoidCallback? onRevealPaint;
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

  /// Tells [onRevealPaint] after this frame if this is the card's first
  /// paint in view; called after painting.
  void revealPainted() {
    if (onRevealPaint == null || _scheduled || !inViewport) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) onRevealPaint?.call();
    });
  }
}
