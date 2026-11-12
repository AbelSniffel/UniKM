/// GameCard widget — grid, list, and slim-list display for a single [Game].
///
/// Heavy logic has been extracted to dedicated files:
///  - Painters / data classes → game_card_painters.dart
///  - Badge / chip builders  → game_card_badges.dart
///  - Tag row + fit cache    → game_card_tags.dart
///  - Pointer / selection    → game_card_interaction.dart (mixin)
///  - Shared action handlers → game_selection_actions.dart
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import '../../providers/app_providers.dart';
import 'game_card_badges.dart';
import 'game_card_interaction.dart';
import 'game_card_painters.dart';
import 'game_card_tags.dart';
import 'game_cover_image.dart';
import 'game_selection_actions.dart';
import 'popup_menu_helpers.dart';
import 'used_overlay.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────

class GameCard extends ConsumerStatefulWidget {
  const GameCard({
    super.key,
    required this.game,
    this.viewMode,
    this.dragSelectionHandledByParent = false,
  });

  final Game game;
  final GameListViewMode? viewMode;
  final bool dragSelectionHandledByParent;

  @override
  ConsumerState<GameCard> createState() => _GameCardState();
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class _GameCardState extends ConsumerState<GameCard>
    with TickerProviderStateMixin, GameCardInteractionMixin<GameCard> {
  static const Duration _newBadgeLifetime = Duration(days: 1);
  static const Duration _hoverAnimationDuration = Duration(milliseconds: 180);

  // ── Per-card animation state ───────────────────────────────────────────────
  bool _isHovered = false;
  bool _imageLoadFailed = false;

  late final AnimationController _hoverController;
  late final Animation<double> _hoverAnim;
  late final AnimationController _selectionController;
  late final Animation<double> _selectionAnim;

  // ── GameCardInteractionMixin contract ──────────────────────────────────────
  @override
  Game get cardGame => widget.game;

  @override
  bool get dragSelectionHandledByParent => widget.dragSelectionHandledByParent;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(
      duration: _hoverAnimationDuration,
      reverseDuration: _hoverAnimationDuration,
      vsync: this,
    );
    _hoverAnim = CurvedAnimation(
      parent: _hoverController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _selectionController = AnimationController(
      duration: kMediumAnimation,
      vsync: this,
    );
    _selectionAnim = CurvedAnimation(
      parent: _selectionController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didUpdateWidget(GameCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game.coverImage != widget.game.coverImage) {
      _imageLoadFailed = false;
    }
  }

  @override
  void dispose() {
    _hoverController.dispose();
    _selectionController.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final cardSettings = ref.watch(gameCardSettingsProvider);
    final viewMode = widget.viewMode ?? ref.watch(viewModeProvider);
    final isSelected = ref.watch(
      gamesProvider.select((s) => s.selectedGameIds.contains(widget.game.id)),
    );
    final hasBeenViewed = ref.watch(
      viewedNewGameIdsProvider.select((ids) => ids.contains(widget.game.id)),
    );
    final fetchStatus = ref.watch(
      batchFetchProvider.select((s) => s.getStatus(widget.game.id)),
    );

    final showNewBadge = _shouldShowNewBadge(hasBeenViewed);
    final CardViewOptions options = (
      showPlatform:
          cardSettings.showPlatform &&
          (!cardSettings.showPlatformOnHoverOnly || _isHovered),
      showTags: cardSettings.showTags,
      showTagsOnHoverOnly: cardSettings.showTagsOnHoverOnly,
      showDeadline: cardSettings.showDeadline,
      showRatingsNow:
          cardSettings.showRatings &&
          (!cardSettings.showTagsOnHoverOnly || _isHovered),
    );

    // Drive selection animation — forward/reverse are no-ops when already at
    // the target value so this is inexpensive.
    if (isSelected) {
      _selectionController.forward();
    } else {
      _selectionController.reverse();
    }

    if (viewMode == GameListViewMode.grid) {
      return _buildGridCard(
        theme,
        isSelected,
        options,
        fetchStatus,
        showNewBadge,
      );
    }
    if (cardSettings.slimListView) {
      return _buildSlimListCard(
        theme,
        isSelected,
        options,
        fetchStatus,
        showNewBadge,
      );
    }
    return _buildListCard(
      theme,
      isSelected,
      options,
      fetchStatus,
      showNewBadge,
    );
  }

  // ── Grid card ──────────────────────────────────────────────────────────────

  Widget _buildGridCard(
    AppThemeData theme,
    bool isSelected,
    CardViewOptions options,
    GameFetchStatus? fetchStatus,
    bool showNewBadge,
  ) {
    final radius = BorderRadius.circular(theme.cornerRadius);
    // A cover names the game itself, so the title shows only without one,
    // and always then, so no card is left blank.
    final bool titleVisible = !widget.game.hasCoverImage || _imageLoadFailed;

    // Grid cards show no tags: the cover has no room for them.
    return _buildAnimatedShell(
      width: kGridCardWidth,
      height: kGridCardHeight,
      scaleFactor: 0.015,
      decorationBuilder: (t) => BoxDecoration(
        borderRadius: radius,
        boxShadow: _hoverShadow(theme, t, 0.2),
      ),
      child: ClipRRect(
        borderRadius: radius,
        // On fractional pixels a bright cover bleeds through the dark USED
        // tint along the card's edges. The tint reaches a pixel past them,
        // and a used card's layers are clipped once, together.
        clipBehavior: widget.game.isUsed
            ? Clip.antiAliasWithSaveLayer
            : Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          // The rounded clip above trims the tint's extra pixel.
          clipBehavior: Clip.none,
          children: [
            _buildCoverImage(theme),
            if (widget.game.isUsed)
              Positioned.fill(
                left: -1,
                top: -1,
                right: -1,
                bottom: -1,
                child: UsedOverlay(
                  theme: theme,
                  patternSize: const Size(kGridCardWidth, kGridCardHeight),
                  gridView: true,
                ),
              ),
            // Above the USED pattern, so a used card shows its selection and
            // hover glow as brightly as any other.
            _buildGradientOverlay(theme, isSelected),
            _buildSelectionOverlay(theme, isSelected),
            _buildAnimatedFetchOverlay(theme, fetchStatus),
            if (showNewBadge) _buildNewChip(theme),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (options.showDeadline && widget.game.hasDeadline) ...[
                    GameCardBadges.deadlineBadge(
                      theme,
                      widget.game.deadlineDate,
                    ),
                    if (titleVisible) const SizedBox(height: 4),
                  ],
                  if (titleVisible)
                    GameCardBadges.titleChip(theme, widget.game.title),
                ],
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: GameCardBadges.topRightChips(
                theme,
                widget.game,
                showPlatform: options.showPlatform,
                showRatings: options.showRatingsNow,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── List card ──────────────────────────────────────────────────────────────

  Widget _buildListCard(
    AppThemeData theme,
    bool isSelected,
    CardViewOptions options,
    GameFetchStatus? fetchStatus,
    bool showNewBadge,
  ) {
    final listRadius = BorderRadius.circular(theme.cornerRadius);
    final leftRadius = BorderRadius.horizontal(
      left: Radius.circular(theme.cornerRadius),
    );
    final gradientColors = _computeListGradientColors(theme, isSelected);
    final listGradient = LinearGradient(
      // ignore: prefer_const_constructors
      transform: GradientRotation(25 * math.pi / 180),
      colors: [theme.background, gradientColors[1], gradientColors[0]],
      stops: const [0.10, 0.5, 1.0],
    );

    return _buildAnimatedShell(
      height: kListCardHeight,
      scaleFactor: 0.006,
      decorationBuilder: (t) => BoxDecoration(
        gradient: listGradient,
        boxShadow: _hoverShadow(theme, t, 0.18),
        borderRadius: listRadius,
      ),
      child: Stack(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: leftRadius,
                child: SizedBox(
                  width: kListCardImageWidth,
                  height: kListCardHeight,
                  child: _buildCoverImage(theme),
                ),
              ),
              const Expanded(child: SizedBox.expand()),
            ],
          ),
          if (widget.game.isUsed)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: listRadius,
                child: LayoutBuilder(
                  builder: (context, constraints) => UsedOverlay(
                    theme: theme,
                    patternSize: constraints.biggest,
                  ),
                ),
              ),
            ),
          if (showNewBadge) _buildNewChip(theme),
          _buildSelectionOverlay(
            theme,
            isSelected,
            imageWidth: kListCardImageWidth,
          ),
          _buildAnimatedFetchOverlay(
            theme,
            fetchStatus,
            imageWidth: kListCardImageWidth,
          ),
          if (options.showDeadline && widget.game.hasDeadline)
            Positioned(
              left: 8,
              bottom: 8,
              child: GameCardBadges.deadlineBadge(
                theme,
                widget.game.deadlineDate,
              ),
            ),
          _buildListContentPane(theme, options),
        ],
      ),
    );
  }

