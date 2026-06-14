/// Game library grid/list view with loading, error, and empty states
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/shortcuts/app_shortcuts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/game.dart';
import '../../../providers/app_providers.dart';
import '../../dialogs/import_export_dialog.dart';
import '../../widgets/app_progress_indicator.dart';
import '../../widgets/game_card.dart';
import '../../widgets/selection_overlay.dart' as app_selection_overlay;
import 'animated_game_card.dart';
import 'selection_ribbon.dart';

class GameLibraryView extends ConsumerWidget {
  const GameLibraryView({
    super.key,
    required this.scrollController,
    required this.playEntryAnimations,
    required this.gameListFocusNode,
    this.isVeryNarrowLayout = false,
    required this.onSelectAll,
    required this.onDeleteSelection,
    required this.onCopySelection,
  });

  final ScrollController scrollController;
  final bool playEntryAnimations;
  final FocusNode gameListFocusNode;
  final bool isVeryNarrowLayout;
  final VoidCallback onSelectAll;
  final Future<void> Function() onDeleteSelection;
  final Future<void> Function() onCopySelection;

  static const int _maxAnimatedEntries = 120;
  static const int _maxAnimatedStaggerIndex = 14;
  static const int _progressiveRevealInitialCount = 36;
  static const int _progressiveRevealBatchSize = 24;
  static const Duration _progressiveRevealTick = Duration(milliseconds: 50);
  static const double _gridCacheExtent = kGridCardHeight + kGridCardSpacing;
  static bool shouldUseProgressiveReveal(int totalItems) => true;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    // Use select to watch specific parts of state relevant to the list
    final isLoading = ref.watch(gamesProvider.select((s) => s.isLoading));
    final error = ref.watch(gamesProvider.select((s) => s.error));
    // Watch filteredGames explicitly. Since it's a stable list (same reference) when selection changes, this won't rebuild.
    final filteredGames = ref.watch(
      gamesProvider.select((s) => s.filteredGames),
    );
    final viewMode = ref.watch(viewModeProvider);

    if (isLoading) return _buildLoadingState(theme);
    if (error != null) return _buildErrorState(ref, theme, error);
    if (filteredGames.isEmpty) {
      final hasActiveFilters = ref.watch(
        gamesProvider.select(
          (s) =>
              s.searchQuery.isNotEmpty ||
              s.tagFilters.isNotEmpty ||
              s.showDeadlineOnly ||
              s.showDlcOnly ||
              s.showUsedOnly ||
              s.showNoPicturesOnly ||
              s.showNoTagsOnly,
        ),
      );

      return _buildEmptyState(
        context,
        ref,
        theme,
        filteredGames.isEmpty,
        hasActiveFilters,
      );
    }

