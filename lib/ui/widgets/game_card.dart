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
import 'package:intl/intl.dart' hide TextDirection;

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

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────

class GameCard extends ConsumerStatefulWidget {
  const GameCard({super.key, required this.game});

  final Game game;

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

  // Corner-ribbon constants.
  static const double _kRibbonHeight = 18.0;
  static const double _kRibbonContainerWidth = 130.0;
  static const double _kRibbonOffset = 15.0;
  static final DateFormat _ribbonDateFormat = DateFormat('dd/MM/yyyy');

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
    final viewMode = ref.watch(viewModeProvider);
    final isSelected = ref.watch(
      gamesProvider.select((s) => s.selectedGameIds.contains(widget.game.id)),
    );
    final viewedGameIds = ref.watch(viewedNewGameIdsProvider);
    final fetchStatus = ref.watch(
      batchFetchProvider.select((s) => s.getStatus(widget.game.id)),
    );

    final showNewBadge = _shouldShowNewBadge(viewedGameIds);
    final options = CardViewOptions(
      showTitle: cardSettings.showTitle,
      showTitleOnNoPicture: cardSettings.showTitleOnNoPicture,
      showPlatform: cardSettings.showPlatform,
      showTags: cardSettings.showTags,
      showTagsOnHoverOnly: cardSettings.showTagsOnHoverOnly,
      showDeadline: cardSettings.showDeadline,
      showRatingsNow:
          cardSettings.showRatings &&
          (!cardSettings.showTagsOnHoverOnly || _isHovered),
      slimListView: cardSettings.slimListView,
    );

    // Drive selection animation — forward/reverse are no-ops when already at
    // the target value so this is inexpensive.
    if (isSelected) {
      _selectionController.forward();
    } else {
      _selectionController.reverse();
    }

