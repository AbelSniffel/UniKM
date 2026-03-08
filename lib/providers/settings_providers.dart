/// Settings providers: user preferences, slice providers for typed access.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/settings/settings_model.dart';
import 'database_providers.dart';

// =============================================================================
// SETTINGS PROVIDERS
// =============================================================================

/// Settings state notifier
class SettingsNotifier extends Notifier<Map<String, dynamic>> {
  late SharedPreferences _prefs;

  @override
  Map<String, dynamic> build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return _loadSettings();
  }

  Map<String, dynamic> _loadSettings() {
    return {
      // Updates
      SettingsKeys.autoUpdateCheck:
          _prefs.getBool(SettingsKeys.autoUpdateCheck) ??
          DefaultSettings.autoUpdateCheck,
      SettingsKeys.updateRepo:
          _prefs.getString(SettingsKeys.updateRepo) ??
          DefaultSettings.updateRepo,
      SettingsKeys.includePreReleases:
          _prefs.getBool(SettingsKeys.includePreReleases) ??
          DefaultSettings.includePreReleases,
      SettingsKeys.autoCheckIntervalMinutes:
          _prefs.getInt(SettingsKeys.autoCheckIntervalMinutes) ??
          DefaultSettings.autoCheckIntervalMinutes,
      SettingsKeys.skippedVersions:
          _prefs.getStringList(SettingsKeys.skippedVersions) ?? [],
      SettingsKeys.githubApiToken:
          _prefs.getString(SettingsKeys.githubApiToken) ??
          DefaultSettings.githubApiToken,

      // SettingsPage legacy/current theme key (UI convenience)
      // Keep in sync with activeTheme so selection reflects persisted theme.
      SettingsKeys.currentTheme:
          _prefs.getString(SettingsKeys.currentTheme) ??
          _prefs.getString(SettingsKeys.activeTheme) ??
          DefaultSettings.activeTheme,

      // Theme
      SettingsKeys.activeTheme:
          _prefs.getString(SettingsKeys.activeTheme) ??
          DefaultSettings.activeTheme,
      SettingsKeys.customThemes:
          _prefs.getStringList(SettingsKeys.customThemes) ?? [],

      // Navigation
      SettingsKeys.navBarPosition: NavBarPosition.values.firstWhere(
        (e) =>
            e.name ==
            (_prefs.getString(SettingsKeys.navBarPosition) ??
                DefaultSettings.navBarPosition.name),
        orElse: () => DefaultSettings.navBarPosition,
      ),
      SettingsKeys.navBarAppearance: NavBarAppearance.values.firstWhere(
        (e) =>
            e.name ==
            (_prefs.getString(SettingsKeys.navBarAppearance) ??
                DefaultSettings.navBarAppearance.name),
        orElse: () => DefaultSettings.navBarAppearance,
      ),
      SettingsKeys.navBarCollapsed:
          _prefs.getBool(SettingsKeys.navBarCollapsed) ??
          DefaultSettings.navBarCollapsed,
      SettingsKeys.navBarCenterButtons:
          _prefs.getBool(SettingsKeys.navBarCenterButtons) ??
          DefaultSettings.navBarCenterButtons,

      // Animations
      SettingsKeys.gradientAnimation: GradientAnimation.values.firstWhere(
        (e) =>
            e.name ==
            (_prefs.getString(SettingsKeys.gradientAnimation) ??
                DefaultSettings.gradientAnimation.name),
        orElse: () => DefaultSettings.gradientAnimation,
      ),
      SettingsKeys.tooltipAnimation: TooltipAnimation.values.firstWhere(
        (e) =>
            e.name ==
            (_prefs.getString(SettingsKeys.tooltipAnimation) ??
                DefaultSettings.tooltipAnimation.name),
        orElse: () => DefaultSettings.tooltipAnimation,
      ),
      SettingsKeys.tooltipShowDelay:
          _prefs.getInt(SettingsKeys.tooltipShowDelay) ??
          DefaultSettings.tooltipShowDelay,
      // Global toggle to swap primary <-> accent for gradient bars
      SettingsKeys.swapGradientColors:
          _prefs.getBool(SettingsKeys.swapGradientColors) ??
          DefaultSettings.swapGradientColors,

      // Game List
      SettingsKeys.gameListViewMode: GameListViewMode.values.firstWhere(
        (e) =>
            e.name ==
            (_prefs.getString(SettingsKeys.gameListViewMode) ??
                DefaultSettings.gameListViewMode.name),
        orElse: () => DefaultSettings.gameListViewMode,
      ),
      SettingsKeys.gameSortMode: GameSortMode.values.firstWhere(
        (e) =>
            e.name ==
            (_prefs.getString(SettingsKeys.gameSortMode) ??
                DefaultSettings.gameSortMode.name),
        orElse: () => DefaultSettings.gameSortMode,
      ),

      // Game Card Visual
      SettingsKeys.showTitleChip:
          _prefs.getBool(SettingsKeys.showTitleChip) ??
          DefaultSettings.showTitleChip,
      SettingsKeys.showPlatformChip:
          _prefs.getBool(SettingsKeys.showPlatformChip) ??
          DefaultSettings.showPlatformChip,
      SettingsKeys.showTagsChip:
          _prefs.getBool(SettingsKeys.showTagsChip) ??
          DefaultSettings.showTagsChip,
      SettingsKeys.showTagsOnHoverOnly:
          _prefs.getBool(SettingsKeys.showTagsOnHoverOnly) ??
          DefaultSettings.showTagsOnHoverOnly,
      SettingsKeys.showDeadlineChip:
          _prefs.getBool(SettingsKeys.showDeadlineChip) ??
          DefaultSettings.showDeadlineChip,

      // SettingsPage Card Visual toggles
      SettingsKeys.showPlatformBadges:
          _prefs.getBool(SettingsKeys.showPlatformBadges) ?? true,
      SettingsKeys.showTagChips:
          _prefs.getBool(SettingsKeys.showTagChips) ?? true,
      SettingsKeys.showRatings:
          _prefs.getBool(SettingsKeys.showRatings) ?? true,

      // Toggle & Section Style
      SettingsKeys.toggleStyle: ToggleStyle.values.firstWhere(
        (e) =>
            e.name ==
            (_prefs.getString(SettingsKeys.toggleStyle) ??
                DefaultSettings.toggleStyle.name),
        orElse: () => DefaultSettings.toggleStyle,
      ),
      SettingsKeys.sectionTitleLocation: SectionTitleLocation.values.firstWhere(
        (e) =>
            e.name ==
            (_prefs.getString(SettingsKeys.sectionTitleLocation) ??
                DefaultSettings.sectionTitleLocation.name),
        orElse: () => DefaultSettings.sectionTitleLocation,
      ),

      // Backup
      SettingsKeys.autoBackupEnabled:
          _prefs.getBool(SettingsKeys.autoBackupEnabled) ??
          DefaultSettings.autoBackupEnabled,
      SettingsKeys.autoBackupIntervalMinutes:
          _prefs.getInt(SettingsKeys.autoBackupIntervalMinutes) ??
          DefaultSettings.autoBackupIntervalMinutes,
      SettingsKeys.backupMaxCount:
          _prefs.getInt(SettingsKeys.backupMaxCount) ??
          DefaultSettings.backupMaxCount,

      // Database
      SettingsKeys.databasePath:
          _prefs.getString(SettingsKeys.databasePath) ?? '',
      SettingsKeys.isEncrypted:
          _prefs.getBool(SettingsKeys.isEncrypted) ?? false,
      SettingsKeys.recentDatabasePaths:
          _prefs.getStringList(SettingsKeys.recentDatabasePaths) ??
          const <String>[],

      // Notifications
      SettingsKeys.notificationsEnabled:
          _prefs.getBool(SettingsKeys.notificationsEnabled) ?? true,
      SettingsKeys.deadlineReminders:
          _prefs.getBool(SettingsKeys.deadlineReminders) ?? true,
      SettingsKeys.updateNotifications:
          _prefs.getBool(SettingsKeys.updateNotifications) ?? true,

      // Security
      SettingsKeys.encryptionEnabled:
          _prefs.getBool(SettingsKeys.encryptionEnabled) ?? false,
      SettingsKeys.maskKeys: _prefs.getBool(SettingsKeys.maskKeys) ?? true,
      SettingsKeys.autoHideKeys:
          _prefs.getBool(SettingsKeys.autoHideKeys) ?? true,

      // Debug
      SettingsKeys.developerMode:
          _prefs.getBool(SettingsKeys.developerMode) ??
          DefaultSettings.developerMode,
      SettingsKeys.showStatusBar:
          _prefs.getBool(SettingsKeys.showStatusBar) ??
          DefaultSettings.showStatusBar,
      SettingsKeys.showFpsCounter:
          _prefs.getBool(SettingsKeys.showFpsCounter) ??
          DefaultSettings.showFpsCounter,

      // Window
      SettingsKeys.windowWidth:
          _prefs.getDouble(SettingsKeys.windowWidth) ??
          DefaultSettings.windowWidth,
      SettingsKeys.windowHeight:
          _prefs.getDouble(SettingsKeys.windowHeight) ??
          DefaultSettings.windowHeight,
      SettingsKeys.windowX: _prefs.getDouble(SettingsKeys.windowX),
      SettingsKeys.windowY: _prefs.getDouble(SettingsKeys.windowY),
      SettingsKeys.windowMaximized:
          _prefs.getBool(SettingsKeys.windowMaximized) ?? false,

      // Maintenance
      SettingsKeys.legacyDefaultTagsCleanupDone:
          _prefs.getBool(SettingsKeys.legacyDefaultTagsCleanupDone) ??
          DefaultSettings.legacyDefaultTagsCleanupDone,
    };
  }

  /// Get a setting value
  T get<T>(String key) => state[key] as T;

  /// Set a setting value
  Future<void> set<T>(String key, T value) async {
    // Update state
    state = {...state, key: value};
    await _persistValue(key, value);
  }

  /// Set multiple settings in a single state update.
  Future<void> setMany(Map<String, dynamic> updates) async {
    if (updates.isEmpty) {
      return;
    }

    state = {...state, ...updates};

    for (final entry in updates.entries) {
      await _persistValue(entry.key, entry.value);
    }
  }

  Future<void> _persistValue(String key, Object? value) async {
    if (value is bool) {
      await _prefs.setBool(key, value);
    } else if (value is int) {
      await _prefs.setInt(key, value);
    } else if (value is double) {
      await _prefs.setDouble(key, value);
    } else if (value is String) {
      await _prefs.setString(key, value);
    } else if (value is List<String>) {
      await _prefs.setStringList(key, value);
    } else if (value is Enum) {
      await _prefs.setString(key, value.name);
    }
  }

  /// Alias for set() - used by settings page
  Future<void> setSetting<T>(String key, T value) => set(key, value);

  /// Load settings from SharedPreferences (for initial load)
  Future<void> loadSettings() async {
    // Settings are already loaded in build(), this is a no-op for refresh
  }

  /// Reset all settings to defaults
  ///
  /// Preserve any user-created custom themes so those are not lost when the
  /// user resets preferences.
  Future<void> resetToDefaults() async {
    final preservedCustomThemes =
        _prefs.getStringList(SettingsKeys.customThemes) ?? [];

    await _prefs.clear();

    if (preservedCustomThemes.isNotEmpty) {
      await _prefs.setStringList(
        SettingsKeys.customThemes,
        preservedCustomThemes,
      );
    }

    state = _loadSettings();
  }
}

