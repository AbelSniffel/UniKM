/// Home page header with search, filters, tags, and view mode toggle
library;

import 'package:flutter/material.dart';
import '../../widgets/app_combo_box.dart';
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
import '../../widgets/app_tab_bar.dart';
import '../../widgets/app_progress_indicator.dart';
import '../../widgets/app_tag_chip.dart';
import '../../widgets/platform_icon.dart';
import '../../widgets/page_bar_surface.dart';
import '../../widgets/popup_menu_helpers.dart';
import '../../widgets/section_groupbox.dart';
import '../../widgets/tag_list.dart';
import 'animated_view_mode_toggle.dart';

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
  bool _showFiltersPanel = false;
  final ScrollController _filtersScrollController = ScrollController();
  late final AnimationController _filterPanelController;
  String _tagSearchQuery = '';
  final _tagSearchController = TextEditingController();
  int _filterTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _filterPanelController = AnimationController(
      vsync: this,
      duration: kFilterExpandAnimation,
    );
  }

  @override
  void didUpdateWidget(covariant HomeHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isVeryNarrowLayout && _filterTabIndex == 2) {
      _filterTabIndex = 0;
    }
  }

  @override
  void dispose() {
    _tagSearchController.dispose();
    _filtersScrollController.dispose();
    _filterPanelController.dispose();
    super.dispose();
  }

  void _toggleFilterPanel() {
    setState(() => _showFiltersPanel = !_showFiltersPanel);
    final target = _showFiltersPanel ? 1.0 : 0.0;
    final duration = _showFiltersPanel
        ? kFilterExpandAnimation
        : kFilterCollapseAnimation;
    _filterPanelController.animateTo(
      target,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : Duration(
              microseconds:
                  (duration.inMicroseconds *
                          (target - _filterPanelController.value).abs())
                      .round(),
            ),
      curve: kFilterPanelCurve,
    );
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

    return PageBarSurface(
      theme: theme,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Home/view control, game count, and search/filters inline
            LayoutBuilder(
              builder: (context, constraints) {
                final viewModeToggle = _buildViewModeToggle(
                  context,
                  ref,
                  theme,
                  viewMode,
                  selectedListViewMode,
                );
                final searchField = AppSearchField(
                  theme: theme,
                  controller: widget.searchController,
                  focusNode: widget.searchFocusNode,
                  hintText: 'Search by title or key...',
                  onChanged: (value) => ref
                      .read(gamesProvider.notifier)
                      .setSearchQueryDebounced(value),
                  onCleared: () =>
                      ref.read(gamesProvider.notifier).setSearchQuery(''),
                );
                final filtersButton = _buildFiltersToggleButton(
                  context,
                  theme,
                  activeFiltersState,
                  platformFilter: platformFilter,
                );
                final counter = _buildGamesCountChip(
                  theme,
                  gamesCount,
                  totalGamesCount,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.isVeryNarrowLayout) ...[
                      Row(
                        children: [
                          _LibrarySyncButton(theme: theme),
                          const SizedBox(width: kElementHSpacing),
                          Expanded(
                            child: _buildGamesCountChip(
                              theme,
                              gamesCount,
                              totalGamesCount,
                              expand: true,
                              centerText: true,
                            ),
                          ),
                          const SizedBox(width: kElementHSpacing),
                          viewModeToggle,
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: searchField),
                          const SizedBox(width: kElementHSpacing),
                          filtersButton,
                        ],
                      ),
                    ] else
                      Row(
                        children: [
                          if (isMobilePlatform) ...[
                            _LibrarySyncButton(theme: theme),
                            const SizedBox(width: kElementHSpacing),
                          ],
                          counter,
                          const SizedBox(width: kElementHSpacing),
                          Expanded(flex: 2, child: searchField),
                          const SizedBox(width: kElementHSpacing),
                          Expanded(
                            child: _buildPlatformDropdown(
                              theme,
                              platformFilter,
                            ),
                          ),
                          const SizedBox(width: kElementHSpacing),
                          Expanded(child: _buildSortDropdown(theme, sortMode)),
                          const SizedBox(width: kElementHSpacing),
                          filtersButton,
                          const SizedBox(width: kElementHSpacing),
                          viewModeToggle,
                        ],
                      ),

                    // Filters panel (animated show/hide)
                    SizeTransition(
                      sizeFactor: _filterPanelController,
                      alignment: Alignment.topCenter,
                      child: FadeTransition(
                        opacity: _filterPanelController,
                        child: IgnorePointer(
                          ignoring: !_showFiltersPanel,
                          child: _buildFiltersPanel(
                            theme,
                            tags,
                            activeFiltersState,
                            isVeryNarrow: widget.isVeryNarrowLayout,
                            platformFilter: platformFilter,
                            sortMode: sortMode,
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
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // View mode toggle
  // ---------------------------------------------------------------------------

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
      key: const ValueKey('library-game-counter'),
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

    if (expand) return animatedCounter;
    return Align(alignment: Alignment.centerLeft, child: animatedCounter);
  }

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
      onSelectGridView: () => ref
          .read(viewModeProvider.notifier)
          .setViewMode(GameListViewMode.grid),
      onSelectListViewMode: (mode) {
        final notifier = ref.read(settingsProvider.notifier);
        notifier.setMany({
          ...listViewDensityModeSettings(mode),
          SettingsKeys.gameListViewMode: GameListViewMode.list,
        });
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Platform dropdown
  // ---------------------------------------------------------------------------

  Widget _buildPlatformDropdown(AppThemeData theme, String? platformFilter) {
    return AppComboBox<String>(
      initialValue: platformFilter ?? '',
      onChanged: (value) {
        final platform = (value == null || value.isEmpty) ? null : value;
        ref.read(gamesProvider.notifier).setPlatformFilter(platform);
      },
      theme: theme,
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
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Sort dropdown
  // ---------------------------------------------------------------------------

  Widget _buildSortDropdown(AppThemeData theme, GameSortMode sortMode) {
    return AppComboBox<GameSortMode>(
      initialValue: sortMode,
      onChanged: (value) {
        if (value != null) {
          ref.read(gamesProvider.notifier).setSortMode(value);
        }
      },
      theme: theme,
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
  }) {
    final filterCount =
        state.tagFilters.length +
        (platformFilter != null && platformFilter.isNotEmpty ? 1 : 0) +
        (state.showDeadlineOnly ? 1 : 0) +
        (state.showDlcOnly ? 1 : 0) +
        (state.showUsedOnly ? 1 : 0) +
        (state.showNoPicturesOnly ? 1 : 0) +
        (state.showNoTagsOnly ? 1 : 0);
    final hasActiveFilters = filterCount > 0;
    final isActive = _showFiltersPanel;
    final btn = AppNavigationButton(
      theme: theme,
      isSelected: isActive || hasActiveFilters,
      isEnabled: true,
      isHorizontal: true,
      hasNotification: hasActiveFilters,
      onTap: _toggleFilterPanel,
      iconData: Icons.tune,
      tooltipMessage: hasActiveFilters
          ? 'Filters ($filterCount active)'
          : 'Filters',
      selectedBackgroundColor: theme.accent.withValues(alpha: 0.30),
    );
    return GestureDetector(
      onSecondaryTapUp: (details) => _showFiltersContextMenu(
        context,
        details.globalPosition,
        theme,
        state,
      ),
      child: btn,
    );
  }

  // ---------------------------------------------------------------------------
  // Filters panel (expandable)
  // ---------------------------------------------------------------------------

  Widget _buildFiltersPanel(
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
    required bool isVeryNarrow,
    required String? platformFilter,
    required GameSortMode sortMode,
  }) {
    final selectedTagIds = state.tagFilters.toSet();
    final matchingTags = tags
        .where(
          (tag) =>
              _tagSearchQuery.isEmpty ||
              tag.name.toLowerCase().contains(_tagSearchQuery.toLowerCase()),
        )
        .toList();
    final optionCount = [
      state.showDeadlineOnly,
      state.showDlcOnly,
      state.showUsedOnly,
      state.showNoTagsOnly,
      state.showNoPicturesOnly,
    ].where((enabled) => enabled).length;
    final platformCount = platformFilter?.isNotEmpty == true ? 1 : 0;
    final hasSortingOverrides =
        platformCount > 0 || sortMode != DefaultSettings.gameSortMode;
    final tabId = ['tags', 'options', 'sorting'][_filterTabIndex];
    final maxFilterPanelHeight = (MediaQuery.sizeOf(context).height * 0.45)
        .clamp(50.0, 450.0)
        .toDouble();
    final notifier = ref.read(gamesProvider.notifier);

    String tabLabel(String label, int count) =>
        count > 0 ? '$label ($count)' : label;
    Widget group(Widget child) => SectionGroupBox(
      key: ValueKey('home-filter-group-$tabId'),
      title: '',
      showTitle: false,
      theme: theme,
      child: child,
    );
    final content = switch (_filterTabIndex) {
      0 => group(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSearchField(
              theme: theme,
              backgroundColor: Color.lerp(theme.surface, theme.background, 0.6),
              hintText: 'Search tags...',
              controller: _tagSearchController,
              onChanged: (value) => setState(() => _tagSearchQuery = value),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
            const SizedBox(height: 6),
            TagList(
              tags: matchingTags,
              selectedTagIds: selectedTagIds,
              theme: theme,
              onTagToggled: notifier.toggleTagFilter,
              maxHeight: 120,
            ),
          ],
        ),
      ),
      1 => group(
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            AppOptionChip(
              label: 'Deadline',
              theme: theme,
              isSelected: state.showDeadlineOnly,
              onTap: () =>
                  notifier.setShowDeadlineOnly(!state.showDeadlineOnly),
            ),
            AppOptionChip(
              label: 'DLC',
              theme: theme,
              isSelected: state.showDlcOnly,
              onTap: () => notifier.setShowDlcOnly(!state.showDlcOnly),
            ),
            AppOptionChip(
              label: 'Used',
              theme: theme,
              isSelected: state.showUsedOnly,
              onTap: () => notifier.setShowUsedOnly(!state.showUsedOnly),
            ),
            AppOptionChip(
              label: 'No Tags',
              theme: theme,
              isSelected: state.showNoTagsOnly,
              onTap: () => notifier.setShowNoTagsOnly(!state.showNoTagsOnly),
            ),
            AppOptionChip(
              label: 'No Pictures',
              theme: theme,
              isSelected: state.showNoPicturesOnly,
              onTap: () =>
                  notifier.setShowNoPicturesOnly(!state.showNoPicturesOnly),
            ),
          ],
        ),
      ),
      _ => group(
        Column(
          children: [
            _buildPlatformDropdown(theme, platformFilter),
            const SizedBox(height: 6),
            _buildSortDropdown(theme, sortMode),
          ],
        ),
      ),
    };
    final VoidCallback? onClear = switch (_filterTabIndex) {
      0 => selectedTagIds.isEmpty ? null : () => notifier.setTagFilters([]),
      1 => optionCount == 0 ? null : _clearBoolFilters,
      _ =>
        !hasSortingOverrides
            ? null
            : () async {
                notifier.setPlatformFilter(null);
                await notifier.setSortMode(DefaultSettings.gameSortMode);
              },
    };
    final panel = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxFilterPanelHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTabBar(
            key: const ValueKey('home-filter-tabs'),
            theme: theme,
            tabs: [
              AppTab(tabLabel('Tags', selectedTagIds.length)),
              AppTab(tabLabel('Options', optionCount)),
              if (isVeryNarrow) AppTab(tabLabel('Sorting', platformCount)),
            ],
            selectedIndex: _filterTabIndex,
            onChanged: (index) {
              if (_filtersScrollController.hasClients) {
                _filtersScrollController.jumpTo(0);
              }
              setState(() => _filterTabIndex = index);
            },
          ),
          const SizedBox(height: 8),
          Flexible(
            child: Scrollbar(
              controller: _filtersScrollController,
              child: SingleChildScrollView(
                controller: _filtersScrollController,
                primary: false,
                child: AppTabTransition(
                  index: _filterTabIndex,
                  child: KeyedSubtree(
                    key: ValueKey('home-filter-tab-$tabId'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        content,
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            key: ValueKey(
                              'home-filter-$tabId-${_filterTabIndex == 2 ? 'default' : 'clear'}',
                            ),
                            onPressed: onClear,
                            icon: Icon(
                              _filterTabIndex == 2
                                  ? Icons.restore
                                  : Icons.filter_list_off,
                            ),
                            label: Text(
                              _filterTabIndex == 2 ? 'Default' : 'Clear',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Padding(
      key: const ValueKey('home-filter-panel-height'),
      padding: const EdgeInsets.only(top: 8),
      child: MediaQuery.disableAnimationsOf(context)
          ? panel
          : AnimatedSize(
              duration: kFilterExpandAnimation,
              curve: kFilterPanelCurve,
              alignment: Alignment.topCenter,
              child: panel,
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
    final hasAnyFilters =
        hasTagFilters ||
        hasBoolFilters ||
        ref.read(gamesProvider).platformFilter?.isNotEmpty == true;

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
              Expanded(
                child: Text(
                  'Clear Tag Filters',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hasTagFilters ? theme.textPrimary : theme.textHint,
                  ),
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
              Expanded(
                child: Text(
                  'Clear Options',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hasBoolFilters ? theme.textPrimary : theme.textHint,
                  ),
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
              Expanded(
                child: Text(
                  'Clear All Filters',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hasAnyFilters ? theme.textPrimary : theme.textHint,
                  ),
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

class _LibrarySyncButton extends ConsumerWidget {
  const _LibrarySyncButton({required this.theme});

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
          : Icon(icon, color: enabled ? color : theme.textSecondary),
    );
  }
}
