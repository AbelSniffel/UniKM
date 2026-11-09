/// Settings page - app configuration
/// Matches the original Python SettingsPage with 5+ sections
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/nav_button_group.dart';
import '../widgets/navigation_panel.dart' show isVeryNarrowAppLayout;
import '../widgets/background_pattern.dart';
import '../widgets/platform_menu_button.dart';
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
    Widget Function({required AppThemeData theme, required String searchQuery});

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

  bool shouldShow(WidgetRef ref, TargetPlatform platform, String query) =>
      query.isEmpty ||
      (platformSearchGroups?.call(platform) ?? searchGroups).any(
        (group) => matchesSettingsSearchGroup(query, group),
      ) ||
      (extraMatch?.call(ref, (text) => settingsSearchMatches(query, text)) ??
          false);
}

final List<_SettingsSectionDefinition> _settingsSections = [
  _SettingsSectionDefinition(
    id: 'appearance',
    railLabel: 'Appearance',
    headerTitle: 'Appearance',
    icon: Icons.palette,
    searchGroups: AppearanceSection.searchGroups,
    extraMatch: (ref, matchesSearch) => ref
        .watch(allThemesProvider)
        .any((themeData) => matchesSearch(themeData.name)),
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
    searchGroups: AdvancedSection.searchGroups,
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

/// A section button's width: the rail shows icons only.
const double _settingsRailButtonExtent = 40;

/// The rail's width: a button plus its group and outer padding.
const double _settingsRailWidth =
    _settingsRailButtonExtent +
    (_settingsRailOuterPadding + NavButtonGroup.padding) * 2;

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
    final navigation = ref.watch(
      appShellSettingsProvider.select(
        (settings) => (settings.navBarPosition, settings.navBarAppearance),
      ),
    );
    // Narrow windows swap the section rail for a picker beside the search bar.
    final narrow = isVeryNarrowAppLayout(
      MediaQuery.sizeOf(context).width,
      position: navigation.$1,
      appearance: navigation.$2,
    );
    final searchQuery = ref.watch(settingsPageSearchQueryProvider);
    final isSearching = searchQuery.isNotEmpty;
    final effectiveSection = searchQuery.isNotEmpty ? 'all' : selectedSection;
    final selectedSectionDefinition = _selectedSectionDefinitionFor(
      selectedSection,
    );

    void selectSection(String sectionId) =>
        ref.read(settingsPageSelectedSectionProvider.notifier).set(sectionId);
    final rail = _SettingsSectionRail(
      selectedSection: selectedSection,
      isSearching: isSearching,
      onSectionSelected: selectSection,
    );
    final body = _SettingsPageBody(
      sectionIndex: _settingsRailSections.indexWhere(
        (section) => section.$1 == effectiveSection,
      ),
      scrollController: _contentScrollController,
      searchController: _searchController,
      searchQuery: searchQuery,
      selectedSection: selectedSection,
      showSectionPicker: narrow,
      onSectionSelected: isSearching ? null : selectSection,
      onSearchChanged: (value) => ref
          .read(settingsPageSearchQueryProvider.notifier)
          .set(value.trim().toLowerCase()),
      sections: effectiveSection == 'all'
          ? _settingsSections
          : [?selectedSectionDefinition],
    );

    return Row(children: [if (!narrow) rail, body]);
  }

  _SettingsSectionDefinition? _selectedSectionDefinitionFor(String sectionId) {
    for (final section in _settingsSections) {
      if (section.id == sectionId) return section;
    }

    return null;
  }
}

/// The section list beside the page: icon-only buttons, named in tooltips.
class _SettingsSectionRail extends ConsumerWidget {
  const _SettingsSectionRail({
    required this.selectedSection,
    required this.isSearching,
    required this.onSectionSelected,
  });

  final String selectedSection;
  final bool isSearching;
  final ValueChanged<String> onSectionSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return RepaintBoundary(
      child: Container(
        width: _settingsRailWidth,
        decoration: BoxDecoration(
          color: theme.navBackground,
          border: Border(right: BorderSide(color: theme.border)),
          boxShadow: [
            BoxShadow(
              color: theme.border.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        // The navigation panel's background and pattern, lined up with it,
        // with the pattern just a little stronger than behind pages.
        child: PanelPatternSurface(
          strength: PanelPatternSurface.sidePanelStrength,
          child: ListView(
            key: const ValueKey('settings-section-navigation'),
            padding: const EdgeInsets.all(_settingsRailOuterPadding),
            children: [
              NavButtonGroup(
                theme: theme,
                isHorizontal: false,
                children: [
                  for (final (id, label, icon) in _settingsRailSections)
                    AppNavigationButton(
                      key: ValueKey<String>('settings-rail-$id'),
                      theme: theme,
                      isSelected: !isSearching && selectedSection == id,
                      isEnabled: !isSearching,
                      isHorizontal: false,
                      onTap: () => onSectionSelected(id),
                      iconData: icon,
                      tooltipMessage: label,
                    ),
                ],
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
    required this.selectedSection,
    required this.showSectionPicker,
    required this.onSectionSelected,
    required this.onSearchChanged,
    required this.sections,
  });

  final int sectionIndex;
  final ScrollController scrollController;
  final TextEditingController searchController;
  final String searchQuery;
  final String selectedSection;
  final bool showSectionPicker;

  /// Null while searching, which shows every section.
  final ValueChanged<String>? onSectionSelected;
  final ValueChanged<String> onSearchChanged;
  final List<_SettingsSectionDefinition> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    final search = AppSearchField(
      theme: theme,
      controller: searchController,
      hintText: 'Search settings...',
      onChanged: onSearchChanged,
    );
    final (_, sectionLabel, sectionIcon) = _settingsRailSections.firstWhere(
      (section) => section.$1 == selectedSection,
      orElse: () => _settingsRailSections.first,
    );
    final sectionPicker = IconMenuButton<String>(
      key: const ValueKey<String>('settings-section-picker'),
      theme: theme,
      value: selectedSection,
      tooltip: 'Section: $sectionLabel',
      onSelected: onSectionSelected,
      icon: (color, size) => Icon(sectionIcon, color: color, size: size),
      choices: [
        for (final (id, label, icon) in _settingsRailSections)
          (id, label, Icon(icon, size: 20)),
      ],
    );
    final searchField = Container(
      key: const ValueKey<String>('settings-search-container'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      // Separates the fixed search bar from the scrolling sections.
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.border)),
      ),
      // The picker stretches to the search bar's height.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: search),
            if (showSectionPicker) ...[const SizedBox(width: 8), sectionPicker],
          ],
        ),
      ),
    );

    // Filter whole sections before arranging their connected groupboxes.
    final visibleSections = sections
        .where(
          (s) => s.shouldShow(ref, Theme.of(context).platform, searchQuery),
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
            child: section.builder(theme: theme, searchQuery: searchQuery),
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
