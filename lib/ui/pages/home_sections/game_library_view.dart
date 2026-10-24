/// Game library grid/list view with loading, error, and empty states
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/shortcuts/app_shortcuts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../dialogs/import_export_dialog.dart';
import '../../widgets/app_progress_indicator.dart';
import '../../widgets/game_card.dart';
import '../../widgets/selection_overlay.dart' as app_selection_overlay;
import 'animated_game_card.dart';

class GameLibraryView extends ConsumerStatefulWidget {
  const GameLibraryView({
    super.key,
    required this.scrollController,
    this.animateEntries = false,
    required this.gameListFocusNode,
    required this.onSelectAll,
    required this.onDeleteSelection,
    required this.onCopySelection,
  });

  final ScrollController scrollController;
  final bool animateEntries;
  final FocusNode gameListFocusNode;
  final VoidCallback onSelectAll;
  final Future<void> Function() onDeleteSelection;
  final Future<void> Function() onCopySelection;

  @override
  ConsumerState<GameLibraryView> createState() => _GameLibraryViewState();
}

class _GameLibraryViewState extends ConsumerState<GameLibraryView> {
  var _revealCoordinator = GameCardRevealCoordinator();
  Object? _database;
  static const double _gridCacheExtent = kGridCardHeight + kGridCardSpacing;

  @override
  Widget build(BuildContext context) {
    final database = ref.watch(databaseProvider);
    if (!identical(database, _database)) {
      _database = database;
      _revealCoordinator = GameCardRevealCoordinator();
    }
    final theme = ref.watch(themeProvider);
    // Use select to watch specific parts of state relevant to the list
    final isLoading = ref.watch(gamesProvider.select((s) => s.isLoading));
    final error = ref.watch(gamesProvider.select((s) => s.error));
    // Metadata changes are observed by each card without rebuilding the list.
    final gameIds = ref.watch(filteredGameIdsProvider);
    final viewMode = ref.watch(viewModeProvider);
    final slimList = ref.watch(
      gameCardSettingsProvider.select((s) => s.slimListView),
    );

    if (isLoading) return _buildLoadingState(theme);
    if (error != null) return _buildErrorState(ref, theme, error);
    if (gameIds.isEmpty) {
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
        gameIds.isEmpty,
        hasActiveFilters,
      );
    }

