/// Compact selection actions anchored to the bottom of the library.
/// Frequent actions stay visible; remaining actions use a native overflow menu.
/// The selected-games list opens above the bar without moving library content.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/button_group_shape.dart';
import '../../../models/game.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/app_progress_indicator.dart';
import '../../widgets/game_selection_actions.dart';
import '../../widgets/popup_menu_helpers.dart';

// ---------------------------------------------------------------------------
// Provider selectors (file-private)

final _ribbonSelectedCountProvider = gamesProvider.select(
  (s) => s.selectedGameIds.length,
);
final _ribbonSelectedGamesProvider = selectedGamesProvider;
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
    GameSelectionActions.openSteamPages(
      ref,
      ref.read(selectedSteamGamesProvider),
    );
  }

  void _toggleUsed(WidgetRef ref) {
    final allUsed = ref.read(selectedGamesAllUsedProvider);
    GameSelectionActions.toggleUsed(
      ref,
      ref.read(selectedGamesProvider),
      !allUsed,
    );
  }

  void _fetchSelectedSteamGames(BuildContext context, WidgetRef ref) {
    GameSelectionActions.fetchSteamData(
      context,
      ref,
      ref.read(selectedSteamGamesProvider),
    );
  }

  void _deleteSelection(
    BuildContext context,
    WidgetRef ref,
    AppThemeData theme,
  ) {
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
    final allSelected = ref.watch(
      gamesProvider.select(
        (state) =>
            state.filteredGames.isNotEmpty &&
            state.filteredGames.every(
              (game) => state.selectedGameIds.contains(game.id),
            ),
      ),
    );
    final isMultiSelectEnabled = ref.watch(_ribbonMultiSelectEnabledProvider);
    final isFetchActive = ref.watch(
      batchFetchProvider.select((s) => s.isActive),
    );
    final hasSteamGames = ref.watch(
      selectedSteamGamesProvider.select((games) => games.isNotEmpty),
    );
    final actions = [
      _RibbonAction(
        id: 'edit',
        label: 'Edit',
        tooltip: 'Game Editor',
        icon: Icons.edit_outlined,
        onPressed: isFetchActive ? null : () => _openDetails(context, ref),
      ),
      _RibbonAction(
        id: 'copy',
        label: 'Copy',
        icon: Icons.copy_all_outlined,
        onPressed: () => _showCopyDialog(context, ref),
      ),
      _RibbonAction(
        id: 'used',
        label: allUsed ? 'Mark unused' : 'Mark used',
        tooltip: allUsed ? 'Mark Unused' : 'Mark Used',
        icon: allUsed ? Icons.check_box : Icons.check_box_outline_blank,
        onPressed: isFetchActive ? null : () => _toggleUsed(ref),
      ),
      _RibbonAction(
        id: 'all',
        group: _RibbonActionGroup.selection,
        label: allSelected ? 'Deselect all' : 'Select all',
        tooltip: allSelected ? 'Deselect all games' : 'Select all games',
        icon: allSelected ? Icons.deselect : Icons.select_all,
        onPressed: allSelected ? notifier.clearSelection : notifier.selectAll,
      ),
      _RibbonAction(
        id: 'multi',
        group: _RibbonActionGroup.selection,
        label: 'Multi-select',
        icon: Icons.library_add_check_outlined,
        selected: isMultiSelectEnabled,
        onPressed: () =>
            ref.read(selectionMultiSelectModeProvider.notifier).toggle(),
      ),
      _RibbonAction(
        id: 'fetch',
        group: _RibbonActionGroup.steam,
        label: isFetchActive ? 'Fetching…' : 'Fetch',
        tooltip: isFetchActive ? 'Fetching Steam data' : 'Fetch Steam data',
        icon: Icons.cloud_download_outlined,
        busy: isFetchActive,
        onPressed: isFetchActive || !hasSteamGames
            ? null
            : () => _fetchSelectedSteamGames(context, ref),
      ),
      _RibbonAction(
        id: 'steam',
        group: _RibbonActionGroup.steam,
        label: 'Open Steam page',
        icon: Icons.open_in_new,
        onPressed: hasSteamGames ? () => _openSteamPage(ref) : null,
      ),
      _RibbonAction(
        id: 'delete',
        group: _RibbonActionGroup.destructive,
        label: 'Delete',
        icon: Icons.delete_outline,
        destructive: true,
        onPressed: isFetchActive
            ? null
            : () => _deleteSelection(context, ref, theme),
      ),
    ];
    return _RibbonBar(
      theme: theme,
      selectedCount: selectedCount,
      isExpanded: isExpanded,
      isVeryNarrowLayout: isVeryNarrowLayout,
      isMultiSelectEnabled: isMultiSelectEnabled,
      actions: actions,
      onClearAll: notifier.clearSelection,
      onToggleExpand: onToggleExpand,
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

enum _RibbonActionGroup { game, steam, selection, destructive }

TextStyle _actionLabelStyle(BuildContext context) => Theme.of(
  context,
).textTheme.labelLarge!.copyWith(fontWeight: FontWeight.w600);

class _RibbonAction {
  const _RibbonAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.group = _RibbonActionGroup.game,
    this.tooltip,
    this.selected = false,
    this.busy = false,
    this.destructive = false,
  });

  final String id;
  final _RibbonActionGroup group;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool selected;
  final bool busy;
  final bool destructive;
}

