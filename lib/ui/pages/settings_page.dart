/// Settings page - app configuration
/// Matches the original Python SettingsPage with 5+ sections
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/settings/settings_model.dart';
import '../widgets/hover_builder.dart';
import '../widgets/nav_button_group.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../widgets/app_search_field.dart';
import '../widgets/app_tab_bar.dart';
import '../widgets/search_highlight.dart';
import '../widgets/groupbox_family_title.dart';
import '../widgets/settings_section_grid.dart';
import '../widgets/settings_section_family.dart';
import 'settings_sections/settings_sections.dart';

/// Every section widget shares this constructor shape, so the definitions
/// below pass constructor tear-offs.
typedef _SettingsSectionBuilder =
    Widget Function({
      required AppThemeData theme,
      required String searchQuery,
      required bool Function(String) matchesSearch,
    });

typedef _SectionExtraMatch =
    bool Function(WidgetRef ref, bool Function(String) matchesSearch);

class _SettingsSectionDefinition {
  const _SettingsSectionDefinition({
    required this.id,
    required this.railLabel,
    required this.headerTitle,
    required this.icon,
    required this.searchGroups,
    required this.builder,
    this.extraMatch,
    this.platformSearchGroups,
  });

  final String id;
  final String railLabel;
  final String headerTitle;
  final IconData icon;
  final List<SettingsSearchGroup> searchGroups;
  final List<SettingsSearchGroup> Function(TargetPlatform)?
  platformSearchGroups;
  final _SettingsSectionBuilder builder;
  final _SectionExtraMatch? extraMatch;

  bool shouldShow({
    required WidgetRef ref,
    required TargetPlatform platform,
    required bool Function(String) matchesSearch,
    required bool showOnlyMatches,
  }) {
    if (!showOnlyMatches) return true;

    return matchesAnySettingsSearchGroup(
          matchesSearch: matchesSearch,
          groups: platformSearchGroups?.call(platform) ?? searchGroups,
        ) ||
        (extraMatch?.call(ref, matchesSearch) ?? false);
  }
}

final List<_SettingsSectionDefinition> _settingsSections = [
  _SettingsSectionDefinition(
    id: 'appearance',
    railLabel: 'Appearance',
    headerTitle: 'Appearance',
    icon: Icons.palette,
    searchGroups: AppearanceSection.searchGroups,
    extraMatch: (ref, matchesSearch) {
      ref.watch(customThemesJsonProvider);
      return ref
          .read(themeProvider.notifier)
          .getAllThemes()
          .any((themeData) => matchesSearch(themeData.name));
    },
    builder: AppearanceSection.new,
  ),
  _SettingsSectionDefinition(
    id: 'navigation',
    railLabel: 'Navigation',
    headerTitle: 'Navigation Panel',
    icon: Icons.view_sidebar,
    searchGroups: NavigationSection.searchGroups,
    builder: NavigationSection.new,
  ),
  _SettingsSectionDefinition(
    id: 'cards',
    railLabel: 'Game Card',
    headerTitle: 'Game Card Visual',
    icon: Icons.style,
    searchGroups: const [],
    platformSearchGroups: CardDisplaySection.searchGroupsFor,
    builder: CardDisplaySection.new,
  ),
  _SettingsSectionDefinition(
    id: 'database',
    railLabel: 'Database',
    headerTitle: 'Database',
    icon: Icons.storage,
    searchGroups: [
      DatabaseSection.dataManagementSearchGroup,
      DatabaseSection.databaseSyncSearchGroup,
      DatabaseSection.keyVisibilitySearchGroup,
    ],
    builder: DatabaseSection.new,
  ),
  _SettingsSectionDefinition(
    id: 'tags',
    railLabel: 'Tags',
    headerTitle: 'Tags',
    icon: Icons.label,
    searchGroups: [
      TagsSection.customTagsSearchGroup,
      TagsSection.steamTagsSearchGroup,
    ],
    extraMatch: (ref, matchesSearch) =>
        TagsSection.isMaintenanceAvailable(
          cleanupDone: ref.watch(legacyDefaultTagsCleanupDoneProvider),
          customTagNames: ref
              .watch(tagsProvider)
              .where((tag) => !tag.isSteamTag)
              .map((tag) => tag.name),
        ) &&
        TagsSection.maintenanceSearchGroup.indexTexts.any(matchesSearch),
    builder: TagsSection.new,
  ),
  _SettingsSectionDefinition(
    id: 'notifications',
    railLabel: 'Notifications',
    headerTitle: 'Notifications',
    icon: Icons.notifications,
    searchGroups: [NotificationsSection.typesSearchGroup],
    builder: NotificationsSection.new,
  ),
  _SettingsSectionDefinition(
    id: 'updates',
    railLabel: 'Updates',
    headerTitle: 'Updates',
    icon: Icons.download_rounded,
    searchGroups: UpdatesSection.searchGroups,
    builder: UpdatesSection.new,
  ),
  _SettingsSectionDefinition(
    id: 'advanced',
    railLabel: 'Advanced',
    headerTitle: 'Advanced',
    icon: Icons.settings_applications,
    searchGroups: [
      AdvancedSection.systemSearchGroup,
      if (AdvancedSection.showExperimentalSettings)
        AdvancedSection.experimentalSearchGroup,
    ],
    builder: AdvancedSection.new,
  ),
];

