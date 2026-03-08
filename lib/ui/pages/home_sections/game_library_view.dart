/// Game library grid/list view with loading, error, and empty states
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/shortcuts/app_shortcuts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/game.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/game_card.dart';
import 'animated_game_card.dart';
import 'selection_overlay.dart';

class GameLibraryView extends ConsumerWidget {
  const GameLibraryView({
    super.key,
    required this.scrollController,
    required this.playEntryAnimations,
    required this.gameListFocusNode,
    required this.onSelectAll,
    required this.onDeleteSelection,
    required this.onCopySelection,
  });

  final ScrollController scrollController;
  final bool playEntryAnimations;
  final FocusNode gameListFocusNode;
  final VoidCallback onSelectAll;
  final Future<void> Function() onDeleteSelection;
  final Future<void> Function() onCopySelection;

  static const int _maxAnimatedEntries = 120;
  static const int _maxAnimatedStaggerIndex = 14;
  static const int _progressiveRevealThreshold = 180;
  static const int _progressiveRevealInitialCount = 36;
  static const int _progressiveRevealBatchSize = 24;
  static const Duration _progressiveRevealTick = Duration(milliseconds: 50);

  static bool shouldUseProgressiveReveal(int totalItems) {
    return totalItems >= _progressiveRevealThreshold;
  }

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
              s.showNoPicturesOnly,
        ),
      );

      return _buildEmptyState(
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
          CircularProgressIndicator(color: theme.accent),
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
          const SizedBox(height: 8),
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
    WidgetRef ref,
    AppThemeData theme,
    bool isEmpty,
    bool hasFilters,
  ) {
    return Center(
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
                style: TextStyle(
                  color: theme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasFilters
                    ? 'Try adjusting your filters or search query'
                    : 'Add your first game to get started',
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
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => ref
                      .read(currentNavProvider.notifier)
                      .setNav(NavItem.addGames),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Game'),
                ),
              ],
            ],
          ),
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
    final useProgressiveReveal = GameLibraryView.shouldUseProgressiveReveal(
      games.length,
    );
    final shouldAnimateEntries = playEntryAnimations &&
        games.isNotEmpty &&
        games.length <= _maxAnimatedEntries;

    // NOTE: selectedGameIds is intentionally NOT watched here.
    // Selection changes are handled by _GameListWithSelectionOverlay, which
    // wraps only the overlay — so the grid/list itself is never rebuilt on
    // selection changes.

    final persistedScrollOffset = ref.read(gameLibraryScrollOffsetProvider);
    final scrollOffset = scrollController.hasClients && scrollController.offset.isFinite
      ? scrollController.offset
      : persistedScrollOffset;
    final viewportHeight = scrollController.hasClients &&
        scrollController.position.viewportDimension.isFinite &&
        scrollController.position.viewportDimension > 0
      ? scrollController.position.viewportDimension
      : MediaQuery.sizeOf(context).height;

    if (viewMode == GameListViewMode.grid) {
      return _GameListWithSelectionOverlay(
        theme: theme,
        child: _wrapDragSelection(
          ref,
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

    return _GameListWithSelectionOverlay(
      theme: theme,
      child: _wrapDragSelection(
        ref,
        _ProgressiveReveal(
          totalCount: games.length,
          initialVisibleHint: _estimatedVisibleHint(
            context,
            viewMode: viewMode,
            scrollOffset: scrollOffset,
            viewportHeight: viewportHeight,
          ),
          builder: (visibleCount) => ListView.builder(
            key: const PageStorageKey('game-library-scroll'),
            controller: scrollController,
            itemExtent: kListCardHeight + kListCardSpacing,
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

              return Padding(
                padding: const EdgeInsets.only(bottom: kListCardSpacing),
                child: shouldAnimateCard
                    ? AnimatedGameCard(
                        key: ValueKey('anim_${game.id}'),
                        delay: Duration(milliseconds: staggerIndex * 12),
                        slideX: true,
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
  }) {
    if (scrollOffset <= 0 || viewportHeight <= 0) {
      return GameLibraryView._progressiveRevealInitialCount;
    }

    if (viewMode == GameListViewMode.list) {
      final rowExtent = kListCardHeight + kListCardSpacing;
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
    final contentWidth =
        (MediaQuery.sizeOf(context).width - 32).clamp(1.0, double.infinity);
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

  Widget _wrapDragSelection(WidgetRef ref, Widget child) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerUp: (event) {
        if (event.kind == PointerDeviceKind.mouse) {
          ref.read(dragSelectionProvider.notifier).stop();
        }
      },
      onPointerCancel: (event) {
        if (event.kind == PointerDeviceKind.mouse) {
          ref.read(dragSelectionProvider.notifier).stop();
        }
      },
      child: child,
    );
  }
}

/// Wraps the game grid/list with the selection action bar overlay.
///
/// This is extracted into its own [ConsumerWidget] so that selection changes
/// ONLY rebuild the overlay animation — not the underlying grid or list widget.
/// The grid/list is passed in as [child] and remains stable across selection
/// changes, which is the primary driver of resize-adjacent rebuild overhead.
class _GameListWithSelectionOverlay extends ConsumerWidget {
  const _GameListWithSelectionOverlay({
    required this.child,
    required this.theme,
  });

  final Widget child;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedGameIds = ref.watch(
      gamesProvider.select((s) => s.selectedGameIds),
    );
    final hasSelection = selectedGameIds.isNotEmpty;

    return Stack(
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: !hasSelection,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              offset: hasSelection ? Offset.zero : const Offset(0, 1.0),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                opacity: hasSelection ? 1 : 0,
                child: Builder(
                  builder: (ctx) =>
                      buildSelectionOverlay(ctx, ref, theme, selectedGameIds),
                ),
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
