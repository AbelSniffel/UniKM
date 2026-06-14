/// Alternative game-selection UI: a horizontal ribbon anchored to the bottom
/// of the view when games are selected. The ribbon shows selection status,
/// compact action buttons, and a "Clear all" link at the right end. The
/// expanded list grows upward from the bar without shifting sibling widgets.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/game.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/app_progress_indicator.dart';
import '../../widgets/game_selection_actions.dart';

// ---------------------------------------------------------------------------
// Provider selectors (file-private)

final _ribbonSelectedCountProvider = gamesProvider.select(
  (s) => s.selectedGameIds.length,
);
final _ribbonSelectedGamesProvider = gamesProvider.select(
  (s) => s.selectedGames,
);
final _ribbonMultiSelectEnabledProvider = selectionMultiSelectModeProvider;

const double kSelectionRibbonExpandedPanelMaxHeight = 204.0;

// ---------------------------------------------------------------------------

class SelectionRibbon extends ConsumerWidget {
  const SelectionRibbon({
    super.key,
    required this.isExpanded,
    required this.onToggleExpand,
    this.isVeryNarrowLayout = false,
  });

  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final bool isVeryNarrowLayout;

  void _openDetails(BuildContext context, WidgetRef ref) {
    final selectedGames = ref.read(selectedGamesProvider);
    if (selectedGames.isEmpty) return;
    GameSelectionActions.openDetails(
      context,
      ref,
      targets: selectedGames,
      initialGame: selectedGames.first,
    );
  }

  void _showCopyDialog(BuildContext context, WidgetRef ref) {
    final selectedGames = ref.read(selectedGamesProvider);
    if (selectedGames.isEmpty) return;
    GameSelectionActions.showCopyDialog(context, ref, selectedGames);
  }

  void _openSteamPage(WidgetRef ref) {
    GameSelectionActions.openSteamPages(ref, ref.read(selectedSteamGamesProvider));
  }

  void _toggleUsed(WidgetRef ref) {
    final allUsed = ref.read(selectedGamesAllUsedProvider);
    GameSelectionActions.toggleUsed(ref, ref.read(selectedGamesProvider), !allUsed);
  }

  void _fetchSelectedSteamGames(BuildContext context, WidgetRef ref) {
    GameSelectionActions.fetchSteamData(
      context,
      ref,
      ref.read(selectedSteamGamesProvider),
    );
  }