final List<(String, String, IconData)> _settingsRailSections = [
  ('all', 'All', Icons.dashboard_customize),
  ..._settingsSections.map(
    (section) => (section.id, section.railLabel, section.icon),
  ),
];

/// Space around the section button group inside the rail.
const double _settingsRailOuterPadding = 8;

/// A section button's width when only its icon shows.
const double _settingsRailCollapsedButtonExtent = 40;

/// Slack on the measured label, which uses a fallback font, so none is cut.
const double _settingsRailLabelWidthBuffer = 24;

// The collapse toggle at the foot of the rail.
const double _settingsRailToggleVerticalPadding = 8;
const double _settingsRailToggleHeight =
    (_settingsRailToggleVerticalPadding * 2) + kIconSize;

final double _settingsRailMaxLabelWidth = _measureSettingsRailMaxLabelWidth();

/// An expanded section button: the longest label under its icon, plus the
/// button's own padding.
final double _settingsRailExpandedButtonWidth = math.max(
  _settingsRailCollapsedButtonExtent,
  _settingsRailMaxLabelWidth + 24 + _settingsRailLabelWidthBuffer,
);

/// The rail's width: a button plus its group and outer padding.
double _settingsRailWidth({required bool collapsed}) =>
    (collapsed
        ? _settingsRailCollapsedButtonExtent
        : _settingsRailExpandedButtonWidth) +
    (_settingsRailOuterPadding + NavButtonGroup.padding) * 2;

/// Phones and very narrow windows always collapse the rail.
bool _settingsRailForceCollapsed(BuildContext context, bool veryNarrow) {
  final platform = Theme.of(context).platform;
  return veryNarrow ||
      platform == TargetPlatform.android ||
      platform == TargetPlatform.iOS;
}

double _measureSettingsRailMaxLabelWidth() {
  final painter = TextPainter(textDirection: TextDirection.ltr, maxLines: 1);
  var maxWidth = 0.0;

  for (final (_, label, _) in _settingsRailSections) {
    painter.text = TextSpan(text: label, style: const TextStyle(fontSize: 14));
    painter.layout();
    if (painter.width > maxWidth) maxWidth = painter.width;
  }

  return maxWidth;
}

