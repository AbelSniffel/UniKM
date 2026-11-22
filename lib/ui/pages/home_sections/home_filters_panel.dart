/// Home library filters: platform and sort, the tag filter and the Show only
/// toggles, laid out alike in a sidebar beside the library, where the tag
/// list fills the height, or on very narrow layouts in a panel below the
/// toolbar.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/platform_patterns.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/animated_height.dart';
import '../../widgets/app_action_button.dart';
import '../../widgets/app_scrollbar.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/background_pattern.dart';
import '../../widgets/platform_icon.dart';
import '../../widgets/platform_menu_button.dart';
import '../../widgets/tag_list.dart';

/// The filter sidebar's width beside the library: room for platform and sort
/// to name even their longest choices, such as "Humble Bundle".
const double kHomeFilterSidebarWidth = 380;

/// The opacity of the surface colour veiling the panel behind the strips
/// above and below the tags (platform and sort, and Show only), so they stand
/// a little apart from the tags on the panel's own surface.
const double kHomeFilterBandAlpha = 0.75;

/// In the panel below the toolbar the tag list scrolls past this height.
const double _kTagListMaxHeight = 112;

/// Below this height, scaled with the text, the sidebar scrolls with the tag
/// list capped as below the toolbar, rather than the tags filling it. It
/// leaves the list at least that cap beside the platform and sort band, the
/// search and the Show only band (two rows of toggles in the sidebar).
const double _kSidebarFillMinHeight = 340;

/// A "show only" option: its label, state and setter.
typedef HomeFilterOption = ({
  String label,
  bool Function(LibraryFilter state) isOn,
  void Function(GamesNotifier notifier, bool value) set,
});

final List<HomeFilterOption> homeFilterOptions = [
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

/// Turns every Show only option off.
void clearHomeOptionFilters(GamesNotifier notifier) {
  for (final option in homeFilterOptions) {
    option.set(notifier, false);
  }
}

/// Opens or closes a filter reveal, taking only the time the remaining
/// distance needs, so reversing midway stays smooth.
void animateHomeFilterReveal(
  BuildContext context,
  AnimationController controller, {
  required bool show,
}) {
  final target = show ? 1.0 : 0.0;
  final duration = show ? kFilterExpandAnimation : kFilterCollapseAnimation;
  controller.animateTo(
    target,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(
            microseconds:
                (duration.inMicroseconds * (target - controller.value).abs())
                    .round(),
          ),
    curve: kFilterPanelCurve,
  );
}

IconData _sortIconFor(GameSortMode mode) => switch (mode) {
  GameSortMode.deadlineFirst => Icons.schedule,
  GameSortMode.titleAZ || GameSortMode.titleZA => Icons.sort_by_alpha,
  GameSortMode.platformAZ || GameSortMode.platformZA => Icons.videogame_asset,
  GameSortMode.dateNewest => Icons.calendar_month,
  GameSortMode.dateOldest => Icons.history,
  GameSortMode.ratingHigh => Icons.trending_up,
  GameSortMode.ratingLow => Icons.trending_down,
};

/// The platform and sort menu buttons atop the filters, sharing the width
/// and naming their choices where the names fit.
List<Widget> _buildHomePlatformAndSort(
  WidgetRef ref,
  AppThemeData theme,
  String? platformFilter,
) {
  final notifier = ref.read(gamesProvider.notifier);
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
      expanded: true,
      tooltip: 'Platform: ${selectedPlatform ?? 'All Platforms'}',
      segment: true,
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
          notifier.setPlatformFilter(value.isEmpty ? null : value),
    ),
    IconMenuButton<GameSortMode>(
      key: const ValueKey('home-sort-button'),
      expanded: true,
      tooltip: 'Sort: ${sortMode.displayName}',
      segment: true,
      icon: (color, size) =>
          Icon(_sortIconFor(sortMode), color: color, size: size),
      value: sortMode,
      choices: [
        for (final mode in GameSortMode.values)
          (mode, mode.displayName, Icon(_sortIconFor(mode), size: 18)),
      ],
      onSelected: notifier.setSortMode,
    ),
  ];
}

