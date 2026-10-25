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
import 'corner_ribbon.dart';
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

  // Corner-ribbon constants.
  static const double _kRibbonHeight = 22.5;
  static const double _kDlcRibbonHeight = 25.0;
  static const double _kSlimDlcRibbonExtent = 46.0;
  static const double _kRibbonContainerWidth = 130.0;
  static const double _kRibbonOffset = 9.0;
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
    final options = CardViewOptions(
      showTitle: cardSettings.showTitle,
      showTitleOnNoPicture: cardSettings.showTitleOnNoPicture,
      showPlatform:
          cardSettings.showPlatform &&
          (!cardSettings.showPlatformOnHoverOnly || _isHovered),
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
                    UsedOverlay(
                      theme: theme,
                      patternSize: const Size(kGridCardWidth, kGridCardHeight),
                      gridView: true,
                    ),
                  _buildSelectionOverlay(theme, isSelected),
                  _buildAnimatedFetchOverlay(theme, fetchStatus),
                  ..._buildCornerRibbons(
                    theme,
                    hasDlc: hasDlc,
                    showNewBadge: showNewBadge,
                  ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (options.showDeadline &&
                            widget.game.hasDeadline) ...[
                          _buildDeadlineBadge(theme),
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
          _buildListRibbonPane(
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
            Positioned(left: 8, bottom: 8, child: _buildDeadlineBadge(theme)),
          _buildListContentPane(
            context,
            theme,
            options: options,
            tagsEnabled: tagsEnabled,
            tagsVisible: tagsVisible,
            showListSideChips: showListSideChips,
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
          if (showDlc)
            Positioned(
              left: 0,
              top: 0,
              width: _kSlimDlcRibbonExtent,
              height: kSlimListCardHeight,
              child: IgnorePointer(
                child: ClipRect(
                  child: Stack(
                    children: [
                      _buildRibbonBand(
                        label: 'DLC',
                        color: theme.accent,
                        textColor: theme.primaryButtonText,
                        bandIndex: 0,
                        compact: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                showDlc ? _kSlimDlcRibbonExtent : 10,
                6,
                10,
                6,
              ),
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

  Widget _buildDeadlineBadge(AppThemeData theme) =>
      GameCardBadges.deadlineBadge(
        theme,
        widget.game.deadlineDate,
        borderRadius: GameCardBadges.chipBorderRadius(theme, kBadgeHeight),
        showIcon: true,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minHeight: kBadgeHeight,
      );

  Widget _buildListCoverPane(
    AppThemeData theme, {
    required double cardImageWidth,
    required double cardHeight,
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
            child: _buildCoverImage(theme),
          ),
        ),
        const Expanded(child: SizedBox.expand()),
      ],
    );
  }

  Widget _buildListRibbonPane(
    AppThemeData theme, {
    required double cardImageWidth,
    required double cardHeight,
    required bool hasDlc,
    required bool showNewBadge,
  }) {
    return Positioned(
      left: 0,
      top: 0,
      width: cardImageWidth,
      height: cardHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(theme.cornerRadius),
        ),
        child: Stack(
          children: _buildCornerRibbons(
            theme,
            hasDlc: hasDlc,
            showNewBadge: showNewBadge,
          ),
        ),
      ),
    );
  }

  Widget _buildListContentPane(
    BuildContext context,
    AppThemeData theme, {
    required CardViewOptions options,
    required bool tagsEnabled,
    required bool tagsVisible,
    required bool showListSideChips,
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

  /// Animated selection overlay driven by [_selectionController].
  Widget _buildSelectionOverlay(
    AppThemeData theme,
    bool isSelected, {
    double? imageWidth,
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

          final centeredIcon = Center(child: iconWidget);

          return Container(
            decoration: theme.selectionOverlayDecoration(t),
            child: imageWidth == null
                ? centeredIcon
                : Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(width: imageWidth, child: centeredIcon),
                  ),
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
    bool slim = false,
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
                imageWidth: imageWidth,
                slim: slim,
              ),
            )
          : const SizedBox.shrink(key: ValueKey<Null>(null)),
    );
  }

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

    final centeredIcon = Center(child: statusIcon);
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
            : imageWidth == null
            ? centeredIcon
            : Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(width: imageWidth, child: centeredIcon),
              ),
      ),
    );
  }

  // ── Corner ribbon ──────────────────────────────────────────────────────────

  /// The DLC and NEW bands shared by the grid and list layouts.
  List<Widget> _buildCornerRibbons(
    AppThemeData theme, {
    required bool hasDlc,
    required bool showNewBadge,
  }) => [
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
  ];

  Positioned _buildRibbonBand({
    required String label,
    required Color color,
    required Color textColor,
    required int bandIndex,
    DateTime? addedDate,
    bool compact = false,
  }) {
    final isDlc = label == 'DLC';
    final bandHeight = compact
        ? 20.0
        : (isDlc ? _kDlcRibbonHeight : _kRibbonHeight);
    // NEW follows the larger DLC band when both ribbons are visible.
    final cx =
        (compact ? 8.5 : _kRibbonOffset) +
        (bandIndex * _kDlcRibbonHeight + bandHeight / 2) / math.sqrt2;

    final bandWidth = math.max(
      compact ? 96.0 : _kRibbonContainerWidth * (isDlc ? 1.25 : 1),
      2 * math.sqrt2 * cx + bandHeight,
    );

    Widget band = Container(
      width: bandWidth,
      height: bandHeight,
      color: color,
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: compact ? 11 : 13.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          decoration: TextDecoration.none,
        ),
      ),
    );

    if (addedDate != null && (compact || bandIndex > 0)) {
      band = Tooltip(
        message: 'Added ${_ribbonDateFormat.format(addedDate)}',
        child: band,
      );
    }

    if (!compact && bandIndex == 0) {
      Widget corner = CornerRibbon(
        label: label,
        color: color,
        textColor: textColor,
        bandHeight: bandHeight,
        bandWidth: bandWidth,
        offset: _kRibbonOffset,
      );
      if (addedDate != null) {
        corner = Tooltip(
          message: 'Added ${_ribbonDateFormat.format(addedDate)}',
          child: corner,
        );
      }
      return Positioned(left: 0, top: 0, child: corner);
    }

    return Positioned(
      left: cx - bandWidth / 2,
      top: cx - bandHeight / 2,
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
      ref.read(lastSelectedGameIdProvider.notifier).set(widget.game.id);
    }

    final theme = ref.read(themeProvider);
    final targetGames = _getTargetGames();
    final count = targetGames.length;
    final suffix = count > 1 ? ' ($count)' : '';
    final isFetching = ref.read(batchFetchProvider).isActive;
    final hasSteamTargets = targetGames.any((g) => g.platform == 'Steam');

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
        menuRowItem(value: 'copy', icon: Icons.copy_all, label: 'Copy$suffix'),
        const PopupMenuDivider(),
        menuRowItem(
          value: 'details',
          icon: Icons.edit_outlined,
          label: 'Game Editor$suffix',
          enabled: !isFetching,
          disabledIcon: Icons.lock_rounded,
          disabledLabel: 'Game Editor (Locked)$suffix',
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

  bool _shouldShowNewBadge(bool hasBeenViewed) {
    if (hasBeenViewed) return false;
    final age = DateTime.now().difference(widget.game.createdAt);
    return !age.isNegative && age <= _newBadgeLifetime;
  }

  List<Color> _computeListGradientColors(AppThemeData theme, bool isSelected) {
    if (isSelected) return theme.listCardSelectedGradient;
    if (_isHovered) return theme.listCardHoverGradient;
    return theme.listCardDefaultGradient;
  }
}