/// Settings page
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _searchController = TextEditingController();
  final _contentScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final savedQuery = ref.read(settingsPageSearchQueryProvider);
    if (savedQuery.isNotEmpty) {
      _searchController.value = TextEditingValue(
        text: savedQuery,
        selection: TextSelection.collapsed(offset: savedQuery.length),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _contentScrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_contentScrollController.hasClients) _contentScrollController.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsPageSearchQueryProvider, (_, _) => _scrollToTop());
    ref.listen(settingsPageSelectedSectionProvider, (_, _) => _scrollToTop());
    final selectedSection = ref.watch(settingsPageSelectedSectionProvider);
    final searchQuery = ref.watch(settingsPageSearchQueryProvider);
    final isSearching = searchQuery.isNotEmpty;
    final effectiveSection = searchQuery.isNotEmpty ? 'all' : selectedSection;
    final selectedSectionDefinition = _selectedSectionDefinitionFor(
      selectedSection,
    );

    bool matchesSearch(String text) => settingsSearchMatches(searchQuery, text);

    // Created outside the layout callback: a resize then reuses these widgets,
    // so the page lays out again at the new width without rebuilding. The
    // rail changes only when the width crosses the very narrow breakpoint.
    _SettingsSectionRail rail({required bool veryNarrow}) =>
        _SettingsSectionRail(
          selectedSection: selectedSection,
          isSearching: isSearching,
          isVeryNarrowLayout: veryNarrow,
          onSectionSelected: (sectionId) => ref
              .read(settingsPageSelectedSectionProvider.notifier)
              .set(sectionId),
        );
    final wideRail = rail(veryNarrow: false);
    final narrowRail = rail(veryNarrow: true);
    final body = _SettingsPageBody(
      sectionIndex: _settingsRailSections.indexWhere(
        (section) => section.$1 == effectiveSection,
      ),
      scrollController: _contentScrollController,
      searchController: _searchController,
      searchQuery: searchQuery,
      onSearchChanged: (value) => ref
          .read(settingsPageSearchQueryProvider.notifier)
          .set(value.trim().toLowerCase()),
      sections: effectiveSection == 'all'
          ? _settingsSections
          : [?selectedSectionDefinition],
      matchesSearch: matchesSearch,
      showOnlyMatches: searchQuery.isNotEmpty,
    );

    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          constraints.maxWidth < kVeryNarrowLayoutBreakpoint
              ? narrowRail
              : wideRail,
          body,
        ],
      ),
    );
  }

  _SettingsSectionDefinition? _selectedSectionDefinitionFor(String sectionId) {
    for (final section in _settingsSections) {
      if (section.id == sectionId) return section;
    }

    return null;
  }
}

class _SettingsSectionRail extends ConsumerWidget {
  const _SettingsSectionRail({
    required this.selectedSection,
    required this.isSearching,
    required this.isVeryNarrowLayout,
    required this.onSectionSelected,
  });

