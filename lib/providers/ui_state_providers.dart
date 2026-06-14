/// Riverpod providers for UI state (page navigation, view mode, drag selection).
library;

import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/steam_service.dart';
import '../core/settings/settings_model.dart';
import '../core/utils/batch_parser.dart';
import '../models/game.dart';
import 'settings_providers.dart';

// =============================================================================
// NAV ITEMS
// =============================================================================

/// The top-level navigation destinations in the app.
enum NavItem {
  home('Library', Icons.home, Icons.home_outlined),
  addGames('Add', Icons.add_circle, Icons.add_circle_outline),
  updates('Updates', Icons.download_rounded, Icons.download_rounded),
  settings('Settings', Icons.settings, Icons.settings_outlined);

  const NavItem(this.label, this.selectedIcon, this.unselectedIcon);

  final String label;
  final IconData selectedIcon;
  final IconData unselectedIcon;
}

/// Current navigation state
final currentNavProvider = NotifierProvider<CurrentNavNotifier, NavItem>(
  CurrentNavNotifier.new,
);

class CurrentNavNotifier extends Notifier<NavItem> {
  @override
  NavItem build() => NavItem.home;

  void setNav(NavItem navItem) {
    state = navItem;
  }
}

// =============================================================================
// PAGE NAVIGATION
// =============================================================================

/// Current page index provider
final currentPageProvider = NotifierProvider<CurrentPageNotifier, int>(
  CurrentPageNotifier.new,
);

class CurrentPageNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setPage(int pageIndex) {
    state = pageIndex;
  }
}

/// Last known game library scroll offset.
///
/// Used to restore the library position when the Home page is rebuilt.
final gameLibraryScrollOffsetProvider =
    NotifierProvider<GameLibraryScrollOffsetNotifier, double>(
      GameLibraryScrollOffsetNotifier.new,
    );

class GameLibraryScrollOffsetNotifier extends Notifier<double> {
  @override
  double build() => 0.0;

  void setOffset(double offset) {
    state = offset;
  }
}

final homePageEntryAnimationsPlayedProvider =
    NotifierProvider<HomePageEntryAnimationsPlayedNotifier, bool>(
      HomePageEntryAnimationsPlayedNotifier.new,
    );

class HomePageEntryAnimationsPlayedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void markPlayed() {
    state = true;
  }
}

final settingsPageSelectedSectionProvider =
    NotifierProvider<SettingsPageSelectedSectionNotifier, String>(
      SettingsPageSelectedSectionNotifier.new,
    );

class SettingsPageSelectedSectionNotifier extends Notifier<String> {
  @override
  String build() => 'all';

  void setSelectedSection(String sectionId) {
    state = sectionId;
  }
}

final settingsPageSearchQueryProvider =
    NotifierProvider<SettingsPageSearchQueryNotifier, String>(
      SettingsPageSearchQueryNotifier.new,
    );

class SettingsPageSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) {
    state = query;
  }
}

const String kAutoDetectPlatformValue = '__auto__';

final addGamesSelectedTabProvider =
    NotifierProvider<AddGamesSelectedTabNotifier, int>(
      AddGamesSelectedTabNotifier.new,
    );

class AddGamesSelectedTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setIndex(int index) {
    state = index.clamp(0, 1);
  }
}

class AddGamesSingleEntryDraft {
  const AddGamesSingleEntryDraft({
    this.title = '',
    this.gameKey = '',
    this.notes = '',
    this.coverImage = '',
    this.platform = kAutoDetectPlatformValue,
    this.hasDeadline = false,
    this.deadlineDate,
    this.isDlc = false,
    this.selectedTagIds = const <int>{},
    this.fetchedSteamTags = const <Tag>[],
    this.fetchedSteamTitle,
    this.fetchedAppId,
    this.fetchedCoverImagePath,
    this.fetchedReviewScore,
    this.fetchedReviewCount,
    this.singleSteamCacheAt,
  });

  final String title;
  final String gameKey;
  final String notes;
  final String coverImage;
  final String platform;
  final bool hasDeadline;
  final DateTime? deadlineDate;
  final bool isDlc;
  final Set<int> selectedTagIds;
  final List<Tag> fetchedSteamTags;
  final String? fetchedSteamTitle;
  final String? fetchedAppId;
  final String? fetchedCoverImagePath;
  final int? fetchedReviewScore;
  final int? fetchedReviewCount;
  final DateTime? singleSteamCacheAt;
}