  void _deleteSelection(BuildContext context, WidgetRef ref, AppThemeData theme) {
    GameSelectionActions.deleteGames(
      context,
      ref,
      theme,
      ref.read(selectedGamesProvider),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCount = ref.watch(_ribbonSelectedCountProvider);
    final theme = ref.watch(themeProvider);
    final notifier = ref.read(gamesProvider.notifier);
    final allUsed = ref.watch(selectedGamesAllUsedProvider);
    final isMultiSelectEnabled = ref.watch(_ribbonMultiSelectEnabledProvider);
    final batchFetchState = ref.watch(batchFetchProvider);
    return _RibbonBar(
      theme: theme,
      selectedCount: selectedCount,
      isExpanded: isExpanded,
      isVeryNarrowLayout: isVeryNarrowLayout,
      isMultiSelectEnabled: isMultiSelectEnabled,
      allUsed: allUsed,
      isFetchActive: batchFetchState.isActive,
      onClearAll: notifier.clearSelection,
      onToggleExpand: onToggleExpand,
      onToggleMultiSelect: () {
        ref.read(selectionMultiSelectModeProvider.notifier).toggle();
      },
      onOpenDetails: () => _openDetails(context, ref),
      onCopy: () => _showCopyDialog(context, ref),
      onOpenSteamPage: () => _openSteamPage(ref),
      onToggleUsed: () => _toggleUsed(ref),
      onFetch: () => _fetchSelectedSteamGames(context, ref),
      onDelete: () => _deleteSelection(context, ref, theme),
      onSelectAll: notifier.selectAll,
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
    required this.isVeryNarrowLayout,
    required this.isMultiSelectEnabled,
    required this.allUsed,
    required this.isFetchActive,
    required this.onClearAll,
    required this.onToggleExpand,
    required this.onToggleMultiSelect,
    required this.onOpenDetails,
    required this.onCopy,
    required this.onOpenSteamPage,
    required this.onToggleUsed,
    required this.onFetch,
    required this.onDelete,
    required this.onSelectAll,
  });

  final AppThemeData theme;
  final int selectedCount;
  final bool isExpanded;
  final bool isVeryNarrowLayout;
  final bool isMultiSelectEnabled;
  final bool allUsed;
  final bool isFetchActive;
  final VoidCallback onClearAll;
  final VoidCallback onToggleExpand;
  final VoidCallback onToggleMultiSelect;
  final VoidCallback onOpenDetails;
  final VoidCallback onCopy;
  final VoidCallback onOpenSteamPage;
  final VoidCallback onToggleUsed;
  final VoidCallback onFetch;
  final VoidCallback onDelete;
  final VoidCallback onSelectAll;

  Widget _buildSelectionSummaryChip() {
    final counterColor = isExpanded ? theme.accent : theme.textPrimary;

    return Tooltip(
      message: isExpanded ? 'Close List' : 'Show List',
      child: TextButton(
        onPressed: onToggleExpand,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.checklist_rtl_rounded, color: theme.accent),
            const SizedBox(width: 6),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$selectedCount',
                    style: TextStyle(
                      color: counterColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: ' selected',
                    style: TextStyle(color: theme.textPrimary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNarrowLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _buildSelectionSummaryChip(),
            const SizedBox(width: 8),
            Expanded(
              child: Divider(
                height: 1,
                thickness: 1,
                color: theme.border,
              ),
            ),
            const SizedBox(width: 8),
            _ClearAllButton(theme: theme, onTap: onClearAll),
          ],
        ),
        const SizedBox(height: 6),
        Center(
          child: _ActionButtonsRow(
            theme: theme,
            isExpanded: isExpanded,
            isMultiSelectEnabled: isMultiSelectEnabled,
            allUsed: allUsed,
            isFetchActive: isFetchActive,
            onToggleExpand: onToggleExpand,
            onToggleMultiSelect: onToggleMultiSelect,
            onOpenDetails: onOpenDetails,
            onCopy: onCopy,
            onOpenSteamPage: onOpenSteamPage,
            onToggleUsed: onToggleUsed,
            onFetch: onFetch,
            onDelete: onDelete,
            onSelectAll: onSelectAll,
          ),
        ),
      ],
    );
  }

  Widget _buildDefaultLayout() {
    return Row(
      children: [
        _buildSelectionSummaryChip(),
        _VerticalDivider(theme: theme),
        Expanded(
          child: Center(
            child: _ActionButtonsRow(
              theme: theme,
              isExpanded: isExpanded,
              isMultiSelectEnabled: isMultiSelectEnabled,
              allUsed: allUsed,
              isFetchActive: isFetchActive,
              onToggleExpand: onToggleExpand,
              onToggleMultiSelect: onToggleMultiSelect,
              onOpenDetails: onOpenDetails,
              onCopy: onCopy,
              onOpenSteamPage: onOpenSteamPage,
              onToggleUsed: onToggleUsed,
              onFetch: onFetch,
              onDelete: onDelete,
              onSelectAll: onSelectAll,
            ),
          ),
        ),
        _VerticalDivider(theme: theme),
        _ClearAllButton(theme: theme, onTap: onClearAll),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ribbonBg = theme.accent.withValues(alpha: 0.40);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: ribbonBg),
      child: isVeryNarrowLayout ? _buildNarrowLayout() : _buildDefaultLayout(),
    );
  }
}

// ---------------------------------------------------------------------------

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Container(width: 1.5, height: 22, color: theme.border),
  );
}

