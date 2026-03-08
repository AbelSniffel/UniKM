/// Settings page - app configuration
/// Matches the original Python SettingsPage with 5+ sections
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../widgets/app_search_field.dart';
import 'settings_sections/settings_sections.dart';

/// Settings page
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String _selectedSection = 'all';
  final _searchController = TextEditingController();
  String _searchQuery = '';

  /// Returns effective section - 'all' when searching, otherwise selected section
  String get _effectiveSection =>
      _searchQuery.isNotEmpty ? 'all' : _selectedSection;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);

    final sections = [
      ('all', 'All', Icons.dashboard_customize),
      ('appearance', 'Appearance', Icons.palette),
      ('cards', 'Game Card', Icons.style),
      ('database', 'Database', Icons.storage),
      ('tags', 'Tags', Icons.label),
      ('notifications', 'Notifications', Icons.notifications),
      ('updates', 'Updates', Icons.update),
      ('advanced', 'Advanced', Icons.settings_applications),
    ];

    final isSearching = _searchQuery.isNotEmpty;

    return Row(
      children: [
        // Section list
        Container(
          width: 190,
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
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: sections.length,
            itemBuilder: (context, index) {
              final (id, label, icon) = sections[index];
              final isSelected = !isSearching && _selectedSection == id;

              return ListTile(
                leading: Icon(
                  icon,
                  color: isSelected
                      ? theme.accent
                      : (isSearching ? theme.textHint : theme.textSecondary),
                ),
                title: Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? theme.accent
                        : (isSearching ? theme.textHint : theme.textPrimary),
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                selected: isSelected,
                selectedTileColor: theme.accent.withValues(alpha: 0.1),
                onTap: isSearching
                    ? null
                    : () => setState(() => _selectedSection = id),
              );
            },
          ),
        ),

        // Settings content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Search bar
              Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: AppSearchField(
                  theme: theme,
                  controller: _searchController,
                  hintText: 'Search settings...',
                  onChanged: (value) =>
                      setState(() => _searchQuery = value.toLowerCase()),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
              // Settings content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSectionTitle(theme),
                      const SizedBox(height: 24),
                      _buildSectionContent(theme),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Check if a text matches the search query (partial match)
  bool _matchesSearch(String text) {
    if (_searchQuery.isEmpty) return true;
    return text.toLowerCase().contains(_searchQuery);
  }

  bool _matchesAny(Iterable<String> terms) {
    if (_searchQuery.isEmpty) return true;
    return terms.any(_matchesSearch);
  }

  bool _sectionMatchesSearch(String sectionId) {
    switch (sectionId) {
      case 'appearance':
        return _matchesAny(AppearanceSection.sectionSearchTexts);
      case 'cards':
        return _matchesAny(CardDisplaySection.sectionSearchTexts);
      case 'database':
        return _matchesAny(DatabaseSection.sectionSearchTexts);
      case 'tags':
        return _matchesAny(TagsSection.sectionSearchTexts);
      case 'notifications':
        return _matchesAny(NotificationsSection.sectionSearchTexts);
      case 'updates':
        return _matchesAny(UpdatesSection.sectionSearchTexts);
      case 'advanced':
        return _matchesAny(AdvancedSection.sectionSearchTexts);
      default:
        return false;
    }
  }

  Widget _buildSectionTitle(AppThemeData theme) {
    final titles = {
      'appearance': 'Appearance Settings',
      'cards': 'Game Card Visual Settings',
      'database': 'Database & Security',
      'tags': 'Tag Management',
      'notifications': 'Notification Settings',
      'updates': 'Update Settings',
      'advanced': 'Advanced Settings',
      'all': _searchQuery.isNotEmpty ? 'Search Results' : 'All Settings',
    };

    return Text(
      titles[_effectiveSection] ?? 'Settings',
      style: TextStyle(
        color: theme.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildSectionContent(AppThemeData theme) {
    // When searching, show all sections with matching content
    if (_effectiveSection == 'all') {
      return _AllSectionsContent(
        theme: theme,
        searchQuery: _searchQuery,
        matchesSearch: _matchesSearch,
        sectionMatchesSearch: _sectionMatchesSearch,
        showOnlyMatches: _searchQuery.isNotEmpty,
      );
    }

    switch (_selectedSection) {
      case 'appearance':
        return AppearanceSection(
          theme: theme,
          searchQuery: _searchQuery,
          matchesSearch: _matchesSearch,
        );
      case 'cards':
        return CardDisplaySection(
          theme: theme,
          searchQuery: _searchQuery,
          matchesSearch: _matchesSearch,
        );
      case 'database':
        return DatabaseSection(
          theme: theme,
          searchQuery: _searchQuery,
          matchesSearch: _matchesSearch,
        );
      case 'tags':
        return TagsSection(
          theme: theme,
          searchQuery: _searchQuery,
          matchesSearch: _matchesSearch,
        );
      case 'notifications':
        return NotificationsSection(
          theme: theme,
          searchQuery: _searchQuery,
          matchesSearch: _matchesSearch,
        );
      case 'updates':
        return UpdatesSection(
          theme: theme,
          searchQuery: _searchQuery,
          matchesSearch: _matchesSearch,
        );
      case 'advanced':
        return AdvancedSection(
          theme: theme,
          searchQuery: _searchQuery,
          matchesSearch: _matchesSearch,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Combined view of all sections for search results
class _AllSectionsContent extends ConsumerWidget {
  const _AllSectionsContent({
    required this.theme,
    this.searchQuery = '',
    required this.matchesSearch,
    required this.sectionMatchesSearch,
    required this.showOnlyMatches,
  });

  final AppThemeData theme;
  final String searchQuery;
  final bool Function(String) matchesSearch;
  final bool Function(String) sectionMatchesSearch;
  final bool showOnlyMatches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = <Widget>[];

    // Helper to wrap section with header
    Widget buildSectionWithHeader(String title, Widget section) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: theme.accent.withValues(alpha: 0.25),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(theme.cornerRadius),
              ),
              border: Border(
                top: BorderSide(color: theme.border),
                left: BorderSide(color: theme.border),
                right: BorderSide(color: theme.border),
                // bottom intentionally omitted; the groupbox below will draw the
                // shared edge when it's not attached.
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 16, color: theme.accent),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: theme.accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          section,
          const SizedBox(height: 32),
        ],
      );
    }

    if (!showOnlyMatches || sectionMatchesSearch('appearance')) {
      sections.add(
        buildSectionWithHeader(
          'Appearance',
          AppearanceSection(
            theme: theme,
            searchQuery: searchQuery,
            matchesSearch: matchesSearch,
            attachesToAbove: true,
          ),
        ),
      );
    }
    if (!showOnlyMatches || sectionMatchesSearch('cards')) {
      sections.add(
        buildSectionWithHeader(
          'Game Card Visual',
          CardDisplaySection(
            theme: theme,
            searchQuery: searchQuery,
            matchesSearch: matchesSearch,
            attachesToAbove: true,
          ),
        ),
      );
    }
    if (!showOnlyMatches || sectionMatchesSearch('database')) {
      sections.add(
        buildSectionWithHeader(
          'Database & Security',
          DatabaseSection(
            theme: theme,
            searchQuery: searchQuery,
            matchesSearch: matchesSearch,
            attachesToAbove: true,
          ),
        ),
      );
    }
    if (!showOnlyMatches || sectionMatchesSearch('tags')) {
      sections.add(
        buildSectionWithHeader(
          'Tags',
          TagsSection(
            theme: theme,
            searchQuery: searchQuery,
            matchesSearch: matchesSearch,
            attachesToAbove: true,
          ),
        ),
      );
    }
    if (!showOnlyMatches || sectionMatchesSearch('notifications')) {
      sections.add(
        buildSectionWithHeader(
          'Notifications',
          NotificationsSection(
            theme: theme,
            searchQuery: searchQuery,
            matchesSearch: matchesSearch,
            attachesToAbove: true,
          ),
        ),
      );
    }
    if (!showOnlyMatches || sectionMatchesSearch('updates')) {
      sections.add(
        buildSectionWithHeader(
          'Updates',
          UpdatesSection(
            theme: theme,
            searchQuery: searchQuery,
            matchesSearch: matchesSearch,
            attachesToAbove: true,
          ),
        ),
      );
    }
    if (!showOnlyMatches || sectionMatchesSearch('advanced')) {
      sections.add(
        buildSectionWithHeader(
          'Advanced',
          AdvancedSection(
            theme: theme,
            searchQuery: searchQuery,
            matchesSearch: matchesSearch,
            attachesToAbove: true,
          ),
        ),
      );
    }

    if (sections.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: theme.textHint),
            const SizedBox(height: 16),
            Text(
              'No settings found for "$searchQuery"',
              style: TextStyle(color: theme.textHint, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections,
    );
  }
}
