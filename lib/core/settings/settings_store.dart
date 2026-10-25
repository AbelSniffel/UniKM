import 'package:shared_preferences/shared_preferences.dart';

import 'settings_model.dart';

/// Reads legacy preferences, encodes values, and preserves library paths and
/// custom themes when resetting. It has no provider or presentation dependency.
class SettingsStore {
  const SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  Map<String, dynamic> load() {
    // Retain old button positions; centered buttons map to the split layout.
    final legacyArrangementH = switch (_prefs.getString(
      'nav_bar_button_alignment',
    )) {
      'left' => NavButtonArrangement.start,
      'right' => NavButtonArrangement.end,
      _ =>
        _prefs.getBool('nav_bar_center_buttons') == false
            ? NavButtonArrangement.start
            : NavButtonArrangement.split,
    };
    final navButtonArrangementH = _readEnum(
      SettingsKeys.navButtonArrangementH,
      NavButtonArrangement.values,
      legacyArrangementH,
    );
    final navButtonArrangementV = _readEnum(
      SettingsKeys.navButtonArrangementV,
      NavButtonArrangement.values,
      DefaultSettings.navButtonArrangementV,
    );
    final gradientAnimation = _readEnum(
      SettingsKeys.gradientAnimation,
      GradientAnimation.values,
      DefaultSettings.gradientAnimation,
    );

    return {
      for (final entry in _defaults.entries)
        entry.key: _readPreference(entry.key, entry.value),
      SettingsKeys.autoCheckIntervalMinutes:
          DefaultSettings.autoCheckIntervalMinutes,
      // The current-theme alias falls back to the legacy active-theme key.
      SettingsKeys.currentTheme:
          _prefs.getString(SettingsKeys.currentTheme) ??
          _prefs.getString(SettingsKeys.activeTheme) ??
          DefaultSettings.activeTheme,
      // Navigation
      SettingsKeys.navBarPosition: _readEnum(
        SettingsKeys.navBarPosition,
        NavBarPosition.values,
        DefaultSettings.navBarPosition,
      ),
      SettingsKeys.navBarAppearance: _readEnum(
        SettingsKeys.navBarAppearance,
        NavBarAppearance.values,
        DefaultSettings.navBarAppearance,
      ),
      SettingsKeys.navExpansionMode: _readEnum(
        SettingsKeys.navExpansionMode,
        NavExpansionMode.values,
        DefaultSettings.navExpansionMode,
      ),
      SettingsKeys.navButtonArrangementH: navButtonArrangementH,
      SettingsKeys.navButtonArrangementV: navButtonArrangementV,
      SettingsKeys.navPanelOverlayStyle: _readEnum(
        SettingsKeys.navPanelOverlayStyle,
        NavPanelOverlayStyle.values,
        DefaultSettings.navPanelOverlayStyle,
      ),

      // Animations
      SettingsKeys.gradientAnimation: gradientAnimation,
      SettingsKeys.gradientAnimationSpeed: _readEnum(
        SettingsKeys.gradientAnimationSpeed,
        GradientAnimationSpeed.values,
        DefaultSettings.gradientAnimationSpeed,
      ),
      SettingsKeys.tooltipAnimation: _readEnum(
        SettingsKeys.tooltipAnimation,
        TooltipAnimation.values,
        DefaultSettings.tooltipAnimation,
      ),

      // Game List
      SettingsKeys.gameListViewMode: _readEnum(
        SettingsKeys.gameListViewMode,
        GameListViewMode.values,
        DefaultSettings.gameListViewMode,
      ),
      SettingsKeys.gameSortMode: _readEnum(
        SettingsKeys.gameSortMode,
        GameSortMode.values,
        DefaultSettings.gameSortMode,
      ),

      // Toggle & Section Style
      SettingsKeys.toggleStyle: _readEnum(
        SettingsKeys.toggleStyle,
        ToggleStyle.values,
        DefaultSettings.toggleStyle,
      ),
      SettingsKeys.settingsCardIndicatorStyle: _readEnum(
        SettingsKeys.settingsCardIndicatorStyle,
        SettingsCardIndicatorStyle.values,
        DefaultSettings.settingsCardIndicatorStyle,
      ),
      SettingsKeys.sectionTitleLocation: _readEnum(
        SettingsKeys.sectionTitleLocation,
        SectionTitleLocation.values,
        DefaultSettings.sectionTitleLocation,
      ),
      SettingsKeys.windowX: _prefs.getDouble(SettingsKeys.windowX),
      SettingsKeys.windowY: _prefs.getDouble(SettingsKeys.windowY),
    };
  }

