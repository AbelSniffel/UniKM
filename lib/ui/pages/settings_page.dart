/// Settings page - app configuration
/// Matches the original Python SettingsPage with 5+ sections
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/settings/settings_model.dart';
import '../widgets/hover_builder.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../widgets/app_search_field.dart';
import '../widgets/app_tab_bar.dart';
import '../widgets/groupbox_family_title.dart';
import '../widgets/settings_section_grid.dart';
import '../widgets/settings_section_family.dart';
import 'settings_sections/settings_sections.dart';

typedef _SettingsSectionBuilder =
    Widget Function({
      required AppThemeData theme,
      required String searchQuery,
      required bool Function(String) matchesSearch,
      bool attachesToAbove,
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
    required String searchQuery,
    required bool Function(String) matchesSearch,
    required bool showOnlyMatches,
  }) {
    if (!showOnlyMatches) {
      return true;
    }

    return matchesAnySettingsSearchGroup(
          matchesSearch: matchesSearch,
          groups: platformSearchGroups?.call(platform) ?? searchGroups,
        ) ||
        (extraMatch?.call(ref, matchesSearch) ?? false);
  }

  Widget buildSection({
    required AppThemeData theme,
    required String searchQuery,
    required bool Function(String) matchesSearch,
    bool attachesToAbove = false,
  }) {
    return builder(
      theme: theme,
      searchQuery: searchQuery,
      matchesSearch: matchesSearch,
      attachesToAbove: attachesToAbove,
    );
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
    builder:
        ({
          required theme,
          required searchQuery,
          required matchesSearch,
          bool attachesToAbove = false,
        }) => AppearanceSection(
          theme: theme,
          searchQuery: searchQuery,
          matchesSearch: matchesSearch,
          attachesToAbove: attachesToAbove,
        ),
  ),
  _SettingsSectionDefinition(
    id: 'navigation',
    railLabel: 'Navigation',
    headerTitle: 'Navigation Panel',
    icon: Icons.view_sidebar,
    searchGroups: NavigationSection.searchGroups,
    builder:
        ({
          required theme,
          required searchQuery,
          required matchesSearch,
          bool attachesToAbove = false,
        }) => NavigationSection(
          theme: theme,
          searchQuery: searchQuery,
          matchesSearch: matchesSearch,
          attachesToAbove: attachesToAbove,
        ),
  ),
  _SettingsSectionDefinition(
    id: 'cards',
    railLabel: 'Game Card',
    headerTitle: 'Game Card Visual',
    icon: Icons.style,
    searchGroups: const [],
    platformSearchGroups: CardDisplaySection.searchGroupsFor,
    builder:
        ({
          required theme,
          required searchQuery,
          required matchesSearch,
          bool attachesToAbove = false,
        }) => CardDisplaySection(
          theme: theme,
          searchQuery: searchQuery,
          matchesSearch: matchesSearch,
          attachesToAbove: attachesToAbove,
        ),
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
    builder:
        ({
          required theme,
          required searchQuery,
          required matchesSearch,
          bool attachesToAbove = false,
        }) => DatabaseSection(
          theme: theme,
          searchQuery: searchQuery,
          matchesSearch: matchesSearch,
          attachesToAbove: attachesToAbove,
        ),
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
    builder:
        ({
          required theme,
          required searchQuery,
          required matchesSearch,
          bool attachesToAbove = false,
        }) => TagsSection(
          theme: theme,
          searchQuery: searchQuery,
          matchesSearch: matchesSearch,
          attachesToAbove: attachesToAbove,
        ),
  ),
  _SettingsSectionDefinition(
    id: 'notifications',
    railLabel: 'Notifications',
    headerTitle: 'Notifications',
    icon: Icons.notifications,
    searchGroups: [NotificationsSection.typesSearchGroup],
    builder:
        ({
          required theme,
          required searchQuery,
          required matchesSearch,
          bool attachesToAbove = false,
        }) => NotificationsSection(
          theme: theme,
          searchQuery: searchQuery,
          matchesSearch: matchesSearch,
          attachesToAbove: attachesToAbove,
        ),
  ),
  _SettingsSectionDefinition(
    id: 'updates',
    railLabel: 'Updates',
    headerTitle: 'Updates',
    icon: Icons.download_rounded,
    searchGroups: UpdatesSection.searchGroups,
    builder:
        ({
          required theme,
          required searchQuery,
          required matchesSearch,
          bool attachesToAbove = false,
        }) => UpdatesSection(
          theme: theme,
          searchQuery: searchQuery,
          matchesSearch: matchesSearch,
          attachesToAbove: attachesToAbove,
        ),
  ),
  _SettingsSectionDefinition(
    id: 'advanced',
    railLabel: 'Advanced',
    headerTitle: 'Advanced',
    icon: Icons.settings_applications,
    searchGroups: [
      AdvancedSection.displaySearchGroup,
      AdvancedSection.systemSearchGroup,
      if (AdvancedSection.showExperimentalSettings)
        AdvancedSection.experimentalSearchGroup,
    ],
    builder:
        ({
          required theme,
          required searchQuery,
          required matchesSearch,
          bool attachesToAbove = false,
        }) => AdvancedSection(
          theme: theme,
          searchQuery: searchQuery,
          matchesSearch: matchesSearch,
          attachesToAbove: attachesToAbove,
        ),
  ),
];

