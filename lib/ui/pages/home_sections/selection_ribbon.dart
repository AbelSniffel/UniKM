/// Compact selection actions anchored to the bottom of the library.
/// Frequent actions stay visible; remaining actions use a native overflow menu.
/// The selected games sit above the bar as a horizontally scrolling row of
/// chips; tapping a chip deselects that game.
library;

import 'package:flutter/gestures.dart';
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
import '../../widgets/segmented_bar.dart';

// ---------------------------------------------------------------------------
// Provider selectors (file-private)

final _ribbonSelectedCountProvider = gamesProvider.select(
  (s) => s.selectedGameIds.length,
);

// ---------------------------------------------------------------------------

class SelectionRibbon extends ConsumerWidget {
  const SelectionRibbon({super.key, this.isVeryNarrowLayout = false});

  final bool isVeryNarrowLayout;

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
    final isMultiSelectEnabled = ref.watch(selectionMultiSelectModeProvider);
    List<Game> selected() => ref.read(selectedGamesProvider);
    List<Game> selectedSteam() => ref.read(selectedSteamGamesProvider);
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
        onPressed: isFetchActive
            ? null
            : () {
                final games = selected();
                if (games.isEmpty) return;
                GameSelectionActions.openDetails(
                  context,
                  ref,
                  targets: games,
                  initialGame: games.first,
                );
              },
      ),
      _RibbonAction(
        id: 'copy',
        label: 'Copy',
        icon: Icons.copy_all_outlined,
        onPressed: () {
          final games = selected();
          if (games.isEmpty) return;
          GameSelectionActions.showCopyDialog(context, ref, games);
        },
      ),
      _RibbonAction(
        id: 'used',
        label: allUsed ? 'Mark unused' : 'Mark used',
        tooltip: allUsed ? 'Mark Unused' : 'Mark Used',
        icon: allUsed ? Icons.check_box : Icons.check_box_outline_blank,
        onPressed: isFetchActive
            ? null
            : () => GameSelectionActions.toggleUsed(
                ref,
                selected(),
                !ref.read(selectedGamesAllUsedProvider),
              ),
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
            : () => GameSelectionActions.fetchSteamData(
                context,
                ref,
                selectedSteam(),
              ),
      ),
      _RibbonAction(
        id: 'steam',
        group: _RibbonActionGroup.steam,
        label: 'Open Steam page',
        icon: Icons.open_in_new,
        onPressed: hasSteamGames
            ? () => GameSelectionActions.openSteamPages(ref, selectedSteam())
            : null,
      ),
      _RibbonAction(
        id: 'delete',
        group: _RibbonActionGroup.destructive,
        label: 'Delete',
        icon: Icons.delete_outline,
        destructive: true,
        onPressed: isFetchActive
            ? null
            : () => GameSelectionActions.deleteGames(
                context,
                ref,
                theme,
                selected(),
              ),
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SelectedGamesStrip(theme: theme),
        _RibbonBar(
          theme: theme,
          selectedCount: selectedCount,
          isVeryNarrowLayout: isVeryNarrowLayout,
          isMultiSelectEnabled: isMultiSelectEnabled,
          actions: actions,
          onClearAll: notifier.clearSelection,
        ),
      ],
    );
  }
}

/// Every selected game as a [TintedChip] in one horizontally scrolling row.
class _SelectedGamesStrip extends ConsumerStatefulWidget {
  const _SelectedGamesStrip({required this.theme});

  final AppThemeData theme;

  @override
  ConsumerState<_SelectedGamesStrip> createState() =>
      _SelectedGamesStripState();
}