    // List is ready
    return FocusableActionDetector(
      focusNode: gameListFocusNode,
      shortcuts: AppShortcuts.gameList,
      actions: {
        SelectAllGamesIntent: CallbackAction<SelectAllGamesIntent>(
          onInvoke: (_) {
            onSelectAll();
            return null;
          },
        ),
        DeleteSelectionIntent: CallbackAction<DeleteSelectionIntent>(
          onInvoke: (_) async {
            await onDeleteSelection();
            return null;
          },
        ),
        CopySelectionIntent: CallbackAction<CopySelectionIntent>(
          onInvoke: (_) async {
            await onCopySelection();
            return null;
          },
        ),
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (!gameListFocusNode.hasFocus) {
            FocusScope.of(context).requestFocus(gameListFocusNode);
          }
        },
        child: _buildGameList(
          context,
          ref,
          theme,
          filteredGames,
          viewMode,
          scrollController,
          playEntryAnimations,
        ),
      ),
    );
  }

  Widget _buildLoadingState(AppThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppCircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Loading games...',
            style: TextStyle(color: theme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(WidgetRef ref, AppThemeData theme, String error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 64, color: theme.error),
          const SizedBox(height: 16),
          Text(
            'Error loading games',
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: kElementVSpacing),
          Text(
            error,
            style: TextStyle(color: theme.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => ref.read(gamesProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    WidgetRef ref,
    AppThemeData theme,
    bool isEmpty,
    bool hasFilters,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.hasBoundedHeight
            ? (constraints.maxHeight - 16).clamp(0.0, double.infinity).toDouble()
            : 0.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hasFilters ? Icons.filter_alt_off : Icons.videogame_asset_off,
                    size: 80,
                    color: theme.textHint,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    hasFilters ? 'No games match your filters' : 'No games yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: kElementVSpacing),
                  Text(
                    hasFilters
                        ? 'Try adjusting your filters or search query'
                        : 'Add your first game to get started',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.textSecondary),
                  ),
                  if (hasFilters) ...[
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () {
                        ref.read(gamesProvider.notifier).setSearchQuery('');
                        ref.read(gamesProvider.notifier).clearAllFilters();
                      },
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Clear Filters'),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () => ref
                          .read(currentNavProvider.notifier)
                          .setNav(NavItem.addGames),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Game'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () => showImportDialog(context),
                      icon: const Icon(Icons.download),
                      label: const Text('Import Games'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGameList(
    BuildContext context,
    WidgetRef ref,
    AppThemeData theme,
    List<Game> games,
    GameListViewMode viewMode,
    ScrollController scrollController,
    bool playEntryAnimations,
  ) {
    final slimList = ref.watch(
      gameCardSettingsProvider.select((s) => s.slimListView),
    );
    final listSpacing = slimList ? kSlimListCardSpacing : kListCardSpacing;
    final listItemExtent = (slimList ? kSlimListCardHeight : kListCardHeight) + listSpacing;
    final listCacheExtent = listItemExtent * 2;

    final useProgressiveReveal = GameLibraryView.shouldUseProgressiveReveal(
      games.length,
    );
    final shouldAnimateEntries =
        playEntryAnimations &&
        games.isNotEmpty &&
        games.length <= _maxAnimatedEntries;

    // NOTE: selectedGameIds is intentionally NOT watched here.
    // Selection changes are handled by _GameListWithSelectionOverlay, which
    // wraps only the overlay — so the grid/list itself is never rebuilt on
    // selection changes.

    final persistedScrollOffset = ref.read(gameLibraryScrollOffsetProvider);
    final scrollOffset =
        scrollController.hasClients && scrollController.offset.isFinite
        ? scrollController.offset
        : persistedScrollOffset;
    final viewportHeight =
        scrollController.hasClients &&
            scrollController.position.viewportDimension.isFinite &&
            scrollController.position.viewportDimension > 0
        ? scrollController.position.viewportDimension
        : MediaQuery.sizeOf(context).height;

    if (viewMode == GameListViewMode.grid) {
      return _GameListWithSelectionRibbon(
        isVeryNarrowLayout: isVeryNarrowLayout,
        child: _wrapDragSelection(
          ref,
          theme,
          games,
          viewMode,
          scrollController,
          listItemExtent,
          _ProgressiveReveal(
            totalCount: games.length,
            initialVisibleHint: _estimatedVisibleHint(
              context,
              viewMode: viewMode,
              scrollOffset: scrollOffset,
              viewportHeight: viewportHeight,
            ),
            builder: (visibleCount) => GridView.builder(
              key: const PageStorageKey('game-library-scroll'),
              controller: scrollController,
              cacheExtent: _gridCacheExtent,
              padding: const EdgeInsets.all(12),
              clipBehavior: Clip.hardEdge,
              addAutomaticKeepAlives: false,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: kGridCardWidth + kGridCardSpacing,
                mainAxisExtent: kGridCardHeight + kGridCardSpacing,
                crossAxisSpacing: kGridCardSpacing,
                mainAxisSpacing: kGridCardSpacing,
              ),
              itemCount: visibleCount,
              itemBuilder: (context, index) {
                final game = games[index];
                final card = GameCard(key: ValueKey(game.id), game: game);

                final shouldAnimateCard =
                    shouldAnimateEntries || useProgressiveReveal;
                final cappedIndex = index > _maxAnimatedStaggerIndex
                    ? _maxAnimatedStaggerIndex
                    : index;
                final progressiveStagger = index % 10;
                final staggerIndex = useProgressiveReveal
                    ? progressiveStagger
                    : cappedIndex;

                return shouldAnimateCard
                    ? AnimatedGameCard(
                        key: ValueKey('anim_${game.id}'),
                        delay: Duration(milliseconds: staggerIndex * 16),
                        child: card,
                      )
                    : card;
              },
            ),
          ),
        ),
      );
    }

    return _GameListWithSelectionRibbon(
      isVeryNarrowLayout: isVeryNarrowLayout,
      child: _wrapDragSelection(
        ref,
        theme,
        games,
        viewMode,
        scrollController,
        listItemExtent,
        _ProgressiveReveal(
          totalCount: games.length,
          initialVisibleHint: _estimatedVisibleHint(
            context,
            viewMode: viewMode,
            scrollOffset: scrollOffset,
            viewportHeight: viewportHeight,
            listItemExtent: listItemExtent,
          ),
          builder: (visibleCount) => ListView.builder(
            key: const PageStorageKey('game-library-scroll'),
            controller: scrollController,
            cacheExtent: listCacheExtent,
            itemExtent: listItemExtent,
            padding: const EdgeInsets.all(12),
            clipBehavior: Clip.hardEdge,
            addAutomaticKeepAlives: false,
            itemCount: visibleCount,
            itemBuilder: (context, index) {
              final game = games[index];
              final card = GameCard(key: ValueKey(game.id), game: game);

              final shouldAnimateCard =
                  shouldAnimateEntries || useProgressiveReveal;
              final cappedIndex = index > _maxAnimatedStaggerIndex
                  ? _maxAnimatedStaggerIndex
                  : index;
              final progressiveStagger = index % 10;
              final staggerIndex = useProgressiveReveal
                  ? progressiveStagger
                  : cappedIndex;

              if (slimList) {
                return shouldAnimateCard
                    ? AnimatedGameCard(
                        key: ValueKey('anim_${game.id}'),
                        delay: Duration(milliseconds: staggerIndex * 12),
                        slideX: false,
                        child: card,
                      )
                    : card;
              }

              return Padding(
                padding: EdgeInsets.only(bottom: listSpacing),
                child: shouldAnimateCard
                    ? AnimatedGameCard(
                        key: ValueKey('anim_${game.id}'),
                        delay: Duration(milliseconds: staggerIndex * 12),
                        slideX: false,
                        child: card,
                      )
                    : card,
              );
            },
          ),
        ),
      ),
    );
  }

  int _estimatedVisibleHint(
    BuildContext context, {
    required GameListViewMode viewMode,
    required double scrollOffset,
    required double viewportHeight,
    double? listItemExtent,
  }) {
    if (scrollOffset <= 0 || viewportHeight <= 0) {
      return GameLibraryView._progressiveRevealInitialCount;
    }

    if (viewMode == GameListViewMode.list) {
      final rowExtent = listItemExtent ?? (kListCardHeight + kListCardSpacing);
      final firstVisible = (scrollOffset / rowExtent).floor();
      final viewportRows = (viewportHeight / rowExtent).ceil();
      final lookAheadRows = viewportRows * 2;
      final hint = firstVisible + lookAheadRows + 24;
      return hint < GameLibraryView._progressiveRevealInitialCount
          ? GameLibraryView._progressiveRevealInitialCount
          : hint;
    }

    final rowExtent = kGridCardHeight + kGridCardSpacing;
    final firstVisibleRow = (scrollOffset / rowExtent).floor();
    final viewportRows = (viewportHeight / rowExtent).ceil();
    final contentWidth = (MediaQuery.sizeOf(context).width - 32).clamp(
      1.0,
      double.infinity,
    );
    final columns = (contentWidth / (kGridCardWidth + kGridCardSpacing))
        .ceil()
        .clamp(1, 9999)
        .toInt();
    final hintRows = firstVisibleRow + (viewportRows * 2) + 3;
    final hint = hintRows * columns;
    return hint < GameLibraryView._progressiveRevealInitialCount
        ? GameLibraryView._progressiveRevealInitialCount
        : hint;
  }

  Widget _wrapDragSelection(
    WidgetRef ref,
    AppThemeData theme,
    List<Game> games,
    GameListViewMode viewMode,
    ScrollController scrollController,
    double listItemExtent,
    Widget child,
  ) {
    return _GameLibraryDragSelectionLayer(
      theme: theme,
      games: games,
      viewMode: viewMode,
      scrollController: scrollController,
      listItemExtent: listItemExtent,
      child: child,
    );
  }
}

class _GameLibraryDragSelectionLayer extends ConsumerStatefulWidget {
  const _GameLibraryDragSelectionLayer({
    required this.theme,
    required this.games,
    required this.viewMode,
    required this.scrollController,
    required this.listItemExtent,
    required this.child,
  });

  final AppThemeData theme;
  final List<Game> games;
  final GameListViewMode viewMode;
  final ScrollController scrollController;
  final double listItemExtent;
  final Widget child;

  @override
  ConsumerState<_GameLibraryDragSelectionLayer> createState() =>
      _GameLibraryDragSelectionLayerState();
}

class _GameLibraryDragSelectionLayerState
    extends ConsumerState<_GameLibraryDragSelectionLayer> {
  static const double _dragStartSlop = 6.0;
  static const double _contentPadding = 12.0;
  static const Duration _autoScrollTick = Duration(milliseconds: 16);

  // Marquee tuning knobs.
  static const double _autoScrollEdgeExtent = 72.0;
  static const double _autoScrollMinStep = 4.0;
  static const double _autoScrollMaxStep = 18.0;
  static const app_selection_overlay.SelectionOverlayStyle _marqueeStyle =
      app_selection_overlay.kDefaultSelectionOverlayStyle;

  int? _activePointer;
  Offset? _pointerDownGlobal;
  Offset? _marqueeStartContent;
  Offset? _marqueeCurrentLocal;
  bool _isShiftMarqueeActive = false;
  Set<int> _marqueeSelectedIds = const <int>{};
  Timer? _autoScrollTimer;
  double _autoScrollStep = 0.0;

  bool get _isShiftPressed {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  Offset? _toLocal(Offset globalPosition) {
    final box = _renderBox;
    if (box == null || !box.hasSize) {
      return null;
    }
    return box.globalToLocal(globalPosition);
  }

  double get _scrollOffset =>
      widget.scrollController.hasClients ? widget.scrollController.offset : 0.0;

  Offset _toContentOffset(Offset localOffset, {double? scrollOffset}) {
    return Offset(
      localOffset.dx,
      localOffset.dy + (scrollOffset ?? _scrollOffset),
    );
  }

  Offset _toViewportOffset(Offset contentOffset, {double? scrollOffset}) {
    return Offset(
      contentOffset.dx,
      contentOffset.dy - (scrollOffset ?? _scrollOffset),
    );
  }

  @override
  void dispose() {
    _stopAutoScroll();
    super.dispose();
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollStep = 0.0;
  }

  void _refreshMarqueeSelection(Offset currentLocal) {
    final startContent = _marqueeStartContent;
    if (startContent == null) {
      return;
    }

    final nextSelection = _computeMarqueeSelection(
      startContent,
      _toContentOffset(currentLocal),
    );
    ref.read(gamesProvider.notifier).setSelection(nextSelection);
    ref
        .read(lastSelectedGameIdProvider.notifier)
        .setLastSelectedGameId(
          nextSelection.isEmpty ? null : nextSelection.last,
        );

    setState(() {
      _isShiftMarqueeActive = true;
      _marqueeCurrentLocal = currentLocal;
      _marqueeSelectedIds = nextSelection.toSet();
    });
  }

  double _computeAutoScrollStep({
    required double pointerDy,
    required double viewportHeight,
  }) {
    if (viewportHeight <= 0) {
      return 0.0;
    }

    if (pointerDy < _autoScrollEdgeExtent) {
      final distance = pointerDy.clamp(0.0, _autoScrollEdgeExtent);
      final proximity = 1.0 - (distance / _autoScrollEdgeExtent);
      final eased = proximity * proximity;
      return -(_autoScrollMinStep +
          ((_autoScrollMaxStep - _autoScrollMinStep) * eased));
    }

    final bottomThreshold = viewportHeight - _autoScrollEdgeExtent;
    if (pointerDy > bottomThreshold) {
      final distanceFromBottom = (viewportHeight - pointerDy).clamp(
        0.0,
        _autoScrollEdgeExtent,
      );
      final proximity = 1.0 - (distanceFromBottom / _autoScrollEdgeExtent);
      final eased = proximity * proximity;
      return _autoScrollMinStep +
          ((_autoScrollMaxStep - _autoScrollMinStep) * eased);
    }

    return 0.0;
  }

  void _updateAutoScroll(Offset currentLocal) {
    final box = _renderBox;
    final controller = widget.scrollController;
    if (box == null || !box.hasSize || !controller.hasClients) {
      _stopAutoScroll();
      return;
    }

    final nextStep = _computeAutoScrollStep(
      pointerDy: currentLocal.dy,
      viewportHeight: box.size.height,
    );
    if (nextStep.abs() < 0.01) {
      _stopAutoScroll();
      return;
    }

    _autoScrollStep = nextStep;
    _autoScrollTimer ??= Timer.periodic(_autoScrollTick, (_) {
      if (!_isShiftPressed || !_isShiftMarqueeActive) {
        _stopAutoScroll();
        return;
      }

      final scrollController = widget.scrollController;
      final currentLocalPosition = _marqueeCurrentLocal;
      if (!scrollController.hasClients || currentLocalPosition == null) {
        _stopAutoScroll();
        return;
      }

      final position = scrollController.position;
      final currentOffset = scrollController.offset;
      final nextOffset = (currentOffset + _autoScrollStep).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((nextOffset - currentOffset).abs() < 0.01) {
        _stopAutoScroll();
        return;
      }

      scrollController.jumpTo(nextOffset);
      _refreshMarqueeSelection(currentLocalPosition);
    });
  }

  void _clearMarqueeTracking() {
    _activePointer = null;
    _pointerDownGlobal = null;
    _stopAutoScroll();
    if (_isShiftMarqueeActive ||
        _marqueeStartContent != null ||
        _marqueeCurrentLocal != null ||
        _marqueeSelectedIds.isNotEmpty) {
      setState(() {
        _isShiftMarqueeActive = false;
        _marqueeStartContent = null;
        _marqueeCurrentLocal = null;
        _marqueeSelectedIds = const <int>{};
      });
      return;
    }
    _isShiftMarqueeActive = false;
    _marqueeStartContent = null;
    _marqueeCurrentLocal = null;
    _marqueeSelectedIds = const <int>{};
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) {
      return;
    }
    if ((event.buttons & kPrimaryMouseButton) == 0 || !_isShiftPressed) {
      return;
    }

    _activePointer = event.pointer;
    _pointerDownGlobal = event.position;
    final startLocal = _toLocal(event.position);
    if (startLocal == null) {
      _clearMarqueeTracking();
      return;
    }

    _marqueeStartContent = _toContentOffset(startLocal);
    _marqueeCurrentLocal = startLocal;
    _isShiftMarqueeActive = false;
    _marqueeSelectedIds = const <int>{};
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.kind != PointerDeviceKind.mouse) {
      return;
    }
    if (event.pointer != _activePointer || !_isShiftPressed) {
      return;
    }
    if ((event.buttons & kPrimaryMouseButton) == 0) {
      return;
    }

    final downGlobal = _pointerDownGlobal;
    if (downGlobal == null || _marqueeStartContent == null) {
      return;
    }

    final currentLocal = _toLocal(event.position);
    if (currentLocal == null) {
      return;
    }

    final exceededSlop =
        (event.position - downGlobal).distance > _dragStartSlop;
    if (!exceededSlop && !_isShiftMarqueeActive) {
      return;
    }

    _refreshMarqueeSelection(currentLocal);
    _updateAutoScroll(currentLocal);
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      ref.read(dragSelectionProvider.notifier).stop();
    }
    if (event.pointer == _activePointer) {
      _clearMarqueeTracking();
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      ref.read(dragSelectionProvider.notifier).stop();
    }
    if (event.pointer == _activePointer) {
      _clearMarqueeTracking();
    }
  }

  List<int> _computeMarqueeSelection(Offset start, Offset current) {
    final box = _renderBox;
    if (box == null || !box.hasSize) {
      return const <int>[];
    }

    final rect = Rect.fromPoints(start, current);
    if (rect.width <= 0 && rect.height <= 0) {
      return const <int>[];
    }

    return switch (widget.viewMode) {
      GameListViewMode.list => _computeListSelection(rect, box.size.width),
      GameListViewMode.grid => _computeGridSelection(rect, box.size.width),
    };
  }

  List<int> _computeListSelection(Rect rect, double viewportWidth) {
    final rowWidth = viewportWidth - (_contentPadding * 2);

    final selectedIds = <int>[];
    for (var index = 0; index < widget.games.length; index++) {
      final top = _contentPadding + (index * widget.listItemExtent);
      final itemRect = Rect.fromLTWH(
        _contentPadding,
        top,
        rowWidth,
        widget.listItemExtent,
      );
      if (itemRect.overlaps(rect)) {
        selectedIds.add(widget.games[index].id);
      }
    }
    return selectedIds;
  }

  List<int> _computeGridSelection(Rect rect, double viewportWidth) {
    final availableWidth = (viewportWidth - (_contentPadding * 2)).clamp(
      1.0,
      double.infinity,
    );
    final columns =
        (availableWidth /
                ((kGridCardWidth + kGridCardSpacing) + kGridCardSpacing))
            .ceil()
            .clamp(1, 9999);
    final tileWidth =
        (availableWidth - ((columns - 1) * kGridCardSpacing)) / columns;
    final rowExtent = (kGridCardHeight + kGridCardSpacing) + kGridCardSpacing;

    final selectedIds = <int>[];
    for (var index = 0; index < widget.games.length; index++) {
      final row = index ~/ columns;
      final column = index % columns;
      final left = _contentPadding + (column * (tileWidth + kGridCardSpacing));
      final top = _contentPadding + (row * rowExtent);
      final itemRect = Rect.fromLTWH(left, top, tileWidth, rowExtent);
      if (itemRect.overlaps(rect)) {
        selectedIds.add(widget.games[index].id);
      }
    }
    return selectedIds;
  }

  @override
  Widget build(BuildContext context) {
    final marqueeStartLocal = _marqueeStartContent == null
        ? null
        : _toViewportOffset(_marqueeStartContent!);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_isShiftMarqueeActive &&
              marqueeStartLocal != null &&
              _marqueeCurrentLocal != null)
            IgnorePointer(
              child: app_selection_overlay.SelectionOverlay(
                startPosition: marqueeStartLocal,
                currentPosition: _marqueeCurrentLocal!,
                theme: widget.theme,
                selectedCount: _marqueeSelectedIds.length,
                style: _marqueeStyle,
              ),
            ),
        ],
      ),
    );
  }
}

