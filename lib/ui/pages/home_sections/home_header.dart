/// Home page header: a full-width game count with sync and the view toggle at
/// its ends, a search row with icon-only platform and sort menus and the
/// filters button, and an expandable panel whose Show only and Tags groupboxes
/// sit side by side or stack with the width, each with its own clear button.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/platform_patterns.dart';
import '../../../core/models/device_sync_models.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../dialogs/device_sync_dialog.dart';
import '../../widgets/app_action_button.dart';
import '../../widgets/app_progress_indicator.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/platform_icon.dart';
import '../../widgets/popup_menu_helpers.dart';
import '../../widgets/section_groupbox.dart';
import '../../widgets/settings_header_actions.dart';
import '../../widgets/tag_list.dart';
import 'animated_view_mode_toggle.dart';

/// Below these toolbar widths the search hint is shortened.
const double _kLongSearchHintMinWidth = 460;
const double _kMediumSearchHintMinWidth = 400;

/// From this panel width Tags and Show only sit side by side, sharing one
/// fixed height: the tag list fills what Tags has left, and Show only scrolls
/// if large text makes it taller.
const double _kSideBySidePanelMinWidth = 640;
const double _kSideBySideGroupHeight = 264;

/// A "show only" option: its label, state and setter.
typedef _FilterOption = ({
  String label,
  bool Function(ActiveFiltersState state) isOn,
  void Function(GamesNotifier notifier, bool value) set,
});

final List<_FilterOption> _filterOptions = [
  (
    label: 'Deadline',
    isOn: (s) => s.showDeadlineOnly,
    set: (n, v) => n.setShowDeadlineOnly(v),
  ),
  (
    label: 'DLC',
    isOn: (s) => s.showDlcOnly,
    set: (n, v) => n.setShowDlcOnly(v),
  ),
  (
    label: 'Used',
    isOn: (s) => s.showUsedOnly,
    set: (n, v) => n.setShowUsedOnly(v),
  ),
  (
    label: 'No Tags',
    isOn: (s) => s.showNoTagsOnly,
    set: (n, v) => n.setShowNoTagsOnly(v),
  ),
  (
    label: 'No Pictures',
    isOn: (s) => s.showNoPicturesOnly,
    set: (n, v) => n.setShowNoPicturesOnly(v),
  ),
];

IconData _sortIconFor(GameSortMode mode) => switch (mode) {
  GameSortMode.deadlineFirst => Icons.schedule,
  GameSortMode.titleAZ || GameSortMode.titleZA => Icons.sort_by_alpha,
  GameSortMode.platformAZ || GameSortMode.platformZA => Icons.videogame_asset,
  GameSortMode.dateNewest => Icons.calendar_month,
  GameSortMode.dateOldest => Icons.history,
  GameSortMode.ratingHigh => Icons.trending_up,
  GameSortMode.ratingLow => Icons.trending_down,
};

class HomeHeader extends ConsumerStatefulWidget {
  const HomeHeader({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
    required this.isVeryNarrowLayout,
  });

  final TextEditingController searchController;
  final FocusNode searchFocusNode;

  /// Very narrow layouts have no title bar sync icon, so the header shows it.
  final bool isVeryNarrowLayout;

  @override
  ConsumerState<HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends ConsumerState<HomeHeader>
    with SingleTickerProviderStateMixin {
  bool _showFiltersPanel = false;
  final ScrollController _filtersScrollController = ScrollController();
  late final AnimationController _filterPanelController;
  String _tagSearchQuery = '';
  final _tagSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filterPanelController = AnimationController(
      vsync: this,
      duration: kFilterExpandAnimation,
    );
  }

  @override
  void dispose() {
    _tagSearchController.dispose();
    _filtersScrollController.dispose();
    _filterPanelController.dispose();
    super.dispose();
  }

  GamesNotifier get _notifier => ref.read(gamesProvider.notifier);

  void _toggleFilterPanel() {
    setState(() => _showFiltersPanel = !_showFiltersPanel);
    final target = _showFiltersPanel ? 1.0 : 0.0;
    final duration = _showFiltersPanel
        ? kFilterExpandAnimation
        : kFilterCollapseAnimation;
    _filterPanelController.animateTo(
      target,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : Duration(
              microseconds:
                  (duration.inMicroseconds *
                          (target - _filterPanelController.value).abs())
                      .round(),
            ),
      curve: kFilterPanelCurve,
    );
  }

