/// Home library filters: the Show only toggles and the tag filter. Very
/// narrow layouts show them in a panel below the toolbar, with platform and
/// sort on top; wider ones in a sidebar beside the library, where the tag
/// list fills the height.
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
import '../../widgets/section_groupbox.dart';
import '../../widgets/tag_list.dart';

/// The filter sidebar's width beside the library.
const double kHomeFilterSidebarWidth = 330;

/// In the panel below the toolbar the tag list scrolls past this height.
const double _kTagListMaxHeight = 112;

/// Below this height, scaled with the text, the sidebar scrolls with the tag
/// list capped as below the toolbar, rather than the tags filling it.
const double _kSidebarFillMinHeight = 260;

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

/// The platform and sort menu buttons: on the toolbar, or [expanded] and
/// named atop the filter panel on very narrow layouts.
List<Widget> buildHomePlatformAndSort(
  WidgetRef ref,
  AppThemeData theme,
  String? platformFilter, {
  bool expanded = false,
}) {
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
          notifier.setPlatformFilter(value.isEmpty ? null : value),
    ),
    IconMenuButton<GameSortMode>(
      key: const ValueKey('home-sort-button'),
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
      onSelected: notifier.setSortMode,
    ),
  ];
}

/// One groupbox per filter, each with its own clear button.
class HomeFiltersPanel extends ConsumerStatefulWidget {
  const HomeFiltersPanel({super.key, required this.sidebar});

  /// In the sidebar Show only leads and the tags fill the rest of the
  /// height. Below the toolbar platform and sort share a row on top, and the
  /// tags, capped in height, come before Show only.
  final bool sidebar;

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
    final hasOptions = homeFilterOptions.any((option) => option.isOn(filters));

    Widget clearButton(String id, IconData icon, VoidCallback? onClear) =>
        Tooltip(
          message: 'Clear $id',
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

    // The toggles sit straight on the panel, lined up with the tags
    // groupbox's content; only they wrap, Clear keeps its place at the end.
    final options = Row(
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
              for (final option in homeFilterOptions)
                AppActionButton(
                  label: option.label,
                  theme: theme,
                  selected: option.isOn(filters),
                  onTap: () => option.set(notifier, !option.isOn(filters)),
                ),
            ],
          ),
        ),
        clearButton(
          'options',
          Icons.filter_alt_off_outlined,
          hasOptions ? () => clearHomeOptionFilters(notifier) : null,
        ),
      ],
    );

    // When [fill]ing, the list takes the height left in the groupbox and
    // scrolls past it; otherwise it scrolls past a fixed cap.
    Widget tags({required bool fill}) {
      final list = TagList(
        tags: matchingTags,
        selectedTagIds: selectedTagIds,
        theme: theme,
        onTagToggled: notifier.toggleTagFilter,
        maxHeight: fill ? double.infinity : _kTagListMaxHeight,
      );
      return SectionGroupBox(
        key: const ValueKey('home-filter-group-tags'),
        title: 'Tags',
        theme: theme,
        // A top title, even hidden, lets the content fill a bounded height.
        titleLocation: SectionTitleLocation.top,
        showTitle: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
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
                    onChanged: (value) =>
                        setState(() => _tagSearchQuery = value),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
                clearButton(
                  'tags',
                  Icons.label_off_outlined,
                  selectedTagIds.isEmpty
                      ? null
                      : () => notifier.setTagFilters([]),
                ),
              ],
            ),
            if (fill) Flexible(child: list) else list,
          ],
        ),
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
          final panel = Column(
            key: const ValueKey('home-filter-panel'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              options,
              fill ? Expanded(child: tags(fill: true)) : tags(fill: false),
            ],
          );
          return fill
              ? panel
              : AppScrollbar(
                  controller: _scrollController,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    primary: false,
                    child: panel,
                  ),
                );
        },
      );
    }

    final platformFilter = ref.watch(
      gamesProvider.select((s) => s.filter.platformFilter),
    );
    // The padding sits inside the clipping height animation, leaving room
    // for the groupbox shadows at the sides and bottom.
    return AnimatedHeight(
      duration: kFilterExpandAnimation,
      curve: kFilterPanelCurve,
      child: Padding(
        key: const ValueKey('home-filter-panel-height'),
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
        child: Column(
          key: const ValueKey('home-filter-panel'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            Row(
              key: const ValueKey('home-filter-sorters'),
              spacing: kElementHSpacing,
              children: [
                for (final button in buildHomePlatformAndSort(
                  ref,
                  theme,
                  platformFilter,
                  expanded: true,
                ))
                  Expanded(
                    child: SizedBox(height: kElementHeight, child: button),
                  ),
              ],
            ),
            tags(fill: false),
            options,
          ],
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
class HomeFilterSidebarLayout extends ConsumerStatefulWidget {
  const HomeFilterSidebarLayout({
    super.key,
    required this.showSidebar,
    required this.child,
  });

  final bool showSidebar;

  /// The library.
  final Widget child;

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

class _HomeFilterSidebar extends ConsumerWidget {
  const _HomeFilterSidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return RepaintBoundary(
      key: const ValueKey('home-filter-sidebar'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: theme.border)),
        ),
        child: PanelPatternSurface(
          strength: PanelPatternSurface.sidePanelStrength,
          child: Material(
            type: MaterialType.transparency,
            textStyle: DefaultTextStyle.of(context).style,
            child: const Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 14, 14),
              child: HomeFiltersPanel(sidebar: true),
            ),
          ),
        ),
      ),
    );
  }
}
