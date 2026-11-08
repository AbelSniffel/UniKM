/// Compact selection actions anchored to the bottom of the library.
/// Frequent actions stay visible; remaining actions use the shared anchored overflow menu.
/// The selected games sit above the bar as a horizontally scrolling row of
/// chips; tapping a chip deselects that game.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/game.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/app_progress_indicator.dart';
import '../../widgets/game_selection_actions.dart';
import '../../widgets/nav_button_group.dart';
import '../../widgets/background_pattern.dart';
import '../../widgets/popup_menu_helpers.dart';
import '../../widgets/segmented_bar.dart';

// ---------------------------------------------------------------------------
// Provider selectors (file-private)

final _ribbonSelectedCountProvider = gamesProvider.select(
  (s) => s.selectedGameIds.length,
);

// ---------------------------------------------------------------------------

class SelectionRibbon extends ConsumerWidget {
  const SelectionRibbon({super.key});

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
    // The ribbon stays open with nothing selected; game actions wait for a
    // selection, and editing ones also for a running Steam fetch to finish.
    final canEdit = selectedCount > 0 && !isFetchActive;
    final actions = [
      _RibbonAction(
        id: 'edit',
        label: 'Edit',
        tooltip: 'Game Editor',
        icon: Icons.edit_outlined,
        onPressed: !canEdit
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
        id: 'used',
        label: allUsed ? 'Mark unused' : 'Mark used',
        tooltip: allUsed ? 'Mark Unused' : 'Mark Used',
        icon: allUsed ? Icons.check_box : Icons.check_box_outline_blank,
        onPressed: !canEdit
            ? null
            : () => GameSelectionActions.toggleUsed(
                ref,
                selected(),
                !ref.read(selectedGamesAllUsedProvider),
              ),
      ),
      _RibbonAction(
        id: 'copy',
        label: 'Copy',
        icon: Icons.copy_all_outlined,
        onPressed: selectedCount == 0
            ? null
            : () {
                final games = selected();
                if (games.isEmpty) return;
                GameSelectionActions.showCopyDialog(context, ref, games);
              },
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
        id: 'all',
        group: _RibbonActionGroup.selection,
        label: allSelected ? 'Deselect all' : 'Select all',
        tooltip: allSelected ? 'Deselect all games' : 'Select all games',
        icon: allSelected ? Icons.deselect : Icons.select_all,
        onPressed: allSelected ? notifier.clearSelection : notifier.selectAll,
      ),
      // Steam actions only appear with a Steam game in the selection.
      if (hasSteamGames) ...[
        _RibbonAction(
          id: 'fetch',
          group: _RibbonActionGroup.steam,
          label: isFetchActive ? 'Fetching…' : 'Fetch',
          tooltip: isFetchActive ? 'Fetching Steam data' : 'Fetch Steam data',
          icon: Icons.cloud_download_outlined,
          busy: isFetchActive,
          onPressed: isFetchActive
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
          onPressed: () =>
              GameSelectionActions.openSteamPages(ref, selectedSteam()),
        ),
      ],
      _RibbonAction(
        id: 'delete',
        group: _RibbonActionGroup.destructive,
        label: 'Delete',
        icon: Icons.delete_outline,
        destructive: true,
        onPressed: !canEdit
            ? null
            : () => GameSelectionActions.deleteGames(
                context,
                ref,
                theme,
                selected(),
              ),
      ),
    ];
    // One surface, two rows: the pattern runs on across the chip strip and
    // the action bar.
    return PanelPatternSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The chip strip folds away while nothing is selected, and
          // grows back with the next selection.
          TweenAnimationBuilder<double>(
            tween: Tween(end: selectedCount > 0 ? 1 : 0),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : kFastAnimation,
            curve: Curves.easeOutCubic,
            child: _SelectedGamesStrip(theme: theme),
            builder: (context, height, strip) => ClipRect(
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: height,
                child: strip,
              ),
            ),
          ),
          _RibbonBar(
            theme: theme,
            selectedCount: selectedCount,
            isMultiSelectEnabled: isMultiSelectEnabled,
            actions: actions,
            onClose: () {
              notifier.clearSelection();
              ref.read(selectionRibbonOpenProvider.notifier).close();
            },
          ),
        ],
      ),
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
      // An accent-tinted band over the shared pattern sets the chips apart
      // from the action bar below.
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.15),
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
                    message: 'Deselect',
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

