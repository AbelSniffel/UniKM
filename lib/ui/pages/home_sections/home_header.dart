/// Home page header: the game count, search, icon-only platform and sort
/// menus and the filters button. The button opens the filter sidebar beside
/// the library, or on very narrow layouts an expandable panel below the
/// toolbar.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../dialogs/device_sync_dialog.dart';
import '../../dialogs/library_stats_dialog.dart';
import '../../widgets/app_scrollbar.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/device_sync_icon.dart';
import '../../widgets/background_pattern.dart';
import '../../widgets/popup_menu_helpers.dart';
import 'home_filters_panel.dart';

/// Below these toolbar widths the search hint is shortened.
const double _kLongSearchHintMinWidth = 460;
const double _kMediumSearchHintMinWidth = 400;

class HomeHeader extends ConsumerStatefulWidget {
  const HomeHeader({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
    required this.isVeryNarrowLayout,
  });

  final TextEditingController searchController;
  final FocusNode searchFocusNode;

  /// Very narrow layouts have no title bar sync icon, so the header shows it,
  /// and keep the filters in a panel below the toolbar instead of the
  /// sidebar.
  final bool isVeryNarrowLayout;

  @override
  ConsumerState<HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends ConsumerState<HomeHeader>
    with SingleTickerProviderStateMixin {
  // The panel below the toolbar on very narrow layouts. It follows the
  // filters' shared open state, as the sidebar does, so it is already open
  // or closed when the layout turns very narrow. Only the filters button and
  // the panel's pointer guard watch it, so toggling does not rebuild the
  // toolbar and the whole filter panel.
  final ScrollController _filtersScrollController = ScrollController();
  late final AnimationController _filterPanelController;

  bool get _filtersOpen => homeFiltersOpen(
    ref.read(homeFiltersOpenProvider),
    veryNarrow: widget.isVeryNarrowLayout,
  );

  @override
  void initState() {
    super.initState();
    _filterPanelController = AnimationController(
      vsync: this,
      duration: kFilterExpandAnimation,
      value: _filtersOpen ? 1 : 0,
    );
    // The first layout settles the shared state; it cannot change while the
    // tree builds.
    if (ref.read(homeFiltersOpenProvider) == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ref.read(homeFiltersOpenProvider) != null) return;
        ref.read(homeFiltersOpenProvider.notifier).set(_filtersOpen);
      });
    }
  }

  @override
  void dispose() {
    _filtersScrollController.dispose();
    _filterPanelController.dispose();
    super.dispose();
  }

  GamesNotifier get _notifier => ref.read(gamesProvider.notifier);

  /// Opens or closes the filters: the panel below the toolbar on very
  /// narrow layouts and the sidebar otherwise.
  void _toggleFilters() =>
      ref.read(homeFiltersOpenProvider.notifier).set(!_filtersOpen);

  /// Filters set in the filter panel. The platform counts only while its
  /// button sits in the panel; on the toolbar it shows for itself.
  int _activeFilterCount(LibraryFilter state, String? platformFilter) =>
      state.tagFilters.length +
      homeFilterOptions.where((option) => option.isOn(state)).length +
      (widget.isVeryNarrowLayout && platformFilter?.isNotEmpty == true ? 1 : 0);

  void _clearAllFilters() {
    widget.searchController.clear();
    _notifier.clearAllFilters();
  }

  @override
  Widget build(BuildContext context) {
    // Follows the shared state while wide too, so the panel is already open
    // or closed when the layout turns very narrow.
    ref.listen<bool?>(
      homeFiltersOpenProvider,
      (_, open) => animateHomeFilterReveal(
        context,
        _filterPanelController,
        show: homeFiltersOpen(open, veryNarrow: widget.isVeryNarrowLayout),
      ),
    );
    final theme = ref.watch(themeProvider);
    final platformFilter = ref.watch(
      gamesProvider.select((s) => s.filter.platformFilter),
    );
    final filters = ref.watch(activeFiltersProvider);
    final platform = Theme.of(context).platform;
    final narrow = widget.isVeryNarrowLayout;
    final showSync =
        narrow ||
        platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS;

    // The header never takes more than about half the screen: the filter
    // panel scrolls below the toolbar, which stays put, so the library always
    // keeps room on short or large-text screens.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.55;
    // Styled like the settings section list: the navigation panel's color
    // and pattern, a little stronger than the page's, with a bottom border
    // and a soft shadow over the library.
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.border)),
        boxShadow: [
          BoxShadow(
            color: theme.border.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: PanelPatternSurface(
        strength: PanelPatternSurface.sidePanelStrength,
        child: Material(
          key: const ValueKey('home-header-surface'),
          type: MaterialType.transparency,
          // Keep the inherited text style, as the raised bar did.
          textStyle: DefaultTextStyle.of(context).style,
          child: Padding(
            // 6px of the side and bottom insets sit inside the toolbar and the
            // scrolling panel, so groupbox shadows are never clipped.
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(0, maxHeight - 14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                    child: LayoutBuilder(
                      builder: (context, constraints) => _buildToolbar(
                        theme,
                        filters,
                        platformFilter: platformFilter,
                        showSync: showSync,
                        width: constraints.maxWidth,
                      ),
                    ),
                  ),
                  if (narrow)
                    Flexible(
                      child: AppScrollbar(
                        controller: _filtersScrollController,
                        child: SingleChildScrollView(
                          controller: _filtersScrollController,
                          primary: false,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizeTransition(
                                sizeFactor: _filterPanelController,
                                alignment: Alignment.topCenter,
                                child: FadeTransition(
                                  opacity: _filterPanelController,
                                  child: Consumer(
                                    builder: (context, ref, panel) =>
                                        IgnorePointer(
                                          ignoring: !homeFiltersOpen(
                                            ref.watch(homeFiltersOpenProvider),
                                            veryNarrow: true,
                                          ),
                                          child: panel,
                                        ),
                                    child: const HomeFiltersPanel(
                                      sidebar: false,
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
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Toolbar: count, search, filters and view
  // ---------------------------------------------------------------------------

  Widget _buildToolbar(
    AppThemeData theme,
    LibraryFilter filters, {
    required String? platformFilter,
    required bool showSync,
    required double width,
  }) {
    const gap = SizedBox(width: kElementHSpacing);
    final narrow = widget.isVeryNarrowLayout;
    // On very narrow layouts the count shares a row with sync and filters,
    // above a full-width search, and platform and sort move into the filter
    // panel. Otherwise one row holds them all, the search in the middle. The
    // view choice lives in the navigation panel's More menu.
    final sync = showSync ? _LibrarySyncButton(theme: theme) : null;
    final countLabel = _GamesCount(theme: theme);
    final search = AppSearchField(
      theme: theme,
      controller: widget.searchController,
      focusNode: widget.searchFocusNode,
      hintText: width >= _kLongSearchHintMinWidth
          ? 'Search by title or key...'
          : width >= _kMediumSearchHintMinWidth
          ? 'Search games...'
          : 'Search...',
      onChanged: _notifier.setSearchQueryDebounced,
      onCleared: () => _notifier.setSearchQuery(''),
    );
    final actions = _buttonRow(key: const ValueKey('home-toolbar-actions'), [
      if (!narrow) ...buildHomePlatformAndSort(ref, theme, platformFilter),
      _buildFiltersToggleButton(theme, filters, platformFilter),
    ]);
    if (!narrow) {
      return Row(
        children: [
          if (sync != null) ...[sync, gap],
          countLabel,
          gap,
          Expanded(child: search),
          gap,
          actions,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (sync != null) ...[sync, gap],
            Expanded(child: countLabel),
            gap,
            actions,
          ],
        ),
        const SizedBox(height: 8),
        search,
      ],
    );
  }

  /// Separate header buttons in a row, all as tall as the search bar.
  static Widget _buttonRow(List<Widget> children, {Key? key}) => SizedBox(
    height: kElementHeight,
    child: Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: kElementHSpacing,
      children: children,
    ),
  );

  Widget _buildFiltersToggleButton(
    AppThemeData theme,
    LibraryFilter filters,
    String? platformFilter,
  ) {
    final filterCount = _activeFilterCount(filters, platformFilter);
    final hasActiveFilters = filterCount > 0;
    Widget button(bool show, IconData shownIcon) => AppNavigationButton(
      theme: theme,
      isSelected: show || hasActiveFilters,
      isEnabled: true,
      isHorizontal: true,
      hasNotification: hasActiveFilters,
      onTap: _toggleFilters,
      iconBuilder: (context, _, size) =>
          Icon(show ? shownIcon : Icons.tune, color: theme.accent, size: size),
      tooltipMessage: hasActiveFilters
          ? 'Filters ($filterCount active)'
          : 'Filters',
      selectedBackgroundColor: theme.accent.withValues(alpha: 0.30),
    );
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showFiltersContextMenu(details.globalPosition, theme, filters),
      child: Consumer(
        builder: (context, ref, _) => button(
          homeFiltersOpen(
            ref.watch(homeFiltersOpenProvider),
            veryNarrow: widget.isVeryNarrowLayout,
          ),
          widget.isVeryNarrowLayout ? Icons.expand_less : Icons.tune,
        ),
      ),
    );
  }

  void _showFiltersContextMenu(
    Offset globalPosition,
    AppThemeData theme,
    LibraryFilter state,
  ) {
    final hasTagFilters = state.tagFilters.isNotEmpty;
    final hasBoolFilters = homeFilterOptions.any(
      (option) => option.isOn(state),
    );
    final hasAnyFilters =
        hasTagFilters ||
        hasBoolFilters ||
        ref.read(gamesProvider).filter.platformFilter?.isNotEmpty == true;

    Widget item(IconData icon, String label, VoidCallback? onPressed) =>
        appMenuItem(
          theme,
          leading: Icon(icon, size: 18),
          onPressed: onPressed,
          child: Text(label),
        );

    showAppContextMenu(
      context: context,
      theme: theme,
      position: globalPosition,
      menuChildren: [
        item(
          Icons.label_off_outlined,
          'Clear Tag Filters',
          hasTagFilters ? () => _notifier.setTagFilters([]) : null,
        ),
        item(
          Icons.filter_alt_off_outlined,
          'Clear Options',
          hasBoolFilters ? () => clearHomeOptionFilters(_notifier) : null,
        ),
        appMenuDivider(theme),
        item(
          Icons.clear_all,
          'Clear All Filters',
          hasAnyFilters ? _clearAllFilters : null,
        ),
      ],
    );
  }
}

/// The library size, or "12 / 263 Games" while filters narrow it, as a
/// button that opens the library stats.
class _GamesCount extends ConsumerWidget {
  const _GamesCount({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = ref.watch(
      gamesProvider.select((s) => s.filteredGames.length),
    );
    final total = ref.watch(gamesProvider.select((s) => s.games.length));
    return Tooltip(
      message: 'Library stats',
      child: ElevatedButton(
        key: const ValueKey('library-game-counter'),
        onPressed: () =>
            showLibraryStatsDialog(context, ref.read(allGamesProvider)),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 40),
        ),
        child: Text(
          shown < total ? '$shown / $total Games' : '$total Games',
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _LibrarySyncButton extends ConsumerWidget {
  const _LibrarySyncButton({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The title bar's icon, so both buttons always agree.
    final (:icon, :color) = deviceSyncIcon(
      theme,
      ref.watch(deviceSyncProvider).asData?.value,
    );

    // Same button style as the view toggle.
    return AppNavigationButton(
      theme: theme,
      isSelected: false,
      isEnabled: true,
      isHorizontal: true,
      onTap: () => showDeviceSyncDialog(context),
      tooltipMessage: 'Device Sync',
      iconBuilder: (context, _, size) =>
          Icon(icon, color: color ?? theme.textSecondary, size: size),
    );
  }
}
