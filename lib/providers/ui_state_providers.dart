/// Riverpod providers for UI state (page navigation, view mode, drag selection).
library;

import 'package:material_ui/material_ui.dart' show IconData, Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/steam_service.dart';
import '../core/settings/settings_model.dart';
import '../core/utils/batch_parser.dart';
import '../models/game.dart';
import '../shared/state/session_value.dart';
import 'games_providers.dart' show gamesProvider;
import 'settings_providers.dart';
import '../core/theme/app_theme.dart' show AppThemeData;
import 'theme_providers.dart' show builtInThemeIdsProvider, themeProvider;

/// Window restoration belongs to the app session, rather than to a database
/// shell which is recreated when a database is switched or reloaded.
final desktopWindowSessionProvider = Provider((ref) => DesktopWindowSession());

class DesktopWindowSession {
  bool _initialized = false;

  bool claimInitialization() {
    if (_initialized) return false;
    _initialized = true;
    return true;
  }
}

// =============================================================================
// NAV ITEMS
// =============================================================================

/// The top-level navigation destinations in the app. The buttons always
/// show the filled [icon], chosen or not.
enum NavItem(final String label, final IconData icon) {
  home('Library', Icons.home),
  addGames('Add', Icons.add_circle),
  updates('Updates', Icons.download_rounded),
  settings('Settings', Icons.settings);

  /// The destinations with a navigation button, in order. Updates opens from
  /// the navigation panel's More menu.
  static const pages = [home, addGames, settings];
}

/// Current navigation state. [NavItem.updates] opens a dialog instead of a
/// page, so it is never current.
final currentNavProvider = sessionValueProvider(NavItem.home);

/// Whether the update dialog is shown; setting it opens the dialog.
final updateDialogOpenProvider = sessionValueProvider(false);

// =============================================================================
// PAGE NAVIGATION
// =============================================================================

/// The developer gallery is mounted only while explicitly opened.
final dialogGalleryVisibleProvider = sessionValueProvider(false);

/// Last known game library scroll offset.
///
/// Used to restore the library position when the Home page is rebuilt.
final gameLibraryScrollOffsetProvider = sessionValueProvider(0.0);

/// Whether the library's filters are open: in the sidebar beside the
/// library, or on very narrow layouts in the panel below the toolbar. Both
/// follow this one state, so changing layout keeps them open or closed.
///
/// Null until the library first shows, then set by its layout: open as a
/// sidebar, closed below the toolbar, where it would cover the library. Read
/// it through [homeFiltersOpen].
final homeFiltersOpenProvider = sessionValueProvider<bool?>(null);

/// Whether the library's filters are open, given whether the layout is very
/// narrow until [homeFiltersOpenProvider] is set.
bool homeFiltersOpen(bool? open, {required bool veryNarrow}) =>
    open ?? !veryNarrow;

final settingsPageSelectedSectionProvider = sessionValueProvider('all');

final settingsPageSearchQueryProvider = sessionValueProvider('');

/// Theme-picker tab memory lasts for this app session, including nav changes.
final navigationThemeMenuTabProvider =
    NotifierProvider<NavigationThemeMenuTabNotifier, int>(
      NavigationThemeMenuTabNotifier.new,
    );

/// A theme collection tab (0 Default, 1 Custom) that opens on the active
/// theme's collection and moves to it whenever the active theme changes,
/// including a newly created theme. Live editor previews leave it alone.
class NavigationThemeMenuTabNotifier extends Notifier<int> {
  // From the theme itself: providers derived from the theme may not have
  // updated yet while it notifies.
  int _tabFor(AppThemeData theme) =>
      ref.read(builtInThemeIdsProvider).contains(theme.id) ? 0 : 1;

  @override
  int build() {
    ref.listen(themeProvider, (_, theme) {
      if (!ref.read(themeProvider.notifier).isPreviewMode) {
        state = _tabFor(theme);
      }
    });
    return _tabFor(ref.read(themeProvider));
  }

  void setIndex(int index) => state = index.clamp(0, 1);
}

/// Appearance remembers its own theme collection for this app session.
final appearanceThemeTabProvider =
    NotifierProvider<NavigationThemeMenuTabNotifier, int>(
      NavigationThemeMenuTabNotifier.new,
    );

const String kAutoDetectPlatformValue = '__auto__';

final addGamesSelectedTabProvider = sessionValueProvider(0);