  static int _activeFilterCount(
    ActiveFiltersState state,
    String? platformFilter,
  ) =>
      state.tagFilters.length +
      (platformFilter?.isNotEmpty == true ? 1 : 0) +
      _filterOptions.where((option) => option.isOn(state)).length;

  void _clearBoolFilters() {
    for (final option in _filterOptions) {
      option.set(_notifier, false);
    }
  }

  void _clearAllFilters() {
    widget.searchController.clear();
    _notifier.clearAllFilters();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final platformFilter = ref.watch(
      gamesProvider.select((s) => s.platformFilter),
    );
    final filters = ref.watch(activeFiltersProvider);
    final platform = Theme.of(context).platform;
    final showSync =
        widget.isVeryNarrowLayout ||
        platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS;

    // The header never takes more than about half the screen: the filter
    // panel scrolls below the toolbar, which stays put, so the library always
    // keeps room on short or large-text screens.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.55;
    // Sits on the page background like the settings page header, without a
    // raised surface or shadow; a bottom border separates it from the library.
    return Material(
      key: const ValueKey('home-header-surface'),
      color: theme.background,
      // Keep the inherited text style, as the raised bar did.
      textStyle: DefaultTextStyle.of(context).style,
      animationDuration: Duration.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.border)),
        ),
        child: Padding(
          // 6px of the side and bottom insets sit inside the toolbar and the
          // scrolling panel, so groupbox shadows are never clipped.
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: math.max(0, maxHeight - 14)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                  child: LayoutBuilder(
                    builder: (context, constraints) => _buildToolbar(
                      theme,
                      filters,
                      platformFilter: platformFilter,
                      showSync: showSync,
                      width: constraints.maxWidth,
                    ),
                  ),
                ),
                Flexible(
                  child: Scrollbar(
                    controller: _filtersScrollController,
                    child: SingleChildScrollView(
                      controller: _filtersScrollController,
                      primary: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizeTransition(
                            sizeFactor: _filterPanelController,
                            alignment: Alignment.topCenter,
                            child: FadeTransition(
                              opacity: _filterPanelController,
                              child: IgnorePointer(
                                ignoring: !_showFiltersPanel,
                                child: _buildFiltersPanel(
                                  theme,
                                  filters,
                                  platformFilter,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Toolbar: count, search, filters and view
  // ---------------------------------------------------------------------------

  Widget _buildToolbar(
    AppThemeData theme,
    ActiveFiltersState filters, {
    required String? platformFilter,
    required bool showSync,
    required double width,
  }) {
    final sortMode = ref.watch(gamesProvider.select((s) => s.sortMode));
    final viewMode = ref.watch(viewModeProvider);
    final slimListView = ref.watch(
      gameCardSettingsProvider.select((s) => s.slimListView),
    );
    const gap = SizedBox(width: kElementHSpacing);
    final selectedPlatform = platformFilter?.isNotEmpty == true
        ? GamePlatform.fromDisplayName(platformFilter!)
        : null;
    // On very narrow layouts the count spans a row of its own and holds sync
    // and the view toggle at its ends. Otherwise it leads the search row
    // as a plain label, with sync before it and the view toggle at the end.
    final stacked = widget.isVeryNarrowLayout;
    final sync = showSync ? _LibrarySyncButton(theme: theme) : null;
    final viewToggle = AnimatedViewModeToggle(
      theme: theme,
      isGridView: viewMode == GameListViewMode.grid,
      selectedListViewMode: resolveListViewDensityMode(
        slimListView: slimListView,
      ),
      onToggle: () => ref
          .read(viewModeProvider.notifier)
          .setViewMode(
            viewMode == GameListViewMode.grid
                ? GameListViewMode.list
                : GameListViewMode.grid,
          ),
      onSelectGridView: () => ref
          .read(viewModeProvider.notifier)
          .setViewMode(GameListViewMode.grid),
      onSelectListViewMode: (mode) =>
          ref.read(settingsProvider.notifier).setMany({
            ...listViewDensityModeSettings(mode),
            SettingsKeys.gameListViewMode: GameListViewMode.list,
          }),
    );
    final countLabel = stacked
        ? _GamesCount(
            theme: theme,
            expand: true,
            leading: sync,
            trailing: viewToggle,
          )
        : _GamesCount(theme: theme);
    final searchRow = Row(
      children: [
        if (!stacked) ...[
          if (sync != null) ...[sync, gap],
          countLabel,
          gap,
        ],
        Expanded(
          child: AppSearchField(
            theme: theme,
            controller: widget.searchController,
            focusNode: widget.searchFocusNode,
            hintText: width >= _kLongSearchHintMinWidth
                ? 'Search by title or key...'
                : width >= _kMediumSearchHintMinWidth
                ? 'Search games...'
                : 'Search...',
            onChanged: _notifier.setSearchQueryDebounced,
            onCleared: () => _notifier.setSearchQuery(''),
          ),
        ),
        gap,
        // Platform, sort and filters form one group, like settings headers.
        SettingsHeaderActions(
          key: const ValueKey('home-toolbar-actions'),
          theme: theme,
          children: [
            _IconMenuButton<String>(
              key: const ValueKey('home-platform-button'),
              theme: theme,
              tooltip:
                  'Platform: ${selectedPlatform?.displayName ?? 'All Platforms'}',
              highlighted: selectedPlatform != null,
              iconBuilder: (context, color, size) => selectedPlatform == null
                  ? Icon(
                      Icons.videogame_asset_outlined,
                      color: color,
                      size: size,
                    )
                  : PlatformIcon(
                      platform: selectedPlatform,
                      color: color,
                      size: size,
                    ),
              selected: platformFilter ?? '',
              entries: [
                (
                  value: '',
                  label: 'All Platforms',
                  icon: const Icon(Icons.videogame_asset_outlined, size: 18),
                ),
                for (final platform in GamePlatform.values)
                  (
                    value: platform.displayName,
                    label: platform.displayName,
                    icon: PlatformIcon(
                      platform: platform,
                      color: theme.textPrimary,
                      size: 18,
                    ),
                  ),
              ],
              onSelected: (value) =>
                  _notifier.setPlatformFilter(value.isEmpty ? null : value),
            ),
            _IconMenuButton<GameSortMode>(
              key: const ValueKey('home-sort-button'),
              theme: theme,
              tooltip: 'Sort: ${sortMode.displayName}',
              highlighted: sortMode != DefaultSettings.gameSortMode,
              iconBuilder: (context, color, size) =>
                  Icon(_sortIconFor(sortMode), color: color, size: size),
              selected: sortMode,
              entries: [
                for (final mode in GameSortMode.values)
                  (
                    value: mode,
                    label: mode.displayName,
                    icon: Icon(_sortIconFor(mode), size: 18),
                  ),
              ],
              onSelected: _notifier.setSortMode,
            ),
            _buildFiltersToggleButton(theme, filters, platformFilter),
          ],
        ),
        if (!stacked) ...[gap, viewToggle],
      ],
    );
    if (!stacked) return searchRow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [countLabel, const SizedBox(height: 8), searchRow],
    );
  }

  Widget _buildFiltersToggleButton(
    AppThemeData theme,
    ActiveFiltersState filters,
    String? platformFilter,
  ) {
    final filterCount = _activeFilterCount(filters, platformFilter);
    final hasActiveFilters = filterCount > 0;
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showFiltersContextMenu(details.globalPosition, theme, filters),
      child: AppNavigationButton(
        theme: theme,
        isSelected: _showFiltersPanel || hasActiveFilters,
        isEnabled: true,
        isHorizontal: true,
        hasNotification: hasActiveFilters,
        onTap: _toggleFilterPanel,
        iconData: _showFiltersPanel ? Icons.expand_less : Icons.tune,
        tooltipMessage: hasActiveFilters
            ? 'Filters ($filterCount active)'
            : 'Filters',
        selectedBackgroundColor: theme.accent.withValues(alpha: 0.30),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Filter panel (expandable): one groupbox per filter, each with its own clear
  // ---------------------------------------------------------------------------

  Widget _buildFiltersPanel(
    AppThemeData theme,
    ActiveFiltersState filters,
    String? platformFilter,
  ) {
    final selectedTagIds = filters.tagFilters.toSet();
    final query = _tagSearchQuery.toLowerCase();
    final matchingTags = ref
        .watch(tagsProvider)
        .where((tag) => query.isEmpty || tag.name.toLowerCase().contains(query))
        .toList();
    final hasOptions = _filterOptions.any((option) => option.isOn(filters));

    Widget group({
      required String id,
      required String title,
      required IconData icon,
      required IconData clearIcon,
      required String clearTooltip,
      required VoidCallback? onClear,
      required Widget child,
    }) => SectionGroupBox(
      key: ValueKey('home-filter-group-$id'),
      title: title,
      theme: theme,
      titleIcon: icon,
      titleLocation: SectionTitleLocation.top,
      headerCrossAxisAlignment: CrossAxisAlignment.center,
      headerBottomPadding: 8,
      trailing: IconButton(
        key: ValueKey('home-filter-clear-$id'),
        tooltip: clearTooltip,
        onPressed: onClear,
        icon: Icon(clearIcon, size: 20),
        color: theme.accent,
        visualDensity: VisualDensity.compact,
      ),
      child: child,
    );

    Widget optionsGroup({required bool fill}) => group(
      id: 'options',
      title: 'Show only',
      icon: Icons.filter_alt_outlined,
      clearIcon: Icons.filter_alt_off_outlined,
      clearTooltip: 'Clear options',
      onClear: hasOptions ? _clearBoolFilters : null,
      child: _scrollIf(
        fill,
        Wrap(
          key: const ValueKey('home-filter-options'),
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final option in _filterOptions)
              AppActionButton(
                label: option.label,
                theme: theme,
                selected: option.isOn(filters),
                onTap: () => option.set(_notifier, !option.isOn(filters)),
              ),
          ],
        ),
      ),
    );
    // Filling a fixed height, the tag list takes the space left below the
    // search; stacked, it caps its own height instead.
    Widget tagList({bool scrollable = false, double? maxHeight}) => TagList(
      tags: matchingTags,
      selectedTagIds: selectedTagIds,
      theme: theme,
      onTagToggled: _notifier.toggleTagFilter,
      scrollable: scrollable,
      maxHeight: maxHeight,
    );
    Widget tagsGroup({required bool fill}) => group(
      id: 'tags',
      title: selectedTagIds.isEmpty
          ? 'Tags'
          : 'Tags (${selectedTagIds.length})',
      icon: Icons.label_outline,
      clearIcon: Icons.label_off_outlined,
      clearTooltip: 'Clear tags',
      onClear: selectedTagIds.isEmpty
          ? null
          : () => _notifier.setTagFilters([]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            theme: theme,
            backgroundColor: Color.lerp(theme.surface, theme.background, 0.6),
            hintText: 'Search tags...',
            controller: _tagSearchController,
            onChanged: (value) => setState(() => _tagSearchQuery = value),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
          const SizedBox(height: 6),
          if (fill)
            Expanded(child: tagList(scrollable: true))
          else
            tagList(maxHeight: 150),
        ],
      ),
    );

    const gap = SizedBox.square(dimension: 8);
    final panel = LayoutBuilder(
      key: const ValueKey('home-filter-panel'),
      builder: (context, constraints) =>
          constraints.maxWidth >= _kSideBySidePanelMinWidth
          ? SizedBox(
              height: _kSideBySideGroupHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: tagsGroup(fill: true)),
                  gap,
                  SizedBox(width: 320, child: optionsGroup(fill: true)),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tagsGroup(fill: false),
                gap,
                optionsGroup(fill: false),
              ],
            ),
    );
    // The padding sits inside the clipping size animation, leaving room for
    // the groupbox shadows at the sides and bottom.
    final padded = Padding(
      key: const ValueKey('home-filter-panel-height'),
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
      child: panel,
    );
    return MediaQuery.disableAnimationsOf(context)
        ? padded
        : AnimatedSize(
            duration: kFilterExpandAnimation,
            curve: kFilterPanelCurve,
            alignment: Alignment.topCenter,
            child: padded,
          );
  }

  /// Scrolls [child] when it must fit a fixed height.
  static Widget _scrollIf(bool scroll, Widget child) =>
      scroll ? SingleChildScrollView(primary: false, child: child) : child;

  void _showFiltersContextMenu(
    Offset globalPosition,
    AppThemeData theme,
    ActiveFiltersState state,
  ) {
    final hasTagFilters = state.tagFilters.isNotEmpty;
    final hasBoolFilters = _filterOptions.any((option) => option.isOn(state));
    final hasAnyFilters =
        hasTagFilters ||
        hasBoolFilters ||
        ref.read(gamesProvider).platformFilter?.isNotEmpty == true;

    PopupMenuItem<String> item(
      String value,
      IconData icon,
      String label,
      bool enabled,
    ) {
      final color = enabled ? theme.textPrimary : theme.textHint;
      return PopupMenuItem<String>(
        value: value,
        enabled: enabled,
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: kElementHSpacing),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color),
              ),
            ),
          ],
        ),
      );
    }

    showAppMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: [
        item(
          'clear_tags',
          Icons.label_off_outlined,
          'Clear Tag Filters',
          hasTagFilters,
        ),
        item(
          'clear_options',
          Icons.filter_alt_off_outlined,
          'Clear Options',
          hasBoolFilters,
        ),
        const PopupMenuDivider(height: 1),
        item('clear_all', Icons.clear_all, 'Clear All Filters', hasAnyFilters),
      ],
    ).then((value) {
      switch (value) {
        case 'clear_tags':
          _notifier.setTagFilters([]);
        case 'clear_options':
          _clearBoolFilters();
        case 'clear_all':
          _clearAllFilters();
      }
    });
  }
}

