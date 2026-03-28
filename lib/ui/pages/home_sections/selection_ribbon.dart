/// Alternative game-selection UI: a horizontal ribbon anchored to the bottom
/// of the view when games are selected. The ribbon shows selection status,
/// compact action buttons, and a "Clear all" link at the right end. The
/// expanded list grows upward from the bar without shifting sibling widgets.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/game.dart';
import '../../../providers/app_providers.dart';
import '../../dialogs/copy_actions_dialog.dart';
import '../../dialogs/game_details_dialog.dart';
import '../../dialogs/steam_lookup_dialog.dart';
import '../../widgets/dialog_helpers.dart';
import '../../widgets/notification_system.dart';

// ---------------------------------------------------------------------------
// Provider selectors (file-private)

final _ribbonSelectedCountProvider = gamesProvider.select(
  (s) => s.selectedGameIds.length,
);
final _ribbonSelectedGamesProvider = gamesProvider.select(
  (s) => s.selectedGames,
);

const double kSelectionRibbonExpandedPanelMaxHeight = 204.0;

// ---------------------------------------------------------------------------

class SelectionRibbon extends ConsumerWidget {
  const SelectionRibbon({
    super.key,
    required this.isExpanded,
    required this.onToggleExpand,
  });

  final bool isExpanded;
  final VoidCallback onToggleExpand;

  void _openDetails(BuildContext context, WidgetRef ref) {
    final selectedGameIds = ref.read(
      gamesProvider.select((s) => s.selectedGameIds),
    );
    final allGames = ref.read(gamesProvider.select((s) => s.filteredGames));
    final selectedGames = allGames
        .where((game) => selectedGameIds.contains(game.id))
        .toList();
    final ids = selectedGameIds.isNotEmpty
        ? (selectedGameIds.length > 1
              ? selectedGames.map((game) => game.id).toList()
              : [selectedGameIds.first])
        : <int>[];
    if (ids.isEmpty) {
      NotificationManager.instance.info('No games selected');
      return;
    }

    final initialGame = selectedGames.isNotEmpty
        ? selectedGames.first
        : ref.read(gameByIdProvider(ids.first));
    if (initialGame == null) {
      NotificationManager.instance.error('Unable to open game details');
      return;
    }

    showGameDetailsDialog(
      context,
      initialGame,
      gameIds: ids,
      onViewedGame: (gameId) => markGameAsViewed(ref, gameId),
    );
  }

  void _showCopyDialog(BuildContext context, WidgetRef ref) {
    final selectedGames = ref.read(selectedGamesProvider);
    if (selectedGames.isEmpty) {
      NotificationManager.instance.info('No games selected');
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => CopyActionsDialog(targets: selectedGames),
    );
  }

  Future<void> _openSteamPage(WidgetRef ref) async {
    final selectedGames = ref.read(selectedSteamGamesProvider);
    if (selectedGames.isEmpty) {
      NotificationManager.instance.info('No Steam games selected');
      return;
    }

    for (final game in selectedGames) {
      final Uri url = game.steamAppId.isNotEmpty
          ? Uri.parse('https://store.steampowered.com/app/${game.steamAppId}')
          : Uri.parse(
              'https://store.steampowered.com/search/?term=${Uri.encodeComponent(game.title)}',
            );

      try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } catch (_) {
        NotificationManager.instance.error(
          'Failed to open Steam page for ${game.title}',
        );
      }
    }

