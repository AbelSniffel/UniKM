/// Settings page - app configuration
/// Matches the original Python SettingsPage with 5+ sections
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../widgets/app_search_field.dart';
import '../widgets/hover_builder.dart';
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
    required this.pageTitle,
    required this.headerTitle,
    required this.icon,
    required this.searchGroups,
    required this.builder,
    this.extraMatch,
  });

  final String id;
  final String railLabel;
  final String pageTitle;
  final String headerTitle;
  final IconData icon;
  final List<SettingsSearchGroup> searchGroups;
  final _SettingsSectionBuilder builder;
  final _SectionExtraMatch? extraMatch;

  bool shouldShow({
    required WidgetRef ref,
    required String searchQuery,
    required bool Function(String) matchesSearch,
    required bool showOnlyMatches,
  }) {
    if (!showOnlyMatches) {
      return true;
    }

    return matchesAnySettingsSearchGroup(
          query: searchQuery,
          matchesSearch: matchesSearch,
          groups: searchGroups,
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
    pageTitle: 'Appearance Settings',
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
    id: 'cards',
    railLabel: 'Game Card',
    pageTitle: 'Game Card Visual Settings',
    headerTitle: 'Game Card Visual',
    icon: Icons.style,
    searchGroups: [
      CardDisplaySection.chipsSearchGroup,
      CardDisplaySection.displayRulesSearchGroup,
      CardDisplaySection.viewOptionsSearchGroup,
    ],
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
    pageTitle: 'Database & Security',
    headerTitle: 'Database & Security',
    icon: Icons.storage,
    searchGroups: [
      DatabaseSection.encryptionSearchGroup,
      DatabaseSection.dataManagementSearchGroup,
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
    pageTitle: 'Tag Management',
    headerTitle: 'Tags',
    icon: Icons.label,
    searchGroups: [
      TagsSection.customTagsSearchGroup,
      TagsSection.steamTagsSearchGroup,
      TagsSection.maintenanceSearchGroup,
    ],
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
    pageTitle: 'Notification Settings',
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
    pageTitle: 'Update Settings',
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
    pageTitle: 'Advanced Settings',
    headerTitle: 'Advanced',
    icon: Icons.settings_applications,
    searchGroups: [AdvancedSection.systemSearchGroup],
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
final double _settingsRailExpandedWidth =
    _settingsRailExpandedButtonWidth +
    (_settingsRailItemOuterHorizontalPadding * 2);
final double _settingsRailCollapsedWidth =
    _settingsRailCollapsedButtonExtent +
    (_settingsRailItemOuterHorizontalPadding * 2);

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedSection = ref.watch(settingsPageSelectedSectionProvider);
    final searchQuery = ref.watch(settingsPageSearchQueryProvider);
    final isSearching = searchQuery.isNotEmpty;
    final effectiveSection = searchQuery.isNotEmpty ? 'all' : selectedSection;
    final selectedSectionDefinition = _selectedSectionDefinitionFor(
      selectedSection,
    );

    bool matchesSearch(String text) => _matchesSearch(searchQuery, text);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isVeryNarrowLayout =
            constraints.maxWidth < kVeryNarrowLayoutBreakpoint;

        return Row(
          children: [
            _SettingsSectionRail(
              expandedWidth: _settingsRailExpandedWidth,
              collapsedWidth: _settingsRailCollapsedWidth,
              expandedButtonWidth: _settingsRailExpandedButtonWidth,
              selectedSection: selectedSection,
              isSearching: isSearching,
              isVeryNarrowLayout: isVeryNarrowLayout,
              onSectionSelected: (sectionId) => ref
                  .read(settingsPageSelectedSectionProvider.notifier)
                  .setSelectedSection(sectionId),
            ),

            _SettingsPageBody(
              searchController: _searchController,
              searchQuery: searchQuery,
              onSearchChanged: (value) => ref
                  .read(settingsPageSearchQueryProvider.notifier)
                  .setQuery(value.toLowerCase()),
              buildSectionContent: (theme) => _buildSectionContent(
                theme,
                searchQuery,
                selectedSectionDefinition,
              ),
              buildSectionTitle: (theme) => _buildSectionTitle(
                theme,
                effectiveSection,
                searchQuery,
                selectedSectionDefinition,
              ),
              allSections: effectiveSection == 'all' ? _settingsSections : null,
              matchesSearch: matchesSearch,
              showOnlyMatches: searchQuery.isNotEmpty,
            ),
          ],
        );
      },
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

  Widget _buildSectionTitle(
    AppThemeData theme,
    String effectiveSection,
    String searchQuery,
    _SettingsSectionDefinition? selectedSectionDefinition,
  ) {
    final title = effectiveSection == 'all'
        ? (searchQuery.isNotEmpty ? 'Search Results' : 'All Settings')
        : selectedSectionDefinition?.pageTitle ?? 'Settings';

    return Text(
      title,
      style: TextStyle(
        color: theme.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildSectionContent(
    AppThemeData theme,
    String searchQuery,
    _SettingsSectionDefinition? selectedSectionDefinition,
  ) {
    return selectedSectionDefinition?.buildSection(
          theme: theme,
          searchQuery: searchQuery,
          matchesSearch: (text) => _matchesSearch(searchQuery, text),
        ) ??
        const SizedBox.shrink();
  }
}

class _SettingsSectionRail extends ConsumerWidget {
  const _SettingsSectionRail({
    required this.expandedWidth,
    required this.collapsedWidth,
    required this.expandedButtonWidth,
    required this.selectedSection,
    required this.isSearching,
    required this.isVeryNarrowLayout,
    required this.onSectionSelected,
  });

  final double expandedWidth;
  final double collapsedWidth;
  final double expandedButtonWidth;
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
    final sectionsCollapsed =
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
        width: sectionsCollapsed ? collapsedWidth : expandedWidth,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.surface,
            border: Border(right: BorderSide(color: theme.border)),
            boxShadow: [
              BoxShadow(
                color: theme.border.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _settingsRailSections.length,
                  itemBuilder: (context, index) {
                    final (id, label, icon) = _settingsRailSections[index];
                    final isSelected = !isSearching && selectedSection == id;

                    return _SettingsSectionButton(
                      key: ValueKey<String>('settings-rail-$id'),
                      theme: theme,
                      icon: icon,
                      label: label,
                      expandedButtonWidth: expandedButtonWidth,
                      isSelected: isSelected,
                      isCollapsed: sectionsCollapsed,
                      isEnabled: !isSearching,
                      onTap: () => onSectionSelected(id),
                    );
                  },
                ),
              ),
              if (!forceCollapsed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: _SettingsRailCollapseButton(
                    theme: theme,
                    isCollapsed: sectionsCollapsed,
                    expandedButtonWidth: expandedButtonWidth,
                    onTap: () => ref
                        .read(settingsProvider.notifier)
                        .setSetting(
                          SettingsKeys.settingsSectionPanelCollapsed,
                          !sectionsCollapsed,
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

class _SettingsRailCollapseButton extends StatelessWidget {
  const _SettingsRailCollapseButton({
    required this.theme,
    required this.isCollapsed,
    required this.expandedButtonWidth,
    required this.onTap,
  });

  final AppThemeData theme;
  final bool isCollapsed;
  final double expandedButtonWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final buttonWidth = isCollapsed
        ? _settingsRailCollapsedButtonExtent
        : expandedButtonWidth;
    final borderRadius = BorderRadius.circular(
      math.min(theme.cornerRadius * 1.25, _settingsRailButtonHeight / 2),
    );

    return Tooltip(
      message: isCollapsed ? 'Expand section list' : 'Collapse section list',
      child: HoverPressBuilder(
        onTap: onTap,
        builder: (context, hovered, _) => AnimatedContainer(
          duration: kNavPanelMotionAnimation,
          curve: kNavPanelMotionCurve,
          width: buttonWidth,
          padding: const EdgeInsets.symmetric(
            horizontal: _settingsRailButtonHorizontalPadding,
            vertical: _settingsRailButtonVerticalPadding,
          ),
          decoration: BoxDecoration(
            color: hovered ? theme.navItemHover : Colors.transparent,
            borderRadius: borderRadius,
          ),
          child: AnimatedSwitcher(
            duration: kNavPanelMotionAnimation,
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: Icon(
              isCollapsed ? Icons.chevron_right : Icons.chevron_left,
              key: ValueKey<bool>(isCollapsed),
              color: theme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsPageBody extends ConsumerWidget {
  const _SettingsPageBody({
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.buildSectionContent,
    required this.buildSectionTitle,
    this.allSections,
    this.matchesSearch,
    this.showOnlyMatches = false,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final Widget Function(AppThemeData theme) buildSectionContent;
  final Widget Function(AppThemeData theme) buildSectionTitle;
  final List<_SettingsSectionDefinition>? allSections;
  final bool Function(String)? matchesSearch;
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

    if (allSections != null) {
      // Pre-filter visible sections for lazy rendering
      final visibleSections = allSections!
          .where(
            (s) => s.shouldShow(
              ref: ref,
              searchQuery: searchQuery,
              matchesSearch: matchesSearch!,
              showOnlyMatches: showOnlyMatches,
            ),
          )
          .toList(growable: false);

      return Expanded(
        child: Column(
          children: [
            searchField,
            Expanded(
              child: RepaintBoundary(
                child: CustomScrollView(
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
                        sliver: SliverList.builder(
                          itemCount: visibleSections.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: buildSectionTitle(theme),
                              );
                            }
                            final section = visibleSections[index - 1];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _SettingsSearchSectionHeader(
                                  key: ValueKey<String>(
                                    'settings-section-header-${section.headerTitle}',
                                  ),
                                  theme: theme,
                                  title: section.headerTitle,
                                  searchQuery: searchQuery,
                                  isSearchMatch: showOnlyMatches,
                                ),
                                section.buildSection(
                                  theme: theme,
                                  searchQuery: searchQuery,
                                  matchesSearch: matchesSearch!,
                                  attachesToAbove: true,
                                ),
                                const SizedBox(height: 32),
                              ],
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Expanded(
      child: Column(
        children: [
          searchField,
          Expanded(
            child: RepaintBoundary(
              child: CustomScrollView(
                key: const ValueKey<String>('settings-content-scroll'),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          buildSectionTitle(theme),
                          const SizedBox(height: 20),
                          buildSectionContent(theme),
                        ],
                      ),
                    ),
                  ),
                ],
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
        duration: kMediumAnimation,
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

/// Header widget for section groups in the All/Search settings view
class _SettingsSearchSectionHeader extends StatefulWidget {
  const _SettingsSearchSectionHeader({
    super.key,
    required this.theme,
    required this.title,
    required this.searchQuery,
    required this.isSearchMatch,
  });

  final AppThemeData theme;
  final String title;
  final String searchQuery;
  final bool isSearchMatch;

  @override
  State<_SettingsSearchSectionHeader> createState() =>
      _SettingsSearchSectionHeaderState();
}

class _SettingsSearchSectionHeaderState
    extends State<_SettingsSearchSectionHeader>
    with SingleTickerProviderStateMixin {
  static const Duration _searchFadeDelay = Duration(seconds: 1);
  static const Duration _searchFadeDuration = Duration(milliseconds: 650);

  late final AnimationController _highlightController;
  Timer? _fadeTimer;

  bool get _shouldHighlight =>
      widget.searchQuery.trim().isNotEmpty && widget.isSearchMatch;

  @override
  void initState() {
    super.initState();
    _highlightController = AnimationController(
      vsync: this,
      duration: _searchFadeDuration,
      value: 0,
    );
    _syncHighlightWithSearch();
  }

  @override
  void didUpdateWidget(covariant _SettingsSearchSectionHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery ||
        oldWidget.isSearchMatch != widget.isSearchMatch) {
      _syncHighlightWithSearch();
    }
  }

  void _syncHighlightWithSearch() {
    _fadeTimer?.cancel();

    if (!_shouldHighlight) {
      _highlightController.animateTo(0);
      return;
    }

    _highlightController.value = 1;
    _fadeTimer = Timer(_searchFadeDelay, () {
      if (!mounted) return;
      _highlightController.animateTo(0);
    });
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    _highlightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _highlightController,
      builder: (context, _) {
        final highlightValue = Curves.easeOutCubic.transform(
          _highlightController.value,
        );
        final borderColor =
            Color.lerp(
              widget.theme.border,
              widget.theme.accent,
              highlightValue.clamp(0.0, 1.0),
            ) ??
            widget.theme.border;
        final backgroundColor = Color.alphaBlend(
          widget.theme.accent.withValues(alpha: 0.12 * highlightValue),
          widget.theme.accent.withValues(alpha: 0.35),
        );
        final iconAndTextColor =
            Color.lerp(
              widget.theme.accent,
              Colors.white,
              0.22 * highlightValue,
            ) ??
            widget.theme.accent;

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(widget.theme.cornerRadius),
            ),
            border: Border(
              top: BorderSide(color: borderColor),
              left: BorderSide(color: borderColor),
              right: BorderSide(color: borderColor),
            ),
            boxShadow: highlightValue <= 0
                ? const []
                : [
                    BoxShadow(
                      color: widget.theme.accent.withValues(
                        alpha: 0.18 * highlightValue,
                      ),
                      blurRadius: 14,
                      spreadRadius: 1.5,
                    ),
                  ],
          ),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, size: 20, color: iconAndTextColor),
              const SizedBox(width: kElementHSpacing),
              Text(
                widget.title,
                style: TextStyle(
                  color: iconAndTextColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
