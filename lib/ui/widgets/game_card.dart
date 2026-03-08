/// GameCard widget - displays a game in grid or list view
/// Matches the original Python GameCard with all features
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/platform_patterns.dart';
import '../../core/services/steam_service.dart';
import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import '../../providers/app_providers.dart';
import 'game_cover_image.dart';
import 'notification_system.dart';
import 'tag_width_cache.dart';
import '../dialogs/game_details_dialog.dart';
import '../dialogs/steam_lookup_dialog.dart';
import '../dialogs/copy_actions_dialog.dart';

/// Game card widget with grid and list modes
/// Handles its own selection state and interactions for efficiency
class GameCard extends ConsumerStatefulWidget {
  const GameCard({super.key, required this.game});

  final Game game;

  @override
  ConsumerState<GameCard> createState() => _GameCardState();
}

class _GameCardState extends ConsumerState<GameCard>
    with TickerProviderStateMixin {
  bool _isHovered = false;

  // Unified hover AnimationController — a single clock drives both the scale
  // Transform and the box-shadow alpha for grid cards, replacing the previous
  // TweenAnimationBuilder + AnimatedContainer dual-controller pattern.
  late final AnimationController _hoverController;
  late final Animation<double> _hoverAnim;

  // Selection AnimationController — replaces TweenAnimationBuilder in
  // _buildSelectionOverlay so the controller is never recreated on each
  // isSelected flip, eliminating per-frame EdgeInsets/Color/BoxShadow
  // allocations from a TweenAnimationBuilder's internal controller.
  late final AnimationController _selectionController;
  late final Animation<double> _selectionAnim;

  // Tag-row layout cache keyed on (maxWidth, textScale, tag-id fingerprint).
  // Skips the O(n) text-measurement loop when nothing relevant has changed
  // (most hover / selection state rebuilds fall into this fast path).
  String? _lastTagCacheKey;
  int _cachedTagBestCount = 0;
  double _cachedTagBestWidth = 0.0;
  bool _cachedTagCountFits = false;

  /// Track if we just handled a pointer down event to prevent duplicate
  /// selection handling from onEnter firing right after onPointerDown.
  bool _handledPointerDownThisFrame = false;
  PointerDeviceKind _lastPointerKind = PointerDeviceKind.mouse;
  static final NumberFormat _compactNumber = NumberFormat.compact();
  static final DateFormat _deadlineFormat = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(
      duration: kCardHoverAnimation,
      vsync: this,
    );
    _hoverAnim = CurvedAnimation(
      parent: _hoverController,
      curve: Curves.easeOut,
      reverseCurve: Curves.linear,
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
  void dispose() {
    _hoverController.dispose();
    _selectionController.dispose();
    super.dispose();
  }

  bool get _isCtrlPressed {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
  }

  bool get _isShiftPressed {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  void _handleTap() {
    final notifier = ref.read(gamesProvider.notifier);
    final selectedIds = ref.read(
      gamesProvider.select((s) => s.selectedGameIds),
    );
    final lastId = ref.read(lastSelectedGameIdProvider);

    final isCtrlPressed = _isCtrlPressed;
    final isShiftPressed = _isShiftPressed;

    if (isShiftPressed && lastId != null) {
      // Shift+Click: Range selection
      notifier.selectRange(lastId, widget.game.id);
    } else if (isCtrlPressed) {
      // Ctrl+Click: Toggle selection
      notifier.toggleGameSelection(widget.game.id);
      // Update last selected ID only if we just selected it?
      // Windows updates "focus" regardless of toggle state, usually.
        ref
          .read(lastSelectedGameIdProvider.notifier)
          .setLastSelectedGameId(widget.game.id);
    } else {
      // Standard Click: Select exclusive
      if (selectedIds.contains(widget.game.id) && selectedIds.length == 1) {
        // Already selected and it's the only one, do nothing visually but update focus
      } else {
        notifier.clearSelection();
        notifier.selectGame(widget.game.id);
      }
        ref
          .read(lastSelectedGameIdProvider.notifier)
          .setLastSelectedGameId(widget.game.id);
    }
  }

  void _handleDoubleTap() {
    // Block during batch fetch
    if (ref.read(batchFetchProvider).isActive) {
      NotificationManager.instance.warning(
        'Cannot edit games while Steam data fetch is in progress',
      );
      return;
    }

    final allGames = ref.read(gamesProvider.select((s) => s.filteredGames));
    final selectedIds = ref.read(
      gamesProvider.select((s) => s.selectedGameIds),
    );

    // If multiple selected, pass all of them to allow browsing.
    // If only one (or none selected but double clicked), pass just that one (or surrounding list?).
    // "Multi game edit where I can easily switch between the selected games"
    // implies restricting the view to the selection.

    final List<int> idsToPass;
    if (selectedIds.contains(widget.game.id) && selectedIds.length > 1) {
      // Pass all selected IDs, sorted by their appearance in the full list
      idsToPass = allGames
          .where((g) => selectedIds.contains(g.id))
          .map((g) => g.id)
          .toList();
    } else {
      // Just this one? Or the full list?
      // User requirement was "switch between the *selected* games".
      // If I double click a game and it's the only one selected, maybe no nav needed.
      // But if I want to browse my library?
      // Standard behavior: usually opens details for ONE item.
      // I'll implement "switch between selected".
      idsToPass = [widget.game.id];
    }

    showDialog(
      context: context,
      builder: (context) =>
          GameDetailsDialog(initialGameId: widget.game.id, gameIds: idsToPass),
    );
  }

  void _handleLongPress() {
    // Only allow long-press selection for touch input.
    if (_lastPointerKind != PointerDeviceKind.touch) return;
    // Prevent long press from interfering with drag selection
    if (ref.read(dragSelectionProvider).isActive) return;

    ref.read(gamesProvider.notifier).toggleGameSelection(widget.game.id);
    ref
      .read(lastSelectedGameIdProvider.notifier)
      .setLastSelectedGameId(widget.game.id);
  }

  void _handleDragSelectionEvent(
    PointerEvent event, {
    bool fromPointerDown = false,
  }) {
    if (event.kind != PointerDeviceKind.mouse) return;
    if ((event.buttons & kPrimaryMouseButton) == 0) return;

    final dragState = ref.read(dragSelectionProvider);
    if (!dragState.isActive) return;
    if (dragState.visitedIds.contains(widget.game.id)) return;

    final notifier = ref.read(gamesProvider.notifier);
    final selectedIds = ref.read(
      gamesProvider.select((s) => s.selectedGameIds),
    );
    final lastId = ref.read(lastSelectedGameIdProvider);

    if (_isShiftPressed && lastId != null) {
      notifier.selectRange(lastId, widget.game.id);
    } else if (_isCtrlPressed) {
      notifier.toggleGameSelection(widget.game.id);
    } else {
      final mode =
          dragState.mode ??
          (selectedIds.contains(widget.game.id)
              ? DragSelectionMode.deselect
              : DragSelectionMode.select);
      if (dragState.mode == null) {
        ref.read(dragSelectionProvider.notifier).setMode(mode);
      }

      if (mode == DragSelectionMode.select) {
        notifier.selectGame(widget.game.id);
      } else {
        notifier.deselectGame(widget.game.id);
      }
    }

    ref.read(dragSelectionProvider.notifier).markVisited(widget.game.id);
    ref
      .read(lastSelectedGameIdProvider.notifier)
      .setLastSelectedGameId(widget.game.id);
  }

  List<Game> _getTargetGames() {
    final selectedIds = ref.read(
      gamesProvider.select((s) => s.selectedGameIds),
    );
    if (selectedIds.contains(widget.game.id)) {
      return ref.read(selectedGamesProvider);
    }
    return [widget.game];
  }

  Future<void> _toggleUsed() async {
    final targets = _getTargetGames();
    // Use the opposite state of the clicked game for all
    final nextValue = !widget.game.isUsed;

    final ok = await ref
        .read(gamesProvider.notifier)
        .setGamesUsed(targets.map((g) => g.id).toList(), nextValue);

    if (!ok) {
      final error = ref.read(gamesProvider.select((s) => s.error));
      NotificationManager.instance.error(error ?? 'Failed to update games');
      return;
    }

    final status = nextValue ? 'used' : 'unused';
    if (targets.length == 1) {
      NotificationManager.instance.info('Marked as $status');
    } else {
      NotificationManager.instance.info(
        'Marked ${targets.length} games as $status',
      );
    }
  }

  Future<void> _openSteamPage() async {
    final targets = _getTargetGames();

    for (final game in targets) {
      final title = game.title;
      final appId = game.steamAppId;
      final Uri url = appId.isNotEmpty
          ? Uri.parse('https://store.steampowered.com/app/$appId')
          : Uri.parse(
              'https://store.steampowered.com/search/?term=${Uri.encodeComponent(title)}',
            );

      try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } catch (e) {
        NotificationManager.instance.error(
          'Failed to open Steam page for $title',
        );
      }
    }

    if (targets.length == 1) {
      NotificationManager.instance.info(
        'Opened Steam page for ${targets.first.title}',
      );
    } else {
      NotificationManager.instance.info(
        'Opened Steam pages for ${targets.length} games',
      );
    }
  }

  Future<void> _deleteGames() async {
    // Block during batch fetch
    if (ref.read(batchFetchProvider).isActive) {
      NotificationManager.instance.warning(
        'Cannot delete games while Steam data fetch is in progress',
      );
      return;
    }

    final targets = _getTargetGames();
    final theme = ref.read(themeProvider);

    final title = targets.length == 1
        ? 'Delete "${targets.first.title}"?'
        : 'Delete ${targets.length} games?';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.background,
        title: Text(title),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: theme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ids = targets.map((g) => g.id).toList();
      final ok = await ref.read(gamesProvider.notifier).deleteGames(ids);

      if (!ok) {
        final error = ref.read(gamesProvider.select((s) => s.error));
        NotificationManager.instance.error(error ?? 'Failed to delete games');
        return;
      }

      if (targets.length == 1) {
        NotificationManager.instance.success('Deleted: ${targets.first.title}');
      } else {
        NotificationManager.instance.success('Deleted ${targets.length} games');
      }

      // Do not clear the user's selection here — the provider updates the
      // selectedGameIds to remove deleted IDs. Keeping selection allows the
      // selection bar to remain when other items are still selected.
    }
  }

  Future<void> _steamLookup() async {
    final targets = _getTargetGames()
        .where((g) => g.platform == 'Steam')
        .toList();

    if (targets.isEmpty) {
      NotificationManager.instance.info('No Steam games selected');
      return;
    }

    if (targets.length == 1) {
      await _singleSteamLookup(targets.first);
    } else {
      await performSteamBatchLookup(context, targets);
    }
  }

  Future<void> _singleSteamLookup(Game game) async {
    final steamService = ref.read(steamServiceProvider);
    final resolution = await resolveSteamResultForTitle(
      context,
      title: game.title,
      steamService: steamService,
    );
    if (!mounted) return;

    if (resolution.cancelled) {
      return;
    }

    final result = resolution.result;
    if (result == null) {
      NotificationManager.instance.info(
        'No Steam data found for "${game.title}"',
      );
      return;
    }

    await showSteamLookupDialog(context, game, initialResult: result);
  }

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

    PopupMenuItem<String> menuHeader(String text) {
      return PopupMenuItem<String>(
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
    }

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
      final resolvedEnabled = enabled;
      final resolvedLabel = resolvedEnabled ? label : (disabledLabel ?? label);
      final mutedColor = theme.textSecondary.withValues(alpha: 0.5);

      return PopupMenuItem<String>(
        value: resolvedEnabled ? value : null,
        enabled: resolvedEnabled,
        child: Row(
          children: [
            Icon(
              resolvedEnabled ? icon : (disabledIcon ?? icon),
              size: 18,
              color: resolvedEnabled
                  ? (iconColor ?? theme.textSecondary)
                  : (disabledColor ?? mutedColor),
            ),
            const SizedBox(width: 12),
            Text(
              resolvedLabel,
              style: TextStyle(
                color: resolvedEnabled
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

    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlayObject.size,
      ),
      color: theme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        side: BorderSide(color: theme.border),
      ),
      items: [
        // single copy button to open dialog
        menuHeader('Copy$suffix'),
        menuRowItem(value: 'copy', icon: Icons.copy_all, label: 'Copy$suffix'),
        const PopupMenuDivider(),
        // always offer a "View Details" action, even when multiple games
        // are selected.  The handler (_handleDoubleTap) already knows how to
        // open the details dialog for all selected ids when count > 1.
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
        // show the unified copy dialog
        showDialog(
          context: context,
          builder: (ctx) => CopyActionsDialog(targets: targetGames),
        );
        break;
      case 'details':
        _handleDoubleTap();
        break;
      case 'open_steam':
        _openSteamPage();
        break;
      case 'steam_lookup':
        _steamLookup();
        break;
      case 'toggle_used':
        _toggleUsed();
        break;
      case 'delete':
        _deleteGames();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final cardSettings = ref.watch(gameCardSettingsProvider);
    final viewMode = ref.watch(viewModeProvider);
    final isSelected = ref.watch(
      gamesProvider.select((s) => s.selectedGameIds.contains(widget.game.id)),
    );
    final fetchStatus = ref.watch(
      batchFetchProvider.select((s) => s.getStatus(widget.game.id)),
    );

    // Drive selection animation from build() — forward/reverse are no-ops if
    // the controller is already at the target value, so this is inexpensive.
    if (isSelected) {
      _selectionController.forward();
    } else {
      _selectionController.reverse();
    }

    return viewMode == GameListViewMode.grid
        ? _buildGridCard(
            theme,
            isSelected,
            cardSettings.showTitle,
            cardSettings.showPlatform,
            cardSettings.showTags,
            cardSettings.showTagsOnHoverOnly,
            cardSettings.showDeadline,
            cardSettings.showRatings,
            fetchStatus,
          )
        : _buildListCard(
            theme,
            isSelected,
            cardSettings.showTitle,
            cardSettings.showPlatform,
            cardSettings.showTags,
            cardSettings.showTagsOnHoverOnly,
            cardSettings.showDeadline,
            cardSettings.showRatings,
            fetchStatus,
          );
  }

  Widget _buildGridCard(
    AppThemeData theme,
    bool isSelected,
    bool showTitle,
    bool showPlatform,
    bool showTags,
    bool showTagsOnHoverOnly,
    bool showDeadline,
    bool showRatings,
    GameFetchStatus? fetchStatus,
  ) {
    final showMetaOnHover = showTagsOnHoverOnly;
    final showRatingsNow = showRatings && (!showMetaOnHover || _isHovered);

    // Corner radius captured once per build so the AnimatedBuilder closure
    // never allocates a new BorderRadius on every animation tick.
    final radius = BorderRadius.circular(theme.cornerRadius);

    // Single AnimatedBuilder drives both scale and shadow from one shared
    // AnimationController, replacing the previous TweenAnimationBuilder
    // (scale) + AnimatedContainer (shadow) dual-controller pattern.
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
          // Static child subtree — not rebuilt on every animation tick.
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

                  // Deadline badge on the left edge of the card (over the cover image).
                  if (showDeadline && widget.game.hasDeadline)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: _buildDeadlineBadge(
                        theme,
                        borderRadius: BorderRadius.circular(11),
                        showIcon: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        minHeight: 22.0,
                      ),
                    ),

                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showTitle) _buildTitleChip(theme),
                        const SizedBox(height: 4),
                        if (showTags && widget.game.tags.isNotEmpty)
                          _buildAnimatedTagsRow(
                            context,
                            theme,
                            isVisible: !showTagsOnHoverOnly || _isHovered,
                            // Grid card width is fixed — pass it directly to skip
                            // the LayoutBuilder secondary layout pass on every
                            // visible card during window resize.
                            fixedMaxWidth: kGridCardWidth - 16.0,
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: _buildTopRightChips(
                      theme,
                      showPlatform: showPlatform,
                      showDeadline: showDeadline,
                      showRatings: showRatingsNow,
                    ),
                  ),
                  _buildSelectionOverlay(theme, isSelected),
                  AnimatedSwitcher(
                    duration: kFastAnimation,
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: fetchStatus != null
                        ? KeyedSubtree(
                            key: ValueKey(fetchStatus),
                            child: _buildFetchStatusOverlay(theme, fetchStatus),
                          )
                        : const SizedBox.shrink(key: ValueKey<Null>(null)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListCard(
    AppThemeData theme,
    bool isSelected,
    bool showTitle,
    bool showPlatform,
    bool showTags,
    bool showTagsOnHoverOnly,
    bool showDeadline,
    bool showRatings,
    GameFetchStatus? fetchStatus,
  ) {
    final showMetaOnHover = showTagsOnHoverOnly;
    final showRatingsNow = showRatings && (!showMetaOnHover || _isHovered);

    // Pre-compute decoration constants once per build — not per animation tick.
    final listRadius = BorderRadius.circular(theme.cornerRadius);
    final listGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      // ignore: prefer_const_constructors — GradientRotation has no const constructor
      transform: GradientRotation(
        0 * math.pi / 180,
      ),
      colors: _computeListGradientColors(theme, isSelected),
    );

    return _buildInteractive(
      RepaintBoundary(
        child: AnimatedBuilder(
          animation: _hoverAnim,
          // The card's content (SizedBox > Stack > Row) is the static child —
          // it is NOT rebuilt on animation ticks. Only the DecoratedBox
          // decoration (hover shadow alpha, gradient) changes per tick,
          // eliminating the full layout pass that AnimatedContainer previously
          // triggered on the entire card subtree every animation frame.
          builder: (context, child) {
            final t = _hoverAnim.value;
            return Transform.scale(
              scale: 1.0 + t * 0.006,
              alignment: Alignment.center,
              filterQuality: FilterQuality.medium,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: listGradient,
                  boxShadow: (!isSelected && t > 0.001)
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
                child: child,
              ),
            );
          },
          child: SizedBox(
            height: kListCardHeight,
            child: Stack(
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(theme.cornerRadius),
                      ),
                      child: SizedBox(
                        width: kListCardImageWidth,
                        height: kListCardHeight,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildCoverImage(theme),
                            if (widget.game.isUsed)
                              _buildUsedOverlay(
                                theme,
                                patternSize: const Size(
                                  kListCardImageWidth,
                                  kListCardHeight,
                                ),
                              ),

                            // Deadline badge positioned on the cover image's left edge.
                            if (showDeadline && widget.game.hasDeadline)
                              Positioned(
                                left: 8,
                                top: 8,
                                child: _buildDeadlineBadge(
                                  theme,
                                  borderRadius: BorderRadius.circular(11),
                                  showIcon: true,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  minHeight: 22.0,
                                ),
                              ),

                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.game.title,
                                    style: TextStyle(
                                      color: theme.textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Spacer(),
                            if (showTags && widget.game.tags.isNotEmpty)
                              _buildAnimatedTagsRow(
                                context,
                                theme,
                                isVisible: !showTagsOnHoverOnly || _isHovered,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                _buildSelectionOverlay(
                  theme,
                  isSelected,
                  imageWidth: kListCardImageWidth,
                ),
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
                            imageWidth: kListCardImageWidth,
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey<Null>(null)),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: _buildTopRightChips(
                    theme,
                    showPlatform: showPlatform,
                    showDeadline: showDeadline,
                    showRatings: showRatingsNow,
                  ),
                ),

              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInteractive(Widget child) {
    return Listener(
      onPointerDown: (event) {
        _lastPointerKind = event.kind;
        // Right-click should NOT change the current selection here — allow
        // onSecondaryTapDown / _showContextMenu to decide selection so that
        // right-clicking one item when multiple are selected doesn't
        // deselect the others.
        if (event.kind == PointerDeviceKind.mouse &&
            (event.buttons & kSecondaryMouseButton) != 0) {
          return;
        }

        if (event.kind == PointerDeviceKind.mouse &&
            (event.buttons & kPrimaryMouseButton) != 0) {
          final dragNotifier = ref.read(dragSelectionProvider.notifier);
          final dragState = ref.read(dragSelectionProvider);
          if (_isCtrlPressed || _isShiftPressed) {
            if (!dragState.isActive) {
              dragNotifier.start(startId: widget.game.id);
            }
            // Mark that we handled selection in onPointerDown to prevent
            // onEnter from immediately re-processing this same card.
            _handledPointerDownThisFrame = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handledPointerDownThisFrame = false;
            });
            _handleDragSelectionEvent(event, fromPointerDown: true);
            return;
          }
          if (dragState.isActive) {
            _handleDragSelectionEvent(event, fromPointerDown: true);
            return;
          }
        }
        _handleTap();
      },
      onPointerMove: _handleDragSelectionEvent,
      child: MouseRegion(
        onEnter: (event) {
          // Skip if we just handled this card in onPointerDown to avoid
          // double-toggling selection due to event ordering.
          if (!_handledPointerDownThisFrame) {
            _handleDragSelectionEvent(event);
          }
          if (!mounted) return;
          setState(() => _isHovered = true);
          _hoverController.forward();
        },
        onExit: (_) {
          if (!mounted) return;
          setState(() => _isHovered = false);
          _hoverController.reverse();
        },
        child: GestureDetector(
          onDoubleTap: _handleDoubleTap,
          onLongPress: _handleLongPress,
          onSecondaryTapDown: (details) =>
              _showContextMenu(context, details.globalPosition),
          child: child,
        ),
      ),
    );
  }

  Widget _buildCoverImage(AppThemeData theme) {
    return GameCoverImage(
      theme: theme,
      coverImage: widget.game.hasCoverImage ? widget.game.coverImage : null,
    );
  }

  /// Apply saturation adjustment to a color (used for tag chip visibility)
  static Color _applySaturation(Color color, double factor) {
    final h = HSLColor.fromColor(color);
    final newS = (h.saturation * factor).clamp(0.0, 1.0);
    return h.withSaturation(newS).toColor();
  }

  /// Use pre-computed theme colors instead of calculating HSL on every frame
  List<Color> _computeListGradientColors(AppThemeData theme, bool isSelected) {
    if (isSelected) {
      return theme.listCardSelectedGradient;
    } else if (_isHovered) {
      return theme.listCardHoverGradient;
    }
    return theme.listCardDefaultGradient;
  }

  Widget _buildGradientOverlay(AppThemeData theme, bool isSelected) {
    if (isSelected) {
      // Use pre-computed gradient — no inline Color.withValues allocation per build.
      return DecoratedBox(
        decoration: BoxDecoration(gradient: theme.gridCardSelectedGradient),
        child: const SizedBox.expand(),
      );
    }

    if (_isHovered) {
      return DecoratedBox(
        decoration: BoxDecoration(gradient: theme.gridCardHoverGradient),
        child: const SizedBox.expand(),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildUsedOverlay(AppThemeData theme, {required Size patternSize}) {
    // Removed RepaintBoundary - it created a separate compositing layer
    // that animated independently during AnimatedScale, causing jitter.
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
            painter: _UsedPatternPainter(
              textColor: Colors.white.withValues(alpha: 0.45),
              // Bottom-left -> top-right tilt.
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

  /// Selection overlay with an animated checkmark.
  ///
  /// Driven by [_selectionController] (a stable controller that persists for
  /// the lifetime of the card) rather than [TweenAnimationBuilder] (which
  /// allocates a new controller on every [isSelected] flip). The [Icon] is
  /// passed as the static [AnimatedBuilder.child] so it is never rebuilt on
  /// animation ticks — only the surrounding [Container] decoration changes.
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
          // if the animation is fully dismissed there's nothing to show at all
          if (t <= 0.0) {
            return const SizedBox.shrink();
          }

          final shadow = t > 0.01
              ? [
                  BoxShadow(
                    color: theme.accent.withValues(alpha: 0.28 * t),
                    blurRadius: 12 * t,
                    spreadRadius: t,
                  ),
                ]
              : null;

          final borderRadius = BorderRadius.circular(theme.cornerRadius);

          final iconWidget = Container(
            padding: EdgeInsets.all(4 + 4 * t),
            decoration: BoxDecoration(
              color: theme.accent.withValues(alpha: t),
              shape: BoxShape.circle,
              boxShadow: shadow,
            ),
            // Static icon — fade it out with the animation so it disappears
            // completely when t == 0.  Avoids the tiny residual checkmark
            // visible on deselected cards.
            child: SizedBox(
              width: 12 + 12 * t,
              height: 12 + 12 * t,
              child: Opacity(opacity: t, child: child),
            ),
          );

          // In list mode, keep the icon centred over the cover image rather
          // than the full card width.
          final centeredIcon = imageWidth != null
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: imageWidth,
                    child: Center(child: iconWidget),
                  ),
                )
              : Center(child: iconWidget);

          return Container(
            decoration: BoxDecoration(
              color: theme.primary.withValues(alpha: 0.35 * t),
              border: Border.all(
                color: theme.accent.withValues(alpha: t),
                width: 3.0,
              ),
              borderRadius: borderRadius,
            ),
            child: centeredIcon,
          );
        },
        child: const FittedBox(child: Icon(Icons.check, color: Colors.white)),
      ),
    );
  }

  /// Fetch status overlay for grid cards during batch Steam data fetch.
  /// Uses [AnimatedSwitcher] (at the call site) for crossfading between states
  /// and a smooth fade-out when the overlay is removed.
  Widget _buildFetchStatusOverlay(
    AppThemeData theme,
    GameFetchStatus status, {
    BorderRadius? borderRadius,
    double? imageWidth,
  }) {
    final Color color;
    final Widget iconContent;
    switch (status) {
      case GameFetchStatus.waiting:
        color = theme.primary;
        iconContent = const Icon(Icons.schedule, color: Colors.white, size: 22);
      case GameFetchStatus.processing:
        color = theme.accent;
        iconContent = const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white,
          ),
        );
      case GameFetchStatus.done:
        color = Colors.green;
        iconContent = const Icon(Icons.check, color: Colors.white, size: 22);
      case GameFetchStatus.error:
        color = Colors.red;
        iconContent =
            const Icon(Icons.error_outline, color: Colors.white, size: 22);
    }

    final effectiveBorderRadius = borderRadius ?? BorderRadius.circular(theme.cornerRadius);
    final circle = AnimatedContainer(
      duration: kFastAnimation,
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        shape: BoxShape.circle,
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
          width: 22,
          height: 22,
          child: Center(child: iconContent),
        ),
      ),
    );

    // In list mode, keep the icon centred over the cover image rather
    // than the full card width.
    final centeredCircle = imageWidth != null
        ? Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: imageWidth,
              child: Center(child: circle),
            ),
          )
        : Center(child: circle);

    return IgnorePointer(
      child: AnimatedContainer(
        duration: kFastAnimation,
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: color.withValues(
            alpha: status == GameFetchStatus.done ? 0.12 : 0.28,
          ),
          border: Border.all(color: color, width: 3),
          borderRadius: effectiveBorderRadius,
        ),
        child: centeredCircle,
      ),
    );
  }

  Widget _buildTopRightChips(
    AppThemeData theme, {
    required bool showPlatform,
    required bool showDeadline,
    required bool showRatings,
  }) {
    // Top-right area only contains review badges now — the deadline badge
    // is rendered on the left edge of the card over the cover image.
    final bool hasRatingData = widget.game.reviewCount > 0;
    final bool showRatingChip = showRatings && hasRatingData;
    final bool hasBadges = hasRatingData;
    final bool hasPlatform = showPlatform;
    final bool hasDlc = widget.game.isDlc;

    if (!hasBadges && !hasPlatform && !hasDlc) return const SizedBox.shrink();

    // Shared inset so platform tag and badge group align to the same top gap.
    const EdgeInsets groupInset = EdgeInsets.symmetric(
      horizontal: 5.0,
      vertical: 5.0,
    );
    const double gap = 4.0;

    return Padding(
      padding: groupInset,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Keep other badges (deadline, etc.) in the badge group. If a
          // platform icon is present we will render the review badge beneath
          // the platform pill instead of inside the badge group.
          // If there are badges but no platform, render the badge group.
          // When DLC is present we render it *below* the badges (vertical
          // stack) so it appears under the rating badge as requested.
          if (hasBadges && !hasPlatform)
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildAnimatedTopToBottomReveal(
                  isVisible: showRatingChip,
                  child: _buildBadgeGroup(
                    theme,
                    showDeadline: showDeadline,
                    showRatings: true,
                  ),
                ),
                if (hasDlc) ...[
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 20.0),
                    child: _buildTagChip(
                      theme,
                      'DLC',
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      overrideBackground: theme.basePrimary,
                      overrideTextColor: theme.primaryButtonText,
                    ),
                  ),
                ],
              ],
            ),
          if (hasBadges && hasPlatform) const SizedBox(width: gap),

          // When a platform chip is shown *and* the game has reviews,
          // stack the platform pill and the review badge vertically so the
          // review badge appears below the platform icon. Append the DLC
          // chip under the rating badge when present.
          if (hasPlatform)
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildPlatformTag(theme),
                if (hasBadges)
                  _buildAnimatedTopToBottomReveal(
                    isVisible: showRatingChip,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _buildRatingBadge(
                        theme,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        minHeight: 20.0,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                if (hasDlc) ...[
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 20.0),
                    child: _buildTagChip(
                      theme,
                      'DLC',
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      overrideBackground: theme.basePrimary,
                      overrideTextColor: theme.primaryButtonText,
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBadgeGroup(
    AppThemeData theme, {
    required bool showDeadline,
    required bool showRatings,
  }) {
    // Badge size
    final badgeHeight = 22.0;
    final builders = <Widget Function(BorderRadius)>[];
    // Use the regular (cozy) padding for all badges so grid/list match.
    final EdgeInsets badgePadding = const EdgeInsets.symmetric(
      horizontal: 8,
      vertical: 2,
    );

    // Deadline badge moved to the left edge of the card (over the cover image).
    // Keep the badge group available for other badges (reviews, etc.).
    // No-op here when only deadline is present.

    if (showRatings && widget.game.reviewCount > 0) {
      builders.add(
        (radius) => _buildRatingBadge(
          theme,
          borderRadius: radius,
          padding: badgePadding,
          minHeight: badgeHeight,
        ),
      );
    }

    if (builders.isEmpty) return const SizedBox.shrink();

    final count = builders.length;
    // Make badges pill-shaped, add spacing between them, and inset the whole
    // group from the card edges so badges don't touch the card border.
    const double gap = 3.0;
    final BorderRadius badgeRadius = BorderRadius.circular(badgeHeight / 2);

    return ClipRRect(
      borderRadius: BorderRadius.only(
        topRight: Radius.circular(theme.cornerRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(count, (index) {
          return Padding(
            padding: EdgeInsets.only(right: index == count - 1 ? 0 : gap),
            child: DefaultTextStyle.merge(
              style: const TextStyle(height: 1.1),
              // use a full pill radius for every badge
              child: builders[index](badgeRadius),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPlatformTag(AppThemeData theme) {
    // Separated from the badge group so it can be sized independently.
    const double platformBadgeHeight = 32.0;
    const EdgeInsets platformPadding = EdgeInsets.symmetric(
      horizontal: 6,
      vertical: 2,
    );

    return _buildPlatformBadge(
      theme,
      padding: platformPadding,
      minHeight: platformBadgeHeight,
    );
  }

  Widget _buildTitleChip(AppThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        // Make the title a true pill/stadium so it matches tag chips
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        widget.game.title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  IconData _platformIconFor(GamePlatform platform) {
    return switch (platform) {
      GamePlatform.steam => FontAwesomeIcons.steamSymbol,
      GamePlatform.epicGames => FontAwesomeIcons.store,
      GamePlatform.gog => FontAwesomeIcons.solidFloppyDisk,
      GamePlatform.origin => FontAwesomeIcons.circleDot,
      GamePlatform.ubisoft => FontAwesomeIcons.coins,
      GamePlatform.xbox => FontAwesomeIcons.xbox,
      GamePlatform.playStation => FontAwesomeIcons.playstation,
      GamePlatform.nintendo => FontAwesomeIcons.gamepad,
      GamePlatform.humble => FontAwesomeIcons.store,
      GamePlatform.itchio => FontAwesomeIcons.gamepad,
      GamePlatform.webLink => FontAwesomeIcons.link,
      GamePlatform.other => FontAwesomeIcons.question,
    };
  }

  double _platformIconSizeFor(GamePlatform platform, {double? minHeight}) {
    final double base = minHeight != null
        ? math.max(23.0, math.min(minHeight * 0.6, 28.0))
        : 18.0;

    double multiplier;
    if (platform == GamePlatform.steam) {
      multiplier = 1.14;
    } else if (platform == GamePlatform.nintendo ||
        platform == GamePlatform.itchio) {
      multiplier = 0.91;
    } else {
      multiplier = 1.0;
    }

    return base * multiplier;
  }

  IconData _ratingIconFor(int score, int reviewCount) {
    if (reviewCount == 0) return Icons.help_outline_rounded;
    if (score >= 95) return Icons.auto_awesome_rounded;
    if (score >= 90) return Icons.thumb_up_alt_rounded;
    if (score >= 75) return Icons.thumb_up_rounded;
    if (score >= 60) return Icons.thumbs_up_down_rounded;
    if (score >= 40) return Icons.thumb_down_alt_rounded;
    return Icons.thumb_down_rounded;
  }

  Widget _buildPlatformBadge(
    AppThemeData theme, {
    BorderRadius? borderRadius,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    double? minHeight,
  }) {
    final platform = widget.game.platformEnum;
    final platformLabel = widget.game.platform;
    // Scale icon size per-platform (steam/gamepad adjusted).
    final double iconSize = _platformIconSizeFor(
      platform,
      minHeight: minHeight,
    );
    // Platform badge no longer displays a "DLC" label — DLC is
    // rendered as a dedicated tag chip in the tags row so layout can
    // reserve space for it. Keep the icon-only circular rendering when a
    // fixed minHeight is provided (common for compact badge placements).
    final bool iconOnly = minHeight != null;
    if (iconOnly) {
      return Tooltip(
        message: platformLabel,
        child: Semantics(
          label: platformLabel,
          child: Container(
            width: minHeight,
            height: minHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.basePrimary,
              shape: BoxShape.circle,
            ),
            child: FaIcon(
              _platformIconFor(platform),
              size: iconSize,
              color: theme.primaryButtonText,
            ),
          ),
        ),
      );
    }

    return Container(
      alignment: Alignment.center,
      padding: padding,
      constraints: minHeight != null
          ? BoxConstraints.tightFor(height: minHeight)
          : null,
      decoration: BoxDecoration(
        color: theme.basePrimary,
        borderRadius: borderRadius ?? BorderRadius.circular(12),
      ),
      child: Tooltip(
        message: platformLabel,
        child: Semantics(
          label: platformLabel,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(
                _platformIconFor(platform),
                size: iconSize,
                color: theme.primaryButtonText,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRatingBadge(
    AppThemeData theme, {
    BorderRadius? borderRadius,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    double? minHeight,
  }) {
    final reviewCount = widget.game.reviewCount;
    final ratingText = reviewCount == 0
        ? 'No Reviews'
        : '${widget.game.reviewScore}% · ${widget.game.reviewRating} · ${_compactNumber.format(reviewCount)}';
    // larger, proportional icon sizing so the badge appears bolder
    final iconSize = minHeight != null
        ? math.max(16.0, math.min(minHeight * 0.6, 22.0))
        : 18.0;

    return Tooltip(
      message: ratingText,
      child: Container(
        alignment: Alignment.center,
        padding: padding,
        constraints: minHeight != null
            ? BoxConstraints.tightFor(height: minHeight)
            : null,
        decoration: BoxDecoration(
          color: widget.game.reviewColor.withValues(alpha: 0.95),
          borderRadius:
              borderRadius ?? BorderRadius.circular(theme.cornerRadius / 2),
        ),
        child: Icon(
          _ratingIconFor(widget.game.reviewScore, reviewCount),
          color: Colors.white,
          size: iconSize,
        ),
      ),
    );
  }

  Widget _buildDeadlineBadge(
    AppThemeData theme, {
    BorderRadius? borderRadius,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    bool showIcon = false,
    double? minHeight,
  }) {
    final daysLeft = widget.game.daysUntilDeadline ?? 0;
    final isExpired = widget.game.isExpired;
    final isUrgent = daysLeft <= 3 && !isExpired;
    final isSoon = daysLeft <= 7 && !isExpired && !isUrgent;
    final isDueSoon = daysLeft <= 14 && !isExpired;
    final iconOnly = !isExpired && !isDueSoon;
    // Scale icon/text with badge height and allow larger caps so 'EXPIRED'
    // becomes prominent.
    final iconSize = minHeight != null
        ? math.max(16.0, math.min(minHeight * 0.6, 22.0))
        : 18.0;

    Color badgeColor;
    String text;

    if (isExpired) {
      badgeColor = Colors.red;
      text = 'Expired';
    } else if (isUrgent) {
      badgeColor = theme.deadlineUrgent;
      text = '$daysLeft days';
    } else if (isSoon) {
      badgeColor = theme.deadlineSoon;
      text = '$daysLeft days';
    } else {
      badgeColor = theme.deadlineNormal;
      final date = widget.game.deadlineDate;
      text = date != null ? _deadlineFormat.format(date) : 'Deadline';
    }

    final deadlineDate = widget.game.deadlineDate;

    // Compute tooltip message without an IIFE — avoids a closure allocation on every build.
    final String tooltipMessage;
    if (isExpired) {
      if (deadlineDate == null) {
        tooltipMessage = 'Expired';
      } else {
        final daysAgo = daysLeft.abs();
        final agoText = daysAgo == 0
            ? 'today'
            : daysAgo == 1
            ? '1 day ago'
            : '$daysAgo days ago';
        tooltipMessage =
            'Expired $agoText · ${_deadlineFormat.format(deadlineDate)}';
      }
    } else if (deadlineDate == null) {
      tooltipMessage = text;
    } else if (daysLeft == 0) {
      tooltipMessage = 'Due today · ${_deadlineFormat.format(deadlineDate)}';
    } else {
      tooltipMessage =
          'Due in $daysLeft days · ${_deadlineFormat.format(deadlineDate)}';
    }

    if (iconOnly && minHeight != null) {
      return Tooltip(
        message: tooltipMessage,
        child: Container(
          width: minHeight,
          height: minHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
          child: Icon(Icons.schedule, color: Colors.white, size: iconSize),
        ),
      );
    }

    return Tooltip(
      message: tooltipMessage,
      child: Container(
        alignment: Alignment.center,
        padding: padding,
        constraints: minHeight != null
            ? BoxConstraints.tightFor(height: minHeight)
            : null,
        decoration: BoxDecoration(
          color: badgeColor,
          borderRadius:
              borderRadius ?? BorderRadius.circular(theme.cornerRadius / 2),
        ),
        child: iconOnly
            ? Icon(Icons.schedule, color: Colors.white, size: iconSize)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showIcon) ...[
                    Icon(
                      Icons.schedule,
                      color: Colors.white,
                      size: iconSize - 2,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    text,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildTagsRow(
    BuildContext context,
    AppThemeData theme, {
    double? fixedMaxWidth,
  }) {
    final tagNames = widget.game.tags.map((t) => t.name).toList();
    if (tagNames.isEmpty) return const SizedBox.shrink();

    // When a fixed width is provided (grid mode — always kGridCardWidth - 16),
    // skip LayoutBuilder entirely. Grid card dimensions never change on resize,
    // eliminating the extra layout pass forced by LayoutBuilder for every
    // visible card on every resize frame.
    if (fixedMaxWidth != null) {
      final textScaler = MediaQuery.textScalerOf(context);
      return _buildTagsRowForWidth(
        context,
        theme,
        fixedMaxWidth,
        tagNames,
        textScaler,
      );
    }

    // List-mode fallback: width is dynamic (viewport-relative). Bucket to the
    // nearest 8 px so the cache key is stable across small resize increments,
    // reducing O(n) remeasurement frequency ~8× during window drag.
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final rawWidth =
            constraints.hasBoundedWidth && constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        // Bucket to nearest 8 px to stabilise the cache key during resize.
        final bucketedWidth = (rawWidth / 8).floorToDouble() * 8.0;
        return _buildTagsRowForWidth(
          context,
          theme,
          bucketedWidth,
          tagNames,
          textScaler,
        );
      },
    );
  }

  Widget _buildTagsRowForWidth(
    BuildContext context,
    AppThemeData theme,
    double maxWidth,
    List<String> tagNames,
    TextScaler textScaler,
  ) {
    final textDirection = Directionality.of(context);
    final tagStyle = TextStyle(
      color: theme.textPrimary,
      fontSize: 11,
      fontWeight: FontWeight.w300,
    );
    final countStyle = TextStyle(
      color: theme.textPrimary,
      fontSize: 11,
      fontWeight: FontWeight.w300,
    );
    final baseTextStyle = DefaultTextStyle.of(context).style;
    final resolvedTagStyle = baseTextStyle.merge(tagStyle);
    final resolvedCountStyle = baseTextStyle.merge(countStyle);
    const chipPadding = EdgeInsets.symmetric(horizontal: 6, vertical: 2);
    const countPadding = EdgeInsets.symmetric(horizontal: 6, vertical: 2);
    const gap = 4.0;

    double measureChip(String text, TextStyle style, EdgeInsets padding) {
      final textWidth = TagWidthCache.measureTextWidth(
        text,
        style,
        textDirection,
        textScaler,
      );
      // Add a safety buffer to account for:
      // 1. Container borders (usually 1-2px)
      // 2. Sub-pixel anti-aliasing differences
      // 3. Potential slight font mismatches
      // This ensures tags are strictly hidden rather than truncated.
      return textWidth + padding.horizontal + 2.0;
    }

    // Cache key encodes the available width, text scale, and tag-id
    // fingerprint. The layout loop is only re-run when one of these
    // actually changes (rare on typical hover/selection rebuilds).
    final tagFingerprint = widget.game.tags.map((t) => t.id).join(',');
    final tagKey =
        '${maxWidth.toStringAsFixed(0)}:${textScaler.scale(1.0).toStringAsFixed(3)}:$tagFingerprint';

    int bestCount;
    double bestTagsWidth;
    bool countFits;

    if (tagKey == _lastTagCacheKey) {
      // Fast path: reuse cached layout, skipping all measurement calls.
      bestCount = _cachedTagBestCount;
      bestTagsWidth = _cachedTagBestWidth;
      countFits = _cachedTagCountFits;
    } else {
      // Slow path: measure each tag and find the best-fit visible count.
      final separatorWidth = TagWidthCache.measureTextWidth(
        ' · ',
        resolvedTagStyle,
        textDirection,
        textScaler,
      );

      final tagNameWidths = List<double>.generate(
        tagNames.length,
        (index) => TagWidthCache.measureTextWidth(
          tagNames[index],
          resolvedTagStyle,
          textDirection,
          textScaler,
        ),
        growable: false,
      );

      final countWidthCache = <int, double>{};
      double countChipWidthFor(int remaining) {
        return countWidthCache.putIfAbsent(
          remaining,
          () => measureChip('+$remaining', resolvedCountStyle, countPadding),
        );
      }

      bestCount = 0;
      double runningTextWidth = 0.0;
      bestTagsWidth = 0.0;
      for (var i = 0; i < tagNames.length; i++) {
        runningTextWidth += tagNameWidths[i];
        if (i > 0) {
          runningTextWidth += separatorWidth;
        }

        final visibleCount = i + 1;
        final remaining = tagNames.length - visibleCount;
        final tagsWidth = runningTextWidth + chipPadding.horizontal + 2.0;

        double trailingCountWidth = 0.0;
        if (remaining > 0) {
          trailingCountWidth = countChipWidthFor(remaining) + gap;
        }

        if (tagsWidth + trailingCountWidth <= maxWidth) {
          bestCount = visibleCount;
          bestTagsWidth = tagsWidth;
        } else {
          break;
        }
      }

      // countFits must be computed here while countChipWidthFor is in scope.
      final remainingForFit = tagNames.length - bestCount;
      countFits = remainingForFit > 0
          ? (countChipWidthFor(remainingForFit) +
                    (bestTagsWidth > 0 ? bestTagsWidth + gap : 0.0) <=
                maxWidth)
          : false;

      // Persist results — non-reactive cache fields, no setState needed.
      _lastTagCacheKey = tagKey;
      _cachedTagBestCount = bestCount;
      _cachedTagBestWidth = bestTagsWidth;
      _cachedTagCountFits = countFits;
    }

    final showTagsText = bestCount > 0;
    final remainingCount = tagNames.length - bestCount;

    final displayTags = showTagsText
        ? tagNames.take(bestCount).join(' · ')
        : '';
    final displayCount = remainingCount > 0 ? '+$remainingCount' : '';
    final representativeTag = showTagsText
        ? widget.game.tags.first
        : widget.game.tags.first;

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showTagsText)
            Flexible(
              fit: FlexFit.loose,
              child: _buildTagChip(
                theme,
                displayTags,
                padding: chipPadding,
                overrideBackground: representativeTag.isSteamTag
                    ? theme.accent
                    : representativeTag.color,
                overrideTextColor: theme.primaryButtonText,
              ),
            ),

          if (remainingCount > 0 && countFits) ...[
            if (showTagsText) const SizedBox(width: gap),
            _buildTagChip(
              theme,
              displayCount,
              padding: countPadding,
              weight: FontWeight.w600,
              overrideBackground: representativeTag.isSteamTag
                  ? theme.accent.withValues(alpha: 0.92)
                  : representativeTag.color.withValues(alpha: 0.92),
              overrideTextColor: theme.primaryButtonText,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnimatedTagsRow(
    BuildContext context,
    AppThemeData theme, {
    required bool isVisible,
    double? fixedMaxWidth,
  }) {
    // When the tag row is hidden we avoid constructing the real widget at all
    // because building it triggers expensive width measurement logic. The
    // animation widgets still need a child to size against, so use a simple
    // shrink widget instead.  This dramatically cuts down on layout/paint
    // churn during window resize when tags are not visible.
    final Widget childWidget = isVisible
        ? _buildTagsRow(context, theme, fixedMaxWidth: fixedMaxWidth)
        : const SizedBox.shrink();

    return ClipRect(
      child: AnimatedSize(
        duration: kFastAnimation,
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomLeft,
        child: Align(
          alignment: Alignment.bottomLeft,
          heightFactor: isVisible ? 1.0 : 0.0,
          child: IgnorePointer(
            ignoring: !isVisible,
            child: AnimatedOpacity(
              duration: kVeryFastAnimation,
              curve: Curves.easeOutCubic,
              opacity: isVisible ? 1.0 : 0.0,
              child: childWidget,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedTopToBottomReveal({
    required bool isVisible,
    required Widget child,
  }) {
    return ClipRect(
      child: AnimatedSize(
        duration: kFastAnimation,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: isVisible ? 1.0 : 0.0,
          child: IgnorePointer(
            ignoring: !isVisible,
            child: AnimatedOpacity(
              duration: kVeryFastAnimation,
              curve: Curves.easeOutCubic,
              opacity: isVisible ? 1.0 : 0.0,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTagChip(
    AppThemeData theme,
    String text, {
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    FontWeight weight = FontWeight.w600,
    Color? overrideBackground,
    Color? overrideTextColor,
  }) {
    // If an explicit background is provided (representative tag color),
    // prefer it — but slightly boost very low-saturation tag colors so
    // they remain visible on busy covers.
    Color chipColor;
    if (overrideBackground != null) {
      chipColor = overrideBackground.withValues(alpha: 0.95);
      final hOverride = HSLColor.fromColor(chipColor);
      if (hOverride.saturation < 0.06) {
        chipColor = _applySaturation(chipColor, 1.2).withValues(alpha: 0.95);
      }
    } else {
      // Use pre-computed theme value — HSL/saturation check was done once when
      // the theme was built rather than on every widget build call.
      chipColor = theme.tagChipDefaultColor;
    }

    // Ensure readable label color on top of chip
    final chipTextColor =
        overrideTextColor ??
        (chipColor.computeLuminance() > 0.5 ? Colors.black : Colors.white);

    return Container(
      padding: padding,
      // Use an effectively infinite radius so the chip becomes a true
      // pill/stadium regardless of text size or font metrics.
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(12),
        // subtle border to separate chip from busy cover images
        border: Border.all(color: theme.border.withValues(alpha: 0.12)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: chipTextColor,
          fontSize: 11, // increased to match measurement style above
          fontWeight: weight,
        ),
      ),
    );
  }
}

class _UsedPatternPainter extends CustomPainter {
  const _UsedPatternPainter({
    required this.textColor,
    required this.angleDegrees,
    required this.patternSize,
  });

  static const String _label = 'USED';
  static final Map<int, TextPainter> _textPainterCache = <int, TextPainter>{};
  static const int _maxCacheEntries = 16;

  final Color textColor;
  final double angleDegrees;
  final Size patternSize;

  TextPainter _resolveTextPainter(double fontSize) {
    // Quantize to keep cache small and stable during window resize drags.
    final quantized = (fontSize * 2).round() / 2;
    final cacheKey = Object.hash(textColor.toARGB32(), quantized);
    final cached = _textPainterCache[cacheKey];
    if (cached != null) return cached;

    final painter = TextPainter(
      text: TextSpan(
        text: _label,
        style: TextStyle(
          color: textColor,
          fontSize: quantized,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    if (_textPainterCache.length >= _maxCacheEntries) {
      _textPainterCache.remove(_textPainterCache.keys.first);
    }
    _textPainterCache[cacheKey] = painter;
    return painter;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Clip to visible bounds, but generate pattern from a fixed virtual size
    // so watermark stays visually static while parent layouts resize.
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final shortestSide = math.min(patternSize.width, patternSize.height);
    final fontSize = (shortestSide * 0.10).clamp(18.0, 28.0);
    final textPainter = _resolveTextPainter(fontSize);

    final textWidth = textPainter.width;
    final textHeight = textPainter.height;
    final xStep = textWidth + fontSize * 1.3;
    final yStep = textHeight + fontSize * 1.3;

    final diagonal = math.sqrt(
      patternSize.width * patternSize.width +
          patternSize.height * patternSize.height,
    );
    final angle = angleDegrees * (math.pi / 180);

    // Stable top-left anchor to avoid perceived drift during resize.
    canvas.translate(patternSize.width / 2, patternSize.height / 2);
    canvas.rotate(angle);
    canvas.translate(-diagonal / 2, -diagonal / 2);

    for (double rowY = -yStep; rowY < diagonal + yStep; rowY += yStep) {
      final rowOffset = ((rowY / yStep).floor().isEven) ? 0.0 : xStep * 0.5;
      for (double colX = -xStep; colX < diagonal + xStep; colX += xStep) {
        textPainter.paint(canvas, Offset(colX + rowOffset, rowY));
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _UsedPatternPainter oldDelegate) {
    return oldDelegate.textColor != textColor ||
        oldDelegate.angleDegrees != angleDegrees ||
        oldDelegate.patternSize != patternSize;
  }
}