    if (selectedGames.length == 1) {
      NotificationManager.instance.info(
        'Opened Steam page for ${selectedGames.first.title}',
      );
    } else {
      NotificationManager.instance.info(
        'Opened Steam pages for ${selectedGames.length} games',
      );
    }
  }

  Future<void> _toggleUsed(WidgetRef ref) async {
    final selectedGameIds = ref.read(
      gamesProvider.select((s) => s.selectedGameIds),
    );
    final allUsed = ref.read(selectedGamesAllUsedProvider);
    await ref
        .read(gamesProvider.notifier)
        .setGamesUsed(selectedGameIds.toList(), !allUsed);
    NotificationManager.instance.success(
      '${selectedGameIds.length} ${!allUsed ? 'marked as used' : 'marked as unused'}',
    );
  }

  Future<void> _fetchSelectedSteamGames(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final selectedGames = ref.read(selectedSteamGamesProvider);
    final batchFetchState = ref.read(batchFetchProvider);
    if (selectedGames.isEmpty) {
      NotificationManager.instance.info('No Steam games selected');
      return;
    }
    if (batchFetchState.isActive) {
      NotificationManager.instance.info('A fetch is already in progress');
      return;
    }

    await performSteamBatchLookup(context, selectedGames);
  }

  Future<void> _deleteSelection(
    BuildContext context,
    WidgetRef ref,
    AppThemeData theme,
  ) async {
    final selectedGameIds = ref.read(
      gamesProvider.select((s) => s.selectedGameIds),
    );
    final confirmed = await showConfirmDialog(
      context: context,
      theme: theme,
      title: 'Delete ${selectedGameIds.length} games?',
      message: 'This action cannot be undone.',
      confirmLabel: 'Delete',
      confirmIcon: Icons.delete,
      destructive: true,
    );

    if (confirmed) {
      await ref
          .read(gamesProvider.notifier)
          .deleteGames(selectedGameIds.toList());
      NotificationManager.instance.success(
        'Deleted ${selectedGameIds.length} games',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCount = ref.watch(_ribbonSelectedCountProvider);
    final theme = ref.watch(themeProvider);
    final notifier = ref.read(gamesProvider.notifier);
    final allUsed = ref.watch(selectedGamesAllUsedProvider);
    final batchFetchState = ref.watch(batchFetchProvider);
    return _RibbonBar(
      theme: theme,
      selectedCount: selectedCount,
      isExpanded: isExpanded,
      allUsed: allUsed,
      isFetchActive: batchFetchState.isActive,
      onClearAll: notifier.clearSelection,
      onToggleExpand: onToggleExpand,
      onOpenDetails: () => _openDetails(context, ref),
      onCopy: () => _showCopyDialog(context, ref),
      onOpenSteamPage: () => _openSteamPage(ref),
      onToggleUsed: () => _toggleUsed(ref),
      onFetch: () => _fetchSelectedSteamGames(context, ref),
      onDelete: () => _deleteSelection(context, ref, theme),
    );
  }
}

class SelectionRibbonExpandedPanel extends ConsumerWidget {
  const SelectionRibbonExpandedPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final selectedGames = ref.watch(_ribbonSelectedGamesProvider);
    final notifier = ref.read(gamesProvider.notifier);

    return ClipRect(
      child: AnimatedSize(
        duration: kMediumAnimation,
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        child: _ExpandedPanel(
          theme: theme,
          games: selectedGames,
          onDeselect: notifier.deselectGame,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _RibbonBar extends StatelessWidget {
  const _RibbonBar({
    required this.theme,
    required this.selectedCount,
    required this.isExpanded,
    required this.allUsed,
    required this.isFetchActive,
    required this.onClearAll,
    required this.onToggleExpand,
    required this.onOpenDetails,
    required this.onCopy,
    required this.onOpenSteamPage,
    required this.onToggleUsed,
    required this.onFetch,
    required this.onDelete,
  });

  final AppThemeData theme;
  final int selectedCount;
  final bool isExpanded;
  final bool allUsed;
  final bool isFetchActive;
  final VoidCallback onClearAll;
  final VoidCallback onToggleExpand;
  final VoidCallback onOpenDetails;
  final VoidCallback onCopy;
  final VoidCallback onOpenSteamPage;
  final VoidCallback onToggleUsed;
  final VoidCallback onFetch;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ribbonBg = theme.accent.withValues(alpha: 0.40);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: ribbonBg),
      child: Row(
        children: [
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.checklist_rtl_rounded, size: 18, color: theme.accent),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$selectedCount',
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(text: ' selected'),
                  ],
                ),
              ),
            ],
          ),
          _VerticalDivider(theme: theme),
          Expanded(
            child: Center(
              child: _ActionButtonsRow(
                theme: theme,
                isExpanded: isExpanded,
                allUsed: allUsed,
                isFetchActive: isFetchActive,
                onToggleExpand: onToggleExpand,
                onOpenDetails: onOpenDetails,
                onCopy: onCopy,
                onOpenSteamPage: onOpenSteamPage,
                onToggleUsed: onToggleUsed,
                onFetch: onFetch,
                onDelete: onDelete,
              ),
            ),
          ),
          _VerticalDivider(theme: theme),
          _ClearAllButton(theme: theme, onTap: onClearAll),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Container(width: 1, height: 22, color: theme.border),
  );
}

class _ActionButtonsRow extends StatelessWidget {
  const _ActionButtonsRow({
    required this.theme,
    required this.isExpanded,
    required this.allUsed,
    required this.isFetchActive,
    required this.onToggleExpand,
    required this.onOpenDetails,
    required this.onCopy,
    required this.onOpenSteamPage,
    required this.onToggleUsed,
    required this.onFetch,
    required this.onDelete,
  });

  final AppThemeData theme;
  final bool isExpanded;
  final bool allUsed;
  final bool isFetchActive;
  final VoidCallback onToggleExpand;
  final VoidCallback onOpenDetails;
  final VoidCallback onCopy;
  final VoidCallback onOpenSteamPage;
  final VoidCallback onToggleUsed;
  final VoidCallback onFetch;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _RibbonActionButton(
          theme: theme,
          icon: Icons.checklist_rtl_rounded,
          tooltip: isExpanded ? 'Close List' : 'Show List',
          onTap: onToggleExpand,
          foreground: isExpanded ? theme.accent : null,
        ),
        _RibbonActionButton(
          theme: theme,
          icon: Icons.info_outline,
          tooltip: 'View Details',
          onTap: onOpenDetails,
        ),
        _RibbonActionButton(
          theme: theme,
          icon: Icons.copy_all,
          tooltip: 'Copy',
          onTap: onCopy,
        ),
        _RibbonActionButton(
          theme: theme,
          icon: Icons.open_in_new,
          tooltip: 'Open Steam Page',
          onTap: onOpenSteamPage,
        ),
        _RibbonActionButton(
          theme: theme,
          icon: allUsed ? Icons.check_box : Icons.check_box_outline_blank,
          tooltip: allUsed ? 'Mark Unused' : 'Mark Used',
          onTap: onToggleUsed,
        ),
        _RibbonActionButton(
          theme: theme,
          icon: Icons.cloud_download,
          tooltip: 'Fetch',
          onTap: onFetch,
          foreground: isFetchActive
              ? theme.textSecondary.withValues(alpha: 0.4)
              : null,
        ),
        _RibbonActionButton(
          theme: theme,
          icon: Icons.delete_outline,
          tooltip: 'Delete',
          onTap: onDelete,
          isDestructive: true,
        ),
      ],
    );
  }
}

