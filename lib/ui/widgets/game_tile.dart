/// A library card as one render object. A [GameTile] watches its game,
/// selection and the card settings, and [RenderGameTile] lays the card out,
/// paints it and runs its animations, so a card entering the list costs a
/// few elements where a card of widgets cost over a hundred.
/// Badges get their tooltips only while the card is hovered.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/format_utils.dart';
import '../../models/game.dart';
import '../../providers/app_providers.dart';
import '../pages/home_sections/game_card_reveal.dart';
import 'game_card_badges.dart';
import 'game_card_interaction.dart';
import 'game_tile_render.dart';

export 'game_tile_render.dart' show GameTileDesign;

class const GameTile({
  super.key,
  required final int gameId,
  required final GameTileDesign design,

  /// Reveals the card as it comes into view; without one it shows at once.
  final GameCardRevealCoordinator? coordinator,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<GameTile> createState() => _GameTileState();
}

class _GameTileState extends ConsumerState<GameTile>
    with
        TickerProviderStateMixin,
        GameCardInteractionMixin<GameTile>,
        GameCardReveal {
  late Game _game;
  bool _hovered = false;
  TapGestureRecognizer? _secondaryTap;
  DoubleTapGestureRecognizer? _doubleTap;
  LongPressGestureRecognizer? _longPress;

  /// The spinner stays a moment after its fetch, as its status fades out.
  GameFetchStatus? _fetchStatus;
  Timer? _spinnerFade;

  /// The cover that failed to load; the grid card shows its title instead.
  String? _failedCover;

  /// A chip a finger pressed, and the one whose tooltip a long press there
  /// shows, as a chip's own Tooltip shows it on touch screens.
  GameTileSlot? _pressedChip, _touchTooltip;
  final _touchTooltipKey = GlobalKey<TooltipState>();
  Timer? _touchTooltipTimer;

  @override
  Game get cardGame => _game;

  @override
  bool get dragSelectionHandledByParent => widget.design != GameTileDesign.grid;

  @override
  void dispose() {
    _secondaryTap?.dispose();
    _doubleTap?.dispose();
    _longPress?.dispose();
    _spinnerFade?.cancel();
    _touchTooltipTimer?.cancel();
    super.dispose();
  }

  // The gestures a GestureDetector around the card would recognise.
  void _onPointer(PointerEvent event) {
    switch (event) {
      case PointerDownEvent():
        final settings = MediaQuery.maybeGestureSettingsOf(context);
        for (final recognizer in <GestureRecognizer>[
          _secondaryTap ??= TapGestureRecognizer(debugOwner: this)
            ..onSecondaryTapDown = (details) =>
                showContextMenu(details.globalPosition),
          _doubleTap ??= DoubleTapGestureRecognizer(debugOwner: this)
            ..onDoubleTap = handleDoubleTap,
          _longPress ??= LongPressGestureRecognizer(debugOwner: this)
            ..onLongPress = _onLongPress
            ..onLongPressUp = _onLongPressUp,
        ]) {
          recognizer
            ..gestureSettings = settings
            ..addPointer(event);
        }
        _pressedChip = event.kind == PointerDeviceKind.mouse
            ? null
            : tile?.tooltipSlotAt(event.localPosition);
        // Pressed, it must react at once: drawn live from now on.
        tile?.revealLive = true;
        handlePointerDown(event);
      case PointerMoveEvent():
        handlePointerMove(event);
      case PointerUpEvent():
        handlePointerUp(event);
      case PointerCancelEvent():
        handlePointerCancel(event);
      default:
    }
  }

  /// A long press on a chip with a tooltip shows the tooltip, and the
  /// card does not take it.
  void _onLongPress() {
    final chip = _pressedChip;
    if (chip == null) return handleLongPress();
    Feedback.forLongPress(context);
    _touchTooltipTimer?.cancel();
    setState(() => _touchTooltip = chip);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _touchTooltipKey.currentState?.ensureTooltipVisible(),
    );
  }

  /// The tooltip stays a moment after the finger lifts, then goes.
  void _onLongPressUp() {
    if (_touchTooltip == null) return;
    _touchTooltipTimer = Timer(const Duration(milliseconds: 1500), () {
      Tooltip.dismissAllToolTips();
      _touchTooltipTimer = Timer(kFastAnimation, () {
        if (mounted) setState(() => _touchTooltip = null);
      });
    });
  }

  void _onEnter(PointerEnterEvent event) {
    handleDragSelectionEvent(event);
    if (!mounted) return;
    // The zoom starts now, as the card's own MouseRegion started it.
    pointerOver = true;
    tile
      ?..revealLive = true
      ..hover(true);
    setState(() => _hovered = true);
  }

  void _onExit(PointerExitEvent event) {
    if (!dragSelectionHandledByParent) {
      ref.read(dragSelectionProvider.notifier).unmarkVisited(_game.id);
    }
    if (!mounted) return;
    pointerOver = false;
    tile?.hover(false);
    setState(() => _hovered = false);
  }

  Widget _tooltip(GameTileSlot slot, String message) => GameTileSlotWidget(
    key: ValueKey(slot),
    slot: slot,
    child: Tooltip(
      key: slot == _touchTooltip ? _touchTooltipKey : null,
      message: message,
      child: const SizedBox.expand(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(
      gamesByIdProvider.select((games) => games[widget.gameId]),
    );
    if (game == null) return const SizedBox.shrink();
    _game = game;
    final theme = ref.watch(themeProvider);
    final settings = ref.watch(gameCardSettingsProvider);
    final selected = ref.watch(
      gamesProvider.select((s) => s.selectedGameIds.contains(game.id)),
    );
    final viewed = ref.watch(
      viewedNewGameIdsProvider.select((ids) => ids.contains(game.id)),
    );
    final fetchStatus = ref.watch(
      batchFetchProvider.select((s) => s.getStatus(game.id)),
    );
    if (_fetchStatus == GameFetchStatus.processing &&
        fetchStatus != GameFetchStatus.processing) {
      _spinnerFade = Timer(kFastAnimation, () {
        if (mounted) setState(() {});
      });
    }
    _fetchStatus = fetchStatus;
    final slim = widget.design == GameTileDesign.slim;
    final showNew = GameCardBadges.showsNew(game, viewed: viewed);
    final showPlatform =
        settings.showPlatform &&
        (!settings.showPlatformOnHoverOnly || _hovered);
    final showRatings =
        settings.showRatings && (!settings.showTagsOnHoverOnly || _hovered);
    final showDeadline = settings.showDeadline && game.hasDeadline;
    final defaults = DefaultTextStyle.of(context);
    // The chips' tooltips, there while the card is hovered, or one at a
    // time after a long press on a touch screen.
    final tooltips = {
      if (showNew)
        GameTileSlot.newChip:
            'Added ${dayMonthYearFormat.format(game.dateAdded)}',
      if (showDeadline)
        GameTileSlot.deadline: GameCardBadges.deadlineInfo(
          theme,
          game.deadlineDate,
        ).tooltip,
      if (showRatings && game.reviewCount > 0)
        GameTileSlot.rating: GameCardBadges.ratingInfo(theme, game).tooltip,
      if (showPlatform) GameTileSlot.platform: game.platform,
      if (slim && fetchStatus != null)
        GameTileSlot.fetch: switch (fetchStatus) {
          GameFetchStatus.waiting => 'Queued for fetch',
          GameFetchStatus.processing => 'Fetching from Steam',
          GameFetchStatus.done => 'Fetch completed',
          GameFetchStatus.error => 'Fetch failed',
        },
      if (slim && selected) GameTileSlot.selected: 'Selected',
    };

    return GameTileBox(
      data: (
        design: widget.design,
        game: game,
        theme: theme,
        text: (
          style: defaults.style,
          scaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
          heightBehavior:
              defaults.textHeightBehavior ??
              DefaultTextHeightBehavior.maybeOf(context),
          widthBasis: defaults.textWidthBasis,
          bold: MediaQuery.boldTextOf(context),
          icons: IconTheme.of(context),
          pixelRatio: MediaQuery.devicePixelRatioOf(context),
        ),
        hovered: _hovered,
        selected: selected,
        showNew: showNew,
        showPlatform: showPlatform,
        showRatings: showRatings,
        showDeadline: settings.showDeadline,
        fetchStatus: fetchStatus,
        // A cover names the game itself, so the title shows only without
        // one, and always then, so no card is left blank.
        titleVisible: !game.hasCoverImage || _failedCover == game.coverImage,
        images: createLocalImageConfiguration(context),
        showTags: settings.showTags,
        tagsVisible: !settings.showTagsOnHoverOnly || _hovered,
      ),
      vsync: this,
      onPointer: _onPointer,
      onEnter: _onEnter,
      onExit: _onExit,
      onCoverError: () {
        if (mounted) setState(() => _failedCover = _game.coverImage);
      },
      // Its reveal waits for its cover.
      coverListener: revealPlain ? null : this,
      reveal: revealPlain ? null : revealAnimation,
      onRevealPaint: revealPlain ? null : revealVisible,
      children: [
        for (final MapEntry(key: slot, value: message) in tooltips.entries)
          if (_hovered || slot == _touchTooltip) _tooltip(slot, message),
        // AppCircularProgressIndicator's, without its own layer, so it
        // fades with the overlay it sits in.
        if (fetchStatus == GameFetchStatus.processing ||
            (_spinnerFade?.isActive ?? false))
          GameTileSlotWidget(
            key: const ValueKey(GameTileSlot.spinner),
            slot: GameTileSlot.spinner,
            child: CircularProgressIndicator(
              color: theme.accent,
              backgroundColor: theme.accent.withValues(alpha: 0.4),
              strokeWidth: theme.progressIndicatorStrokeWidth,
            ),
          ),
      ],
    );
  }
}