/// One groupbox: platform and sort across its top, the tag filter, with its
/// clear button beside the search, and the Show only options across its
/// foot.
class const HomeFiltersPanel({
  super.key,

  /// In the sidebar the groupbox fills the height, its tag list taking what
  /// the options leave. Below the toolbar the tag list is capped in height.
  required final bool sidebar,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<HomeFiltersPanel> createState() => _HomeFiltersPanelState();
}

class _HomeFiltersPanelState extends ConsumerState<HomeFiltersPanel> {
  final _tagSearchController = TextEditingController();
  final _scrollController = ScrollController();
  String _tagSearchQuery = '';

  @override
  void dispose() {
    _tagSearchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final filters = ref.watch(activeFiltersProvider);
    final notifier = ref.read(gamesProvider.notifier);
    final selectedTagIds = filters.tagFilters.toSet();
    final query = _tagSearchQuery.toLowerCase();
    final matchingTags = ref
        .watch(tagsProvider)
        .where((tag) => tag.name.toLowerCase().contains(query))
        .toList();

    // The Filters button's menu clears them all at once.
    final options = Wrap(
      key: const ValueKey('home-filter-options'),
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final option in homeFilterOptions)
          AppActionButton(
            label: option.label,
            selected: option.isOn(filters),
            onTap: () => option.set(notifier, !option.isOn(filters)),
          ),
      ],
    );

    // In from the sides: the sidebar's 12 px, or below the toolbar its own
    // 14 px, so everything lines up with the search bar.
    final inset = EdgeInsets.symmetric(
      horizontal: widget.sidebar ? 12 : 14,
      vertical: 12,
    );

    // A strip across the top or foot, veiling the panel's surface, which
    // the tags between the strips keep.
    Widget band(Widget child) => Material(
      color: theme.surface.withValues(alpha: kHomeFilterBandAlpha),
      child: Padding(padding: inset, child: child),
    );

    // Platform and sort share the box's width, each naming its choice when
    // the name fits.
    final platformFilter = ref.watch(
      gamesProvider.select((s) => s.filter.platformFilter),
    );
    final sorters = SizedBox(
      height: kElementHeight,
      child: MenuButtonGroup(
        key: const ValueKey('home-filter-sorters'),
        children: _buildHomePlatformAndSort(ref, theme, platformFilter),
      ),
    );

    // Platform and sort across the top, the tag search and list, then Show
    // only across the foot. When [fill]ing, the list takes the height left
    // and scrolls past it, so the options stay in view; otherwise it scrolls
    // past a fixed cap.
    Widget filterBox({required bool fill}) {
      final list = TagList(
        tags: matchingTags,
        selectedTagIds: selectedTagIds,
        theme: theme,
        onTagToggled: notifier.toggleTagFilter,
        maxHeight: fill ? double.infinity : _kTagListMaxHeight,
      );
      final tags = Padding(
        padding: inset,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            AppSearchField(
              hintText: 'Search tags...',
              controller: _tagSearchController,
              onChanged: (value) => setState(() => _tagSearchQuery = value),
              // Clears the chosen tags, shown only while there are some.
              actions: [
                if (selectedTagIds.isNotEmpty)
                  IconButton(
                    key: const ValueKey('home-filter-clear-tags'),
                    tooltip: 'Clear tags',
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.label_off_outlined, color: theme.accent),
                    onPressed: () => notifier.setTagFilters([]),
                  ),
              ],
            ),
            if (fill) Flexible(child: list) else list,
          ],
        ),
      );
      final box = KeyedSubtree(
        key: const ValueKey('home-filter-group-tags'),
        child: tags,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          band(sorters),
          if (fill) Expanded(child: box) else box,
          band(options),
        ],
      );
    }

    if (widget.sidebar) {
      return LayoutBuilder(
        builder: (context, constraints) {
          // Short windows, such as a phone held sideways, scroll the sidebar
          // with the tags capped as below the toolbar.
          final fill =
              constraints.maxHeight >=
              MediaQuery.textScalerOf(context).scale(_kSidebarFillMinHeight);
          return fill
              ? filterBox(fill: true)
              : AppScrollbar(
                  controller: _scrollController,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    primary: false,
                    child: filterBox(fill: false),
                  ),
                );
        },
      );
    }

    // Below the toolbar, laid out as in the sidebar, edge to edge, with a
    // line parting it from the toolbar as the header's border parts the
    // sidebar from the header.
    return AnimatedHeight(
      duration: kFilterExpandAnimation,
      curve: kFilterPanelCurve,
      child: DecoratedBox(
        key: const ValueKey('home-filter-panel-height'),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.border)),
        ),
        child: KeyedSubtree(
          key: const ValueKey('home-filter-panel'),
          child: filterBox(fill: false),
        ),
      ),
    );
  }
}