class _HoverRegion extends StatefulWidget {
  const _HoverRegion({required this.builder, this.cursor});

  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor? cursor;

  @override
  State<_HoverRegion> createState() => _HoverRegionState();
}

class _HoverRegionState extends State<_HoverRegion> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor ?? MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(context, _hovered),
    );
  }
}

class _TapTarget extends StatelessWidget {
  const _TapTarget({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: child,
    );
  }
}

class _RibbonActionButton extends StatelessWidget {
  const _RibbonActionButton({
    required this.theme,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.foreground,
    this.isDestructive = false,
  });

  final AppThemeData theme;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? foreground;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final iconColor = foreground ?? theme.textPrimary;
    final styleColor = theme.primaryButtonText;
    final overlayColor = isDestructive
        ? theme.error.withValues(alpha: 0.90)
        : styleColor.withValues(alpha: 0.15);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(theme.cornerRadius),
          highlightColor: overlayColor,
          splashColor: overlayColor,
          child: Container(
            padding: const EdgeInsets.all(5),
            child: Icon(icon, size: 22, color: iconColor),
          ),
        ),
      ),
    );
  }
}

class _HoverIconButton extends StatelessWidget {
  const _HoverIconButton({
    required this.onTap,
    required this.iconSize,
    required this.padding,
    required this.hoverColor,
    this.shape,
  });

  final VoidCallback onTap;
  final double iconSize;
  final EdgeInsets padding;
  final Color hoverColor;
  final BoxShape? shape;

  @override
  Widget build(BuildContext context) {
    return _HoverRegion(
      cursor: SystemMouseCursors.click,
      builder: (_, hovered) => _TapTarget(
        onTap: onTap,
        child: AnimatedContainer(
          duration: kVeryFastAnimation,
          padding: padding,
          decoration: BoxDecoration(
            color: hovered ? hoverColor : Colors.transparent,
            shape: shape ?? BoxShape.rectangle,
            borderRadius: shape == BoxShape.circle
                ? null
                : BorderRadius.circular(4),
          ),
          child: Icon(Icons.close_rounded, size: iconSize),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ClearAllButton extends StatelessWidget {
  const _ClearAllButton({required this.theme, required this.onTap});

  final AppThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _HoverRegion(
      cursor: SystemMouseCursors.click,
      builder: (_, hovered) => _TapTarget(
        onTap: onTap,
        child: Text(
          'Deselect all',
          style: TextStyle(
            color: hovered ? theme.accent : theme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ExpandedPanel extends StatelessWidget {
  const _ExpandedPanel({
    required this.theme,
    required this.games,
    required this.onDeselect,
  });

  final AppThemeData theme;
  final List<Game> games;
  final void Function(int gameId) onDeselect;

  @override
  Widget build(BuildContext context) {
    final panelBg = Color.lerp(
      theme.background.withValues(alpha: 0.95),
      theme.accent,
      0.20,
    )!;

    return Container(
      constraints: const BoxConstraints(
        maxHeight: kSelectionRibbonExpandedPanelMaxHeight,
      ),
      decoration: BoxDecoration(color: panelBg),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: games.length,
        itemBuilder: (_, index) => _ExpandedPanelRow(
          game: games[index],
          index: index,
          theme: theme,
          onDeselect: () => onDeselect(games[index].id),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ExpandedPanelRow extends StatelessWidget {
  const _ExpandedPanelRow({
    required this.game,
    required this.index,
    required this.theme,
    required this.onDeselect,
  });

  final Game game;
  final int index;
  final AppThemeData theme;
  final VoidCallback onDeselect;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return _HoverRegion(
      builder: (_, hovered) => AnimatedContainer(
        duration: kVeryFastAnimation,
        color: hovered
            ? Color.lerp(t.accent.withValues(alpha: 0.30), Colors.transparent, 0.0)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              alignment: Alignment.centerRight,
              child: Text(
                '${index + 1}.',
                textAlign: TextAlign.left,
                style: TextStyle(color: t.textHint),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(game.title),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _HoverIconButton(
                onTap: onDeselect,
                iconSize: 18,
                padding: const EdgeInsets.all(3),
                hoverColor: t.accent.withValues(alpha: 0.50),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
