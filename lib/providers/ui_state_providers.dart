/// Riverpod providers for UI state (page navigation, view mode, drag selection).
library;

import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/settings_model.dart';
import 'settings_providers.dart';

// =============================================================================
// NAV ITEMS
// =============================================================================

/// The top-level navigation destinations in the app.
enum NavItem {
  home('Library', Icons.home, Icons.home_outlined),
  addGames('Add Games', Icons.add_circle, Icons.add_circle_outline),
  updates('Updates', Icons.update, Icons.update_outlined),
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
    await ref.read(settingsProvider.notifier).set(SettingsKeys.gameListViewMode, mode);
  }
}

final viewModeProvider = NotifierProvider<ViewModeNotifier, GameListViewMode>(() {
  return ViewModeNotifier();
});

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

// =============================================================================
// PAGE NOTIFICATIONS (pulsating nav icons)
// =============================================================================

/// Tracks which nav pages currently have an active notification (unread alert).
/// When a page is in this set, its nav icon pulsates to draw attention.
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

enum DragSelectionMode {
  select,
  deselect,
}

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
}

final dragSelectionProvider = NotifierProvider<DragSelectionNotifier, DragSelectionState>(() {
  return DragSelectionNotifier();
});
