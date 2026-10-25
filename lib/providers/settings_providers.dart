/// Settings providers: user preferences, slice providers for typed access.
library;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/settings_model.dart';
import '../core/settings/settings_store.dart';
import 'database_providers.dart';

// =============================================================================
// SETTINGS PROVIDERS
// =============================================================================

/// Settings state notifier
class SettingsNotifier extends Notifier<Map<String, dynamic>> {
  late SettingsStore _store;
  Future<void> _pendingWrites = Future.value();
  int _pendingResets = 0;

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _pendingWrites.then((_) => operation());
    // A failed write is reported to its caller without blocking later saves.
    _pendingWrites = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  @override
  Map<String, dynamic> build() {
    _store = SettingsStore(ref.watch(sharedPreferencesProvider));
    return _store.load();
  }

  /// Get a setting value
  T get<T>(String key) => state[key] as T;

  /// Set one preference through the same normalization and persistence path
  /// used by multi-setting updates.
  Future<void> set<T>(String key, T value) => setMany({key: value});

  /// Set multiple settings in a single state update.
  Future<void> setMany(Map<String, dynamic> updates) {
    if (updates.isEmpty) return Future.value();
    // A list saved with unchanged contents keeps its instance, so slices
    // holding it (compared by identity) do not notify.
    final values = {
      for (final MapEntry(:key, :value) in updates.entries)
        key:
            value is List &&
                const ListEquality<Object?>().equals(value, state[key])
            ? state[key]
            : value,
    };
    final store = _store;
    final afterReset = _pendingResets > 0;
    // Ordinary edits remain immediate; edits during reset publish after it.
    if (!afterReset) state = {...state, ...values};
    return _enqueue(() async {
      if (afterReset && ref.mounted) state = {...state, ...values};
      for (final entry in values.entries) {
        await store.save(entry.key, entry.value);
      }
    });
  }

  /// Alias for set() - used by settings page
  Future<void> setSetting<T>(String key, T value) => set(key, value);

  /// A change callback that stores each new value under [key].
  ValueChanged<T> setter<T>(String key) =>
      (value) => set(key, value);

  /// Reset preferences while retaining the active database, recents, and custom themes.
  Future<void> resetToDefaults() {
    final store = _store;
    _pendingResets++;
    return _enqueue(() async {
      try {
        final defaults = await store.resetToDefaults();
        if (ref.mounted) state = defaults;
      } finally {
        _pendingResets--;
      }
    });
  }
}

/// Settings provider
final settingsProvider =
    NotifierProvider<SettingsNotifier, Map<String, dynamic>>(
      SettingsNotifier.new,
    );

// =============================================================================
// SETTINGS SLICE PROVIDERS
// =============================================================================

// Keep selection at the settings boundary so unrelated updates do not rebuild
// consumers. Each call creates an independent, overrideable provider.
Provider<T> _settingsSlice<T>(T Function(Map<String, dynamic>) select) =>
    Provider<T>((ref) => ref.watch(settingsProvider.select(select)));

Provider<T> _setting<T>(String key, T fallback) =>
    _settingsSlice((settings) => (settings[key] as T?) ?? fallback);

/// Developer-only identity display; the sync identity itself is always retained.
final showSyncDeviceIdProvider = _setting<bool>(
  SettingsKeys.showSyncDeviceId,
  DefaultSettings.showSyncDeviceId,
);

// Retained for saved-setting compatibility; the UI always uses cards.
final experimentalInteractionCardsProvider = _setting<bool>(
  SettingsKeys.experimentalInteractionCards,
  DefaultSettings.experimentalInteractionCards,
);

/// Typed settings slice used by `GameCard`.
///
/// Uses `select` + value equality to prevent rebuilding every card when
/// unrelated settings change.
final gameCardSettingsProvider = _settingsSlice(gameCardSettingsFromMap);

final notificationsSettingsProvider = _settingsSlice(
  notificationsSettingsFromMap,
);

final updatesSettingsProvider = _settingsSlice(updatesSettingsFromMap);