class const AddGamesSingleEntryDraft({
  final String title = '',
  final String gameKey = '',
  final String notes = '',
  final String coverImage = '',
  final String platform = kAutoDetectPlatformValue,
  final bool hasDeadline = false,
  final DateTime? deadlineDate,
  final bool isDlc = false,
  final bool isUsed = false,
  final Set<int> selectedTagIds = const <int>{},
  final List<Tag> fetchedSteamTags = const <Tag>[],
  final SteamSearchResult? steamPreview,
  final DateTime? singleSteamCacheAt,
});

final addGamesSingleEntryDraftProvider = sessionValueProvider(
  const AddGamesSingleEntryDraft(),
);

class const AddGamesBatchDraft({
  final String text = '',
  final String platform = kAutoDetectPlatformValue,
  final bool hasDeadline = false,
  final DateTime? deadlineDate,
  final List<ParsedBatchEntry> parsedGames = const <ParsedBatchEntry>[],
  final Map<String, SteamSearchResult?> steamResults =
      const <String, SteamSearchResult?>{},
  final Map<String, String?> steamErrors = const <String, String?>{},
});

final addGamesBatchDraftProvider = sessionValueProvider(
  const AddGamesBatchDraft(),
);

// =============================================================================
// VIEW MODE
// =============================================================================

/// View mode provider (grid/list)
class ViewModeNotifier extends Notifier<GameListViewMode> {
  @override
  GameListViewMode build() => ref.watch(gameListViewModeSettingProvider);

  Future<void> setViewMode(GameListViewMode mode) async {
    state = mode;
    await ref
        .read(settingsProvider.notifier)
        .set(SettingsKeys.gameListViewMode, mode);
  }
}

final viewModeProvider = NotifierProvider<ViewModeNotifier, GameListViewMode>(
  ViewModeNotifier.new,
);

/// Last selected game ID for range selection
final lastSelectedGameIdProvider = sessionValueProvider<int?>(null);

final selectionMultiSelectModeProvider = sessionValueProvider(false);

/// Whether the home page's selection ribbon is open. Selecting a game opens
/// it, and only its close button closes it: emptying the selection any other
/// way leaves it open.
final selectionRibbonOpenProvider =
    NotifierProvider<SelectionRibbonOpenNotifier, bool>(
      SelectionRibbonOpenNotifier.new,
    );

class SelectionRibbonOpenNotifier extends Notifier<bool> {
  @override
  bool build() {
    final hasSelection = gamesProvider.select(
      (s) => s.selectedGameIds.isNotEmpty,
    );
    ref.listen(hasSelection, (_, selected) {
      if (selected) state = true;
    });
    return ref.read(hasSelection);
  }

  void close() => state = false;
}

// =============================================================================
// PAGE NOTIFICATIONS
// =============================================================================

/// Tracks which nav pages currently have an active notification (unread alert).
/// When a page is in this set, the shell can render an attention state for its
/// nav button.
final pageNotificationsProvider =
    NotifierProvider<PageNotificationsNotifier, Set<NavItem>>(
      PageNotificationsNotifier.new,
    );

class PageNotificationsNotifier extends Notifier<Set<NavItem>> {
  @override
  Set<NavItem> build() => const {};

  void add(NavItem item) => state = {...state, item};

  void remove(NavItem item) => state = state.difference({item});
}

// =============================================================================
// DRAG SELECTION
// =============================================================================

enum DragSelectionMode() {
  select,
  deselect,
}

class const DragSelectionState({
  final bool isActive = false,
  final DragSelectionMode? mode,
  final Set<int> visitedIds = const {},
}) {
  DragSelectionState copyWith({
    bool? isActive,
    DragSelectionMode? mode,
    Set<int>? visitedIds,
  }) => DragSelectionState(
    isActive: isActive ?? this.isActive,
    mode: mode ?? this.mode,
    visitedIds: visitedIds ?? this.visitedIds,
  );
}

class DragSelectionNotifier extends Notifier<DragSelectionState> {
  @override
  DragSelectionState build() => const DragSelectionState();

  void start() => state = const DragSelectionState(isActive: true);

  void stop() => state = const DragSelectionState();

  void setMode(DragSelectionMode mode) {
    if (state.mode == mode) return;
    state = state.copyWith(mode: mode);
  }

  void markVisited(int id) {
    if (state.visitedIds.contains(id)) return;
    state = state.copyWith(visitedIds: {...state.visitedIds, id});
  }

  void unmarkVisited(int id) {
    if (!state.visitedIds.contains(id)) return;
    final nextVisited = Set<int>.from(state.visitedIds)..remove(id);
    state = state.copyWith(visitedIds: nextVisited);
  }
}

final dragSelectionProvider =
    NotifierProvider<DragSelectionNotifier, DragSelectionState>(
      DragSelectionNotifier.new,
    );