    return viewMode == GameListViewMode.grid
        ? _buildGridCard(theme, isSelected, options, fetchStatus, showNewBadge)
        : _buildListCard(theme, isSelected, options, fetchStatus, showNewBadge);
  }

  // ── Grid card ──────────────────────────────────────────────────────────────

  Widget _buildGridCard(
    AppThemeData theme,
    bool isSelected,
    CardViewOptions options,
    GameFetchStatus? fetchStatus,
    bool showNewBadge,
  ) {
    final hasDlc = widget.game.isDlc;
    final radius = BorderRadius.circular(theme.cornerRadius);
    final bool titleVisible = options.showTitleOnNoPicture
        ? (!widget.game.hasCoverImage || _imageLoadFailed)
        : options.showTitle;
    final bool tagsEnabled = options.showTags && widget.game.tags.isNotEmpty;
    final bool tagsVisible =
        tagsEnabled && (!options.showTagsOnHoverOnly || _isHovered);

    return _buildInteractive(
      RepaintBoundary(
        child: AnimatedBuilder(
          animation: _hoverAnim,
          builder: (context, child) {
            final t = _hoverAnim.value;
            return Transform.scale(
              scale: 1.0 + t * 0.015,
              alignment: Alignment.center,
              filterQuality: FilterQuality.medium,
              child: SizedBox(
                width: kGridCardWidth,
                height: kGridCardHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    boxShadow: t > 0.001
                        ? [
                            BoxShadow(
                              color: theme.accent.withValues(alpha: t * 0.2),
                              blurRadius: t * 12,
                              spreadRadius: t * 2,
                            ),
                          ]
                        : null,
                  ),
                  child: child,
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: radius,
            child: SizedBox(
              width: kGridCardWidth,
              height: kGridCardHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCoverImage(theme),
                  _buildGradientOverlay(theme, isSelected),
                  if (widget.game.isUsed)
                    _buildUsedOverlay(
                      theme,
                      patternSize: const Size(kGridCardWidth, kGridCardHeight),
                    ),
                  _buildSelectionOverlay(theme, isSelected),
                  AnimatedSwitcher(
                    duration: kFastAnimation,
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: fetchStatus != null
                        ? KeyedSubtree(
                            key: ValueKey(fetchStatus),
                            child: _buildFetchStatusOverlay(
                              theme,
                              fetchStatus,
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey<Null>(null)),
                  ),
                  if (hasDlc)
                    _buildRibbonBand(
                      label: 'DLC',
                      color: theme.accent,
                      textColor: theme.primaryButtonText,
                      bandIndex: 0,
                    ),
                  if (showNewBadge)
                    _buildRibbonBand(
                      label: 'NEW',
                      color: theme.secondary,
                      textColor: theme.primaryButtonText,
                      bandIndex: hasDlc ? 1 : 0,
                      addedDate: widget.game.createdAt,
                    ),
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
                            widget.game,
                            borderRadius: GameCardBadges.chipBorderRadius(
                              theme,
                              kBadgeHeight,
                            ),
                            showIcon: true,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            minHeight: kBadgeHeight,
                          ),
                          if (titleVisible) const SizedBox(height: 4),
                        ],
                        if (titleVisible)
                          GameCardBadges.titleChip(theme, widget.game.title),
                        if (tagsEnabled)
                          GameCardTagsRow(
                            game: widget.game,
                            theme: theme,
                            isVisible: tagsVisible,
                            fixedMaxWidth: kGridCardWidth - 16.0,
                            topSpacing: 4.0,
                          ),
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
          ),
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
    final hasDlc = widget.game.isDlc;
    final layout = ListCardLayout.fromOptions(options);

    if (layout.useSlim) {
      return _buildSlimListCard(theme, isSelected, options, fetchStatus);
    }

    final listRadius = BorderRadius.circular(theme.cornerRadius);
    final gradientColors = _computeListGradientColors(theme, isSelected);
    final listGradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      // ignore: prefer_const_constructors
      transform: GradientRotation(25 * math.pi / 180),
      colors: [theme.background, gradientColors[1], gradientColors[0]],
      stops: const [0.10, 0.5, 1.0],
    );
    final bool tagsEnabled = options.showTags && widget.game.tags.isNotEmpty;
    final bool tagsVisible =
        tagsEnabled && (!options.showTagsOnHoverOnly || _isHovered);
    final showListSideChips =
        options.showPlatform ||
        (options.showRatingsNow && widget.game.reviewCount > 0);

    return _buildListAnimatedShell(
      height: layout.cardHeight,
      scaleFactor: 0.006,
      decorationBuilder: (t) => BoxDecoration(
        gradient: listGradient,
        boxShadow: t > 0.001
            ? [
                BoxShadow(
                  color: theme.accent.withValues(alpha: t * 0.18),
                  blurRadius: t * 12,
                  spreadRadius: t * 2,
                ),
              ]
            : null,
        borderRadius: listRadius,
      ),
      child: Stack(
        children: [
          _buildListCoverPane(
            theme,
            cardImageWidth: layout.cardImageWidth,
            cardHeight: layout.cardHeight,
            hasDlc: hasDlc,
            showNewBadge: showNewBadge,
          ),
          _buildSelectionOverlay(
            theme,
            isSelected,
            imageWidth: layout.cardImageWidth,
          ),
          _buildAnimatedFetchOverlay(
            theme,
            fetchStatus,
            imageWidth: layout.cardImageWidth,
          ),
          if (options.showDeadline && widget.game.hasDeadline)
            Positioned(
              left: 8,
              bottom: 8,
              child: GameCardBadges.deadlineBadge(
                theme,
                widget.game,
                borderRadius: GameCardBadges.chipBorderRadius(
                  theme,
                  kBadgeHeight,
                ),
                showIcon: true,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minHeight: kBadgeHeight,
              ),
            ),
          _buildListContentPane(
            context,
            theme,
            options: options,
            tagsEnabled: tagsEnabled,
            tagsVisible: tagsVisible,
            showListSideChips: showListSideChips,
            ratingLeftOfPlatform: false,
            cardImageWidth: layout.cardImageWidth,
          ),
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
  ) {
    final showDeadline = options.showDeadline && widget.game.hasDeadline;
    final showUsed = widget.game.isUsed;
    final showDlc = widget.game.isDlc;
    final showRating = options.showRatingsNow && widget.game.reviewCount > 0;

    return _buildListAnimatedShell(
      height: kSlimListCardHeight,
      scaleFactor: 0.012,
      decorationBuilder: (_) => BoxDecoration(
        color: theme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.zero,
      ),
      child: Stack(
        children: [
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
          _buildAnimatedFetchOverlay(
            theme,
            fetchStatus,
            showStatusIcon: false,
            showBorder: false,
            borderRadius: BorderRadius.zero,
            doneTintAlpha: 0.24,
            activeTintAlpha: 0.44,
          ),
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
                    showUsed: showUsed,
                    showDeadline: showDeadline,
                    showDlc: showDlc,
                    showRating: showRating,
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

  // ── Shared animated shell for list modes ───────────────────────────────────

  Widget _buildListAnimatedShell({
    required double height,
    required double scaleFactor,
    required BoxDecoration Function(double t) decorationBuilder,
    required Widget child,
  }) {
    return _buildInteractive(
      RepaintBoundary(
        child: AnimatedBuilder(
          animation: _hoverAnim,
          builder: (context, staticChild) {
            final t = _hoverAnim.value;
            return Transform.scale(
              scale: 1.0 + t * scaleFactor,
              alignment: Alignment.center,
              filterQuality: FilterQuality.medium,
              child: DecoratedBox(
                decoration: decorationBuilder(t),
                child: staticChild,
              ),
            );
          },
          child: SizedBox(height: height, child: child),
        ),
      ),
    );
  }

  // ── Interactive wrapper ────────────────────────────────────────────────────

  Widget _buildInteractive(Widget child) {
    return Listener(
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
          ref.read(dragSelectionProvider.notifier).unmarkVisited(widget.game.id);
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
  }

  // ── Sub-section builders ───────────────────────────────────────────────────

  Widget _buildCoverImage(AppThemeData theme) {
    return GameCoverImage(
      theme: theme,
      coverImage: widget.game.hasCoverImage ? widget.game.coverImage : null,
      onError: _imageLoadFailed
          ? null
          : () {
              if (mounted) setState(() => _imageLoadFailed = true);
            },
    );
  }

  Widget _buildListCoverPane(
    AppThemeData theme, {
    required double cardImageWidth,
    required double cardHeight,
    required bool hasDlc,
    required bool showNewBadge,
  }) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(theme.cornerRadius),
          ),
          child: SizedBox(
            width: cardImageWidth,
            height: cardHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildCoverImage(theme),
                if (widget.game.isUsed)
                  _buildUsedOverlay(
                    theme,
                    patternSize: Size(cardImageWidth, cardHeight),
                  ),
                if (hasDlc)
                  _buildRibbonBand(
                    label: 'DLC',
                    color: theme.accent,
                    textColor: theme.primaryButtonText,
                    bandIndex: 0,
                  ),
                if (showNewBadge)
                  _buildRibbonBand(
                    label: 'NEW',
                    color: theme.secondary,
                    textColor: theme.primaryButtonText,
                    bandIndex: hasDlc ? 1 : 0,
                    addedDate: widget.game.createdAt,
                  ),
              ],
            ),
          ),
        ),
        Expanded(child: const SizedBox.expand()),
      ],
    );
  }

  Widget _buildListContentPane(
    BuildContext context,
    AppThemeData theme, {
    required CardViewOptions options,
    required bool tagsEnabled,
    required bool tagsVisible,
    required bool showListSideChips,
    required bool ratingLeftOfPlatform,
    required double cardImageWidth,
  }) {
    return Positioned.fill(
      child: Row(
        children: [
          SizedBox(width: cardImageWidth),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (tagsEnabled) ...[
                          const Spacer(),
                          GameCardTagsRow(
                            game: widget.game,
                            theme: theme,
                            isVisible: tagsVisible,
                            topSpacing: 6.0,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (showListSideChips) ...[
                    const SizedBox(width: kElementHSpacing),
                    GameCardBadges.topRightChips(
                      theme,
                      widget.game,
                      showPlatform: options.showPlatform,
                      showRatings: options.showRatingsNow,
                      padding: EdgeInsets.zero,
                      ratingLeftOfPlatform: ratingLeftOfPlatform,
                    ),
                  ],
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
    if (isSelected) {
      return CustomPaint(
        painter: CardGlowPainter(
          accentColor: theme.accent,
          primaryColor: theme.secondary,
          selected: true,
          cornerRadius: theme.cornerRadius,
        ),
        child: const SizedBox.expand(),
      );
    }

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _hoverAnim,
        builder: (context, child) {
          final t = _hoverAnim.value;
          if (t <= 0.0) return const SizedBox.shrink();
          return Opacity(opacity: t, child: child);
        },
        child: CustomPaint(
          painter: CardGlowPainter(
            accentColor: theme.accent,
            primaryColor: theme.secondary,
            selected: false,
            cornerRadius: theme.cornerRadius,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget _buildUsedOverlay(AppThemeData theme, {required Size patternSize}) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: theme.usedOverlay.withValues(alpha: 0.6)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.95,
                colors: [
                  Colors.transparent,
                  theme.usedOverlay.withValues(alpha: 0.4),
                ],
                stops: const [0.55, 1.0],
              ),
            ),
          ),
          CustomPaint(
            painter: UsedPatternPainter(
              textColor: Colors.white.withValues(alpha: 0.45),
              angleDegrees: -35,
              patternSize: patternSize,
            ),
            isComplex: true,
            willChange: false,
            child: const SizedBox.expand(),
          ),
        ],
      ),
    );
  }

  /// Animated selection overlay driven by [_selectionController].
  Widget _buildSelectionOverlay(
    AppThemeData theme,
    bool isSelected, {
    double? imageWidth,
    double tintOpacityScale = 1.0,
    bool showBorder = true,
    BorderRadius? borderRadiusOverride,
    Alignment iconAlignment = Alignment.center,
    EdgeInsets iconPadding = EdgeInsets.zero,
    Color? overlayColor,
  }) {
    return IgnorePointer(
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

          final borderRadius =
              borderRadiusOverride ??
              BorderRadius.circular(theme.cornerRadius);

          final iconWidget = Container(
            padding: EdgeInsets.all(4 + 4 * t),
            decoration: BoxDecoration(
              color: theme.accent.withValues(alpha: t),
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(theme.cornerRadius),
              boxShadow: shadow,
            ),
            child: SizedBox(
              width: 10 + 10 * t,
              height: 10 + 10 * t,
              child: Opacity(opacity: t, child: child),
            ),
          );

          final centeredIcon = imageWidth != null
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: imageWidth,
                    child: Align(
                      alignment: iconAlignment,
                      child: Padding(padding: iconPadding, child: iconWidget),
                    ),
                  ),
                )
              : Align(
                  alignment: iconAlignment,
                  child: Padding(padding: iconPadding, child: iconWidget),
                );

          return Container(
            decoration: BoxDecoration(
              color: (overlayColor ?? theme.secondary).withValues(
                alpha: 0.55 * t * tintOpacityScale,
              ),
              border: showBorder
                  ? Border.all(
                      color: theme.accent.withValues(alpha: t),
                      width: 3.0,
                    )
                  : null,
              borderRadius: borderRadius,
            ),
            child: centeredIcon,
          );
        },
        child: const FittedBox(child: Icon(Icons.check, color: Colors.white)),
      ),
    );
  }

  Widget _buildAnimatedFetchOverlay(
    AppThemeData theme,
    GameFetchStatus? fetchStatus, {
    double? imageWidth,
    bool showBorder = true,
    BorderRadius? borderRadius,
    double doneTintAlpha = 0.32,
    double activeTintAlpha = 0.28,
    Alignment indicatorAlignment = Alignment.center,
    EdgeInsets indicatorPadding = EdgeInsets.zero,
    bool showTint = true,
    bool showStatusIcon = true,
  }) {
    return AnimatedSwitcher(
      duration: kFastAnimation,
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: fetchStatus != null
          ? KeyedSubtree(
              key: ValueKey(fetchStatus),
              child: _buildFetchStatusOverlay(
                theme,
                fetchStatus,
                borderRadius: borderRadius,
                imageWidth: imageWidth,
                showBorder: showBorder,
                doneTintAlpha: doneTintAlpha,
                activeTintAlpha: activeTintAlpha,
                indicatorAlignment: indicatorAlignment,
                indicatorPadding: indicatorPadding,
                showTint: showTint,
                showStatusIcon: showStatusIcon,
              ),
            )
          : const SizedBox.shrink(key: ValueKey<Null>(null)),
    );
  }

  Widget _buildFetchStatusOverlay(
    AppThemeData theme,
    GameFetchStatus status, {
    BorderRadius? borderRadius,
    double? imageWidth,
    bool showBorder = true,
    double doneTintAlpha = 0.32,
    double activeTintAlpha = 0.28,
    Alignment indicatorAlignment = Alignment.center,
    EdgeInsets indicatorPadding = EdgeInsets.zero,
    bool showTint = true,
    bool showStatusIcon = true,
  }) {
    final visual = GameCardBadges.fetchStatusVisual(
      theme,
      status,
      iconSize: kSelectionIndicatorSize,
    );
    final color = visual.color;
    final effectiveBorderRadius =
        borderRadius ?? BorderRadius.circular(theme.cornerRadius);

    final statusIcon = AnimatedContainer(
      duration: kFastAnimation,
      curve: Curves.easeOut,
      padding: kSelectionIndicatorPadding,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 14,
            spreadRadius: 2,
          ),
        ],
      ),
      child: AnimatedSwitcher(
        duration: kVeryFastAnimation,
        transitionBuilder: (child, anim) => ScaleTransition(
          scale: anim,
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: SizedBox(
          key: ValueKey(status),
          width: kSelectionIndicatorSize,
          height: kSelectionIndicatorSize,
          child: Center(child: visual.icon),
        ),
      ),
    );

    Widget alignedStatusIcon = const SizedBox.shrink();
    if (showStatusIcon) {
      final positionedIcon = Align(
        alignment: indicatorAlignment,
        child: Padding(padding: indicatorPadding, child: statusIcon),
      );
      alignedStatusIcon = imageWidth != null
          ? Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(width: imageWidth, child: positionedIcon),
            )
          : positionedIcon;
    }

    if (!showTint && !showBorder) {
      return IgnorePointer(child: alignedStatusIcon);
    }

    final tintAlpha =
        status == GameFetchStatus.done ? doneTintAlpha : activeTintAlpha;
    final overlayChild =
        showStatusIcon ? alignedStatusIcon : const SizedBox.expand();

    return IgnorePointer(
      child: AnimatedContainer(
        duration: kFastAnimation,
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: showTint
              ? color.withValues(alpha: tintAlpha)
              : Colors.transparent,
          border: showBorder
              ? Border.all(
                  color: status == GameFetchStatus.processing
                      ? Colors.transparent
                      : color,
                  width: 3,
                )
              : null,
          borderRadius: effectiveBorderRadius,
        ),
        child: overlayChild,
      ),
    );
  }

  // ── Corner ribbon ──────────────────────────────────────────────────────────

  Positioned _buildRibbonBand({
    required String label,
    required Color color,
    required Color textColor,
    required int bandIndex,
    DateTime? addedDate,
  }) {
    final cx =
        _kRibbonOffset + (bandIndex + 0.5) * _kRibbonHeight / math.sqrt2;

    Widget band = Container(
      width: _kRibbonContainerWidth,
      height: _kRibbonHeight,
      color: color,
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          decoration: TextDecoration.none,
        ),
      ),
    );

    if (addedDate != null) {
      band = Tooltip(
        message: 'Added ${_ribbonDateFormat.format(addedDate)}',
        child: band,
      );
    }

    return Positioned(
      left: cx - _kRibbonContainerWidth / 2,
      top: cx - _kRibbonHeight / 2,
      child: Transform.rotate(angle: -math.pi / 4, child: band),
    );
  }

  // ── Context menu ───────────────────────────────────────────────────────────

  void _showContextMenu(BuildContext context, Offset position) async {
    final selectedIds = ref.read(
      gamesProvider.select((s) => s.selectedGameIds),
    );
    if (!selectedIds.contains(widget.game.id)) {
      ref.read(gamesProvider.notifier).clearSelection();
      ref.read(gamesProvider.notifier).selectGame(widget.game.id);
      ref
          .read(lastSelectedGameIdProvider.notifier)
          .setLastSelectedGameId(widget.game.id);
    }

    final theme = ref.read(themeProvider);
    final targetGames = _getTargetGames();
    final count = targetGames.length;
    final suffix = count > 1 ? ' ($count)' : '';
    final isFetching = ref.read(batchFetchProvider).isActive;
    final hasSteamTargets = targetGames.any((g) => g.platform == 'Steam');

    PopupMenuItem<String> menuHeader(String text) => PopupMenuItem<String>(
      enabled: false,
      height: 32,
      child: Text(
        text,
        style: TextStyle(
          color: theme.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );

    PopupMenuItem<String> menuRowItem({
      required String value,
      required IconData icon,
      required String label,
      Color? iconColor,
      Color? textColor,
      bool enabled = true,
      IconData? disabledIcon,
      String? disabledLabel,
      Color? disabledColor,
    }) {
      final resolvedLabel = enabled ? label : (disabledLabel ?? label);
      final mutedColor = theme.textSecondary.withValues(alpha: 0.5);
      return PopupMenuItem<String>(
        value: enabled ? value : null,
        enabled: enabled,
        child: Row(
          children: [
            Icon(
              enabled ? icon : (disabledIcon ?? icon),
              size: 18,
              color: enabled
                  ? (iconColor ?? theme.textSecondary)
                  : (disabledColor ?? mutedColor),
            ),
            const SizedBox(width: 12),
            Text(
              resolvedLabel,
              style: TextStyle(
                color: enabled
                    ? (textColor ?? theme.textPrimary)
                    : (disabledColor ?? mutedColor),
              ),
            ),
          ],
        ),
      );
    }

    final overlayState = Overlay.maybeOf(context);
    final overlayObject = overlayState?.context.findRenderObject();
    if (overlayObject is! RenderBox) return;

    final value = await showAppMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlayObject.size,
      ),
      items: [
        menuHeader('Copy$suffix'),
        menuRowItem(value: 'copy', icon: Icons.copy_all, label: 'Copy$suffix'),
        const PopupMenuDivider(),
        menuRowItem(
          value: 'details',
          icon: Icons.info_outline,
          label: 'View Details$suffix',
          enabled: !isFetching,
          disabledIcon: Icons.lock_rounded,
          disabledLabel: 'View Details (Locked)$suffix',
        ),
        if (hasSteamTargets) ...[
          menuRowItem(
            value: 'open_steam',
            icon: Icons.open_in_new,
            label: 'Open Steam Page$suffix',
          ),
          menuRowItem(
            value: 'steam_lookup',
            icon: Icons.cloud_download,
            label: 'Fetch Steam Data$suffix',
            iconColor: theme.accent,
            enabled: !isFetching,
            disabledIcon: Icons.lock_rounded,
            disabledLabel: 'Fetch Steam Data (Locked)$suffix',
          ),
        ],
        const PopupMenuDivider(),
        menuRowItem(
          value: 'toggle_used',
          icon: widget.game.isUsed
              ? Icons.radio_button_unchecked
              : Icons.check_circle,
          label:
              (widget.game.isUsed ? 'Mark as Unused' : 'Mark as Used') + suffix,
          enabled: !isFetching,
          disabledIcon: Icons.lock_rounded,
          disabledLabel: 'Mark as Used/Unused (Locked)$suffix',
        ),
        const PopupMenuDivider(),
        menuRowItem(
          value: 'delete',
          icon: Icons.delete_outline,
          label: 'Delete$suffix',
          iconColor: theme.error,
          textColor: theme.error,
          enabled: !isFetching,
          disabledIcon: Icons.lock_rounded,
          disabledLabel: 'Delete (Locked)$suffix',
        ),
      ],
    );

    if (value == null) return;
    if (!context.mounted) return;

    switch (value) {
      case 'copy':
        GameSelectionActions.showCopyDialog(context, ref, targetGames);
      case 'details':
        handleDoubleTap();
      case 'open_steam':
        GameSelectionActions.openSteamPages(ref, targetGames);
      case 'steam_lookup':
        GameSelectionActions.fetchSteamData(context, ref, targetGames);
      case 'toggle_used':
        GameSelectionActions.toggleUsed(ref, targetGames, !widget.game.isUsed);
      case 'delete':
        GameSelectionActions.deleteGames(context, ref, theme, targetGames);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<Game> _getTargetGames() {
    final selectedIds = ref.read(
      gamesProvider.select((s) => s.selectedGameIds),
    );
    if (selectedIds.contains(widget.game.id)) {
      return ref.read(selectedGamesProvider);
    }
    return [widget.game];
  }

  bool _shouldShowNewBadge(Set<int> viewedGameIds) {
    if (viewedGameIds.contains(widget.game.id)) return false;
    final age = DateTime.now().difference(widget.game.createdAt);
    return !age.isNegative && age <= _newBadgeLifetime;
  }

  List<Color> _computeListGradientColors(AppThemeData theme, bool isSelected) {
    if (isSelected) return theme.listCardSelectedGradient;
    if (_isHovered) return theme.listCardHoverGradient;
    return theme.listCardDefaultGradient;
  }
}
