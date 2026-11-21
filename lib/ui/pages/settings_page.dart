/// Settings page - app configuration
/// Matches the original Python SettingsPage with 5+ sections
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
typedef _SettingsSectionBuilder = Widget Function({
  required String searchQuery,
});

typedef _SectionExtraMatch = bool Function(
  WidgetRef ref,
  bool Function(String) matchesSearch,
);

class const _SettingsSectionDefinition({
  required final String id,
  required final String railLabel,
  required final String headerTitle,
  required final IconData icon,
  required final List<SettingsSearchGroup> searchGroups,
  required final _SettingsSectionBuilder builder,
  final _SectionExtraMatch? extraMatch,
}) {
  bool shouldShow(WidgetRef ref, String query) =>
      query.isEmpty ||
      searchGroups.any((group) => matchesSettingsSearchGroup(query, group)) ||
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
    searchGroups: CardDisplaySection.searchGroups,
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

/// The section rail's width: an icon's pill and its margins.
const double _settingsRailWidth = 60;

/// Settings page
class const SettingsPage({super.key}) extends ConsumerStatefulWidget {
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

/// The section list beside the page: icons, named in tooltips, the chosen
/// one in an accent pill. All sits apart above the sections.
class const _SettingsSectionRail({
  required final String selectedSection,
  required final bool isSearching,
  required final ValueChanged<String> onSectionSelected,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    Widget item((String, String, IconData) section) => _SettingsRailItem(
      key: ValueKey<String>('settings-rail-${section.$1}'),
      label: section.$2,
      icon: section.$3,
      selected: !isSearching && selectedSection == section.$1,
      // A search shows every section, so none can be picked meanwhile.
      onTap: isSearching ? null : () => onSectionSelected(section.$1),
    );
    return RepaintBoundary(
      child: Container(
        width: _settingsRailWidth,
        decoration: BoxDecoration(
          color: theme.navBackground,
          border: Border(right: BorderSide(color: theme.border)),
        ),
        // The navigation panel's background and pattern, lined up with it,
        // with the pattern just a little stronger than behind pages.
        child: PanelPatternSurface(
          strength: PanelPatternSurface.sidePanelStrength,
          child: ListView(
            key: const ValueKey('settings-section-navigation'),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            children: [
              item(_settingsRailSections.first),
              Divider(
                height: 12,
                indent: 12,
                endIndent: 12,
                color: theme.border,
              ),
              for (final section in _settingsRailSections.skip(1))
                item(section),
            ],
          ),
        ),
      ),
    );
  }
}

class const _SettingsRailItem({
  super.key,
  required final String label,
  required final IconData icon,
  required final bool selected,
  required final VoidCallback? onTap,
}) extends StatefulWidget {
  @override
  State<_SettingsRailItem> createState() => _SettingsRailItemState();
}

class _SettingsRailItemState extends State<_SettingsRailItem> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final radius = BorderRadius.circular(theme.cornerRadius);
    final enabled = widget.onTap != null;
    final animate = !MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: Tooltip(
        message: widget.label,
        child: Opacity(
          opacity: !enabled && !widget.selected ? 0.5 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: AnimatedContainer(
              duration: animate
                  ? const Duration(milliseconds: 160)
                  : Duration.zero,
              curve: Curves.easeOutCubic,
              height: 40,
              decoration: BoxDecoration(
                color: widget.selected
                    ? theme.accent.withValues(alpha: 0.22)
                    : Colors.transparent,
                borderRadius: radius,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: widget.onTap,
                  onHover: (hovered) => setState(() => _hovered = hovered),
                  borderRadius: radius,
                  // Grows a fifth while hovered or chosen, as the navigation
                  // panel's icons do.
                  child: AnimatedScale(
                    scale: enabled && (widget.selected || _hovered) ? 1.2 : 1,
                    duration: animate
                        ? const Duration(milliseconds: 100)
                        : Duration.zero,
                    child: Icon(
                      widget.icon,
                      size: 22,
                      color: widget.selected
                          ? theme.accent
                          : theme.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class const _SettingsPageBody({
  required final int sectionIndex,
  required final ScrollController scrollController,
  required final TextEditingController searchController,
  required final String searchQuery,
  required final String selectedSection,
  required final bool showSectionPicker,

  /// Null while searching, which shows every section.
  required final ValueChanged<String>? onSectionSelected,
  required final ValueChanged<String> onSearchChanged,
  required final List<_SettingsSectionDefinition> sections,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    final search = AppSearchField(
      controller: searchController,
      hintText: 'Search settings...',
      onChanged: onSearchChanged,
    );
    final (_, sectionLabel, sectionIcon) = _settingsRailSections.firstWhere(
      (section) => section.$1 == selectedSection,
      orElse: () => _settingsRailSections.first,
    );
    // As the sidebar's chosen section: its icon in an accent pill.
    final sectionPicker = DecoratedBox(
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(theme.cornerRadius),
      ),
      child: IconMenuButton<String>(
        key: const ValueKey<String>('settings-section-picker'),
        value: selectedSection,
        tooltip: 'Section: $sectionLabel',
        onSelected: onSectionSelected,
        icon: (color, size) => Icon(sectionIcon, color: color, size: size),
        choices: [
          for (final (id, label, icon) in _settingsRailSections)
            (id, label, Icon(icon, size: 20)),
        ],
      ),
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
            if (showSectionPicker) ...[sectionPicker, const SizedBox(width: 8)],
            Expanded(child: search),
          ],
        ),
      ),
    );

    // Filter whole sections before arranging their connected groupboxes.
    final visibleSections = sections
        .where((s) => s.shouldShow(ref, searchQuery))
        .toList(growable: false);
    // As above, only the column count follows the width; the section widgets
    // are reused by each layout pass.
    final sectionCards = [
      for (final section in visibleSections)
        RepaintBoundary(
          key: ValueKey('settings-section-card-${section.id}'),
          child: SettingsSectionFamily(
            header: GroupBoxFamilyTitle(
              key: ValueKey<String>(
                'settings-section-header-${section.headerTitle}',
              ),
              theme: theme,
              title: section.headerTitle,
              icon: section.icon,
              trailing: switch (section.id) {
                'appearance' => const ThemeHeaderActions(),
                'database' => const DatabaseHeaderActions(),
                _ => null,
              },
            ),
            child: section.builder(searchQuery: searchQuery),
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