/// Wraps the game grid/list with the selection ribbon.
///
/// This is extracted into its own [ConsumerStatefulWidget] so that selection
/// changes
/// ONLY rebuild the ribbon animation — not the underlying grid or list widget.
/// The grid/list is passed in as [child] and remains stable across selection
/// changes, which is the primary driver of resize-adjacent rebuild overhead.
class _GameListWithSelectionRibbon extends ConsumerStatefulWidget {
  const _GameListWithSelectionRibbon({
    required this.child,
    this.isVeryNarrowLayout = false,
  });

  final Widget child;
  final bool isVeryNarrowLayout;

  @override
  ConsumerState<_GameListWithSelectionRibbon> createState() =>
      _GameListWithSelectionRibbonState();
}

class _GameListWithSelectionRibbonState
    extends ConsumerState<_GameListWithSelectionRibbon>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  bool _hasSelection = false;
  late final AnimationController _ribbonController;
  late final Animation<double> _ribbonAnimation;
  ProviderSubscription<bool>? _hasSelectionSub;

  @override
  void initState() {
    super.initState();
    _ribbonController = AnimationController(
      vsync: this,
      duration: kFastAnimation,
    );
    _ribbonAnimation = CurvedAnimation(
      parent: _ribbonController,
      curve: Curves.easeInOutCubic,
    );

    // Sync immediately so the ribbon is pre-shown if games are already selected
    // (e.g. navigating back to this page with an active selection).
    _hasSelection = ref.read(
      gamesProvider.select((s) => s.selectedGameIds.isNotEmpty),
    );
    if (_hasSelection) _ribbonController.value = 1.0;

    _hasSelectionSub = ref.listenManual(
      gamesProvider.select((s) => s.selectedGameIds.isNotEmpty),
      (_, hasSelection) {
        setState(() => _hasSelection = hasSelection);
        if (hasSelection) {
          _ribbonController.forward();
        } else {
          ref.read(selectionMultiSelectModeProvider.notifier).setEnabled(false);
          _ribbonController.reverse().then((_) {
            if (mounted && _expanded) setState(() => _expanded = false);
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _hasSelectionSub?.close();
    _ribbonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showExpandedList = _hasSelection && _expanded;

    return Column(
      children: [
        Expanded(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              widget.child,
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: !showExpandedList,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    offset: showExpandedList
                        ? Offset.zero
                        : const Offset(0, 1.0),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      opacity: showExpandedList ? 1.0 : 0.0,
                      child: const SelectionRibbonExpandedPanel(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // SizeTransition + FadeTransition share one controller so the ribbon
        // content is always present during animation — no empty-container
        // artifact from swapping children mid-transition.
        ClipRect(
          child: SizeTransition(
            sizeFactor: _ribbonAnimation,
            axisAlignment: 1.0,
            child: FadeTransition(
              opacity: _ribbonAnimation,
              child: SelectionRibbon(
                isExpanded: _expanded,
                isVeryNarrowLayout: widget.isVeryNarrowLayout,
                onToggleExpand: () => setState(() => _expanded = !_expanded),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressiveReveal extends StatefulWidget {
  const _ProgressiveReveal({
    required this.totalCount,
    required this.initialVisibleHint,
    required this.builder,
  });

  final int totalCount;
  final int initialVisibleHint;
  final Widget Function(int visibleCount) builder;

  @override
  State<_ProgressiveReveal> createState() => _ProgressiveRevealState();
}

class _ProgressiveRevealState extends State<_ProgressiveReveal> {
  Timer? _timer;
  int _visibleCount = 0;

  @override
  void initState() {
    super.initState();
    _syncToTotal();
  }

  @override
  void didUpdateWidget(covariant _ProgressiveReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.totalCount != widget.totalCount) {
      _syncToTotal();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncToTotal() {
    _timer?.cancel();

    final total = widget.totalCount;
    if (total <= 0) {
      if (_visibleCount != 0) {
        setState(() => _visibleCount = 0);
      }
      return;
    }

    if (!GameLibraryView.shouldUseProgressiveReveal(total)) {
      if (_visibleCount != total) {
        setState(() => _visibleCount = total);
      }
      return;
    }

    final initial = total < GameLibraryView._progressiveRevealInitialCount
        ? total
        : GameLibraryView._progressiveRevealInitialCount;
    final hintedInitial = widget.initialVisibleHint < initial
        ? initial
        : widget.initialVisibleHint;
    final targetInitial = hintedInitial > total ? total : hintedInitial;

    if (_visibleCount > total) {
      setState(() => _visibleCount = total);
      return;
    }

    // Do not collapse visibleCount on transient rebuilds (such as navigation
    // switches or viewport reattachment), otherwise scroll can visually snap.
    if (_visibleCount < targetInitial) {
      setState(() => _visibleCount = targetInitial);
    }

    if (_visibleCount >= total) return;

    _timer = Timer.periodic(GameLibraryView._progressiveRevealTick, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final next = _visibleCount + GameLibraryView._progressiveRevealBatchSize;
      if (next >= total) {
        setState(() => _visibleCount = total);
        timer.cancel();
        return;
      }

      setState(() => _visibleCount = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final clamped = _visibleCount > widget.totalCount
        ? widget.totalCount
        : _visibleCount;
    return widget.builder(clamped);
  }
}
