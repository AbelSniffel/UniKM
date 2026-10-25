/// Home page - game library display
/// Matches the original Python HomePage with grid/list views
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/shortcuts/app_shortcuts.dart';
import '../dialogs/copy_actions_dialog.dart';
import '../dialogs/delete_games_dialog.dart';
import '../../providers/app_providers.dart';
import '../widgets/notification_system.dart';
import 'home_sections/game_library_view.dart';
import 'home_sections/home_header.dart';

export '../dialogs/delete_games_dialog.dart' show showDeleteGamesDialog;

/// Home page with game library
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key, this.isVeryNarrowLayout = false});

  final bool isVeryNarrowLayout;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _gameListFocusNode = FocusNode();
  late final ScrollController _scrollController;

  @override
  void dispose() {
    if (_scrollController.hasClients) {
      ref
          .read(gameLibraryScrollOffsetProvider.notifier)
          .set(_scrollController.offset);
    }
    _scrollController.removeListener(_saveScrollOffset);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _gameListFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _syncSearchController(ref.read(gamesProvider).searchQuery);
    _scrollController = ScrollController(
      initialScrollOffset: ref.read(gameLibraryScrollOffsetProvider),
    )..addListener(_saveScrollOffset);
  }

  void _saveScrollOffset() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    if (!offset.isFinite) return;

    if ((ref.read(gameLibraryScrollOffsetProvider) - offset).abs() >= 1.0) {
      ref.read(gameLibraryScrollOffsetProvider.notifier).set(offset);
    }
  }

  void _syncSearchController(String searchQuery) {
    if (_searchController.text == searchQuery) return;
    _searchController.value = TextEditingValue(
      text: searchQuery,
      selection: TextSelection.collapsed(offset: searchQuery.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(
      gamesProvider.select((s) => s.searchQuery),
      (_, next) => _syncSearchController(next),
    );

    return Shortcuts(
      shortcuts: AppShortcuts.global,
      child: Actions(
        actions: {
          DeselectAllGamesIntent: CallbackAction<DeselectAllGamesIntent>(
            onInvoke: (_) {
              if (_searchFocusNode.hasFocus) {
                if (_searchController.text.isNotEmpty) {
                  _searchController.clear();
                  ref.read(gamesProvider.notifier).setSearchQuery('');
                  return null;
                }
                _searchFocusNode.unfocus();
              }
              ref.read(gamesProvider.notifier).clearSelection();
              return null;
            },
          ),
        },
        child: Column(
          children: [
            // Header with search and filters (internal state handling)
            HomeHeader(
              searchController: _searchController,
              searchFocusNode: _searchFocusNode,
              isVeryNarrowLayout: widget.isVeryNarrowLayout,
            ),

            // Game grid/list (internal state handling)
            Expanded(
              child: GameLibraryView(
                scrollController: _scrollController,
                gameListFocusNode: _gameListFocusNode,
                onSelectAll: _handleSelectAll,
                onDeleteSelection: () => _handleDeleteSelection(context),
                onCopySelection: () => _handleCopySelection(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleSelectAll() {
    if (_searchFocusNode.hasFocus) return;
    ref.read(gamesProvider.notifier).selectAll();
  }

  Future<void> _handleCopySelection(BuildContext context) async {
    if (_searchFocusNode.hasFocus) return;
    final gamesState = ref.read(gamesProvider);
    final selectedIds = gamesState.selectedGameIds;
    if (selectedIds.isEmpty) return;
    await showCopyActionsDialog(context, [
      for (final game in gamesState.games)
        if (selectedIds.contains(game.id)) game,
    ]);
  }

  Future<void> _handleDeleteSelection(BuildContext context) async {
    if (_searchFocusNode.hasFocus) return;

    final selectedIds = ref.read(gamesProvider).selectedGameIds;
    if (selectedIds.isEmpty) return;

    final theme = ref.read(themeProvider);
    final confirmed = await showDeleteGamesDialog(
      context,
      theme,
      selectedIds.length,
      gameTitle: selectedIds.length == 1
          ? ref
                .read(gamesProvider)
                .games
                .where((game) => selectedIds.contains(game.id))
                .firstOrNull
                ?.title
          : null,
    );

    if (confirmed) {
      await ref.read(gamesProvider.notifier).deleteGames(selectedIds.toList());
      NotificationManager.instance.success(
        'Deleted ${selectedIds.length} game${selectedIds.length > 1 ? 's' : ''}',
      );
    }
  }
}