/// The library size, or "12 / 263 Games" while filters narrow it, centered
/// in a full-width label with optional controls at either end.
class _GamesCount extends ConsumerWidget {
  const _GamesCount({
    required this.theme,
    this.leading,
    this.trailing,
    this.expand = false,
  });

  final AppThemeData theme;
  final Widget? leading;
  final Widget? trailing;

  /// Spans its row with the text centered; otherwise sizes to its content.
  final bool expand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = ref.watch(
      gamesProvider.select((s) => s.filteredGames.length),
    );
    final total = ref.watch(gamesProvider.select((s) => s.games.length));
    final text = Text(
      shown < total ? '$shown / $total Games' : '$total Games',
      style: TextStyle(color: theme.accent, fontWeight: FontWeight.w600),
      textAlign: TextAlign.center,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
    final hasControls = leading != null || trailing != null;
    // A min-size row keeps each control at its natural width; the toolbar
    // buttons otherwise fill the width they are offered.
    Widget control(Widget child) =>
        Row(mainAxisSize: MainAxisSize.min, children: [child]);
    return Container(
      key: const ValueKey('library-game-counter'),
      // Controls inside keep clear of the label's edges.
      padding: hasControls
          ? const EdgeInsets.all(4)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(theme.cornerRadius),
      ),
      child: expand
          // The text centers on the whole label, clear of the end controls,
          // whether or not both ends have one.
          ? Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 52),
                  child: text,
                ),
                if (leading != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: control(leading!),
                  ),
                if (trailing != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: control(trailing!),
                  ),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 6)],
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: hasControls ? 6 : 0,
                    ),
                    child: text,
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 6), trailing!],
              ],
            ),
    );
  }
}