  final String selectedSection;
  final bool isSearching;
  final bool isVeryNarrowLayout;
  final ValueChanged<String> onSectionSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final forceCollapsed = _settingsRailForceCollapsed(
      context,
      isVeryNarrowLayout,
    );
    final collapsed =
        forceCollapsed ||
        ref.watch(
          appShellSettingsProvider.select(
            (s) => s.settingsSectionPanelCollapsed,
          ),
        );
    return RepaintBoundary(
      child: AnimatedContainer(
        duration: kNavPanelMotionAnimation,
        curve: kNavPanelMotionCurve,
        width: _settingsRailWidth(collapsed: collapsed),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.surface,
            border: Border(right: BorderSide(color: theme.border)),
            boxShadow: [
              BoxShadow(
                color: theme.border.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  key: const ValueKey('settings-section-navigation'),
                  padding: const EdgeInsets.all(_settingsRailOuterPadding),
                  children: [
                    NavButtonGroup(
                      theme: theme,
                      isHorizontal: false,
                      children: [
                        for (final (id, label, icon) in _settingsRailSections)
                          _SettingsSectionButton(
                            key: ValueKey<String>('settings-rail-$id'),
                            theme: theme,
                            icon: icon,
                            label: label,
                            isSelected: !isSearching && selectedSection == id,
                            isCollapsed: collapsed,
                            isEnabled: !isSearching,
                            onTap: () => onSectionSelected(id),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!forceCollapsed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Tooltip(
                    message: collapsed
                        ? 'Expand section list'
                        : 'Collapse section list',
                    child: HoverBuilder(
                      cursor: SystemMouseCursors.click,
                      builder: (context, hovered) => GestureDetector(
                        onTap: () => ref
                            .read(settingsProvider.notifier)
                            .setSetting(
                              SettingsKeys.settingsSectionPanelCollapsed,
                              !collapsed,
                            ),
                        child: AnimatedContainer(
                          duration: kNavPanelMotionAnimation,
                          curve: kNavPanelMotionCurve,
                          width: collapsed
                              ? _settingsRailCollapsedButtonExtent
                              : _settingsRailExpandedButtonWidth,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                            vertical: _settingsRailToggleVerticalPadding,
                          ),
                          decoration: BoxDecoration(
                            color: hovered
                                ? theme.navItemHover
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(
                              math.min(
                                theme.cornerRadius * 1.25,
                                _settingsRailToggleHeight / 2,
                              ),
                            ),
                          ),
                          child: AnimatedSwitcher(
                            duration: kNavPanelMotionAnimation,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: ScaleTransition(
                                    scale: animation,
                                    child: child,
                                  ),
                                ),
                            child: Icon(
                              collapsed
                                  ? Icons.chevron_right
                                  : Icons.chevron_left,
                              key: ValueKey(collapsed),
                              color: theme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsPageBody extends ConsumerWidget {
  const _SettingsPageBody({
    required this.sectionIndex,
    required this.scrollController,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.sections,
    required this.matchesSearch,
    this.showOnlyMatches = false,
  });

  final int sectionIndex;
  final ScrollController scrollController;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final List<_SettingsSectionDefinition> sections;
  final bool Function(String) matchesSearch;
  final bool showOnlyMatches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    final searchField = Container(
      key: const ValueKey<String>('settings-search-container'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: AppSearchField(
        theme: theme,
        controller: searchController,
        hintText: 'Search settings...',
        onChanged: onSearchChanged,
      ),
    );

    // Filter whole sections before arranging their connected groupboxes.
    final visibleSections = sections
        .where(
          (s) => s.shouldShow(
            ref: ref,
            platform: Theme.of(context).platform,
            matchesSearch: matchesSearch,
            showOnlyMatches: showOnlyMatches,
          ),
        )
        .toList(growable: false);
    // As above, only the column count follows the width; the section widgets
    // are reused by each layout pass.
    final sectionCards = [
      for (final section in visibleSections)
        RepaintBoundary(
          key: ValueKey('settings-section-card-${section.id}'),
          child: SettingsSectionFamily(
            theme: theme,
            header: GroupBoxFamilyTitle(
              key: ValueKey<String>(
                'settings-section-header-${section.headerTitle}',
              ),
              theme: theme,
              title: section.headerTitle,
              icon: section.icon,
              trailingBuilder: switch (section.id) {
                'appearance' => (bool expanded) => ThemeHeaderActions(
                  expanded: expanded,
                ),
                'database' => (bool expanded) => DatabaseHeaderActions(
                  expanded: expanded,
                ),
                _ => null,
              },
            ),
            child: section.builder(
              theme: theme,
              searchQuery: searchQuery,
              matchesSearch: matchesSearch,
            ),
          ),
        ),
    ];

    return Expanded(
      child: Column(
        children: [
          searchField,
          Expanded(
            child: AppTabTransition(
              key: const ValueKey('settings-section-transition'),
              index: sectionIndex,
              slide: false,
              child: RepaintBoundary(
                // Settings cards mark their label when it matches.
                child: SettingsSearchScope(
                  query: searchQuery,
                  child: CustomScrollView(
                    controller: scrollController,
                    key: const ValueKey<String>('settings-content-scroll'),
                    slivers: [
                      if (visibleSections.isEmpty)
                        SliverFillRemaining(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 48,
                                  color: theme.textHint,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No settings found for "$searchQuery"',
                                  style: TextStyle(
                                    color: theme.textHint,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                          sliver: SliverToBoxAdapter(
                            child: LayoutBuilder(
                              builder: (context, constraints) =>
                                  SettingsSectionGrid(
                                    columns: settingsSectionColumnCount(
                                      constraints.maxWidth,
                                    ),
                                    spacing: kSettingsSectionSpacing,
                                    children: sectionCards,
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
        ],
      ),
    );
  }
}

/// A section button in the rail: the navigation panel's vertical button, with
/// its label under the icon on the selected section only.
class _SettingsSectionButton extends StatelessWidget {
  const _SettingsSectionButton({
    super.key,
    required this.theme,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isCollapsed,
    required this.isEnabled,
    required this.onTap,
  });

  final AppThemeData theme;
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isCollapsed;
  final bool isEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final showLabel = !isCollapsed && isSelected;
    return AppNavigationButton(
      theme: theme,
      isSelected: isSelected,
      isEnabled: isEnabled,
      isHorizontal: false,
      onTap: onTap,
      iconData: icon,
      labelText: label,
      labelVisible: showLabel,
      labelFadeDuration: kNavButtonExpandAnimation,
      labelFadeCurve: kNavButtonExpandCurve,
      tooltipMessage: showLabel ? null : label,
    );
  }
}
