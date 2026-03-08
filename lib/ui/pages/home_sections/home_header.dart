/// Home page header with search, filters, tags, and view mode toggle
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/platform_patterns.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/game.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/app_search_field.dart';
import 'animated_view_mode_toggle.dart';

class HomeHeader extends ConsumerStatefulWidget {
  const HomeHeader({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
  });

  final TextEditingController searchController;
  final FocusNode searchFocusNode;

  @override
  ConsumerState<HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends ConsumerState<HomeHeader> {
  bool _showTagsPanel = false;
  String _tagSearchQuery = '';

  IconData _sortIconFor(GameSortMode mode) {
    return switch (mode) {
      GameSortMode.deadlineFirst => Icons.schedule,
      GameSortMode.titleAZ => Icons.sort_by_alpha,
      GameSortMode.titleZA => Icons.sort_by_alpha,
      GameSortMode.platformAZ => Icons.videogame_asset,
      GameSortMode.platformZA => Icons.videogame_asset,
      GameSortMode.dateNewest => Icons.calendar_month,
      GameSortMode.dateOldest => Icons.history,
      GameSortMode.ratingHigh => Icons.trending_up,
      GameSortMode.ratingLow => Icons.trending_down,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final gamesCount = ref.watch(
      gamesProvider.select((s) => s.filteredGames.length),
    );
    final totalGamesCount = ref.watch(
      gamesProvider.select((s) => s.games.length),
    );
    final platformFilter = ref.watch(
      gamesProvider.select((s) => s.platformFilter),
    );
    final sortMode = ref.watch(gamesProvider.select((s) => s.sortMode));
    final activeFiltersState = ref.watch(activeFiltersProvider);
    final viewMode = ref.watch(viewModeProvider);
    final tags = ref.watch(tagsProvider);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(bottom: BorderSide(color: theme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title, game count, and search/filters inline
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 900;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Game Library',
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: theme.accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(
                            theme.cornerRadius,
                          ),
                        ),
                        child: Text(
                          gamesCount == totalGamesCount
                              ? '$gamesCount games'
                              : '$gamesCount / $totalGamesCount games',
                          style: TextStyle(
                            color: theme.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Search field (always visible, fills remaining space)
                      Expanded(
                        child: AppSearchField(
                          theme: theme,
                          controller: widget.searchController,
                          focusNode: widget.searchFocusNode,
                          hintText: 'Search by title or key...',
                          onChanged: (value) {
                            ref
                                .read(gamesProvider.notifier)
                                .setSearchQuery(value);
                          },
                          onCleared: () {
                            ref
                                .read(gamesProvider.notifier)
                                .setSearchQuery('');
                          },
                        ),
                      ),

                      // Wide layout: platform, sort, filters inline
                      if (!isNarrow) ...[
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: _buildPlatformDropdown(
                            theme,
                            platformFilter,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 170),
                          child: _buildSortDropdown(theme, sortMode),
                        ),
                        const SizedBox(width: 8),
                        _buildFiltersToggleButton(
                          context,
                          theme,
                          activeFiltersState,
                        ),
                      ],
                      const SizedBox(width: 8),

                      // View mode toggle (always visible)
                      _buildViewModeToggle(context, ref, theme, viewMode),
                    ],
                  ),

                  // Narrow layout: platform, sort, filters on second row
                  if (isNarrow) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildPlatformDropdown(
                            theme,
                            platformFilter,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildSortDropdown(theme, sortMode),
                        ),
                        const SizedBox(width: 8),
                        _buildFiltersToggleButton(
                          context,
                          theme,
                          activeFiltersState,
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),

          // Filters panel (animated show/hide)
          ClipRect(
            child: AnimatedSize(
              duration: kMediumAnimation,
              curve: Curves.linearToEaseOut,
              alignment: Alignment.topCenter,
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: _showTagsPanel ? 1.0 : 0.0,
                child: IgnorePointer(
                  ignoring: !_showTagsPanel,
                  child: AnimatedOpacity(
                    duration: kMediumAnimation,
                    curve: Curves.linear,
                    opacity: _showTagsPanel ? 1.0 : 0.0,
                    child: _buildTagsPanel(theme, tags, activeFiltersState),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // View mode toggle
  // ---------------------------------------------------------------------------

  Widget _buildViewModeToggle(
    BuildContext context,
    WidgetRef ref,
    AppThemeData theme,
    GameListViewMode viewMode,
  ) {
    return AnimatedViewModeToggle(
      theme: theme,
      isGridView: viewMode == GameListViewMode.grid,
      onToggle: () {
        final newMode = viewMode == GameListViewMode.grid
            ? GameListViewMode.list
            : GameListViewMode.grid;
        ref.read(viewModeProvider.notifier).setViewMode(newMode);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Platform dropdown
  // ---------------------------------------------------------------------------

  Widget _buildPlatformDropdown(
    AppThemeData theme,
    String? platformFilter,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: platformFilter ?? '',
      isExpanded: true,
      onChanged: (value) {
        final platform = (value == null || value.isEmpty) ? null : value;
        ref.read(gamesProvider.notifier).setPlatformFilter(platform);
      },
      style: TextStyle(color: theme.textPrimary),
      dropdownColor: theme.surface,
      decoration: InputDecoration(
        filled: true,
        fillColor: theme.inputBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(theme.cornerRadius),
          borderSide: BorderSide(color: theme.border),
        ),
      ),
      hint: Text('All Platforms', style: TextStyle(color: theme.textHint)),
      items: [
        DropdownMenuItem<String>(
          value: '',
          child: Text(
            'All Platforms',
            style: TextStyle(color: theme.textPrimary),
          ),
        ),
        ...GamePlatform.values.map(
          (p) => DropdownMenuItem<String>(
            value: p.displayName,
            child: Text(
              p.displayName,
              style: TextStyle(color: theme.textPrimary),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Sort dropdown
  // ---------------------------------------------------------------------------

  Widget _buildSortDropdown(AppThemeData theme, GameSortMode sortMode) {
    return DropdownButtonFormField<GameSortMode>(
      initialValue: sortMode,
      onChanged: (value) {
        if (value != null) {
          ref.read(gamesProvider.notifier).setSortMode(value);
        }
      },
      style: TextStyle(color: theme.textPrimary),
      dropdownColor: theme.surface,
      isExpanded: true,
      decoration: InputDecoration(
        filled: true,
        fillColor: theme.inputBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(theme.cornerRadius),
          borderSide: BorderSide(color: theme.border),
        ),
      ),
      items: GameSortMode.values
          .map(
            (mode) => DropdownMenuItem(
              value: mode,
              child: Row(
                children: [
                  Icon(
                    _sortIconFor(mode),
                    color: theme.textSecondary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      mode.displayName,
                      style: TextStyle(color: theme.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Filters toggle button
  // ---------------------------------------------------------------------------

  Widget _buildFiltersToggleButton(
    BuildContext context,
    AppThemeData theme,
    ({
      String searchQuery,
      List<int> tagFilters,
      bool showDeadlineOnly,
      bool showDlcOnly,
      bool showUsedOnly,
      bool showNoPicturesOnly,
    }) state,
  ) {
    final filterCount =
        state.tagFilters.length +
        (state.showDeadlineOnly ? 1 : 0) +
        (state.showDlcOnly ? 1 : 0) +
        (state.showUsedOnly ? 1 : 0) +
        (state.showNoPicturesOnly ? 1 : 0);
    final hasActiveFilters = filterCount > 0;
    final isActive = _showTagsPanel || hasActiveFilters;

    return GestureDetector(
      onTap: () => setState(() => _showTagsPanel = !_showTagsPanel),
      onSecondaryTapUp: (details) => _showFiltersContextMenu(
        context,
        details.globalPosition,
        theme,
        state,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: theme.controlPadding,
          decoration: BoxDecoration(
            color: isActive ? theme.accent : theme.inputBackground,
            borderRadius: BorderRadius.circular(theme.cornerRadius),
            border: Border.all(color: isActive ? theme.accent : theme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune,
                color: isActive ? theme.primaryButtonText : theme.textSecondary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                hasActiveFilters ? 'Filters ($filterCount)' : 'Filters',
                style: TextStyle(
                  color: isActive
                      ? theme.primaryButtonText
                      : theme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Filters panel (expandable)
  // ---------------------------------------------------------------------------

  Widget _buildTagsPanel(
    AppThemeData theme,
    List<Tag> tags,
    ({
      String searchQuery,
      List<int> tagFilters,
      bool showDeadlineOnly,
      bool showDlcOnly,
      bool showUsedOnly,
      bool showNoPicturesOnly,
    }) state,
  ) {
    final tagFilters = state.tagFilters;
    // Filter tags by search query
    final filteredTags = _tagSearchQuery.isEmpty
        ? tags
        : tags
              .where(
                (t) => t.name.toLowerCase().contains(
                  _tagSearchQuery.toLowerCase(),
                ),
              )
              .toList();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        border: Border.all(color: theme.accent.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filter option chips row (top)
          Row(
            children: [
              _buildFilterOptionChip(
                theme: theme,
                label: 'Deadline Only',
                isActive: state.showDeadlineOnly,
                onTap: () => ref
                    .read(gamesProvider.notifier)
                    .setShowDeadlineOnly(!state.showDeadlineOnly),
              ),
              const SizedBox(width: 6),
              _buildFilterOptionChip(
                theme: theme,
                label: 'DLC Only',
                isActive: state.showDlcOnly,
                onTap: () => ref
                    .read(gamesProvider.notifier)
                    .setShowDlcOnly(!state.showDlcOnly),
              ),
              const SizedBox(width: 6),
              _buildFilterOptionChip(
                theme: theme,
                label: 'Used Only',
                isActive: state.showUsedOnly,
                onTap: () => ref
                    .read(gamesProvider.notifier)
                    .setShowUsedOnly(!state.showUsedOnly),
              ),
              const SizedBox(width: 6),
              _buildFilterOptionChip(
                theme: theme,
                label: 'No Pictures',
                isActive: state.showNoPicturesOnly,
                onTap: () => ref
                    .read(gamesProvider.notifier)
                    .setShowNoPicturesOnly(!state.showNoPicturesOnly),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: (state.showDeadlineOnly || state.showDlcOnly ||
                        state.showUsedOnly || state.showNoPicturesOnly)
                    ? _clearBoolFilters
                    : null,
                icon: const Icon(Icons.filter_list_off, size: 16),
                label: const Text('Clear Options'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: theme.border.withValues(alpha: 0.3), height: 1),
          const SizedBox(height: 10),
          // Search bar + clear button
          Row(
            children: [
              Expanded(
                child: AppSearchField(
                  theme: theme,
                  hintText: 'Search tags...',
                  onChanged: (value) => setState(() => _tagSearchQuery = value),
                  showClearButton: false,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: tagFilters.isNotEmpty
                    ? () => ref.read(gamesProvider.notifier).setTagFilters([])
                    : null,
                icon: const Icon(Icons.label_off, size: 16),
                label: Text(
                  tagFilters.isNotEmpty
                      ? 'Clear Tags (${tagFilters.length})'
                      : 'Clear Tags',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Scrollable tags using native Wrap for correct row-wrapping
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: filteredTags.map((tag) {
                  return _buildFilterTagChip(theme, tag, tagFilters);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _clearBoolFilters() {
    final notifier = ref.read(gamesProvider.notifier);
    notifier.setShowDeadlineOnly(false);
    notifier.setShowDlcOnly(false);
    notifier.setShowUsedOnly(false);
    notifier.setShowNoPicturesOnly(false);
  }

  void _clearAllFilters() {
    ref.read(gamesProvider.notifier).setTagFilters([]);
    _clearBoolFilters();
  }

  void _showFiltersContextMenu(
    BuildContext context,
    Offset globalPosition,
    AppThemeData theme,
    ({
      String searchQuery,
      List<int> tagFilters,
      bool showDeadlineOnly,
      bool showDlcOnly,
      bool showUsedOnly,
      bool showNoPicturesOnly,
    }) state,
  ) {
    final hasTagFilters = state.tagFilters.isNotEmpty;
    final hasBoolFilters =
        state.showDeadlineOnly ||
        state.showDlcOnly ||
        state.showUsedOnly ||
        state.showNoPicturesOnly;
    final hasAnyFilters = hasTagFilters || hasBoolFilters;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      color: theme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        side: BorderSide(color: theme.border),
      ),
      items: [
        PopupMenuItem<String>(
          value: 'clear_tags',
          enabled: hasTagFilters,
          child: Row(
            children: [
              Icon(
                Icons.label_off,
                size: 18,
                color: hasTagFilters ? theme.textPrimary : theme.textHint,
              ),
              const SizedBox(width: 8),
              Text(
                'Clear Tag Filters',
                style: TextStyle(
                  color: hasTagFilters ? theme.textPrimary : theme.textHint,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'clear_options',
          enabled: hasBoolFilters,
          child: Row(
            children: [
              Icon(
                Icons.filter_list_off,
                size: 18,
                color: hasBoolFilters ? theme.textPrimary : theme.textHint,
              ),
              const SizedBox(width: 8),
              Text(
                'Clear Options',
                style: TextStyle(
                  color: hasBoolFilters ? theme.textPrimary : theme.textHint,
                ),
              ),
            ],
          ),
        ),
        PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'clear_all',
          enabled: hasAnyFilters,
          child: Row(
            children: [
              Icon(
                Icons.clear_all,
                size: 18,
                color: hasAnyFilters ? theme.textPrimary : theme.textHint,
              ),
              const SizedBox(width: 8),
              Text(
                'Clear All Filters',
                style: TextStyle(
                  color: hasAnyFilters ? theme.textPrimary : theme.textHint,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'clear_tags') {
        ref.read(gamesProvider.notifier).setTagFilters([]);
      } else if (value == 'clear_options') {
        _clearBoolFilters();
      } else if (value == 'clear_all') {
        _clearAllFilters();
      }
    });
  }

  Widget _buildFilterOptionChip({
    required AppThemeData theme,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final baseColor = theme.accent;
    final bg = isActive ? baseColor.withValues(alpha: 0.35) : Colors.transparent;
    final borderColor = isActive
        ? baseColor.withValues(alpha: 0.5)
        : baseColor.withValues(alpha: 0.0);
    final iconColor = isActive ? baseColor : baseColor.withValues(alpha: 0.4);

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isActive ? Icons.check_box : Icons.check_box_outline_blank,
                color: iconColor,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: theme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a single tag chip matching the tag management section styling.
  Widget _buildFilterTagChip(
    AppThemeData theme,
    Tag tag,
    List<int> tagFilters,
  ) {
    final isSelected = tagFilters.contains(tag.id);
    final isSteam = tag.isSteamTag;
    final baseColor = isSteam ? theme.accent : theme.primary;

    // Match tag management chip styling from tags_section.dart _TagChip
    final bg = isSelected
        ? baseColor.withValues(alpha: 0.35)
        : Colors.transparent;
    final borderColor = isSelected
        ? baseColor.withValues(alpha: 0.5)
        : baseColor.withValues(alpha: 0.0);
    final dotColor = isSelected ? baseColor : baseColor.withValues(alpha: 0.4);

    return GestureDetector(
      onTap: () => ref.read(gamesProvider.notifier).toggleTagFilter(tag.id),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Colored dot indicator (same as tag management)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                tag.name,
                style: TextStyle(
                  color: theme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