final addGamesSingleEntryDraftProvider = NotifierProvider<
    AddGamesSingleEntryDraftNotifier,
    AddGamesSingleEntryDraft>(AddGamesSingleEntryDraftNotifier.new);

class AddGamesSingleEntryDraftNotifier
    extends Notifier<AddGamesSingleEntryDraft> {
  @override
  AddGamesSingleEntryDraft build() => const AddGamesSingleEntryDraft();

  void replace(AddGamesSingleEntryDraft draft) {
    state = draft;
  }

  void clear() {
    state = const AddGamesSingleEntryDraft();
  }
}

class AddGamesBatchDraft {
  const AddGamesBatchDraft({
    this.text = '',
    this.platform = kAutoDetectPlatformValue,
    this.hasDeadline = false,
    this.deadlineDate,
    this.parsedGames = const <ParsedBatchEntry>[],
    this.steamResults = const <String, SteamSearchResult?>{},
    this.steamErrors = const <String, String?>{},
  });

  final String text;
  final String platform;
  final bool hasDeadline;
  final DateTime? deadlineDate;
  final List<ParsedBatchEntry> parsedGames;
  final Map<String, SteamSearchResult?> steamResults;
  final Map<String, String?> steamErrors;
}

final addGamesBatchDraftProvider = NotifierProvider<
    AddGamesBatchDraftNotifier,
    AddGamesBatchDraft>(AddGamesBatchDraftNotifier.new);

class AddGamesBatchDraftNotifier extends Notifier<AddGamesBatchDraft> {
  @override
  AddGamesBatchDraft build() => const AddGamesBatchDraft();

  void replace(AddGamesBatchDraft draft) {
    state = draft;
  }

  void clear() {
    state = const AddGamesBatchDraft();
  }
}

// =============================================================================
// VIEW MODE
// =============================================================================

/// View mode provider (grid/list)
class ViewModeNotifier extends Notifier<GameListViewMode> {
  @override
  GameListViewMode build() {
    return ref.watch(gameListViewModeSettingProvider);
  }

  Future<void> setViewMode(GameListViewMode mode) async {
    state = mode;
    await ref
        .read(settingsProvider.notifier)
        .set(SettingsKeys.gameListViewMode, mode);
  }
}

final viewModeProvider = NotifierProvider<ViewModeNotifier, GameListViewMode>(
  () {
    return ViewModeNotifier();
  },
);

/// Health monitor visibility provider
final healthMonitorVisibleProvider =
    NotifierProvider<HealthMonitorVisibilityNotifier, bool>(
      HealthMonitorVisibilityNotifier.new,
    );

class HealthMonitorVisibilityNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setVisible(bool visible) {
    state = visible;
  }
}

/// Last selected game ID for range selection
final lastSelectedGameIdProvider =
    NotifierProvider<LastSelectedGameIdNotifier, int?>(
      LastSelectedGameIdNotifier.new,
    );

class LastSelectedGameIdNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void setLastSelectedGameId(int? gameId) {
    state = gameId;
  }
}

final selectionMultiSelectModeProvider =
    NotifierProvider<SelectionMultiSelectModeNotifier, bool>(
      SelectionMultiSelectModeNotifier.new,
    );

class SelectionMultiSelectModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setEnabled(bool enabled) {
    state = enabled;
  }

  void toggle() {
    state = !state;
  }
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

  void clear() => state = const {};
}

// =============================================================================
// DRAG SELECTION
// =============================================================================

enum DragSelectionMode { select, deselect }

class DragSelectionState {
  const DragSelectionState({
    this.isActive = false,
    this.mode,
    this.startId,
    this.visitedIds = const {},
  });

  final bool isActive;
  final DragSelectionMode? mode;
  final int? startId;
  final Set<int> visitedIds;

  DragSelectionState copyWith({
    bool? isActive,
    DragSelectionMode? mode,
    int? startId,
    Set<int>? visitedIds,
  }) {
    return DragSelectionState(
      isActive: isActive ?? this.isActive,
      mode: mode ?? this.mode,
      startId: startId ?? this.startId,
      visitedIds: visitedIds ?? this.visitedIds,
    );
  }
}

class DragSelectionNotifier extends Notifier<DragSelectionState> {
  @override
  DragSelectionState build() => const DragSelectionState();

  void start({int? startId}) {
    state = DragSelectionState(
      isActive: true,
      startId: startId,
      visitedIds: const {},
    );
  }

  void stop() {
    state = const DragSelectionState();
  }

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
    NotifierProvider<DragSelectionNotifier, DragSelectionState>(() {
      return DragSelectionNotifier();
    });
