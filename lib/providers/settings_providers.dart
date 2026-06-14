/// Settings providers: user preferences, slice providers for typed access.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../core/services/platform_file_actions.dart';
import '../core/settings/settings_model.dart';
import 'database_providers.dart';
import '../ui/widgets/notification_system.dart';

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
    final navPanelGradientBar =
        _prefs.getBool(SettingsKeys.navPanelGradientBar) ??
        DefaultSettings.navPanelGradientBar;
    final navBarButtonAlignmentName = _prefs.getString(
      SettingsKeys.navBarButtonAlignment,
    );
    final legacyCenterButtons = _prefs.getBool(
      SettingsKeys.navBarCenterButtons,
    );
    final navBarButtonAlignment = NavBarButtonAlignment.values.firstWhere(
      (e) => e.name == navBarButtonAlignmentName,
      orElse: () {
        if (legacyCenterButtons != null) {
          return legacyCenterButtons
              ? NavBarButtonAlignment.center
              : NavBarButtonAlignment.left;
        }
        return DefaultSettings.navBarButtonAlignment;
      },
    );
    final legacyArrangementH = switch (navBarButtonAlignment) {
      NavBarButtonAlignment.left => NavButtonArrangement.start,
      NavBarButtonAlignment.center => NavButtonArrangement.center,
      NavBarButtonAlignment.right => NavButtonArrangement.end,
    };
    final navButtonArrangementH = NavButtonArrangement.values.firstWhere(
      (e) => e.name == _prefs.getString(SettingsKeys.navButtonArrangementH),
      orElse: () => legacyArrangementH,
    );
    final navButtonArrangementV = NavButtonArrangement.values.firstWhere(
      (e) => e.name == _prefs.getString(SettingsKeys.navButtonArrangementV),
      orElse: () => DefaultSettings.navButtonArrangementV,
    );
    final gradientAnimation = normalizeGradientAnimation(
      GradientAnimation.values.firstWhere(
        (e) =>
            e.name ==
            (_prefs.getString(SettingsKeys.gradientAnimation) ??
                DefaultSettings.gradientAnimation.name),
        orElse: () => DefaultSettings.gradientAnimation,
      ),
      navPanelGradientBar: navPanelGradientBar,
    );

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
      SettingsKeys.autoCheckIntervalMinutes: kDefaultAutoUpdateIntervalMinutes,
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
      SettingsKeys.navBarButtonAlignment: navBarButtonAlignment,
      SettingsKeys.navPanelGradientBar: navPanelGradientBar,
      SettingsKeys.navBarCombineButtons:
          _prefs.getBool(SettingsKeys.navBarCombineButtons) ??
          DefaultSettings.navBarCombineButtons,
      SettingsKeys.navButtonArrangementH: navButtonArrangementH,
      SettingsKeys.navButtonArrangementV: navButtonArrangementV,
      SettingsKeys.navPanelOverlayStyle: NavPanelOverlayStyle.values.firstWhere(
        (e) =>
            e.name ==
            (_prefs.getString(SettingsKeys.navPanelOverlayStyle) ??
                DefaultSettings.navPanelOverlayStyle.name),
        orElse: () => DefaultSettings.navPanelOverlayStyle,
      ),
      SettingsKeys.settingsSectionPanelCollapsed:
          _prefs.getBool(SettingsKeys.settingsSectionPanelCollapsed) ??
          DefaultSettings.settingsSectionPanelCollapsed,

      // Animations
      SettingsKeys.gradientAnimation: gradientAnimation,
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
      SettingsKeys.viewedNewGameIds:
          _prefs.getStringList(SettingsKeys.viewedNewGameIds) ??
          const <String>[],

      // Game Card Visual
      SettingsKeys.showTitleChip:
          _prefs.getBool(SettingsKeys.showTitleChip) ??
          DefaultSettings.showTitleChip,
      SettingsKeys.showTitleOnNoPicture:
          _prefs.getBool(SettingsKeys.showTitleOnNoPicture) ??
          DefaultSettings.showTitleOnNoPicture,
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
      SettingsKeys.slimListView:
          _prefs.getBool(SettingsKeys.slimListView) ??
          DefaultSettings.slimListView,

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
      SettingsKeys.useThemeToggleRadius:
          _prefs.getBool(SettingsKeys.useThemeToggleRadius) ??
          DefaultSettings.useThemeToggleRadius,

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

      // Device Sync
      SettingsKeys.syncEnabled:
          _prefs.getBool(SettingsKeys.syncEnabled) ??
          DefaultSettings.syncEnabled,
      SettingsKeys.syncAutoOnStartup:
          _prefs.getBool(SettingsKeys.syncAutoOnStartup) ??
          DefaultSettings.syncAutoOnStartup,
      SettingsKeys.syncDeviceId:
          _prefs.getString(SettingsKeys.syncDeviceId) ??
          DefaultSettings.syncDeviceId,
      SettingsKeys.syncTrustedPeersJson:
          _prefs.getString(SettingsKeys.syncTrustedPeersJson) ??
          DefaultSettings.syncTrustedPeersJson,
      SettingsKeys.syncLastTrustedPeerId:
          _prefs.getString(SettingsKeys.syncLastTrustedPeerId) ??
          DefaultSettings.syncLastTrustedPeerId,
      SettingsKeys.syncLastSyncAtIso:
          _prefs.getString(SettingsKeys.syncLastSyncAtIso) ??
          DefaultSettings.syncLastSyncAtIso,
      SettingsKeys.syncDbRevisionId:
          _prefs.getString(SettingsKeys.syncDbRevisionId) ??
          DefaultSettings.syncDbRevisionId,
      SettingsKeys.syncDbTimestampMillis:
          _prefs.getInt(SettingsKeys.syncDbTimestampMillis) ??
          DefaultSettings.syncDbTimestampMillis,
      SettingsKeys.syncStaticPrivateKey:
          _prefs.getString(SettingsKeys.syncStaticPrivateKey) ??
          DefaultSettings.syncStaticPrivateKey,
      SettingsKeys.syncStaticPublicKey:
          _prefs.getString(SettingsKeys.syncStaticPublicKey) ??
          DefaultSettings.syncStaticPublicKey,

      // Notifications
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
      SettingsKeys.showGameDetailsSkmId:
          _prefs.getBool(SettingsKeys.showGameDetailsSkmId) ??
          DefaultSettings.showGameDetailsSkmId,

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

  Map<String, dynamic> _normalizeUpdates(Map<String, dynamic> updates) {
    final normalized = Map<String, dynamic>.from(updates);
    final nextNavPanelGradientBar =
        (normalized[SettingsKeys.navPanelGradientBar] as bool?) ??
        (state[SettingsKeys.navPanelGradientBar] as bool?) ??
        DefaultSettings.navPanelGradientBar;
    final rawGradientAnimation =
        (normalized[SettingsKeys.gradientAnimation] as GradientAnimation?) ??
        (state[SettingsKeys.gradientAnimation] as GradientAnimation?) ??
        DefaultSettings.gradientAnimation;
    final nextGradientAnimation = normalizeGradientAnimation(
      rawGradientAnimation,
      navPanelGradientBar: nextNavPanelGradientBar,
    );

    if (nextGradientAnimation != rawGradientAnimation ||
        normalized.containsKey(SettingsKeys.gradientAnimation) ||
        normalized.containsKey(SettingsKeys.navPanelGradientBar)) {
      normalized[SettingsKeys.gradientAnimation] = nextGradientAnimation;
    }

    return normalized;
  }

  bool _shouldNotifyGradientFallback(
    Map<String, dynamic> updates,
    Map<String, dynamic> normalized,
  ) {
    if (updates[SettingsKeys.navPanelGradientBar] != false) {
      return false;
    }

    final rawGradientAnimation =
        (updates[SettingsKeys.gradientAnimation] as GradientAnimation?) ??
        (state[SettingsKeys.gradientAnimation] as GradientAnimation?) ??
        DefaultSettings.gradientAnimation;
    final nextGradientAnimation =
        (normalized[SettingsKeys.gradientAnimation] as GradientAnimation?) ??
        rawGradientAnimation;

    return rawGradientAnimation == GradientAnimation.wave &&
        nextGradientAnimation == GradientAnimation.scroll;
  }

  /// Set a setting value
  Future<void> set<T>(String key, T value) async {
    final normalized = _normalizeUpdates({key: value});
    final shouldNotifyGradientFallback = _shouldNotifyGradientFallback({
      key: value,
    }, normalized);
    state = {...state, ...normalized};
    for (final entry in normalized.entries) {
      await _persistValue(entry.key, entry.value);
    }
    if (shouldNotifyGradientFallback) {
      NotificationManager.instance.info(
        'Changed Gradient Bar effect to Scroll',
      );
    }
  }

  /// Set multiple settings in a single state update.
  Future<void> setMany(Map<String, dynamic> updates) async {
    if (updates.isEmpty) {
      return;
    }

    final normalized = _normalizeUpdates(updates);
    final shouldNotifyGradientFallback = _shouldNotifyGradientFallback(
      updates,
      normalized,
    );

    state = {...state, ...normalized};

    for (final entry in normalized.entries) {
      await _persistValue(entry.key, entry.value);
    }
    if (shouldNotifyGradientFallback) {
      NotificationManager.instance.info(
        'Changed Gradient Bar effect to Scroll',
      );
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
    final preservedRecentDbs =
        _prefs.getStringList(SettingsKeys.recentDatabasePaths) ?? [];

    await _prefs.clear();

    if (preservedCustomThemes.isNotEmpty) {
      await _prefs.setStringList(
        SettingsKeys.customThemes,
        preservedCustomThemes,
      );
    }

    if (preservedRecentDbs.isNotEmpty) {
      await _prefs.setStringList(
        SettingsKeys.recentDatabasePaths,
        preservedRecentDbs,
      );
    }

    // Keep device-sync toggles explicitly reset to default-off values.
    await _prefs.setBool(SettingsKeys.syncEnabled, DefaultSettings.syncEnabled);
    await _prefs.setBool(
      SettingsKeys.syncAutoOnStartup,
      DefaultSettings.syncAutoOnStartup,
    );

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

final useThemeToggleRadiusSettingProvider = Provider<bool>((ref) {
  return ref.watch(
    settingsProvider.select(
      (s) =>
          (s[SettingsKeys.useThemeToggleRadius] as bool?) ??
          DefaultSettings.useThemeToggleRadius,
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

final navBarButtonAlignmentProvider = Provider<NavBarButtonAlignment>((ref) {
  return ref.watch(
    settingsProvider.select(
      (s) =>
          (s[SettingsKeys.navBarButtonAlignment] as NavBarButtonAlignment?) ??
          DefaultSettings.navBarButtonAlignment,
    ),
  );
});

final navPanelGradientBarProvider = Provider<bool>((ref) {
  if (PlatformFileActions.isMobilePlatform) return true;
  return ref.watch(
    settingsProvider.select(
      (s) =>
          (s[SettingsKeys.navPanelGradientBar] as bool?) ??
          DefaultSettings.navPanelGradientBar,
    ),
  );
});

final navBarCombineButtonsProvider = Provider<bool>((ref) {
  return ref.watch(
    settingsProvider.select(
      (s) =>
          (s[SettingsKeys.navBarCombineButtons] as bool?) ??
          DefaultSettings.navBarCombineButtons,
    ),
  );
});

/// Arrangement for horizontal nav panel (top/bottom position).
final navButtonArrangementHProvider = Provider<NavButtonArrangement>((ref) {
  return ref.watch(
    settingsProvider.select(
      (s) =>
          (s[SettingsKeys.navButtonArrangementH] as NavButtonArrangement?) ??
          DefaultSettings.navButtonArrangementH,
    ),
  );
});

/// Arrangement for vertical nav panel (left/right position).
final navButtonArrangementVProvider = Provider<NavButtonArrangement>((ref) {
  return ref.watch(
    settingsProvider.select(
      (s) =>
          (s[SettingsKeys.navButtonArrangementV] as NavButtonArrangement?) ??
          DefaultSettings.navButtonArrangementV,
    ),
  );
});

final navPanelOverlayStyleSettingProvider = Provider<NavPanelOverlayStyle>((
  ref,
) {
  return ref.watch(
    settingsProvider.select(
      (s) =>
          (s[SettingsKeys.navPanelOverlayStyle] as NavPanelOverlayStyle?) ??
          DefaultSettings.navPanelOverlayStyle,
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

final viewedNewGameIdsProvider = Provider<Set<int>>((ref) {
  final rawIds = ref.watch(
    settingsProvider.select(
      (s) => (s[SettingsKeys.viewedNewGameIds] as List<String>?) ?? const [],
    ),
  );
  return rawIds.map(int.tryParse).whereType<int>().toSet();
});

Future<void> markGameAsViewed(WidgetRef ref, int gameId) {
  return markGamesAsViewed(ref, <int>[gameId]);
}

Future<void> markGamesAsViewed(WidgetRef ref, Iterable<int> gameIds) async {
  final requestedIds = gameIds
      .where((id) => id > 0)
      .map((id) => id.toString())
      .toSet();
  if (requestedIds.isEmpty) {
    return;
  }

  final currentIds = ref.read(
    settingsProvider.select(
      (s) => (s[SettingsKeys.viewedNewGameIds] as List<String>?) ?? const [],
    ),
  );
  final mergedSet = {...currentIds, ...requestedIds};
  if (mergedSet.length == currentIds.length) {
    return;
  }

  final merged = mergedSet.toList()..sort();
  await ref
      .read(settingsProvider.notifier)
      .setSetting(SettingsKeys.viewedNewGameIds, merged);
}

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