    // List is ready
    return FocusableActionDetector(
      focusNode: widget.gameListFocusNode,
      shortcuts: AppShortcuts.gameList,
      actions: {
        SelectAllGamesIntent: CallbackAction<SelectAllGamesIntent>(
          onInvoke: (_) {
            widget.onSelectAll();
            return null;
          },
        ),
        DeleteSelectionIntent: CallbackAction<DeleteSelectionIntent>(
          onInvoke: (_) async {
            await widget.onDeleteSelection();
            return null;
          },
        ),
        CopySelectionIntent: CallbackAction<CopySelectionIntent>(
          onInvoke: (_) async {
            await widget.onCopySelection();
            return null;
          },
        ),
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (!widget.gameListFocusNode.hasFocus) {
            FocusScope.of(context).requestFocus(widget.gameListFocusNode);
          }
        },
        child: _buildGameList(
          context,
          ref,
          theme,
          gameIds,
          viewMode,
          widget.scrollController,
          slimList,
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
          Icon(Icons.error, size: 64, color: theme.error),
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
            ? (constraints.maxHeight - 16)
                  .clamp(0.0, double.infinity)
                  .toDouble()
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
                    hasFilters
                        ? Icons.filter_alt_off
                        : Icons.videogame_asset_off,
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
                    ElevatedButton(
                      onPressed: () {
                        ref.read(gamesProvider.notifier).setSearchQuery('');
                        ref.read(gamesProvider.notifier).clearAllFilters();
                      },
                      child: const Text('Clear Filters'),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () => ref
                          .read(currentNavProvider.notifier)
                          .set(NavItem.addGames),
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
    List<int> gameIds,
    GameListViewMode viewMode,
    ScrollController scrollController,
    bool slimList,
  ) {
    final listSpacing = slimList ? kSlimListCardSpacing : kListCardSpacing;
    final listItemExtent =
        (slimList ? kSlimListCardHeight : kListCardHeight) + listSpacing;
    final listCacheExtent = listItemExtent * 2;

    // NOTE: selectedGameIds is intentionally NOT watched here.
    // The shell owns the selection ribbon, so selection changes do not
    // rebuild the grid/list.

    if (viewMode == GameListViewMode.grid) {
      return _wrapDragSelection(
        ref,
        theme,
        gameIds,
        viewMode,
        scrollController,
        listItemExtent,
        GridView.builder(
          scrollCacheExtent: ScrollCacheExtent.pixels(_gridCacheExtent),
          key: const PageStorageKey('game-library-scroll'),
          controller: scrollController,
          padding: const EdgeInsets.all(12),
          clipBehavior: Clip.hardEdge,
          addAutomaticKeepAlives: false,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: kGridCardWidth + kGridCardSpacing,
            mainAxisExtent: kGridCardHeight + kGridCardSpacing,
            crossAxisSpacing: kGridCardSpacing,
            mainAxisSpacing: kGridCardSpacing,
          ),
          itemCount: gameIds.length,
          itemBuilder: (context, index) {
            final gameId = gameIds[index];
            final card = _LibraryGameCard(
              key: ValueKey(gameId),
              gameId: gameId,
              viewMode: viewMode,
              dragSelectionHandledByParent: viewMode == GameListViewMode.list,
            );

            return _revealCard(gameId, card);
          },
        ),
      );
    }

    return _wrapDragSelection(
      ref,
      theme,
      gameIds,
      viewMode,
      scrollController,
      listItemExtent,
      ListView.builder(
        scrollCacheExtent: ScrollCacheExtent.pixels(listCacheExtent),
        key: const PageStorageKey('game-library-scroll'),
        controller: scrollController,
        itemExtent: listItemExtent,
        padding: const EdgeInsets.all(12),
        clipBehavior: Clip.hardEdge,
        addAutomaticKeepAlives: false,
        itemCount: gameIds.length,
        itemBuilder: (context, index) {
          final gameId = gameIds[index];
          final card = _LibraryGameCard(
            key: ValueKey(gameId),
            gameId: gameId,
            viewMode: viewMode,
            dragSelectionHandledByParent: viewMode == GameListViewMode.list,
          );

          final revealed = _revealCard(gameId, card);
          return slimList
              ? revealed
              : Padding(
                  padding: EdgeInsets.only(bottom: listSpacing),
                  child: revealed,
                );
        },
      ),
    );
  }

  Widget _revealCard(int gameId, Widget card) => widget.animateEntries
      ? AnimatedGameCard(
          key: ValueKey('anim_$gameId'),
          gameId: gameId,
          coordinator: _revealCoordinator,
          child: card,
        )
      : card;

  Widget _wrapDragSelection(
    WidgetRef ref,
    AppThemeData theme,
    List<int> gameIds,
    GameListViewMode viewMode,
    ScrollController scrollController,
    double listItemExtent,
    Widget child,
  ) {
    return _GameLibraryDragSelectionLayer(
      theme: theme,
      gameIds: gameIds,
      viewMode: viewMode,
      scrollController: scrollController,
      listItemExtent: listItemExtent,
      child: child,
    );
  }
}

class _LibraryGameCard extends ConsumerWidget {
  const _LibraryGameCard({
    super.key,
    required this.gameId,
    required this.viewMode,
    required this.dragSelectionHandledByParent,
  });

  final int gameId;
  final GameListViewMode viewMode;
  final bool dragSelectionHandledByParent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameByIdProvider(gameId));
    if (game == null) return const SizedBox.shrink();
    return GameCard(
      key: ValueKey(gameId),
      game: game,
      viewMode: viewMode,
      dragSelectionHandledByParent: dragSelectionHandledByParent,
    );
  }
}

class _GameLibraryDragSelectionLayer extends ConsumerStatefulWidget {
  const _GameLibraryDragSelectionLayer({
    required this.theme,
    required this.gameIds,
    required this.viewMode,
    required this.scrollController,
    required this.listItemExtent,
    required this.child,
  });

  final AppThemeData theme;
  final List<int> gameIds;
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

  int? _paintPointer;
  Offset? _paintDownGlobal;
  Offset? _paintPreviousContent;
  bool _painting = false;
  final Set<int> _paintVisited = {};

  bool get _isCtrlPressed {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
  }