/// Settings provider
final settingsProvider =
    NotifierProvider<SettingsNotifier, Map<String, dynamic>>(() {
      return SettingsNotifier();
    });

// =============================================================================
// SETTINGS SLICE PROVIDERS
// =============================================================================

/// Typed settings slice used by `GameCard`.
///
/// Uses `select` + value equality to prevent rebuilding every card when
/// unrelated settings change.
final gameCardSettingsProvider = Provider<GameCardSettings>((ref) {
  return ref.watch(settingsProvider.select((s) => GameCardSettings.fromMap(s)));
});

final appearanceSettingsProvider = Provider<AppearanceSettings>((ref) {
  return ref.watch(
    settingsProvider.select((s) => AppearanceSettings.fromMap(s)),
  );
});

final librarySettingsProvider = Provider<LibrarySettings>((ref) {
  return ref.watch(settingsProvider.select((s) => LibrarySettings.fromMap(s)));
});

final notificationsSettingsProvider = Provider<NotificationsSettings>((ref) {
  return ref.watch(
    settingsProvider.select((s) => NotificationsSettings.fromMap(s)),
  );
});

final updatesSettingsProvider = Provider<UpdatesSettings>((ref) {
  return ref.watch(settingsProvider.select((s) => UpdatesSettings.fromMap(s)));
});