/// One choice in an [_IconMenuButton] menu.
typedef _MenuEntry<T> = ({T value, String label, Widget icon});

/// A compact icon button that opens a menu of choices, the current one
/// checked, like the navigation theme menu.
class _IconMenuButton<T> extends StatefulWidget {
  const _IconMenuButton({
    super.key,
    required this.theme,
    required this.tooltip,
    required this.highlighted,
    required this.iconBuilder,
    required this.selected,
    required this.entries,
    required this.onSelected,
  });

  final AppThemeData theme;
  final String tooltip;

  /// Shown selected while the choice differs from the default.
  final bool highlighted;
  final Widget Function(BuildContext context, Color color, double size)
  iconBuilder;
  final T selected;
  final List<_MenuEntry<T>> entries;
  final ValueChanged<T> onSelected;

  @override
  State<_IconMenuButton<T>> createState() => _IconMenuButtonState<T>();
}

class _IconMenuButtonState<T> extends State<_IconMenuButton<T>> {
  final _controller = MenuController();
  final _buttonFocus = FocusNode();

  @override
  void dispose() {
    _buttonFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    // Large text never pushes the menu or its items past a narrow screen.
    final maxSize = Size(
      math.max(0, MediaQuery.sizeOf(context).width - 16),
      double.infinity,
    );
    return MenuAnchor(
      controller: _controller,
      animated: !MediaQuery.disableAnimationsOf(context),
      childFocusNode: _buttonFocus,
      consumeOutsideTap: true,
      useRootOverlay: true,
      reservedPadding: const EdgeInsets.all(8),
      alignmentOffset: const Offset(0, 4),
      style: appMenuStyle(
        theme,
        alignment: Alignment.bottomLeft,
      ).copyWith(maximumSize: WidgetStatePropertyAll(maxSize)),
      menuChildren: [
        for (final entry in widget.entries)
          MenuItemButton(
            style: MenuItemButton.styleFrom(maximumSize: maxSize),
            leadingIcon: IconTheme.merge(
              data: IconThemeData(color: theme.textPrimary),
              child: entry.icon,
            ),
            trailingIcon: entry.value == widget.selected
                ? Icon(Icons.check, size: 18, color: theme.accent)
                : const SizedBox(width: 18),
            onPressed: () => widget.onSelected(entry.value),
            child: Text(
              entry.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: entry.value == widget.selected
                    ? theme.accent
                    : theme.textPrimary,
              ),
            ),
          ),
      ],
      builder: (context, controller, _) => Focus(
        focusNode: _buttonFocus,
        child: AppNavigationButton(
          theme: theme,
          isSelected: widget.highlighted || controller.isOpen,
          isEnabled: true,
          isHorizontal: true,
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          iconBuilder: widget.iconBuilder,
          tooltipMessage: widget.tooltip,
          selectedBackgroundColor: theme.accent.withValues(alpha: 0.30),
        ),
      ),
    );
  }
}