final List<(String, String, IconData)> _settingsRailSections = [
  ('all', 'All', Icons.dashboard_customize),
  ..._settingsSections.map(
    (section) => (section.id, section.railLabel, section.icon),
  ),
];

const double _settingsRailItemOuterHorizontalPadding = 8;
const double _settingsRailItemOuterVerticalPadding = 2;
const double _settingsRailButtonHorizontalPadding = 12;
const double _settingsRailButtonVerticalPadding = 8;
const double _settingsRailIconSize = 22;
const double _settingsRailIconLabelSpacing = 8;
const double _settingsRailLabelWidthBuffer = 25;
const double _settingsRailCollapsedButtonExtent =
    (_settingsRailButtonHorizontalPadding * 2) + _settingsRailIconSize;
const double _settingsRailButtonHeight =
    (_settingsRailButtonVerticalPadding * 2) + _settingsRailIconSize;

final double _settingsRailMaxLabelWidth = _measureSettingsRailMaxLabelWidth();
final double _settingsRailExpandedButtonWidth =
    _settingsRailCollapsedButtonExtent +
    _settingsRailIconLabelSpacing +
    _settingsRailMaxLabelWidth +
    _settingsRailLabelWidthBuffer;

double _measureSettingsRailMaxLabelWidth() {
  final painter = TextPainter(textDirection: TextDirection.ltr, maxLines: 1);
  var maxWidth = 0.0;

  for (final (_, label, _) in _settingsRailSections) {
    painter.text = TextSpan(
      text: label,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
    painter.layout();
    if (painter.width > maxWidth) {
      maxWidth = painter.width;
    }
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
    if (_contentScrollController.hasClients) {
      _contentScrollController.jumpTo(0);
    }
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

    bool matchesSearch(String text) => _matchesSearch(searchQuery, text);

    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          _SettingsSectionRail(
            selectedSection: selectedSection,
            isSearching: isSearching,
            isVeryNarrowLayout:
                constraints.maxWidth < kVeryNarrowLayoutBreakpoint,
            onSectionSelected: (sectionId) => ref
                .read(settingsPageSelectedSectionProvider.notifier)
                .set(sectionId),
          ),
          _SettingsPageBody(
            sectionIndex: _settingsRailSections.indexWhere(
              (section) => section.$1 == effectiveSection,
            ),
            scrollController: _contentScrollController,
            searchController: _searchController,
            searchQuery: searchQuery,
            onSearchChanged: (value) => ref
                .read(settingsPageSearchQueryProvider.notifier)
                .set(value.toLowerCase()),
            sections: effectiveSection == 'all'
                ? _settingsSections
                : [?selectedSectionDefinition],
            matchesSearch: matchesSearch,
            showOnlyMatches: searchQuery.isNotEmpty,
          ),
        ],
      ),
    );
  }

  /// Check if a text matches the search query (partial match)
  bool _matchesSearch(String searchQuery, String text) {
    if (searchQuery.isEmpty) return true;
    return text.toLowerCase().contains(searchQuery);
  }

  _SettingsSectionDefinition? _selectedSectionDefinitionFor(String sectionId) {
    for (final section in _settingsSections) {
      if (section.id == sectionId) {
        return section;
      }
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
    final platform = Theme.of(context).platform;
    final forceCollapsed =
        isVeryNarrowLayout ||
        platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS;
    final collapsed =
        forceCollapsed ||
        ref.watch(
          appShellSettingsProvider.select(
            (s) => s.settingsSectionPanelCollapsed,
          ),
        );
    return RepaintBoundary(
      child: AnimatedContainer(
        duration: forceCollapsed ? Duration.zero : kNavPanelMotionAnimation,
        curve: kNavPanelMotionCurve,
        width:
            (collapsed
                ? _settingsRailCollapsedButtonExtent
                : _settingsRailExpandedButtonWidth) +
            _settingsRailItemOuterHorizontalPadding * 2,
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
                child: ListView.builder(
                  key: const ValueKey('settings-section-navigation'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _settingsRailSections.length,
                  itemBuilder: (context, index) {
                    final (id, label, icon) = _settingsRailSections[index];
                    return _SettingsSectionButton(
                      key: ValueKey<String>('settings-rail-$id'),
                      theme: theme,
                      icon: icon,
                      label: label,
                      expandedButtonWidth: _settingsRailExpandedButtonWidth,
                      isSelected: !isSearching && selectedSection == id,
                      isCollapsed: collapsed,
                      isEnabled: !isSearching,
                      onTap: () => onSectionSelected(id),
                    );
                  },
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: _settingsRailButtonHorizontalPadding,
                            vertical: _settingsRailButtonVerticalPadding,
                          ),
                          decoration: BoxDecoration(
                            color: hovered
                                ? theme.navItemHover
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(
                              math.min(
                                theme.cornerRadius * 1.25,
                                _settingsRailButtonHeight / 2,
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
            searchQuery: searchQuery,
            matchesSearch: matchesSearch,
            showOnlyMatches: showOnlyMatches,
          ),
        )
        .toList(growable: false);

    return Expanded(
      child: Column(
        children: [
          searchField,
          Expanded(
            child: AppTabTransition(
              key: const ValueKey('settings-section-transition'),
              index: sectionIndex,
              child: RepaintBoundary(
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
                            builder: (context, constraints) => SettingsSectionGrid(
                              columns: settingsSectionColumnCount(
                                constraints.maxWidth,
                              ),
                              spacing: kSettingsSectionSpacing,
                              children: [
                                for (final section in visibleSections)
                                  RepaintBoundary(
                                    key: ValueKey(
                                      'settings-section-card-${section.id}',
                                    ),
                                    child: SettingsSectionFamily(
                                      header: GroupBoxFamilyTitle(
                                        key: ValueKey<String>(
                                          'settings-section-header-${section.headerTitle}',
                                        ),
                                        theme: theme,
                                        title: section.headerTitle,
                                        icon: section.icon,
                                        trailingBuilder: switch (section.id) {
                                          'appearance' =>
                                            (bool expanded) =>
                                                ThemeHeaderActions(
                                                  expanded: expanded,
                                                ),
                                          'database' =>
                                            (bool expanded) =>
                                                DatabaseHeaderActions(
                                                  expanded: expanded,
                                                ),
                                          _ => null,
                                        },
                                        searchQuery: searchQuery,
                                        isSearchMatch: showOnlyMatches,
                                      ),
                                      child: section.buildSection(
                                        theme: theme,
                                        searchQuery: searchQuery,
                                        matchesSearch: matchesSearch,
                                        attachesToAbove: false,
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
        ],
      ),
    );
  }
}

class _SettingsSectionButton extends StatefulWidget {
  const _SettingsSectionButton({
    super.key,
    required this.theme,
    required this.icon,
    required this.label,
    required this.expandedButtonWidth,
    required this.isSelected,
    required this.isCollapsed,
    required this.isEnabled,
    required this.onTap,
  });

  final AppThemeData theme;
  final IconData icon;
  final String label;
  final double expandedButtonWidth;
  final bool isSelected;
  final bool isCollapsed;
  final bool isEnabled;
  final VoidCallback onTap;

  @override
  State<_SettingsSectionButton> createState() => _SettingsSectionButtonState();
}

class _SettingsSectionButtonState extends State<_SettingsSectionButton> {
  Timer? _hideLabelTimer;
  bool _showLabel = true;

  @override
  void initState() {
    super.initState();
    _showLabel = !widget.isCollapsed;
  }

  @override
  void didUpdateWidget(covariant _SettingsSectionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isCollapsed == widget.isCollapsed) {
      return;
    }

    _hideLabelTimer?.cancel();

    if (widget.isCollapsed) {
      _hideLabelTimer = Timer(kFastAnimation, () {
        if (!mounted || !widget.isCollapsed) {
          return;
        }
        setState(() {
          _showLabel = false;
        });
      });
      return;
    }

    setState(() {
      _showLabel = true;
    });
  }

  @override
  void dispose() {
    _hideLabelTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keepsExpandedLayout = !widget.isCollapsed || _showLabel;
    final buttonWidth = keepsExpandedLayout
        ? widget.expandedButtonWidth
        : _settingsRailCollapsedButtonExtent;
    final roundedRadius = math.min(
      widget.theme.cornerRadius * 1.25,
      _settingsRailButtonHeight / 2,
    );
    final borderRadiusMultiplier = widget.theme.cornerRadius == 0
        ? 1.0
        : roundedRadius / widget.theme.cornerRadius;
    final button = AnimatedContainer(
      duration: kMediumAnimation,
      curve: Curves.easeInOutCubic,
      width: buttonWidth,
      child: AppNavigationButton(
        theme: widget.theme,
        variant: AppNavigationButtonVariant.settingsSection,
        isSelected: widget.isSelected,
        isEnabled: widget.isEnabled,
        isHorizontal: true,
        onTap: widget.onTap,
        iconData: widget.icon,
        iconSize: _settingsRailIconSize,
        labelText: _showLabel ? widget.label : null,
        tooltipMessage: widget.isCollapsed && !_showLabel ? widget.label : null,
        padding: const EdgeInsets.symmetric(
          horizontal: _settingsRailButtonHorizontalPadding,
          vertical: _settingsRailButtonVerticalPadding,
        ),
        alignment: Alignment.centerLeft,
        borderRadiusMultiplier: borderRadiusMultiplier,
        minWidth: _settingsRailCollapsedButtonExtent,
        minHeight: _settingsRailButtonHeight,
        horizontalSpacing: _settingsRailIconLabelSpacing,
        horizontalMainAxisSize: MainAxisSize.max,
        horizontalMainAxisAlignment: MainAxisAlignment.start,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _settingsRailItemOuterHorizontalPadding,
        vertical: _settingsRailItemOuterVerticalPadding,
      ),
      child: button,
    );
  }
}
