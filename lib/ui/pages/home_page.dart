/// Home page - game library display
/// Matches the original Python HomePage with grid/list views
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/shortcuts/app_shortcuts.dart';
import '../../core/utils/game_clipboard.dart';
import '../../providers/app_providers.dart';
import '../widgets/notification_system.dart';
import '../widgets/dialog_helpers.dart';
import 'home_sections/game_library_view.dart';
import 'home_sections/home_header.dart';

/// Home page with game library
class HomePage extends ConsumerStatefulWidget {
  const HomePage({
    super.key,
    this.isVeryNarrowLayout = false,
  });

  final bool isVeryNarrowLayout;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _gameListFocusNode = FocusNode();
  late final ScrollController _scrollController;

  // Only play the entry animations on the initial build to avoid re-running
  // them on small state updates.
  bool _playEntryAnimations = false;

  @override
  void dispose() {
    if (_scrollController.hasClients) {
      ref
          .read(gameLibraryScrollOffsetProvider.notifier)
          .setOffset(_scrollController.offset);
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
    final initialSearchQuery = ref.read(gamesProvider).searchQuery;
    _syncSearchController(initialSearchQuery);
    final initialOffset = ref.read(gameLibraryScrollOffsetProvider);
    _playEntryAnimations = !ref.read(homePageEntryAnimationsPlayedProvider);
    _scrollController = ScrollController(
      initialScrollOffset: initialOffset,
      keepScrollOffset: true,
    );
    _scrollController.addListener(_saveScrollOffset);

    if (_playEntryAnimations) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(homePageEntryAnimationsPlayedProvider.notifier).markPlayed();
        setState(() => _playEntryAnimations = false);
      });
    }
  }

  void _saveScrollOffset() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    if (!offset.isFinite) return;

    final notifier = ref.read(gameLibraryScrollOffsetProvider.notifier);
    final savedOffset = ref.read(gameLibraryScrollOffsetProvider);
    if ((savedOffset - offset).abs() >= 1.0) {
      notifier.setOffset(offset);
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
                playEntryAnimations: _playEntryAnimations,
                gameListFocusNode: _gameListFocusNode,
                isVeryNarrowLayout: widget.isVeryNarrowLayout,
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
    await _copySelectedGames(context);
  }

  Future<void> _handleDeleteSelection(BuildContext context) async {
    if (_searchFocusNode.hasFocus) return;

    final selectedIds = ref.read(gamesProvider).selectedGameIds;
    if (selectedIds.isEmpty) return;

    final theme = ref.read(themeProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ThemedAlertDialog(
        theme: theme,

        title: DialogHeader(
          icon: Icons.delete_forever,
          iconColor: theme.error,
          title: 'Delete ${selectedIds.length} game${selectedIds.length > 1 ? "s" : ""}?',
          theme: theme,
        ),
        content: Text(
          'This action cannot be undone.',
          style: TextStyle(color: theme.textSecondary),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: theme.error),
            child: Text('Delete', style: TextStyle(color: theme.textPrimary)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(gamesProvider.notifier).deleteGames(selectedIds.toList());
      NotificationManager.instance.success(
        'Deleted ${selectedIds.length} game${selectedIds.length > 1 ? 's' : ''}',
      );
    }
  }

  Future<void> _copySelectedGames(BuildContext context) async {
    final selectedIds = ref.read(gamesProvider).selectedGameIds;
    if (selectedIds.isEmpty) return;

    final gamesState = ref.read(gamesProvider);
    final selectedGames = gamesState.games
        .where((g) => selectedIds.contains(g.id))
        .toList();
    final hasSteamKeys = selectedGames.any(
      (g) => g.platform == 'Steam' && g.gameKey.isNotEmpty,
    );

    final choice = await _showCopyFormatDialog(
      context: context,
      count: selectedGames.length,
      hasSteamKeys: hasSteamKeys,
    );
    if (!mounted || choice == null) return;

    switch (choice) {
      case 'copy_key':
        GameClipboard.copyKeysOnly(selectedGames);
        break;
      case 'copy_title_key':
        GameClipboard.copyTitleWithKey(selectedGames);
        break;
      case 'copy_discord':
        GameClipboard.copyDiscordSpoiler(selectedGames);
        break;
      case 'copy_steam_link':
        GameClipboard.copySteamLink(selectedGames, includeTitle: false);
        break;
      case 'copy_steam_link_title':
        GameClipboard.copySteamLink(selectedGames, includeTitle: true);
        break;
    }
  }

  Future<String?> _showCopyFormatDialog({
    required BuildContext context,
    required int count,
    required bool hasSteamKeys,
  }) {
    final theme = ref.read(themeProvider);

    return showDialog<String>(
      context: context,
      builder: (ctx) => ThemedAlertDialog(
        theme: theme,

        title: DialogHeader(
          icon: Icons.copy,
          title: 'Copy $count game${count == 1 ? "" : "s"}',
          theme: theme,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.copy, color: theme.textSecondary),
              title: Text(
                'Key Only',
                style: TextStyle(color: theme.textPrimary),
              ),
              onTap: () => Navigator.pop(ctx, 'copy_key'),
            ),
            ListTile(
              leading: const SizedBox(width: 24),
              title: Text(
                'Title + Key',
                style: TextStyle(color: theme.textPrimary),
              ),
              onTap: () => Navigator.pop(ctx, 'copy_title_key'),
            ),
            ListTile(
              leading: const SizedBox(width: 24),
              title: Text(
                'Discord Spoiler',
                style: TextStyle(color: theme.textPrimary),
              ),
              onTap: () => Navigator.pop(ctx, 'copy_discord'),
            ),
            if (hasSteamKeys) ...[
              const Divider(height: 8),
              ListTile(
                leading: const SizedBox(width: 24),
                title: Text(
                  'Link Only',
                  style: TextStyle(color: theme.textPrimary),
                ),
                onTap: () => Navigator.pop(ctx, 'copy_steam_link'),
              ),
              ListTile(
                leading: const SizedBox(width: 24),
                title: Text(
                  'Title + Link',
                  style: TextStyle(color: theme.textPrimary),
                ),
                onTap: () => Navigator.pop(ctx, 'copy_steam_link_title'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