  // ── Slim list card ─────────────────────────────────────────────────────────

  Widget _buildSlimListCard(
    AppThemeData theme,
    bool isSelected,
    CardViewOptions options,
    GameFetchStatus? fetchStatus,
    bool showNewBadge,
  ) {
    final showDeadline = options.showDeadline && widget.game.hasDeadline;
    final showUsed = widget.game.isUsed;
    final showRating = options.showRatingsNow && widget.game.reviewCount > 0;

    return _buildAnimatedShell(
      height: kSlimListCardHeight,
      scaleFactor: 0.012,
      decorationBuilder: (_) => BoxDecoration(
        color: theme.surface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.zero,
      ),
      child: Stack(
        children: [
          if (showUsed)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) => UsedOverlay(
                  theme: theme,
                  patternSize: Size(constraints.maxWidth, kSlimListCardHeight),
                  tileToCanvas: true,
                ),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: kFastAnimation,
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: theme.accent.withValues(
                    alpha: isSelected
                        ? (_isHovered ? 0.80 : 0.65)
                        : (_isHovered ? 0.40 : 0.0),
                  ),
                  borderRadius: BorderRadius.zero,
                ),
              ),
            ),
          ),
          _buildAnimatedFetchOverlay(theme, fetchStatus, slim: true),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.game.title,
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GameCardBadges.slimTrailingChips(
                    theme,
                    widget.game,
                    showDeadline: showDeadline,
                    showRating: showRating,
                    showDlc: widget.game.isDlc,
                    showNew: showNewBadge,
                    showPlatform: options.showPlatform,
                    fetchStatus: fetchStatus,
                    isSelected: isSelected,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared animated shell ──────────────────────────────────────────────────

  Widget _buildAnimatedShell({
    double? width,
    required double height,
    required double scaleFactor,
    required BoxDecoration Function(double t) decorationBuilder,
    required Widget child,
  }) => _buildInteractive(
    RepaintBoundary(
      child: AnimatedBuilder(
        animation: _hoverAnim,
        builder: (context, staticChild) {
          final t = _hoverAnim.value;
          // No filterQuality: that scales an offscreen image of the card
          // whose bounds snap to whole pixels, so the card shook while
          // zooming. A plain transform scales it at sub-pixel precision.
          return Transform.scale(
            scale: 1.0 + t * scaleFactor,
            child: DecoratedBox(
              decoration: decorationBuilder(t),
              child: staticChild,
            ),
          );
        },
        // The content keeps its own layer, so zooming only moves it.
        child: RepaintBoundary(
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    ),
  );

  List<BoxShadow>? _hoverShadow(AppThemeData theme, double t, double alpha) =>
      t > 0.001
      ? [
          BoxShadow(
            color: theme.accent.withValues(alpha: t * alpha),
            blurRadius: t * 12,
            spreadRadius: t * 2,
          ),
        ]
      : null;

  // ── Interactive wrapper ────────────────────────────────────────────────────

  Widget _buildInteractive(Widget child) => Listener(
    onPointerDown: handlePointerDown,
    onPointerMove: handlePointerMove,
    onPointerUp: handlePointerUp,
    onPointerCancel: handlePointerCancel,
    child: MouseRegion(
      onEnter: (event) {
        handleDragSelectionEvent(event);
        if (!mounted) return;
        setState(() => _isHovered = true);
        _hoverController.forward();
      },
      onExit: (_) {
        if (!dragSelectionHandledByParent) {
          ref
              .read(dragSelectionProvider.notifier)
              .unmarkVisited(widget.game.id);
        }
        if (!mounted) return;
        setState(() => _isHovered = false);
        _hoverController.reverse();
      },
      child: GestureDetector(
        onDoubleTap: handleDoubleTap,
        onLongPress: handleLongPress,
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: child,
      ),
    ),
  );

  // ── Sub-section builders ───────────────────────────────────────────────────

  Widget _buildCoverImage(AppThemeData theme) => GameCoverImage(
    theme: theme,
    coverImage: widget.game.hasCoverImage ? widget.game.coverImage : null,
    onError: _imageLoadFailed
        ? null
        : () {
            if (mounted) setState(() => _imageLoadFailed = true);
          },
  );

  Widget _buildListContentPane(AppThemeData theme, CardViewOptions options) {
    final tagsEnabled = options.showTags && widget.game.tags.isNotEmpty;
    final showSideChips =
        options.showPlatform ||
        widget.game.isDlc ||
        (options.showRatingsNow && widget.game.reviewCount > 0);
    return Positioned.fill(
      child: Row(
        children: [
          const SizedBox(width: kListCardImageWidth),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: kElementHSpacing,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.game.title,
                          style: TextStyle(
                            color: theme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          // Two lines still leave room for the tag row.
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (tagsEnabled) ...[
                          const Spacer(),
                          GameCardTagsRow(
                            game: widget.game,
                            theme: theme,
                            isVisible:
                                !options.showTagsOnHoverOnly || _isHovered,
                            topSpacing: 6.0,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (showSideChips)
                    GameCardBadges.topRightChips(
                      theme,
                      widget.game,
                      showPlatform: options.showPlatform,
                      showRatings: options.showRatingsNow,
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Overlay builders ───────────────────────────────────────────────────────

  Widget _buildGradientOverlay(AppThemeData theme, bool isSelected) {
    final glow = CustomPaint(
      painter: CardGlowPainter(
        accentColor: theme.accent,
        primaryColor: theme.secondary,
        selected: isSelected,
        cornerRadius: theme.cornerRadius,
      ),
      child: const SizedBox.expand(),
    );
    if (isSelected) return glow;

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _hoverAnim,
        builder: (context, child) {
          final t = _hoverAnim.value;
          if (t <= 0.0) return const SizedBox.shrink();
          return Opacity(opacity: t, child: child);
        },
        child: glow,
      ),
    );
  }

  /// Centres [child] over the cover image of list cards ([imageWidth] set),
  /// or over the whole card.
  Widget _overImage(Widget child, double? imageWidth) => imageWidth == null
      ? child
      : Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(width: imageWidth, child: child),
        );

  /// Animated selection overlay driven by [_selectionController].
  Widget _buildSelectionOverlay(
    AppThemeData theme,
    bool isSelected, {
    double? imageWidth,
  }) => IgnorePointer(
    ignoring: !isSelected,
    child: AnimatedBuilder(
      animation: _selectionAnim,
      builder: (context, child) {
        final t = _selectionAnim.value.clamp(0.0, 1.0);
        if (t <= 0.0) return const SizedBox.shrink();

        final shadow = t > 0.01
            ? [
                BoxShadow(
                  color: theme.accent.withValues(alpha: 0.28 * t),
                  blurRadius: 12 * t,
                  spreadRadius: t,
                ),
              ]
            : null;

        final iconWidget = Container(
          padding: EdgeInsets.all(4 + 4 * t),
          decoration: BoxDecoration(
            color: theme.accent.withValues(alpha: t),
            borderRadius: BorderRadius.circular(theme.cornerRadius),
            boxShadow: shadow,
          ),
          child: SizedBox(
            width: 10 + 10 * t,
            height: 10 + 10 * t,
            child: Opacity(opacity: t, child: child),
          ),
        );

        return Container(
          decoration: theme.selectionOverlayDecoration(t),
          child: _overImage(Center(child: iconWidget), imageWidth),
        );
      },
      child: FittedBox(child: Icon(Icons.check, color: theme.onAccentText)),
    ),
  );

  Widget _buildAnimatedFetchOverlay(
    AppThemeData theme,
    GameFetchStatus? fetchStatus, {
    double? imageWidth,
    bool slim = false,
  }) => AnimatedSwitcher(
    duration: kFastAnimation,
    transitionBuilder: (child, anim) =>
        FadeTransition(opacity: anim, child: child),
    child: fetchStatus != null
        ? KeyedSubtree(
            key: ValueKey(fetchStatus),
            child: _buildFetchStatusOverlay(
              theme,
              fetchStatus,
              imageWidth: imageWidth,
              slim: slim,
            ),
          )
        : const SizedBox.shrink(key: ValueKey<Null>(null)),
  );

  Widget _buildFetchStatusOverlay(
    AppThemeData theme,
    GameFetchStatus status, {
    double? imageWidth,
    bool slim = false,
  }) {
    final visual = GameCardBadges.fetchStatusVisual(
      theme,
      status,
      iconSize: kSelectionIndicatorSize,
    );
    final color = visual.color;

    final statusIcon = AnimatedContainer(
      duration: kFastAnimation,
      curve: Curves.easeOut,
      padding: kSelectionIndicatorPadding,
      decoration: BoxDecoration(
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
      child: GameCardBadges.fetchStatusIcon(
        visual,
        status,
        kSelectionIndicatorSize,
      ),
    );

    final tintAlpha = status == GameFetchStatus.done
        ? (slim ? 0.24 : 0.32)
        : (slim ? 0.44 : 0.28);

    return IgnorePointer(
      child: AnimatedContainer(
        duration: kFastAnimation,
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: color.withValues(alpha: tintAlpha),
          border: !slim
              ? Border.all(
                  color: status == GameFetchStatus.processing
                      ? Colors.transparent
                      : color,
                  width: 3,
                )
              : null,
          borderRadius: slim
              ? BorderRadius.zero
              : BorderRadius.circular(theme.cornerRadius),
        ),
        child: slim
            ? const SizedBox.expand()
            : _overImage(Center(child: statusIcon), imageWidth),
      ),
    );
  }

  // ── NEW chip ──────────────────────────────────────────────────────────────

  Widget _buildNewChip(AppThemeData theme) => Positioned(
    left: 5,
    top: 5,
    child: GameCardBadges.newChip(theme, widget.game.dateAdded),
  );

  // ── Context menu ───────────────────────────────────────────────────────────

  void _showContextMenu(BuildContext context, Offset position) {
    final selectedIds = ref.read(
      gamesProvider.select((s) => s.selectedGameIds),
    );
    if (!selectedIds.contains(widget.game.id)) {
      ref.read(gamesProvider.notifier).clearSelection();
      ref.read(gamesProvider.notifier).selectGame(widget.game.id);
      ref.read(lastSelectedGameIdProvider.notifier).set(widget.game.id);
    }

    final theme = ref.read(themeProvider);
    final targetGames = _getTargetGames();
    final count = targetGames.length;
    final suffix = count > 1 ? ' ($count)' : '';
    final isFetching = ref.read(batchFetchProvider).isActive;
    final hasSteamTargets = targetGames.any((g) => g.platform == 'Steam');

    // Items with a [lockedLabel] are disabled while a Steam fetch runs.
    Widget item(
      IconData icon,
      String label,
      VoidCallback onPressed, {
      Color? iconColor,
      Color? color,
      String? lockedLabel,
    }) {
      final enabled = lockedLabel == null || !isFetching;
      return appMenuItem(
        theme,
        leading: Icon(
          enabled ? icon : Icons.lock_rounded,
          size: 18,
          color: enabled ? iconColor : theme.textHint,
        ),
        color: enabled ? color : null,
        // The menu runs its choice a frame after closing.
        onPressed: enabled
            ? () {
                if (context.mounted) onPressed();
              }
            : null,
        child: Text(enabled ? '$label$suffix' : '$lockedLabel (Locked)$suffix'),
      );
    }

    showAppContextMenu(
      context: context,
      theme: theme,
      position: position,
      menuChildren: [
        item(
          Icons.copy_all,
          'Copy',
          () => GameSelectionActions.showCopyDialog(context, ref, targetGames),
        ),
        appMenuDivider(theme),
        item(
          Icons.edit_outlined,
          'Game Editor',
          handleDoubleTap,
          lockedLabel: 'Game Editor',
        ),
        if (hasSteamTargets) ...[
          item(
            Icons.open_in_new,
            'Open Steam Page',
            () => GameSelectionActions.openSteamPages(ref, targetGames),
          ),
          item(
            Icons.cloud_download,
            'Fetch Steam Data',
            () =>
                GameSelectionActions.fetchSteamData(context, ref, targetGames),
            iconColor: theme.accent,
            lockedLabel: 'Fetch Steam Data',
          ),
        ],
        appMenuDivider(theme),
        item(
          widget.game.isUsed
              ? Icons.radio_button_unchecked
              : Icons.check_circle,
          widget.game.isUsed ? 'Mark as Unused' : 'Mark as Used',
          () => GameSelectionActions.toggleUsed(
            ref,
            targetGames,
            !widget.game.isUsed,
          ),
          lockedLabel: 'Mark as Used/Unused',
        ),
        appMenuDivider(theme),
        item(
          Icons.delete_outline,
          'Delete',
          () => GameSelectionActions.deleteGames(
            context,
            ref,
            theme,
            targetGames,
          ),
          color: theme.error,
          lockedLabel: 'Delete',
        ),
      ],
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<Game> _getTargetGames() =>
      ref.read(gamesProvider).selectedGameIds.contains(widget.game.id)
      ? ref.read(selectedGamesProvider)
      : [widget.game];

  bool _shouldShowNewBadge(bool hasBeenViewed) {
    if (hasBeenViewed) return false;
    final age = DateTime.now().difference(widget.game.dateAdded);
    return !age.isNegative && age <= _newBadgeLifetime;
  }

  List<Color> _computeListGradientColors(AppThemeData theme, bool isSelected) {
    if (isSelected) return theme.listCardSelectedGradient;
    if (_isHovered) return theme.listCardHoverGradient;
    return theme.listCardDefaultGradient;
  }
}