class _RibbonBar extends StatelessWidget {
  const _RibbonBar({
    required this.theme,
    required this.selectedCount,
    required this.isExpanded,
    required this.isVeryNarrowLayout,
    required this.isMultiSelectEnabled,
    required this.actions,
    required this.onClearAll,
    required this.onToggleExpand,
  });

  final AppThemeData theme;
  final int selectedCount;
  final bool isExpanded;
  final bool isVeryNarrowLayout;
  final bool isMultiSelectEnabled;
  final List<_RibbonAction> actions;
  final VoidCallback onClearAll;
  final VoidCallback onToggleExpand;

  Widget _selectionSummary(
    BuildContext context,
    bool showLabels,
    bool tiny,
    double width,
  ) => SizedBox(
    key: const ValueKey('selection-summary'),
    width: width,
    height: 40,
    child: Tooltip(
      message: isExpanded ? 'Close List' : 'Show List',
      child: Semantics(
        button: true,
        selected: isExpanded,
        label:
            '$selectedCount games selected${isMultiSelectEnabled ? ', multi-select enabled' : ''}',
        excludeSemantics: true,
        child: TextButton(
          onPressed: onToggleExpand,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            foregroundColor: theme.textPrimary,
            backgroundColor: isExpanded
                ? theme.buttonGroupBackground
                : Colors.transparent,
          ),
          child: Row(
            children: [
              if (!tiny) ...[
                Icon(
                  isMultiSelectEnabled
                      ? Icons.library_add_check_rounded
                      : Icons.checklist_rounded,
                  size: 20,
                  color: theme.accent,
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  showLabels ? '$selectedCount selected' : '$selectedCount',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge!.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_up,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _moreMenu(
    BuildContext context,
    List<_RibbonAction> overflow,
    bool showLabels,
  ) => AppPopupMenuButton<_RibbonAction>(
    key: const ValueKey('selection-more-actions'),
    tooltip: 'More actions',
    borderRadius: BorderRadius.circular(theme.cornerRadius * 1.25),
    color: theme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(theme.cornerRadius),
    ),
    onSelected: (action) => action.onPressed?.call(),
    itemBuilder: (context) => [
      for (final (index, action) in overflow.indexed) ...[
        if (index > 0 && action.group != overflow[index - 1].group)
          const PopupMenuDivider(),
        PopupMenuItem<_RibbonAction>(
          key: ValueKey('selection-menu-${action.id}'),
          value: action,
          enabled: action.onPressed != null,
          child: Row(
            children: [
              Icon(
                action.icon,
                size: 20,
                color: action.onPressed == null
                    ? theme.textHint
                    : action.destructive
                    ? theme.error
                    : theme.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  action.label,
                  style: TextStyle(
                    color: action.onPressed == null
                        ? theme.textHint
                        : action.destructive
                        ? theme.error
                        : theme.textPrimary,
                  ),
                ),
              ),
              if (action.id == 'multi') ...[
                const SizedBox(width: 12),
                Icon(
                  action.selected
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 18,
                  color: action.selected ? theme.accent : theme.textHint,
                ),
              ],
            ],
          ),
        ),
      ],
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.more_horiz, size: 22, color: theme.textPrimary),
          if (showLabels) ...[
            const SizedBox(width: 6),
            Text(
              'More',
              style: Theme.of(
                context,
              ).textTheme.labelLarge!.copyWith(color: theme.textPrimary),
            ),
          ],
        ],
      ),
    ),
  );

  double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('selection-ribbon-bar'),
    height: kNavigationPanelHorizontalExtent,
    decoration: BoxDecoration(
      color: theme.navBackground,
      border: Border(top: BorderSide(color: theme.border)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final showLabels =
            !isVeryNarrowLayout &&
            constraints.maxWidth >= 840 &&
            MediaQuery.textScalerOf(context).scale(14) <= 17;
        final tiny = constraints.maxWidth < 280;
        final labelStyle = Theme.of(context).textTheme.labelLarge!;
        final summaryWidth =
            ((tiny ? 38 : 64) +
                    _textWidth(
                      context,
                      showLabels ? '$selectedCount selected' : '$selectedCount',
                      labelStyle.copyWith(fontWeight: FontWeight.bold),
                    ))
                .clamp(40.0, constraints.maxWidth * 0.45)
                .toDouble();
        final moreWidth = showLabels
            ? 48 + _textWidth(context, 'More', labelStyle)
            : 42.0;
        final clearWidth = showLabels
            ? 42 + _textWidth(context, 'Deselect all', labelStyle)
            : 40.0;
        final actionWidths = [
          for (final action in actions)
            showLabels
                ? 42 +
                      _textWidth(
                        context,
                        action.label,
                        _actionLabelStyle(context),
                      )
                : 40.0,
        ];
        final cumulativeWidths = <double>[0];
        for (var index = 0; index < actions.length; index++) {
          cumulativeWidths.add(
            cumulativeWidths.last +
                actionWidths[index] +
                (index > 0 && actions[index].group != actions[index - 1].group
                    ? 8
                    : 0),
          );
        }
        final available =
            constraints.maxWidth - summaryWidth - 8 - clearWidth - 4;
        var visibleCount = actions.length;
        if (cumulativeWidths.last > available) {
          visibleCount = 0;
          while (visibleCount < actions.length &&
              cumulativeWidths[visibleCount + 1] + moreWidth + 8 <= available) {
            visibleCount++;
          }
        }
        final groups = <List<_RibbonAction>>[];
        for (final action in actions.take(visibleCount)) {
          if (groups.isEmpty || groups.last.last.group != action.group) {
            groups.add([]);
          }
          groups.last.add(action);
        }
        final hasOverflow = visibleCount < actions.length;
        final controlsWidth =
            cumulativeWidths[visibleCount] +
            (hasOverflow ? moreWidth + (visibleCount > 0 ? 8 : 0) : 0);
        final centeredLeft = (constraints.maxWidth - controlsWidth) / 2;
        final controlsLeft = centeredLeft.clamp(
          summaryWidth + 8,
          constraints.maxWidth - clearWidth - 4 - controlsWidth,
        );
        final controls = Transform.translate(
          offset: Offset(controlsLeft - centeredLeft, 0),
          child: Row(
            key: const ValueKey('selection-action-groups'),
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (index, group) in groups.indexed) ...[
                if (index > 0) const SizedBox(width: 8),
                Material(
                  key: ValueKey('selection-group-${group.first.group.name}'),
                  color: theme.buttonGroupBackground,
                  borderRadius: BorderRadius.circular(
                    theme.cornerRadius * 1.25,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (index, action) in group.indexed)
                        ButtonGroupShape(
                          borderRadius: buttonGroupBorderRadius(
                            index: index,
                            count: group.length,
                            radius: theme.cornerRadius * 1.25,
                            textDirection: Directionality.of(context),
                          ),
                          child: _ActionControl(
                            theme: theme,
                            action: action,
                            showLabel: showLabels,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (hasOverflow) ...[
                if (visibleCount > 0) const SizedBox(width: 8),
                Material(
                  key: const ValueKey('selection-group-more'),
                  color: theme.buttonGroupBackground,
                  borderRadius: BorderRadius.circular(
                    theme.cornerRadius * 1.25,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    width: moreWidth,
                    height: 40,
                    child: _moreMenu(
                      context,
                      actions.skip(visibleCount).toList(),
                      showLabels,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
        return Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _selectionSummary(context, showLabels, tiny, summaryWidth),
            ),
            Align(alignment: Alignment.center, child: controls),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: clearWidth,
                height: 40,
                child: Tooltip(
                  message: 'Deselect all',
                  child: showLabels
                      ? TextButton.icon(
                          onPressed: onClearAll,
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Deselect all'),
                          style: TextButton.styleFrom(
                            foregroundColor: theme.textSecondary,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                      : IconButton(
                          onPressed: onClearAll,
                          icon: const Icon(Icons.close, size: 20),
                          color: theme.textSecondary,
                          constraints: const BoxConstraints.tightFor(
                            width: 40,
                            height: 40,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _ActionControl extends StatelessWidget {
  const _ActionControl({
    required this.theme,
    required this.action,
    required this.showLabel,
  });
  final AppThemeData theme;
  final _RibbonAction action;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final icon = action.busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: AppCircularProgressIndicator(),
          )
        : Icon(action.icon, size: 20);
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
      maximumSize: showLabel
          ? null
          : const WidgetStatePropertyAll(Size(40, 40)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 8),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: ButtonGroupShape.maybeOf(context) ?? BorderRadius.zero,
        ),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? theme.textHint
            : action.destructive
            ? theme.error
            : theme.textPrimary,
      ),
      backgroundColor: WidgetStatePropertyAll(
        action.selected ? theme.navItemSelected : Colors.transparent,
      ),
      textStyle: WidgetStatePropertyAll(_actionLabelStyle(context)),
    );
    return Tooltip(
      message: action.tooltip ?? action.label,
      child: action.id == 'edit'
          ? ElevatedButton(
              key: ValueKey('selection-action-${action.id}'),
              onPressed: action.onPressed,
              style: style.copyWith(
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.disabled)
                      ? theme.primaryButtonDisabled
                      : theme.primaryButton,
                ),
              ),
              child: showLabel
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        icon,
                        const SizedBox(width: 6),
                        Text(action.label),
                      ],
                    )
                  : icon,
            )
          : TextButton(
              key: ValueKey('selection-action-${action.id}'),
              onPressed: action.onPressed,
              style: style,
              child: showLabel
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        icon,
                        const SizedBox(width: 6),
                        Text(action.label),
                      ],
                    )
                  : icon,
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
  final ValueChanged<int> onDeselect;

  @override
  Widget build(BuildContext context) => Material(
    color: theme.surface,
    child: Container(
      constraints: const BoxConstraints(
        maxHeight: kSelectionRibbonExpandedPanelMaxHeight,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.border)),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: games.length,
        itemBuilder: (context, index) => ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Text(
            '${index + 1}',
            style: TextStyle(color: theme.textHint),
          ),
          minLeadingWidth: 16,
          title: Text(
            games[index].title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: theme.textPrimary),
          ),
          trailing: IconButton(
            tooltip: 'Deselect ${games[index].title}',
            icon: const Icon(Icons.close, size: 18),
            color: theme.textSecondary,
            onPressed: () => onDeselect(games[index].id),
          ),
        ),
      ),
    ),
  );
}
