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
import '../../widgets/horizontal_fold.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/background_pattern.dart';
import '../../widgets/platform_icon.dart';
import '../../widgets/platform_menu_button.dart';
import '../../widgets/tag_list.dart';

/// The filter sidebar's width beside the library: room for platform and sort
/// to name even their longest choices, such as "Humble Bundle".
const double kHomeFilterSidebarWidth = 380;

/// The opacity of the surface colour veiling the panel behind the whole
/// filter box: platform and sort, the tags, and Show only.
const double kHomeFilterBandAlpha = 0.60;

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
  return [
    IconMenuButton<String>(
      key: const ValueKey('home-platform-button'),
      expanded: true,
      tooltip: 'Platform: ${selectedPlatform ?? 'All Platforms'}',
      segment: true,
      icon: (platform, color, size) => platform.isEmpty
          ? Icon(Icons.videogame_asset_outlined, color: color, size: size)
          : PlatformIcon(
              platform: GamePlatform.fromDisplayName(platform),
              color: color,
              size: size,
            ),
      value: platformFilter ?? '',
      choices: [
        ('', 'All Platforms'),
        for (final platform in platforms) (platform, platform),
      ],
      onSelected: (value) =>
          notifier.setPlatformFilter(value.isEmpty ? null : value),
    ),
    IconMenuButton<GameSortMode>(
      key: const ValueKey('home-sort-button'),
      expanded: true,
      tooltip: 'Sort: ${sortMode.displayName}',
      segment: true,
      icon: (mode, color, size) =>
          Icon(_sortIconFor(mode), color: color, size: size),
      value: sortMode,
      choices: [
        for (final mode in GameSortMode.values) (mode, mode.displayName),
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

    // 12 px in from the sides, in the sidebar or the box below the toolbar.
    const inset = EdgeInsets.all(12);

    // A strip across the top or foot, with a line on its side facing the
    // tags. The veil under the whole box is shared with the tags.
    Widget band(Widget child, {required bool top}) {
      final line = BorderSide(color: theme.border);
      return DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: top ? Border(bottom: line) : Border(top: line),
        ),
        child: Padding(padding: inset, child: child),
      );
    }

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
              // Clears the chosen tags, unfolding while there are some.
              actions: [
                HorizontalFold(
                  child: selectedTagIds.isEmpty
                      ? null
                      : IconButton(
                          key: const ValueKey('home-filter-clear-tags'),
                          tooltip: 'Clear tags',
                          padding: EdgeInsets.zero,
                          // A light secondary tint makes it stand out, and
                          // lets the search's border and glow show through.
                          style: IconButton.styleFrom(
                            backgroundColor: theme.secondary.withValues(
                              alpha: 0.18,
                            ),
                          ),
                          icon: Icon(
                            Icons.label_off_outlined,
                            color: theme.secondary,
                          ),
                          onPressed: () => notifier.setTagFilters([]),
                        ),
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
      return Material(
        color: theme.surface.withValues(alpha: kHomeFilterBandAlpha),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            band(sorters, top: true),
            if (fill) Expanded(child: box) else box,
            band(options, top: false),
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

    // Below the toolbar, laid out as in the sidebar, in a box of its own
    // as the sidebar is: lined up with the search bar's sides, a gap above
    // the header's foot, rounded like the game cards and outlined.
    final radius = BorderRadius.circular(theme.cornerRadius);
    return AnimatedHeight(
      duration: kFilterExpandAnimation,
      curve: kFilterPanelCurve,
      child: Padding(
        key: const ValueKey('home-filter-panel-height'),
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.all(color: theme.border),
            borderRadius: radius,
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: KeyedSubtree(
              key: const ValueKey('home-filter-panel'),
              child: filterBox(fill: false),
            ),
          ),
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
              // As far from the top and foot as the library's cards are.
              Positioned(
                top: _kSidebarGap,
                right: kHomeFilterSidebarWidth * (shown - 1),
                bottom: _kSidebarGap,
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

/// The sidebar's gap above and below it: the library's padding, so it
/// lines up with the cards.
const double _kSidebarGap = 12;

class const _HomeFilterSidebar() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    // Rounded on the library's side as the game cards are.
    final radius = BorderRadius.horizontal(
      left: Radius.circular(theme.cornerRadius),
    );
    return RepaintBoundary(
      key: const ValueKey('home-filter-sidebar'),
      // The outline, drawn over the sidebar's surface, which would
      // otherwise cover it.
      child: CustomPaint(
        foregroundPainter: _SidebarOutline(radius, theme.border),
        // The navigation panel's surface, as the header and settings
        // section list have.
        child: ClipRRect(
          borderRadius: radius,
          child: PanelPatternSurface(
            child: Material(
              type: MaterialType.transparency,
              textStyle: DefaultTextStyle.of(context).style,
              child: const HomeFiltersPanel(sidebar: true),
            ),
          ),
        ),
      ),
    );
  }
}

/// The sidebar's outline on its top, library side and foot, but not along
/// the window's edge: a uniform border's right side, pushed past the edge
/// and clipped away.
class const _SidebarOutline(final BorderRadius radius, final Color color)
    extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas
      ..save()
      ..clipRect(rect)
      ..drawRRect(
        radius
            .toRRect(Rect.fromLTRB(0, 0, size.width + 1, size.height))
            .deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = color,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_SidebarOutline old) =>
      old.radius != radius || old.color != color;
}