class _ActionButtonsRow extends StatelessWidget {
  const _ActionButtonsRow({
    required this.theme,
    required this.isExpanded,
    required this.isMultiSelectEnabled,
    required this.allUsed,
    required this.isFetchActive,
    required this.onToggleExpand,
    required this.onToggleMultiSelect,
    required this.onOpenDetails,
    required this.onCopy,
    required this.onOpenSteamPage,
    required this.onToggleUsed,
    required this.onFetch,
    required this.onDelete,
    required this.onSelectAll,
  });

  final AppThemeData theme;
  final bool isExpanded;
  final bool isMultiSelectEnabled;
  final bool allUsed;
  final bool isFetchActive;
  final VoidCallback onToggleExpand;
  final VoidCallback onToggleMultiSelect;
  final VoidCallback onOpenDetails;
  final VoidCallback onCopy;
  final VoidCallback onOpenSteamPage;
  final VoidCallback onToggleUsed;
  final VoidCallback onFetch;
  final VoidCallback onDelete;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _RibbonActionButton(
          theme: theme,
          icon: Icons.add_box_outlined,
          iconWidget: _MultiSelectIcon(
            theme: theme,
            enabled: isMultiSelectEnabled,
          ),
          tooltip: isMultiSelectEnabled
              ? 'Disable Multi-Select'
              : 'Enable Multi-Select',
          onTap: onToggleMultiSelect,
          foreground: isMultiSelectEnabled ? theme.accent : null,
        ),
        _RibbonActionButton(
          theme: theme,
          icon: Icons.select_all,
          tooltip: 'Select All',
          onTap: onSelectAll,
        ),
        _RibbonActionButton(
          theme: theme,
          icon: Icons.copy_all,
          tooltip: 'Copy',
          onTap: onCopy,
        ),
        _RibbonActionButton(
          theme: theme,
          icon: allUsed ? Icons.check_box : Icons.check_box_outline_blank,
          tooltip: allUsed ? 'Mark Unused' : 'Mark Used',
          onTap: isFetchActive ? null : onToggleUsed,
        ),
        _RibbonActionButton(
          theme: theme,
          icon: Icons.info_outline,
          tooltip: 'View Details',
          onTap: isFetchActive ? null : onOpenDetails,
        ),
        _RibbonActionButton(
          theme: theme,
          icon: Icons.cloud_download,
          iconWidget: isFetchActive
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: AppCircularProgressIndicator(),
                )
              : null,
          tooltip: 'Fetch',
          onTap: onFetch,
          foreground: isFetchActive
              ? theme.textSecondary.withValues(alpha: 0.4)
              : null,
        ),
        _RibbonActionButton(
          theme: theme,
          icon: Icons.open_in_new,
          tooltip: 'Open Steam Page',
          onTap: onOpenSteamPage,
        ),
        _RibbonActionButton(
          theme: theme,
          icon: Icons.delete_outline,
          tooltip: 'Delete',
          onTap: isFetchActive ? null : onDelete,
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
    this.iconWidget,
    this.foreground,
    this.isDestructive = false,
  });

  final AppThemeData theme;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Widget? iconWidget;
  final Color? foreground;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final iconColor = onTap == null
        ? theme.textSecondary.withValues(alpha: 0.4)
        : (foreground ?? theme.textPrimary);

    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        icon: iconWidget ?? Icon(icon, color: iconColor),
        color: iconColor,
      ),
    );
  }
}

class _MultiSelectIcon extends StatelessWidget {
  const _MultiSelectIcon({required this.theme, required this.enabled});

  final AppThemeData theme;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? theme.accent : theme.textPrimary;
    return AnimatedSwitcher(
      duration: kVeryFastAnimation,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: Icon(
        enabled ? Icons.library_add_check_rounded : Icons.add_box_outlined,
        key: ValueKey<bool>(enabled),
        color: color,
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
        child: TextButton(
          onPressed: onTap,
          child: Text(
            'Deselect all',
            style: TextStyle(
              color: hovered ? theme.accent : theme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
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
            ? Color.lerp(
                t.accent.withValues(alpha: 0.30),
                Colors.transparent,
                0.0,
              )
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