/// The library with the filters in a sidebar at its right, on layouts wider
/// than very narrow; otherwise the library alone. The sidebar slides open and
/// closed with the toolbar's filters button, pushing the library's edge along
/// with it, and is styled like the settings section list.
///
/// The sidebar moves as a layer of its own, so the slide never repaints it;
/// only the library is laid out anew as it narrows or widens.
class const HomeFilterSidebarLayout({
  super.key,
  required final bool showSidebar,

  /// The library.
  required final Widget child,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<HomeFilterSidebarLayout> createState() =>
      _HomeFilterSidebarLayoutState();
}

class _HomeFilterSidebarLayoutState
    extends ConsumerState<HomeFilterSidebarLayout>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool _open(bool? open) =>
      homeFiltersOpen(open, veryNarrow: !widget.showSidebar);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: kFilterExpandAnimation,
      value: _open(ref.read(homeFiltersOpenProvider)) ? 1 : 0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool?>(
      homeFiltersOpenProvider,
      (_, open) =>
          animateHomeFilterReveal(context, _controller, show: _open(open)),
    );
    final open = _open(ref.watch(homeFiltersOpenProvider));
    // Built once here, so each frame of the slide only moves them.
    final library = widget.child;
    final sidebar = ExcludeFocus(
      excluding: !open,
      child: IgnorePointer(ignoring: !open, child: const _HomeFilterSidebar()),
    );
    // The library keeps its place in the stack, so crossing the very narrow
    // breakpoint keeps its state. The stack clips the sidebar as it slides
    // out past its edge.
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final shown = widget.showSidebar ? _controller.value : 0.0;
        return Stack(
          children: [
            Positioned.fill(
              right: kHomeFilterSidebarWidth * shown,
              child: library,
            ),
            if (widget.showSidebar)
              Positioned(
                top: 0,
                right: kHomeFilterSidebarWidth * (shown - 1),
                bottom: 0,
                width: kHomeFilterSidebarWidth,
                // Kept while closed, so the tag search keeps its text.
                child: Visibility(
                  visible: shown > 0,
                  maintainState: true,
                  child: sidebar,
                ),
              ),
          ],
        );
      },
    );
  }
}

class const _HomeFilterSidebar() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return RepaintBoundary(
      key: const ValueKey('home-filter-sidebar'),
      // The line facing the library, drawn over the sidebar's surface,
      // which would otherwise cover it.
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: theme.border)),
        ),
        // The navigation panel's surface, as the header and settings
        // section list have.
        child: PanelPatternSurface(
          child: Material(
            type: MaterialType.transparency,
            textStyle: DefaultTextStyle.of(context).style,
            child: const HomeFiltersPanel(sidebar: true),
          ),
        ),
      ),
    );
  }
}