class _LibrarySyncButton extends ConsumerWidget {
  const _LibrarySyncButton({required this.theme});

  final AppThemeData theme;

  (IconData, Color) _iconForStatus(DeviceSyncStatus status) => switch (status) {
    DeviceSyncStatus.discovering => (Icons.radar, theme.accent),
    DeviceSyncStatus.connecting => (Icons.link, theme.accent),
    DeviceSyncStatus.connected => (Icons.link, theme.secondary),
    DeviceSyncStatus.syncing => (Icons.sync, theme.accent),
    DeviceSyncStatus.error => (Icons.link_off, theme.error),
    DeviceSyncStatus.idle => (Icons.sync_disabled, theme.textSecondary),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(deviceSyncProvider).asData?.value;
    final enabled = sync?.enabled ?? false;
    final status = sync?.status ?? DeviceSyncStatus.idle;
    final statusText = sync?.statusMessage?.toLowerCase() ?? '';
    final busy =
        status == DeviceSyncStatus.syncing ||
        status == DeviceSyncStatus.discovering ||
        status == DeviceSyncStatus.connecting;
    // Unpair events show a broken link, matching the sync dialog; so do
    // peers whose database files differ, to signal out-of-sync.
    final (icon, color) =
        statusText.contains('removed its pairing') ||
            statusText.contains('device removed')
        ? (Icons.link_off, theme.textSecondary)
        : sync?.dbMismatchPeerIds.isNotEmpty ?? false
        ? (Icons.link_off, Colors.orange)
        : _iconForStatus(status);

    // Same button style as the view toggle at the label's other end.
    return AppNavigationButton(
      theme: theme,
      isSelected: false,
      isEnabled: true,
      isHorizontal: true,
      onTap: () => showDeviceSyncDialog(context),
      tooltipMessage: 'Device Sync',
      iconBuilder: (context, _, size) => busy
          ? SizedBox.square(
              dimension: size - 2,
              child: AppCircularProgressIndicator(
                color: enabled ? theme.secondary : theme.textSecondary,
                strokeWidth: 2,
              ),
            )
          : Icon(
              icon,
              color: enabled ? color : theme.textSecondary,
              size: size,
            ),
    );
  }
}