enum _RibbonActionGroup { game, selection, steam, destructive }

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
    required this.isMultiSelectEnabled,
    required this.actions,
    required this.onClose,
  });

  final AppThemeData theme;
  final int selectedCount;
  final bool isMultiSelectEnabled;
  final List<_RibbonAction> actions;
  final VoidCallback onClose;

  /// Icon-only navigation buttons, 4 px smaller than the navigation panel's.
  static const double _button = 36;
  static const double _gap = 8;
  static const double _groupEdges = NavButtonGroup.padding * 2;

  /// The count in an accent label like the home header's game counter,
  /// with "Selected" after it when there is room.
  Widget _selectionSummary(String text, TextStyle style) => Semantics(
    key: const ValueKey('selection-summary'),
    label:
        '$selectedCount games selected${isMultiSelectEnabled ? ', multi-select enabled' : ''}',
    excludeSemantics: true,
    child: Container(
      key: const ValueKey('selection-count'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(text, maxLines: 1, softWrap: false, style: style),
    ),
  );

  /// The overflow actions, opening upward from the bar.
  Widget _moreMenu(List<_RibbonAction> overflow) => AppMenuAnchor(
    theme: theme,
    alignment: Alignment.topLeft,
    alignmentOffset: const Offset(0, -4),
    menuChildren: [
      for (final (index, action) in overflow.indexed) ...[
        if (index > 0 && action.group != overflow[index - 1].group)
          Divider(height: 1, color: theme.border),
        appMenuItem(
          theme,
          key: ValueKey('selection-menu-${action.id}'),
          onPressed: action.onPressed,
          color: _menuColor(action),
          leading: Icon(
            action.icon,
            size: 20,
            color: _menuColor(action) ?? theme.accent,
          ),
          trailing: action.id == 'multi'
              ? Icon(
                  action.selected
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 18,
                  color: action.selected ? theme.accent : theme.textHint,
                )
              : null,
          child: Text(action.label),
        ),
      ],
    ],
    builder: (context, controller, _) => _navButton(
      key: const ValueKey('selection-more-actions'),
      icon: Icons.more_horiz,
      tooltip: 'More actions',
      selected: controller.isOpen,
      onTap: () => controller.isOpen ? controller.close() : controller.open(),
    ),
  );

  /// Disabled and destructive menu items override the usual colours.
  Color? _menuColor(_RibbonAction action) => action.onPressed == null
      ? theme.textHint
      : action.destructive
      ? theme.error
      : null;

  Widget _navButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool selected = false,
    bool busy = false,
    bool destructive = false,
  }) => AppNavigationButton(
    key: key,
    theme: theme,
    isSelected: selected,
    isEnabled: onTap != null,
    isHorizontal: true,
    onTap: onTap,
    tooltipMessage: tooltip,
    // Destructive buttons highlight in the theme's secondary color, like
    // their group.
    tint: destructive ? theme.secondary : null,
    padding: const EdgeInsets.all(6),
    minWidth: _button,
    // A busy button is disabled, but its spinner keeps the accent.
    iconBuilder: (context, color, size) => busy
        ? AppCircularProgressIndicator.icon(size: size)
        : Icon(
            icon,
            size: size,
            color: destructive && onTap != null ? theme.error : color,
          ),
  );

  Widget _actionButton(_RibbonAction action) => _navButton(
    key: ValueKey('selection-action-${action.id}'),
    icon: action.icon,
    tooltip: action.tooltip ?? action.label,
    onTap: action.onPressed,
    selected: action.selected,
    busy: action.busy,
    destructive: action.destructive,
  );

  Widget _group(String id, List<Widget> children) => NavButtonGroup(
    key: ValueKey('selection-group-$id'),
    theme: theme,
    isHorizontal: true,
    color: id == _RibbonActionGroup.destructive.name ? theme.secondary : null,
    children: children,
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
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('selection-ribbon-bar'),
    height: kNavigationPanelHorizontalExtent,
    // Groups fill the height left, like the navigation panel's.
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final countStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
            color: theme.accent,
            fontWeight: FontWeight.w600,
          );
          const singleGroupWidth = _groupEdges + _button;
          // Room for the close button, which is larger on touch platforms.
          const clearWidth = 40.0;
          // Each button adds its width and the spacing before it: the group's
          // edges plus the gap between groups when it starts a new group.
          final cumulativeWidths = <double>[0];
          for (var index = 0; index < actions.length; index++) {
            final startsGroup =
                index == 0 || actions[index].group != actions[index - 1].group;
            cumulativeWidths.add(
              cumulativeWidths.last +
                  _button +
                  (startsGroup
                      ? _groupEdges + (index > 0 ? _gap : 0)
                      : NavButtonGroup.padding),
            );
          }
          double summaryWidth(String text) =>
              24 + _textWidth(context, text, countStyle);
          // How many actions fit beside a summary of [width].
          int fitting(double width) {
            final available =
                constraints.maxWidth - width - clearWidth - 2 * _gap;
            if (cumulativeWidths.last <= available) return actions.length;
            var count = 0;
            while (count < actions.length &&
                cumulativeWidths[count + 1] + singleGroupWidth + _gap <=
                    available) {
              count++;
            }
            return count;
          }

          // "Selected" shows only while every action still fits.
          var summaryText = '$selectedCount Selected';
          var summary = summaryWidth(summaryText);
          var visibleCount = fitting(summary);
          if (visibleCount < actions.length) {
            summaryText = '$selectedCount';
            summary = summaryWidth(summaryText);
            visibleCount = fitting(summary);
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
              (hasOverflow
                  ? singleGroupWidth + (visibleCount > 0 ? _gap : 0)
                  : 0);
          final centeredLeft = (constraints.maxWidth - controlsWidth) / 2;
          final controlsLeft = centeredLeft.clamp(
            summary + _gap,
            constraints.maxWidth - clearWidth - _gap - controlsWidth,
          );
          // The Steam group folds in and out after the selection group, so
          // the groups around it slide apart or together.
          final steam = groups
              .where((group) => group.first.group == _RibbonActionGroup.steam)
              .firstOrNull;
          Widget buttons(List<_RibbonAction> group) => _group(
            group.first.group.name,
            [for (final action in group) _actionButton(action)],
          );
          final row = <Widget>[];
          void add(Widget group) => row.add(
            row.isEmpty
                ? group
                : Padding(
                    padding: const EdgeInsets.only(left: _gap),
                    child: group,
                  ),
          );
          for (final group in groups) {
            if (group == steam) continue;
            add(buttons(group));
            if (group.first.group == _RibbonActionGroup.selection) {
              row.add(
                _FoldingGroup(
                  key: const ValueKey('selection-steam-slot'),
                  child: steam == null ? null : buttons(steam),
                ),
              );
            }
          }
          if (hasOverflow) {
            add(
              _group('more', [_moreMenu(actions.skip(visibleCount).toList())]),
            );
          }
          final controls = Transform.translate(
            offset: Offset(controlsLeft - centeredLeft, 0),
            child: Row(
              key: const ValueKey('selection-action-groups'),
              mainAxisSize: MainAxisSize.min,
              children: row,
            ),
          );
          return Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _selectionSummary(summaryText, countStyle),
              ),
              controls,
              Align(
                alignment: Alignment.centerRight,
                // The same close button as the app's dialogs.
                child: IconButton(
                  key: const ValueKey('selection-clear'),
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// A button group that folds sideways in as [child] arrives and out once it
/// is gone, keeping the last group on screen while it folds away. Its gap to
/// the group before it folds with it.
class _FoldingGroup extends StatefulWidget {
  const _FoldingGroup({super.key, required this.child});

  final Widget? child;

  @override
  State<_FoldingGroup> createState() => _FoldingGroupState();
}

class _FoldingGroupState extends State<_FoldingGroup> {
  Widget? _shown;

  @override
  Widget build(BuildContext context) {
    _shown = widget.child ?? _shown;
    final shown = _shown;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.child == null ? 0 : 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : kFastAnimation,
      curve: Curves.easeOutCubic,
      onEnd: () {
        if (widget.child == null) setState(() => _shown = null);
      },
      builder: (context, width, _) => shown == null || width == 0
          ? const SizedBox.shrink()
          : IgnorePointer(
              ignoring: widget.child == null,
              child: ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: width,
                  child: Opacity(
                    opacity: width,
                    child: Padding(
                      padding: const EdgeInsets.only(left: _RibbonBar._gap),
                      child: shown,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