final securitySettingsProvider = Provider<SecuritySettings>((ref) {
  return ref.watch(settingsProvider.select((s) => SecuritySettings.fromMap(s)));
});

final appShellSettingsProvider = Provider<AppShellSettings>((ref) {
  return ref.watch(settingsProvider.select((s) => AppShellSettings.fromMap(s)));
});

final tooltipSettingsProvider = Provider<TooltipSettings>((ref) {
  return ref.watch(settingsProvider.select((s) => TooltipSettings.fromMap(s)));
});

final backupSettingsProvider = Provider<BackupSettings>((ref) {
  return ref.watch(settingsProvider.select((s) => BackupSettings.fromMap(s)));
});

final toggleStyleProvider = Provider<ToggleStyle>((ref) {
  return ref.watch(
    settingsProvider.select(
      (s) =>
          (s[SettingsKeys.toggleStyle] as ToggleStyle?) ??
          DefaultSettings.toggleStyle,
    ),
  );
});

final sectionTitleLocationProvider = Provider<SectionTitleLocation>((ref) {
  return ref.watch(
    settingsProvider.select(
      (s) =>
          (s[SettingsKeys.sectionTitleLocation] as SectionTitleLocation?) ??
          DefaultSettings.sectionTitleLocation,
    ),
  );
});