class _SelectedGamesStripState extends ConsumerState<_SelectedGamesStrip> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A mouse wheel only reports vertical movement; scroll the row with it.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    final position = _controller.position;
    final delta = event.scrollDelta.dx != 0
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _controller.jumpTo(
        (position.pixels + delta).clamp(0.0, position.maxScrollExtent),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final games = ref.watch(selectedGamesProvider);
    final notifier = ref.read(gamesProvider.notifier);
    final height = (MediaQuery.textScalerOf(context).scale(12) * 1.5 + 22)
        .clamp(40.0, double.infinity);
    return Container(
      key: const ValueKey('selection-games-strip'),
      height: height,
      decoration: BoxDecoration(
        color: theme.navBackground,
        border: Border(top: BorderSide(color: theme.border)),
      ),
      child: Listener(
        onPointerSignal: _onPointerSignal,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
              PointerDeviceKind.stylus,
            },
            scrollbars: false,
          ),
          child: ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: games.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final game = games[index];
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Tooltip(
                    message: 'Deselect ${game.title}',
                    child: TintedChip(
                      key: ValueKey('selection-chip-${game.id}'),
                      theme: theme,
                      color: theme.accent,
                      label: game.title,
                      maxLines: 1,
                      onTap: () => notifier.deselectGame(game.id),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

enum _RibbonActionGroup { game, steam, selection, destructive }

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
    required this.isVeryNarrowLayout,
    required this.isMultiSelectEnabled,
    required this.actions,
    required this.onClearAll,
  });

  final AppThemeData theme;
  final int selectedCount;
  final bool isVeryNarrowLayout;
  final bool isMultiSelectEnabled;
  final List<_RibbonAction> actions;
  final VoidCallback onClearAll;

  Widget _selectionSummary(
    BuildContext context,
    bool showLabels,
    bool tiny,
    double width,
  ) => SizedBox(
    key: const ValueKey('selection-summary'),
    width: width,
    height: 40,
    child: Semantics(
      label:
          '$selectedCount games selected${isMultiSelectEnabled ? ', multi-select enabled' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
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
          ],
        ),
      ),
    ),
  );

  Widget _moreMenu(List<_RibbonAction> overflow) =>
      AppPopupMenuButton<_RibbonAction>(
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
                    color: _menuColor(action) ?? theme.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      action.label,
                      style: TextStyle(
                        color: _menuColor(action) ?? theme.textPrimary,
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
          child: Icon(Icons.more_horiz, size: 22, color: theme.textPrimary),
        ),
      );

  /// Disabled and destructive menu items override the usual colours.
  Color? _menuColor(_RibbonAction action) => action.onPressed == null
      ? theme.textHint
      : action.destructive
      ? theme.error
      : null;

  /// A rounded button group background.
  Widget _group({required Key key, required Widget child}) => Material(
    key: key,
    color: theme.buttonGroupBackground,
    borderRadius: BorderRadius.circular(theme.cornerRadius * 1.25),
    clipBehavior: Clip.antiAlias,
    child: child,
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
    color: theme.navBackground,
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
            ((tiny ? 20 : 42) +
                    _textWidth(
                      context,
                      showLabels ? '$selectedCount selected' : '$selectedCount',
                      labelStyle.copyWith(fontWeight: FontWeight.bold),
                    ))
                .clamp(40.0, constraints.maxWidth * 0.45)
                .toDouble();
        const moreWidth = 42.0;
        final clearWidth = showLabels
            ? 42 + _textWidth(context, 'Deselect all', labelStyle)
            : 40.0;
        const actionWidth = 40.0;
        final cumulativeWidths = <double>[0];
        for (var index = 0; index < actions.length; index++) {
          cumulativeWidths.add(
            cumulativeWidths.last +
                actionWidth +
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
            spacing: 8,
            children: [
              for (final group in groups)
                _group(
                  key: ValueKey('selection-group-${group.first.group.name}'),
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
                          child: _ActionControl(theme: theme, action: action),
                        ),
                    ],
                  ),
                ),
              if (hasOverflow)
                _group(
                  key: const ValueKey('selection-group-more'),
                  child: SizedBox(
                    width: moreWidth,
                    height: 40,
                    child: _moreMenu(actions.skip(visibleCount).toList()),
                  ),
                ),
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
  const _ActionControl({required this.theme, required this.action});
  final AppThemeData theme;
  final _RibbonAction action;

  @override
  Widget build(BuildContext context) {
    final icon = action.busy
        ? const AppCircularProgressIndicator(size: 18)
        : Icon(action.icon, size: 20);
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
      maximumSize: const WidgetStatePropertyAll(Size(40, 40)),
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
    );
    final key = ValueKey('selection-action-${action.id}');
    return Tooltip(
      message: action.tooltip ?? action.label,
      child: action.id == 'edit'
          ? ElevatedButton(
              key: key,
              onPressed: action.onPressed,
              style: style.copyWith(
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.disabled)
                      ? theme.primaryButtonDisabled
                      : theme.primaryButton,
                ),
              ),
              child: icon,
            )
          : TextButton(
              key: key,
              onPressed: action.onPressed,
              style: style,
              child: icon,
            ),
    );
  }
}
