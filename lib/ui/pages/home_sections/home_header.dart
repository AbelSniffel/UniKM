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
import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../dialogs/device_sync_dialog.dart';
import '../../dialogs/library_stats_dialog.dart';
import '../../widgets/app_action_button.dart';
import '../../widgets/app_scrollbar.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/device_sync_icon.dart';
import '../../widgets/background_pattern.dart';
import '../../widgets/platform_icon.dart';
import '../../widgets/platform_menu_button.dart';
import '../../widgets/popup_menu_helpers.dart';
import '../../widgets/section_groupbox.dart';
import '../../widgets/tag_list.dart';

/// Below these toolbar widths the search hint is shortened.
const double _kLongSearchHintMinWidth = 460;
const double _kMediumSearchHintMinWidth = 400;

/// The tag list scrolls past this height.
const double _kTagListMaxHeight = 112;

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
  // Only the filters button and the panel's pointer guard listen, so
  // toggling does not rebuild the toolbar and the whole filter panel.
  final _showFiltersPanel = ValueNotifier(false);
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
    _showFiltersPanel.dispose();
    _tagSearchController.dispose();
    _filtersScrollController.dispose();
    _filterPanelController.dispose();
    super.dispose();
  }

  GamesNotifier get _notifier => ref.read(gamesProvider.notifier);

  void _toggleFilterPanel() {
    final show = _showFiltersPanel.value = !_showFiltersPanel.value;
    final target = show ? 1.0 : 0.0;
    final duration = show ? kFilterExpandAnimation : kFilterCollapseAnimation;
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

  /// Filters set in the filter panel. The platform counts only while its
  /// button sits in the panel; on the toolbar it shows for itself.
  int _activeFilterCount(ActiveFiltersState state, String? platformFilter) =>
      state.tagFilters.length +
      _filterOptions.where((option) => option.isOn(state)).length +
      (widget.isVeryNarrowLayout && platformFilter?.isNotEmpty == true ? 1 : 0);

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
    // Styled like the settings section list: the navigation panel's color
    // and pattern, a little stronger than the page's, with a bottom border
    // and a soft shadow over the library.
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.border)),
        boxShadow: [
          BoxShadow(
            color: theme.border.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: PanelPatternSurface(
        strength: PanelPatternSurface.sidePanelStrength,
        child: Material(
          key: const ValueKey('home-header-surface'),
          type: MaterialType.transparency,
          // Keep the inherited text style, as the raised bar did.
          textStyle: DefaultTextStyle.of(context).style,
          child: Padding(
            // 6px of the side and bottom insets sit inside the toolbar and the
            // scrolling panel, so groupbox shadows are never clipped.
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(0, maxHeight - 14),
              ),
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
                    child: AppScrollbar(
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
                                child: ValueListenableBuilder(
                                  valueListenable: _showFiltersPanel,
                                  builder: (context, show, panel) =>
                                      IgnorePointer(
                                        ignoring: !show,
                                        child: panel,
                                      ),
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
    const gap = SizedBox(width: kElementHSpacing);
    final narrow = widget.isVeryNarrowLayout;
    // On very narrow layouts the count shares a row with sync and filters,
    // above a full-width search, and platform and sort move into the filter
    // panel. Otherwise one row holds them all, the search in the middle. The
    // view choice lives in the navigation panel's More menu.
    final sync = showSync ? _LibrarySyncButton(theme: theme) : null;
    final countLabel = _GamesCount(theme: theme);
    final search = AppSearchField(
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
    );
    final actions = _buttonRow(key: const ValueKey('home-toolbar-actions'), [
      if (!narrow) ..._buildPlatformAndSort(theme, platformFilter),
      _buildFiltersToggleButton(theme, filters, platformFilter),
    ]);
    if (!narrow) {
      return Row(
        children: [
          if (sync != null) ...[sync, gap],
          countLabel,
          gap,
          Expanded(child: search),
          gap,
          actions,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (sync != null) ...[sync, gap],
            Expanded(child: countLabel),
            gap,
            actions,
          ],
        ),
        const SizedBox(height: 8),
        search,
      ],
    );
  }

  /// Separate header buttons in a row, all as tall as the search bar.
  static Widget _buttonRow(List<Widget> children, {Key? key}) => SizedBox(
    height: kElementHeight,
    child: Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: kElementHSpacing,
      children: children,
    ),
  );

  /// The platform and sort menu buttons: on the toolbar, or [expanded] and
  /// named atop the filter panel on very narrow layouts.
  List<Widget> _buildPlatformAndSort(
    AppThemeData theme,
    String? platformFilter, {
    bool expanded = false,
  }) {
    final sortMode = ref.watch(gamesProvider.select((s) => s.sortMode));
    final selectedPlatform = platformFilter?.isNotEmpty == true
        ? platformFilter
        : null;
    // Only platforms in the library are offered; an active filter stays
    // listed even when no game uses it any more, so it can still be seen.
    final libraryPlatforms = ref.watch(libraryPlatformsProvider);
    final platforms = [
      ...libraryPlatforms,
      if (selectedPlatform != null &&
          !libraryPlatforms.contains(selectedPlatform))
        selectedPlatform,
    ];
    Widget platformIcon(String name, Color color, double size) => PlatformIcon(
      platform: GamePlatform.fromDisplayName(name),
      color: color,
      size: size,
    );
    return [
      IconMenuButton<String>(
        key: const ValueKey('home-platform-button'),
        theme: theme,
        expanded: expanded,
        tooltip: 'Platform: ${selectedPlatform ?? 'All Platforms'}',
        // Tabs in the filters panel; the default style on the toolbar.
        tabStyle: expanded,
        icon: (color, size) => selectedPlatform == null
            ? Icon(Icons.videogame_asset_outlined, color: color, size: size)
            : platformIcon(selectedPlatform, color, size),
        value: platformFilter ?? '',
        choices: [
          (
            '',
            'All Platforms',
            const Icon(Icons.videogame_asset_outlined, size: 18),
          ),
          for (final platform in platforms)
            (platform, platform, platformIcon(platform, theme.textPrimary, 18)),
        ],
        onSelected: (value) =>
            _notifier.setPlatformFilter(value.isEmpty ? null : value),
      ),
      IconMenuButton<GameSortMode>(
        key: const ValueKey('home-sort-button'),
        theme: theme,
        expanded: expanded,
        tooltip: 'Sort: ${sortMode.displayName}',
        tabStyle: expanded,
        icon: (color, size) =>
            Icon(_sortIconFor(sortMode), color: color, size: size),
        value: sortMode,
        choices: [
          for (final mode in GameSortMode.values)
            (mode, mode.displayName, Icon(_sortIconFor(mode), size: 18)),
        ],
        onSelected: _notifier.setSortMode,
      ),
    ];
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
      child: ValueListenableBuilder(
        valueListenable: _showFiltersPanel,
        builder: (context, show, _) => AppNavigationButton(
          theme: theme,
          isSelected: show || hasActiveFilters,
          isEnabled: true,
          isHorizontal: true,
          hasNotification: hasActiveFilters,
          onTap: _toggleFilterPanel,
          iconBuilder: (context, _, size) => Icon(
            show ? Icons.expand_less : Icons.tune,
            color: theme.accent,
            size: size,
          ),
          tooltipMessage: hasActiveFilters
              ? 'Filters ($filterCount active)'
              : 'Filters',
          selectedBackgroundColor: theme.accent.withValues(alpha: 0.30),
        ),
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

    // Both clear buttons share the elevated button style.
    Widget clearButton({
      required String id,
      required IconData icon,
      required String tooltip,
      required VoidCallback? onClear,
    }) => Tooltip(
      message: tooltip,
      child: ElevatedButton(
        key: ValueKey('home-filter-clear-$id'),
        onPressed: onClear,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(40, 40),
        ),
        child: Icon(icon, size: 20),
      ),
    );

    Widget group({
      required String id,
      required String title,
      required IconData icon,
      required Widget child,
      Widget? trailing,
      bool showTitle = true,
    }) => SectionGroupBox(
      key: ValueKey('home-filter-group-$id'),
      title: title,
      theme: theme,
      titleIcon: icon,
      titleLocation: SectionTitleLocation.top,
      headerCrossAxisAlignment: CrossAxisAlignment.center,
      headerBottomPadding: 8,
      showTitle: showTitle,
      trailing: trailing,
      child: child,
    );

    // The options sit straight on the header, lined up with the tags
    // groupbox's content (beside it, its top padding too). Only the toggles
    // wrap; Clear keeps its place.
    // Only the toggles wrap; Clear keeps its place at the end.
    final optionsGroup = Row(
      key: const ValueKey('home-filter-group-options'),
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: kElementHSpacing,
      children: [
        Expanded(
          child: Wrap(
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
        clearButton(
          id: 'options',
          icon: Icons.filter_alt_off_outlined,
          tooltip: 'Clear options',
          onClear: hasOptions ? _clearBoolFilters : null,
        ),
      ],
    );
    final tagsGroup = group(
      id: 'tags',
      title: 'Tags',
      icon: Icons.label_outline,
      showTitle: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: kElementHSpacing,
            children: [
              Expanded(
                child: AppSearchField(
                  theme: theme,
                  // A little translucent, so what is behind shows faintly.
                  backgroundColor: Color.lerp(
                    theme.surface,
                    theme.background,
                    0.6,
                  )?.withValues(alpha: 0.9),
                  hintText: 'Search tags...',
                  controller: _tagSearchController,
                  onChanged: (value) => setState(() => _tagSearchQuery = value),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
              clearButton(
                id: 'tags',
                icon: Icons.label_off_outlined,
                tooltip: 'Clear tags',
                onClear: selectedTagIds.isEmpty
                    ? null
                    : () => _notifier.setTagFilters([]),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TagList(
            tags: matchingTags,
            selectedTagIds: selectedTagIds,
            theme: theme,
            onTagToggled: _notifier.toggleTagFilter,
            maxHeight: _kTagListMaxHeight,
          ),
        ],
      ),
    );

    // Tags spans the full width, with Show only below it. Very narrow
    // toolbars leave platform and sort to share a row above them.
    final narrow = widget.isVeryNarrowLayout;
    final panel = Column(
      key: const ValueKey('home-filter-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: narrow
          ? [
              Row(
                key: const ValueKey('home-filter-sorters'),
                spacing: kElementHSpacing,
                children: [
                  for (final button in _buildPlatformAndSort(
                    theme,
                    platformFilter,
                    expanded: true,
                  ))
                    Expanded(
                      child: SizedBox(height: kElementHeight, child: button),
                    ),
                ],
              ),
              tagsGroup,
              optionsGroup,
            ]
          : [tagsGroup, optionsGroup],
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

    Widget item(IconData icon, String label, VoidCallback? onPressed) =>
        appMenuItem(
          theme,
          leading: Icon(icon, size: 18),
          onPressed: onPressed,
          child: Text(label),
        );

    showAppContextMenu(
      context: context,
      theme: theme,
      position: globalPosition,
      menuChildren: [
        item(
          Icons.label_off_outlined,
          'Clear Tag Filters',
          hasTagFilters ? () => _notifier.setTagFilters([]) : null,
        ),
        item(
          Icons.filter_alt_off_outlined,
          'Clear Options',
          hasBoolFilters ? _clearBoolFilters : null,
        ),
        appMenuDivider(theme),
        item(
          Icons.clear_all,
          'Clear All Filters',
          hasAnyFilters ? _clearAllFilters : null,
        ),
      ],
    );
  }
}

/// The library size, or "12 / 263 Games" while filters narrow it, as a
/// button that opens the library stats.
class _GamesCount extends ConsumerWidget {
  const _GamesCount({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = ref.watch(
      gamesProvider.select((s) => s.filteredGames.length),
    );
    final total = ref.watch(gamesProvider.select((s) => s.games.length));
    return Tooltip(
      message: 'Library stats',
      child: ElevatedButton(
        key: const ValueKey('library-game-counter'),
        onPressed: () =>
            showLibraryStatsDialog(context, ref.read(allGamesProvider)),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 40),
        ),
        child: Text(
          shown < total ? '$shown / $total Games' : '$total Games',
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _LibrarySyncButton extends ConsumerWidget {
  const _LibrarySyncButton({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The title bar's icon, so both buttons always agree.
    final (:icon, :color) = deviceSyncIcon(
      theme,
      ref.watch(deviceSyncProvider).asData?.value,
    );

    // Same button style as the view toggle.
    return AppNavigationButton(
      theme: theme,
      isSelected: false,
      isEnabled: true,
      isHorizontal: true,
      onTap: () => showDeviceSyncDialog(context),
      tooltipMessage: 'Device Sync',
      iconBuilder: (context, _, size) =>
          Icon(icon, color: color ?? theme.textSecondary, size: size),
    );
  }
}