final navBarCenterButtonsProvider = Provider<bool>((ref) {
  return ref.watch(
    settingsProvider.select(
      (s) =>
          (s[SettingsKeys.navBarCenterButtons] as bool?) ??
          DefaultSettings.navBarCenterButtons,
    ),
  );
});

final swapGradientColorsProvider = Provider<bool>((ref) {
  return ref.watch(
    settingsProvider.select(
      (s) =>
          (s[SettingsKeys.swapGradientColors] as bool?) ??
          DefaultSettings.swapGradientColors,
    ),
  );
});

final selectionBarCollapsedProvider = Provider<bool>((ref) {
  return ref.watch(
    settingsProvider.select(
      (s) => (s[SettingsKeys.selectionBarCollapsed] as bool?) ?? false,
    ),
  );
});

final legacyDefaultTagsCleanupDoneProvider = Provider<bool>((ref) {
  return ref.watch(
    settingsProvider.select(
      (s) =>
          (s[SettingsKeys.legacyDefaultTagsCleanupDone] as bool?) ??
          DefaultSettings.legacyDefaultTagsCleanupDone,
    ),
  );
});

final activeThemeNameProvider = Provider<String>((ref) {
  return ref.watch(
    settingsProvider.select(
      (s) =>
          (s[SettingsKeys.activeTheme] as String?) ??
          DefaultSettings.activeTheme,
    ),
  );
});

final customThemesJsonProvider = Provider<List<String>>((ref) {
  return ref.watch(
    settingsProvider.select(
      (s) => (s[SettingsKeys.customThemes] as List<String>?) ?? const [],
    ),
  );
});

final gameListViewModeSettingProvider = Provider<GameListViewMode>((ref) {
  return ref.watch(
    settingsProvider.select(
      (s) =>
          (s[SettingsKeys.gameListViewMode] as GameListViewMode?) ??
          DefaultSettings.gameListViewMode,
    ),
  );
});

final gameSortModeSettingProvider = Provider<GameSortMode>((ref) {
  return ref.watch(
    settingsProvider.select(
      (s) =>
          (s[SettingsKeys.gameSortMode] as GameSortMode?) ??
          DefaultSettings.gameSortMode,
    ),
  );
});

// =============================================================================
// DATABASE PATH PROVIDER
// =============================================================================

/// Provider that exposes the current database path.
/// This reads from SharedPreferences and updates when the path changes.
final currentDatabasePathProvider = Provider<String>((ref) {
  final settings = ref.watch(settingsProvider);
  return (settings[SettingsKeys.databasePath] as String?) ?? '';
});