  // Keep each ordinary preference's key, type and fallback together.
  // Fresh empty lists preserve independent defaults for each load.
  static Map<String, Object> get _defaults => {
    SettingsKeys.autoUpdateCheck: DefaultSettings.autoUpdateCheck,
    SettingsKeys.updateRepo: DefaultSettings.updateRepo,
    SettingsKeys.includePreReleases: DefaultSettings.includePreReleases,
    SettingsKeys.skippedVersions: <String>[],
    SettingsKeys.githubApiToken: DefaultSettings.githubApiToken,
    SettingsKeys.activeTheme: DefaultSettings.activeTheme,
    SettingsKeys.customThemes: <String>[],
    SettingsKeys.settingsSectionPanelCollapsed:
        DefaultSettings.settingsSectionPanelCollapsed,
    SettingsKeys.tooltipShowDelay: DefaultSettings.tooltipShowDelay,
    SettingsKeys.swapGradientColors: DefaultSettings.swapGradientColors,
    SettingsKeys.viewedNewGameIds: const <String>[],
    SettingsKeys.showTitleChip: DefaultSettings.showTitleChip,
    SettingsKeys.showTitleOnNoPicture: DefaultSettings.showTitleOnNoPicture,
    SettingsKeys.showPlatformChip: DefaultSettings.showPlatformChip,
    SettingsKeys.showTagsChip: DefaultSettings.showTagsChip,
    SettingsKeys.showPlatformOnHoverOnly:
        DefaultSettings.showPlatformOnHoverOnly,
    SettingsKeys.showTagsOnHoverOnly: DefaultSettings.showTagsOnHoverOnly,
    SettingsKeys.showDeadlineChip: DefaultSettings.showDeadlineChip,
    SettingsKeys.slimListView: DefaultSettings.slimListView,
    SettingsKeys.showPlatformBadges: true,
    SettingsKeys.showTagChips: true,
    SettingsKeys.showRatings: DefaultSettings.showRatings,
    SettingsKeys.useThemeToggleRadius: DefaultSettings.useThemeToggleRadius,
    SettingsKeys.experimentalInteractionCards:
        DefaultSettings.experimentalInteractionCards,
    SettingsKeys.autoBackupEnabled: DefaultSettings.autoBackupEnabled,
    SettingsKeys.autoBackupIntervalMinutes:
        DefaultSettings.autoBackupIntervalMinutes,
    SettingsKeys.backupMaxCount: DefaultSettings.backupMaxCount,
    SettingsKeys.databasePath: '',
    SettingsKeys.isEncrypted: false,
    SettingsKeys.recentDatabasePaths: const <String>[],
    SettingsKeys.syncEnabled: DefaultSettings.syncEnabled,
    SettingsKeys.syncAutoOnStartup: DefaultSettings.syncAutoOnStartup,
    SettingsKeys.syncDeviceId: DefaultSettings.syncDeviceId,
    SettingsKeys.syncTrustedPeersJson: DefaultSettings.syncTrustedPeersJson,
    SettingsKeys.syncRevokedPeersJson: DefaultSettings.syncRevokedPeersJson,
    SettingsKeys.syncLastTrustedPeerId: DefaultSettings.syncLastTrustedPeerId,
    SettingsKeys.syncLastSyncAtIso: DefaultSettings.syncLastSyncAtIso,
    SettingsKeys.syncDbRevisionId: DefaultSettings.syncDbRevisionId,
    SettingsKeys.syncDbTimestampMillis: DefaultSettings.syncDbTimestampMillis,
    SettingsKeys.syncStaticPrivateKey: DefaultSettings.syncStaticPrivateKey,
    SettingsKeys.syncStaticPublicKey: DefaultSettings.syncStaticPublicKey,
    SettingsKeys.deadlineReminders: true,
    SettingsKeys.updateNotifications: true,
    SettingsKeys.encryptionEnabled: false,
    SettingsKeys.maskKeys: true,
    SettingsKeys.autoHideKeys: true,
    SettingsKeys.developerMode: DefaultSettings.developerMode,
    SettingsKeys.showStatusBar: DefaultSettings.showStatusBar,
    SettingsKeys.showFpsCounter: DefaultSettings.showFpsCounter,
    SettingsKeys.showGameDetailsSkmId: DefaultSettings.showGameDetailsSkmId,
    SettingsKeys.showSyncDeviceId: DefaultSettings.showSyncDeviceId,
    SettingsKeys.frameRatePreference: DefaultSettings.frameRatePreference,
    SettingsKeys.windowWidth: DefaultSettings.windowWidth,
    SettingsKeys.windowHeight: DefaultSettings.windowHeight,
    SettingsKeys.windowMaximized: false,
    SettingsKeys.legacyDefaultTagsCleanupDone:
        DefaultSettings.legacyDefaultTagsCleanupDone,
  };

  Object _readPreference(String key, Object fallback) => switch (fallback) {
    bool() => _prefs.getBool(key) ?? fallback,
    int() => _prefs.getInt(key) ?? fallback,
    double() => _prefs.getDouble(key) ?? fallback,
    String() => _prefs.getString(key) ?? fallback,
    List<String>() => _prefs.getStringList(key) ?? fallback,
    _ => throw ArgumentError.value(
      fallback,
      key,
      'Unsupported preference type',
    ),
  };

  T _readEnum<T extends Enum>(String key, List<T> values, T fallback) {
    final stored = _prefs.getString(key);
    return values.firstWhere(
      (value) => value.name == stored,
      orElse: () => fallback,
    );
  }

  Future<void> save(String key, Object? value) async {
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

  /// Reset all settings to defaults
  ///
  /// Preserve the active database choice, recent databases, and custom themes.
  /// Typed reads matter: platform stores return saved lists untyped, which
  /// [save] would not write back.
  Future<Map<String, dynamic>> resetToDefaults() async {
    final preserved = <String, Object>{
      SettingsKeys.databasePath: ?_prefs.getString(SettingsKeys.databasePath),
      for (final key in [
        SettingsKeys.customThemes,
        SettingsKeys.recentDatabasePaths,
      ])
        key: ?_prefs.getStringList(key),
    };
    await _prefs.clear();
    for (final entry in {
      ...preserved,
      SettingsKeys.syncEnabled: DefaultSettings.syncEnabled,
      SettingsKeys.syncAutoOnStartup: DefaultSettings.syncAutoOnStartup,
      SettingsKeys.experimentalInteractionCards:
          DefaultSettings.experimentalInteractionCards,
      SettingsKeys.settingsCardIndicatorStyle:
          DefaultSettings.settingsCardIndicatorStyle,
    }.entries) {
      await save(entry.key, entry.value);
    }

    return load();
  }
}
