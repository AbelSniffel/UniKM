/// Home page header with search, filters, tags, and view mode toggle
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/platform_patterns.dart';
import '../../../core/models/device_sync_models.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/game.dart';
import '../../../providers/app_providers.dart';
import '../../dialogs/device_sync_dialog.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/app_progress_indicator.dart';
import '../../widgets/app_tag_chip.dart';
import '../../widgets/badge.dart';
import '../../widgets/page_header_title.dart';
import '../../widgets/platform_icon.dart';
import '../../widgets/popup_menu_helpers.dart';
import '../../widgets/section_groupbox.dart';
import '../../widgets/tag_list.dart';
import '../settings_sections/settings_common.dart';
import 'animated_view_mode_toggle.dart';

const double _compactHeaderFiltersBreakpoint = 900.0;

class HomeHeader extends ConsumerStatefulWidget {
  const HomeHeader({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
    required this.isVeryNarrowLayout,
  });

  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final bool isVeryNarrowLayout;

  @override
  ConsumerState<HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends ConsumerState<HomeHeader>
    with SingleTickerProviderStateMixin {
  bool _showTagsPanel = false;
  final ScrollController _filtersScrollController = ScrollController();
  late final AnimationController _filterPanelController;
  late final CurvedAnimation _filterPanelAnimation;
  String _tagSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _filterPanelController = AnimationController(
      vsync: this,
      duration: kMediumAnimation,
    );
    _filterPanelAnimation = CurvedAnimation(
      parent: _filterPanelController,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _filtersScrollController.dispose();
    _filterPanelController.dispose();
    _filterPanelAnimation.dispose();
    super.dispose();
  }

  void _toggleFilterPanel() {
    setState(() => _showTagsPanel = !_showTagsPanel);
    if (_showTagsPanel) {
      _filterPanelController.forward();
    } else {
      _filterPanelController.reverse();
    }
  }

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
    final slimListView = ref.watch(
      gameCardSettingsProvider.select((s) => s.slimListView),
    );
    final selectedListViewMode = resolveListViewDensityMode(
      slimListView: slimListView,
    );
    final tags = ref.watch(tagsProvider);
    final platform = Theme.of(context).platform;
    final isMobilePlatform =
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: theme.navBackground,
        border: Border(bottom: BorderSide(color: theme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title, game count, and search/filters inline
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow =
                  constraints.maxWidth < _compactHeaderFiltersBreakpoint;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      PageHeaderTitle(
                        title: 'Game Library',
                        icon: Icons.home,
                        theme: theme,
                        showTitle: false,
                        tooltip: 'Game Library Page',
                      ),
                      if (isMobilePlatform) ...[
                        const SizedBox(width: kElementHSpacing),
                        _MobileSyncButton(theme: theme),
                      ],
                      const SizedBox(width: kElementHSpacing),
                      if (!widget.isVeryNarrowLayout) ...[
                        _buildGamesCountChip(
                          theme,
                          gamesCount,
                          totalGamesCount,
                        ),
                        const SizedBox(width: kElementHSpacing),
                      ],

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
                            ref.read(gamesProvider.notifier).setSearchQuery('');
                          },
                        ),
                      ),
                      if (!isNarrow) ...[
                        const SizedBox(width: kElementHSpacing),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: _buildPlatformDropdown(theme, platformFilter),
                        ),
                        const SizedBox(width: kElementHSpacing),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: _buildSortDropdown(theme, sortMode),
                        ),
                      ],
                      const SizedBox(width: kElementHSpacing),
                      _buildFiltersToggleButton(
                        context,
                        theme,
                        activeFiltersState,
                        platformFilter: platformFilter,
                        includePlatformFilterCount: isNarrow,
                      ),
                      const SizedBox(width: kElementHSpacing),

                      // View mode toggle (always visible)
                      _buildViewModeToggle(
                        context,
                        ref,
                        theme,
                        viewMode,
                        selectedListViewMode,
                      ),
                    ],
                  ),
                  if (widget.isVeryNarrowLayout) ...[
                    const SizedBox(height: 8),
                    _buildGamesCountChip(
                      theme,
                      gamesCount,
                      totalGamesCount,
                      expand: true,
                      centerText: true,
                    ),
                  ],

                  // Filters panel (animated show/hide)
                  SizeTransition(
                    sizeFactor: _filterPanelAnimation,
                    axisAlignment: -1.0,
                    child: FadeTransition(
                      opacity: _filterPanelAnimation,
                      child: IgnorePointer(
                        ignoring: !_showTagsPanel,
                        child: _buildTagsPanel(
                          theme,
                          tags,
                          activeFiltersState,
                          isNarrow: isNarrow,
                          isVeryNarrow: widget.isVeryNarrowLayout,
                          platformFilter: platformFilter,
                          sortMode: sortMode,
                          gamesCount: gamesCount,
                          totalGamesCount: totalGamesCount,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
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
    ListViewDensityMode selectedListViewMode,
  ) {
    return AnimatedViewModeToggle(
      theme: theme,
      isGridView: viewMode == GameListViewMode.grid,
      selectedListViewMode: selectedListViewMode,
      onToggle: () {
        final newMode = viewMode == GameListViewMode.grid
            ? GameListViewMode.list
            : GameListViewMode.grid;
        ref.read(viewModeProvider.notifier).setViewMode(newMode);
      },
      onSelectListViewMode: (mode) {
        final notifier = ref.read(settingsProvider.notifier);
        notifier.setMany(listViewDensityModeSettings(mode));
      },
    );
  }

  Widget _buildGamesCountChip(
    AppThemeData theme,
    int gamesCount,
    int totalGamesCount, {
    bool expand = false,
    bool centerText = false,
  }) {
    final labelStyle = TextStyle(
      color: theme.accent,
      fontWeight: FontWeight.w600,
    );

    final counter = Container(
      width: expand ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(theme.cornerRadius),
      ),
      child: Text(
        gamesCount < totalGamesCount
            ? '$gamesCount / $totalGamesCount Games'
            : '$gamesCount Games',
        style: labelStyle,
        textAlign: centerText ? TextAlign.center : TextAlign.start,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
      ),
    );

    final animatedCounter = ClipRect(
      child: AnimatedSize(
        duration: kFastAnimation,
        curve: Curves.easeInOutCubic,
        alignment: Alignment.centerLeft,
        child: counter,
      ),
    );

    if (expand) {
      return animatedCounter;
    }

    // Align to the left so AnimatedSize grows rightward, not in both directions.
    return Align(alignment: Alignment.centerLeft, child: animatedCounter);
  }

  // ---------------------------------------------------------------------------
  // Platform dropdown
  // ---------------------------------------------------------------------------

  Widget _buildPlatformDropdown(AppThemeData theme, String? platformFilter) {
    return DropdownButtonFormField<String>(
      initialValue: platformFilter ?? '',
      isExpanded: true,
      menuMaxHeight: kDropdownMenuMaxHeight,
      borderRadius: BorderRadius.circular(theme.cornerRadius),
      onChanged: (value) {
        final platform = (value == null || value.isEmpty) ? null : value;
        ref.read(gamesProvider.notifier).setPlatformFilter(platform);
      },
      style: TextStyle(color: theme.textPrimary),
      dropdownColor: theme.surface,
      hint: Text('All Platforms', style: TextStyle(color: theme.textHint)),
      items: [
        DropdownMenuItem<String>(
          value: '',
          child: _buildPlatformMenuLabel(theme, label: 'All Platforms'),
        ),
        ...GamePlatform.values.map(
          (p) => DropdownMenuItem<String>(
            value: p.displayName,
            child: _buildPlatformMenuLabel(
              theme,
              label: p.displayName,
              platform: p,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlatformMenuLabel(
    AppThemeData theme, {
    required String label,
    GamePlatform? platform,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (platform != null) ...[
          PlatformIcon(platform: platform, color: theme.textPrimary, size: 16),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: theme.textPrimary),
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
      menuMaxHeight: kDropdownMenuMaxHeight,
      borderRadius: BorderRadius.circular(theme.cornerRadius),
      onChanged: (value) {
        if (value != null) {
          ref.read(gamesProvider.notifier).setSortMode(value);
        }
      },
      style: TextStyle(color: theme.textPrimary),
      dropdownColor: theme.surface,
      isExpanded: true,
      items: GameSortMode.values
          .map(
            (mode) => DropdownMenuItem(
              value: mode,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_sortIconFor(mode), color: theme.textPrimary, size: 18),
                  const SizedBox(width: kElementHSpacing),
                  Flexible(
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
      bool showNoTagsOnly,
    })
    state, {
    required String? platformFilter,
    required bool includePlatformFilterCount,
  }) {
    final filterCount =
        state.tagFilters.length +
        (includePlatformFilterCount &&
                platformFilter != null &&
                platformFilter.isNotEmpty
            ? 1
            : 0) +
        (state.showDeadlineOnly ? 1 : 0) +
        (state.showDlcOnly ? 1 : 0) +
        (state.showUsedOnly ? 1 : 0) +
        (state.showNoPicturesOnly ? 1 : 0) +
        (state.showNoTagsOnly ? 1 : 0);
    final hasActiveFilters = filterCount > 0;
    final isActive = _showTagsPanel;
    final iconColor = (isActive || hasActiveFilters)
        ? theme.accent
        : theme.textSecondary;

    if (widget.isVeryNarrowLayout) {
      final btn = AppNavigationButton(
        theme: theme,
        isSelected: isActive || hasActiveFilters,
        isEnabled: true,
        isHorizontal: true,
        onTap: _toggleFilterPanel,
        iconData: Icons.tune,
        tooltipMessage:
            hasActiveFilters ? 'Filters ($filterCount active)' : 'Filters',
        selectedBackgroundColor: theme.accent.withValues(alpha: 0.30),
      );
      final withBadge = hasActiveFilters
          ? btn.withCountBadge(
              filterCount,
              backgroundColor: theme.accent,
              borderColor: theme.navBackground,
              theme: theme,
            )
          : btn;
      return GestureDetector(
        onSecondaryTapUp: (details) => _showFiltersContextMenu(
          context,
          details.globalPosition,
          theme,
          state,
        ),
        child: withBadge,
      );
    }

    return ClipRect(
      child: GestureDetector(
        onSecondaryTapUp: (details) => _showFiltersContextMenu(
          context,
          details.globalPosition,
          theme,
          state,
        ),
        child: TextButton.icon(
          onPressed: _toggleFilterPanel,
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (isActive) {
                return theme.accent.withValues(alpha: 0.30);
              }
              if (states.contains(WidgetState.hovered)) {
                return theme.navItemHover;
              }
              return Colors.transparent;
            }),
            overlayColor: WidgetStatePropertyAll(
              theme.accent.withValues(alpha: 0.16),
            ),
            foregroundColor: WidgetStatePropertyAll(theme.textPrimary),
            iconColor: WidgetStatePropertyAll(iconColor),
          ),
          icon: const Icon(Icons.tune),
          // Animate only the count suffix so the button width tracks its
          // label naturally — no manual measurement needed.
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Filters'),
              ClipRect(
                child: AnimatedSize(
                  duration: kFastAnimation,
                  curve: Curves.easeInOutCubic,
                  child: hasActiveFilters
                      ? Text(
                          ' ($filterCount)',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                        )
                      : const SizedBox.shrink(),
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
      bool showNoTagsOnly,
    })
    state, {
    required bool isNarrow,
    required bool isVeryNarrow,
    required String? platformFilter,
    required GameSortMode sortMode,
    required int gamesCount,
    required int totalGamesCount,
  }) {
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

    final hasActiveOptions =
        state.showDeadlineOnly ||
        state.showDlcOnly ||
        state.showUsedOnly ||
        state.showNoPicturesOnly ||
        state.showNoTagsOnly;
    final iconOnlyButtonStyle = ElevatedButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: const Size.square(kElementHeight),
      fixedSize: const Size.square(kElementHeight),
      maximumSize: const Size.square(kElementHeight),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final maxFilterPanelHeight = (MediaQuery.sizeOf(context).height * 0.45)
        .clamp(50.0, 450.0)
        .toDouble();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxFilterPanelHeight),
        child: Scrollbar(
          controller: _filtersScrollController,
          child: SingleChildScrollView(
            controller: _filtersScrollController,
            primary: false,
            child: SettingsSectionGroups(
              entries: [
                SectionGroupEntry(
                  visible: true,
                  builder: (position, isAlternate) => SectionGroupBox(
                    title: '',
                    showTitle: false,
                    theme: theme,
                    groupPosition: position,
                    alternateBackground: isAlternate,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: AppSearchField(
                                theme: theme,
                                backgroundColor: Color.lerp(
                                  theme.surface,
                                  theme.background,
                                  0.6,
                                ),
                                hintText: 'Search tags...',
                                onChanged: (value) =>
                                    setState(() => _tagSearchQuery = value),
                                showClearButton: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                            ),
                            const SizedBox(width: kElementHSpacing),
                            if (isVeryNarrow)
                              ElevatedButton(
                                style: iconOnlyButtonStyle,
                                onPressed: tagFilters.isNotEmpty
                                    ? () => ref
                                          .read(gamesProvider.notifier)
                                          .setTagFilters([])
                                    : null,
                                child: const Icon(Icons.label_off),
                              )
                            else
                              ElevatedButton.icon(
                                onPressed: tagFilters.isNotEmpty
                                    ? () => ref
                                          .read(gamesProvider.notifier)
                                          .setTagFilters([])
                                    : null,
                                icon: const Icon(Icons.label_off),
                                label: Text(
                                  tagFilters.isNotEmpty
                                      ? 'Clear (${tagFilters.length})'
                                      : 'Clear',
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TagList(
                          tags: filteredTags,
                          theme: theme,
                          selectedTagIds: tagFilters.toSet(),
                          onTagToggled: (tagId) => ref
                              .read(gamesProvider.notifier)
                              .toggleTagFilter(tagId),
                          maxHeight: 120,
                        ),
                      ],
                    ),
                  ),
                ),
                SectionGroupEntry(
                  visible: true,
                  builder: (position, isAlternate) => SectionGroupBox(
                    title: '',
                    showTitle: false,
                    theme: theme,
                    groupPosition: position,
                    alternateBackground: isAlternate,
                    child: Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              AppOptionChip(
                                label: 'Deadline',
                                theme: theme,
                                isSelected: state.showDeadlineOnly,
                                onTap: () => ref
                                    .read(gamesProvider.notifier)
                                    .setShowDeadlineOnly(
                                      !state.showDeadlineOnly,
                                    ),
                              ),
                              AppOptionChip(
                                label: 'DLC',
                                theme: theme,
                                isSelected: state.showDlcOnly,
                                onTap: () => ref
                                    .read(gamesProvider.notifier)
                                    .setShowDlcOnly(!state.showDlcOnly),
                              ),
                              AppOptionChip(
                                label: 'Used',
                                theme: theme,
                                isSelected: state.showUsedOnly,
                                onTap: () => ref
                                    .read(gamesProvider.notifier)
                                    .setShowUsedOnly(!state.showUsedOnly),
                              ),
                              AppOptionChip(
                                label: 'No Tags',
                                theme: theme,
                                isSelected: state.showNoTagsOnly,
                                onTap: () => ref
                                    .read(gamesProvider.notifier)
                                    .setShowNoTagsOnly(!state.showNoTagsOnly),
                              ),
                              AppOptionChip(
                                label: 'No Pictures',
                                theme: theme,
                                isSelected: state.showNoPicturesOnly,
                                onTap: () => ref
                                    .read(gamesProvider.notifier)
                                    .setShowNoPicturesOnly(
                                      !state.showNoPicturesOnly,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: kElementHSpacing),
                        if (isVeryNarrow)
                          ElevatedButton(
                            style: iconOnlyButtonStyle,
                            onPressed: hasActiveOptions
                                ? _clearBoolFilters
                                : null,
                            child: const Icon(Icons.filter_list_off),
                          )
                        else
                          ElevatedButton.icon(
                            onPressed: hasActiveOptions
                                ? _clearBoolFilters
                                : null,
                            icon: const Icon(Icons.filter_list_off),
                            label: const Text('Clear'),
                          ),
                      ],
                    ),
                  ),
                ),
                SectionGroupEntry(
                  visible: isNarrow,
                  builder: (position, isAlternate) => SectionGroupBox(
                    title: '',
                    showTitle: false,
                    theme: theme,
                    groupPosition: position,
                    alternateBackground: isAlternate,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isVeryNarrow) ...[
                          _buildPlatformDropdown(theme, platformFilter),
                          const SizedBox(height: 6),
                          _buildSortDropdown(theme, sortMode),
                        ] else
                          Row(
                            children: [
                              Expanded(
                                child: _buildPlatformDropdown(
                                  theme,
                                  platformFilter,
                                ),
                              ),
                              const SizedBox(width: kElementHSpacing),
                              Expanded(
                                child: _buildSortDropdown(theme, sortMode),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _clearBoolFilters() {
    final notifier = ref.read(gamesProvider.notifier);
    notifier.setShowDeadlineOnly(false);
    notifier.setShowDlcOnly(false);
    notifier.setShowUsedOnly(false);
    notifier.setShowNoPicturesOnly(false);
    notifier.setShowNoTagsOnly(false);
  }

  void _clearAllFilters() {
    widget.searchController.clear();
    ref.read(gamesProvider.notifier).clearAllFilters();
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
      bool showNoTagsOnly,
    })
    state,
  ) {
    final hasTagFilters = state.tagFilters.isNotEmpty;
    final hasBoolFilters =
        state.showDeadlineOnly ||
        state.showDlcOnly ||
        state.showUsedOnly ||
        state.showNoPicturesOnly ||
        state.showNoTagsOnly;
    final hasAnyFilters = hasTagFilters || hasBoolFilters;

    showAppMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
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
              const SizedBox(width: kElementHSpacing),
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
              const SizedBox(width: kElementHSpacing),
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
              const SizedBox(width: kElementHSpacing),
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
}

class _MobileSyncButton extends ConsumerWidget {
  const _MobileSyncButton({required this.theme});

  final AppThemeData theme;

  (IconData, Color) _iconForStatus(DeviceSyncStatus status) {
    switch (status) {
      case DeviceSyncStatus.discovering:
        return (Icons.radar, theme.accent);
      case DeviceSyncStatus.connecting:
        return (Icons.link, theme.accent);
      case DeviceSyncStatus.connected:
        return (Icons.link, theme.secondary);
      case DeviceSyncStatus.syncing:
        return (Icons.sync, theme.accent);
      case DeviceSyncStatus.error:
        return (Icons.link_off, theme.error);
      case DeviceSyncStatus.idle:
        return (Icons.sync_disabled, theme.textSecondary);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(deviceSyncProvider).asData?.value;
    final enabled = sync?.enabled ?? false;
    final status = sync?.status ?? DeviceSyncStatus.idle;
    var (icon, color) = _iconForStatus(status);
    final statusText = sync?.statusMessage?.toLowerCase() ?? '';
    final isUnpairNotice =
        statusText.contains('removed its pairing') ||
        statusText.contains('device removed');
    final busy =
        status == DeviceSyncStatus.syncing ||
        status == DeviceSyncStatus.discovering ||
        status == DeviceSyncStatus.connecting;

    // Surface unpair events as a broken link icon to match sync dialog state.
    if (isUnpairNotice) {
      icon = Icons.link_off;
      color = theme.textSecondary;
    }

    // When connected but DB files differ, show a broken link to signal out-of-sync.
    final hasMismatch = sync?.dbMismatchPeerIds.isNotEmpty ?? false;
    if (!isUnpairNotice && hasMismatch) {
      icon = Icons.link_off;
      color = Colors.orange;
    }

    return IconButton(
      tooltip: 'Device Sync',
      iconSize: 22,
      onPressed: () => showDeviceSyncDialog(context),
      icon: busy
          ? SizedBox(
              width: 20,
              height: 20,
              child: AppCircularProgressIndicator(
                color: enabled ? theme.secondary : theme.textSecondary,
                strokeWidth: 2,
              ),
            )
          : Icon(
              icon,
              color: enabled ? color : theme.textSecondary,
            ),
    );
  }
}