final securitySettingsProvider = _settingsSlice(securitySettingsFromMap);

final appShellSettingsProvider = _settingsSlice(appShellSettingsFromMap);

final backupSettingsProvider = _settingsSlice(backupSettingsFromMap);

final toggleStyleProvider = _setting<ToggleStyle>(
  SettingsKeys.toggleStyle,
  DefaultSettings.toggleStyle,
);

final settingsCardIndicatorStyleProvider = _setting<SettingsCardIndicatorStyle>(
  SettingsKeys.settingsCardIndicatorStyle,
  DefaultSettings.settingsCardIndicatorStyle,
);

final sectionTitleLocationProvider = _setting<SectionTitleLocation>(
  SettingsKeys.sectionTitleLocation,
  DefaultSettings.sectionTitleLocation,
);

final navButtonArrangementHProvider = _setting<NavButtonArrangement>(
  SettingsKeys.navButtonArrangementH,
  DefaultSettings.navButtonArrangementH,
);

/// Arrangement for vertical nav panel (left/right position).
final navButtonArrangementVProvider = _setting<NavButtonArrangement>(
  SettingsKeys.navButtonArrangementV,
  DefaultSettings.navButtonArrangementV,
);

final navPanelOverlayStyleSettingProvider = _setting<NavPanelOverlayStyle>(
  SettingsKeys.navPanelOverlayStyle,
  DefaultSettings.navPanelOverlayStyle,
);

final gradientAnimationSpeedProvider = _setting<GradientAnimationSpeed>(
  SettingsKeys.gradientAnimationSpeed,
  DefaultSettings.gradientAnimationSpeed,
);

final swapGradientColorsProvider = _setting<bool>(
  SettingsKeys.swapGradientColors,
  DefaultSettings.swapGradientColors,
);

final viewedNewGameIdsProvider = Provider<Set<int>>((ref) {
  final rawIds = ref.watch(
    settingsProvider.select(
      (s) => (s[SettingsKeys.viewedNewGameIds] as List<String>?) ?? const [],
    ),
  );
  return rawIds.map(int.tryParse).whereType<int>().toSet();
});

Future<void> markGameAsViewed(WidgetRef ref, int gameId) =>
    markGamesAsViewed(ref, <int>[gameId]);

Future<void> markGamesAsViewed(WidgetRef ref, Iterable<int> gameIds) async {
  final requestedIds = gameIds
      .where((id) => id > 0)
      .map((id) => id.toString())
      .toSet();
  if (requestedIds.isEmpty) return;

  final currentIds = ref.read(
    settingsProvider.select(
      (s) => (s[SettingsKeys.viewedNewGameIds] as List<String>?) ?? const [],
    ),
  );
  final mergedSet = {...currentIds, ...requestedIds};
  if (mergedSet.length == currentIds.length) return;

  final merged = mergedSet.toList()..sort();
  await ref
      .read(settingsProvider.notifier)
      .setSetting(SettingsKeys.viewedNewGameIds, merged);
}

final legacyDefaultTagsCleanupDoneProvider = _setting<bool>(
  SettingsKeys.legacyDefaultTagsCleanupDone,
  DefaultSettings.legacyDefaultTagsCleanupDone,
);

final activeThemeNameProvider = _setting<String>(
  SettingsKeys.activeTheme,
  DefaultSettings.activeTheme,
);

final customThemesJsonProvider = _setting<List<String>>(
  SettingsKeys.customThemes,
  const [],
);

final gameListViewModeSettingProvider = _setting<GameListViewMode>(
  SettingsKeys.gameListViewMode,
  DefaultSettings.gameListViewMode,
);

final gameSortModeSettingProvider = _setting<GameSortMode>(
  SettingsKeys.gameSortMode,
  DefaultSettings.gameSortMode,
);

// =============================================================================
// DATABASE PATH PROVIDER
// =============================================================================

/// Provider that exposes the current database path.
/// This reads from SharedPreferences and updates when the path changes.
final currentDatabasePathProvider = _setting<String>(
  SettingsKeys.databasePath,
  '',
);