  // Sweep every row between raw pointer samples. MouseRegion.onEnter only sees
  // the row under a sampled position and can miss rows during a fast drag.
  void _paintListSelection(Offset globalPosition) {
    final local = _toLocal(globalPosition);
    final previous = _paintPreviousContent;
    final box = _renderBox;
    if (local == null || previous == null || box == null || !box.hasSize) {
      return;
    }
    final current = _toContentOffset(local);
    _paintPreviousContent = current;
    final left = _contentPadding;
    final right = box.size.width - _contentPadding;
    // Clip the swept segment horizontally to the row bounds.
    var start = 0.0;
    var end = 1.0;
    final dx = current.dx - previous.dx;
    if (dx == 0) {
      if (current.dx < left || current.dx > right) return;
    } else {
      final a = (left - previous.dx) / dx;
      final b = (right - previous.dx) / dx;
      start = (a < b ? a : b).clamp(0.0, 1.0);
      end = (a > b ? a : b).clamp(0.0, 1.0);
      if ((a < b ? a : b) > 1 || (a > b ? a : b) < 0) return;
    }
    final dy = current.dy - previous.dy;
    final startY = previous.dy + dy * start;
    final endY = previous.dy + dy * end;
    final first =
        (((startY < endY ? startY : endY) - _contentPadding) /
                widget.listItemExtent)
            .floor()
            .clamp(0, widget.gameIds.length);
    final last =
        (((startY > endY ? startY : endY) - _contentPadding) /
                widget.listItemExtent)
            .floor()
            .clamp(-1, widget.gameIds.length - 1);
    final selection = Set<int>.from(ref.read(gamesProvider).selectedGameIds);
    int? lastVisited;
    for (var index = first; index <= last; index++) {
      final id = widget.gameIds[index];
      if (!_paintVisited.add(id)) continue;
      if (!selection.add(id)) selection.remove(id);
      lastVisited = id;
    }
    if (lastVisited != null) {
      ref.read(gamesProvider.notifier).setSelection(selection);
      ref.read(lastSelectedGameIdProvider.notifier).set(lastVisited);
    }
  }

  void _clearPaintTracking() {
    _paintPointer = null;
    _paintDownGlobal = null;
    _paintPreviousContent = null;
    _painting = false;
    _paintVisited.clear();
  }

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
        .set(nextSelection.isEmpty ? null : nextSelection.last);

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
    if ((event.buttons & kPrimaryMouseButton) == 0) return;
    if (widget.viewMode == GameListViewMode.list &&
        !_isShiftPressed &&
        (_isCtrlPressed || ref.read(selectionMultiSelectModeProvider))) {
      final local = _toLocal(event.position);
      if (local == null) return;
      _paintPointer = event.pointer;
      _paintDownGlobal = event.position;
      _paintPreviousContent = _toContentOffset(local);
      _paintVisited.clear();
      _painting = false;
      return;
    }
    if (!_isShiftPressed) return;

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
    if (event.pointer == _paintPointer &&
        (event.buttons & kPrimaryMouseButton) != 0) {
      if (!_painting &&
          (event.position - _paintDownGlobal!).distance > _dragStartSlop) {
        _painting = true;
        ref.read(dragSelectionProvider.notifier).start();
      }
      if (_painting) _paintListSelection(event.position);
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
    if (event.pointer == _paintPointer) {
      if (_painting) _paintListSelection(event.position);
      _clearPaintTracking();
    }
    if (event.kind == PointerDeviceKind.mouse) {
      ref.read(dragSelectionProvider.notifier).stop();
    }
    if (event.pointer == _activePointer) {
      _clearMarqueeTracking();
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer == _paintPointer) _clearPaintTracking();
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
    if (rect.right <= _contentPadding ||
        rect.left >= _contentPadding + rowWidth) {
      return const [];
    }
    final first = ((rect.top - _contentPadding) / widget.listItemExtent)
        .floor()
        .clamp(0, widget.gameIds.length);
    final end = ((rect.bottom - _contentPadding) / widget.listItemExtent)
        .ceil()
        .clamp(0, widget.gameIds.length);

    final selectedIds = <int>[];
    for (var index = first; index < end; index++) {
      final top = _contentPadding + (index * widget.listItemExtent);
      final itemRect = Rect.fromLTWH(
        _contentPadding,
        top,
        rowWidth,
        widget.listItemExtent,
      );
      if (itemRect.overlaps(rect)) {
        selectedIds.add(widget.gameIds[index]);
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
    final firstRow = ((rect.top - _contentPadding) / rowExtent).floor().clamp(
      0,
      widget.gameIds.length,
    );
    final endRow = ((rect.bottom - _contentPadding) / rowExtent).ceil().clamp(
      0,
      widget.gameIds.length,
    );
    final first = (firstRow * columns).clamp(0, widget.gameIds.length);
    final end = (endRow * columns).clamp(0, widget.gameIds.length);

    final selectedIds = <int>[];
    for (var index = first; index < end; index++) {
      final row = index ~/ columns;
      final column = index % columns;
      final left = _contentPadding + (column * (tileWidth + kGridCardSpacing));
      final top = _contentPadding + (row * rowExtent);
      final itemRect = Rect.fromLTWH(left, top, tileWidth, rowExtent);
      if (itemRect.overlaps(rect)) {
        selectedIds.add(widget.gameIds[index]);
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
              ),
            ),
        ],
      ),
    );
  }
}
