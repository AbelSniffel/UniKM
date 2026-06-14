/// Settings model and default values
/// Matches the 25+ settings from the original Python app
library;

import 'dart:io';

import '../constants/app_constants.dart';

/// Navigation bar position options
enum NavBarPosition {
  left,
  right,
  top,
  bottom;

  String get displayName {
    switch (this) {
      case NavBarPosition.left:
        return 'Left';
      case NavBarPosition.right:
        return 'Right';
      case NavBarPosition.top:
        return 'Top';
      case NavBarPosition.bottom:
        return 'Bottom';
    }
  }
}

/// Navigation button placement for both standard and integrated nav layouts.
///
/// In the standard layout, [center] keeps all page buttons centered and
/// [split] separates page buttons into leading/trailing groups.
/// In the integrated gradient layout, [split] splits the page buttons around
/// the gradient bar.
/// [start] places all buttons before the center feature area.
/// [end] places all buttons after the center feature area.
enum NavButtonArrangement {
  start,
  center,
  split,
  end;

  /// Returns the display name for the integrated gradient layout.
  String displayNameForIntegrated({required bool isHorizontal}) {
    switch (this) {
      case NavButtonArrangement.split:
        return 'Split';
      case NavButtonArrangement.center:
        // Center is not exposed in integrated mode, but can be restored when
        // switching back to standard mode.
        return 'Split';
      case NavButtonArrangement.start:
        return isHorizontal ? 'Left' : 'Top';
      case NavButtonArrangement.end:
        return isHorizontal ? 'Right' : 'Bottom';
    }
  }

  /// Returns the display name for the standard nav panel layout.
  String displayNameForStandard({required bool isHorizontal}) {
    switch (this) {
      case NavButtonArrangement.start:
        return isHorizontal ? 'Left' : 'Top';
      case NavButtonArrangement.center:
        return 'Center';
      case NavButtonArrangement.split:
        return 'Split';
      case NavButtonArrangement.end:
        return isHorizontal ? 'Right' : 'Bottom';
    }
  }
}

/// Button placement for the standard horizontal navigation panel.
enum NavBarButtonAlignment {
  left,
  center,
  right;

  String get displayName {
    switch (this) {
      case NavBarButtonAlignment.left:
        return 'Left';
      case NavBarButtonAlignment.center:
        return 'Center';
      case NavBarButtonAlignment.right:
        return 'Right';
    }
  }
}

/// Navigation bar appearance options
enum NavBarAppearance {
  iconAndText,
  iconOnly,
  textOnly;

  String get displayName {
    switch (this) {
      case NavBarAppearance.iconAndText:
        return 'Icon & Text';
      case NavBarAppearance.iconOnly:
        return 'Icon Only';
      case NavBarAppearance.textOnly:
        return 'Text Only';
    }
  }
}

/// Decorative overlay styles applied to the navigation panel background.
enum NavPanelOverlayStyle {
  none,
  gradient,
  diagonalStripes,
  crosshatch,
  hexPattern,
  ripple;

  String get displayName => switch (this) {
    none => 'None',
    diagonalStripes => 'Diagonal',
    crosshatch => 'Crosshatch',
    gradient => 'Gradient',
    hexPattern => 'Hex Pattern',
    ripple => 'Ripple',
  };
}

/// Gradient animation styles
enum GradientAnimation {
  solid,
  scroll,
  pulse,
  heart,
  scanner,
  aurora,
  wave;

  String get displayName => switch (this) {
    solid => 'Solid',
    scroll => 'Scroll',
    pulse => 'Pulse',
    scanner => 'Scanner',
    heart => 'Heart',
    aurora => 'Aurora',
    wave => 'Wave',
  };

  String get description => switch (this) {
    solid => 'No animation, solid primary color',
    scroll => 'Smooth scrolling gradient',
    pulse => 'Gentle breathing pulse',
    scanner => 'Bouncing scanner beam',
    heart => 'Expanding heartbeat pulse',
    aurora => 'Aurora borealis flow',
    wave => 'Layered wave bands flowing across the bar',
  };
}

GradientAnimation normalizeGradientAnimation(
  GradientAnimation animation, {
  required bool navPanelGradientBar,
}) {
  if (!navPanelGradientBar && animation == GradientAnimation.wave) {
    return GradientAnimation.scroll;
  }
  return animation;
}

/// Tooltip animation styles
enum TooltipAnimation {
  fade,
  slide;

  String get displayName {
    switch (this) {
      case TooltipAnimation.fade:
        return 'Fade';
      case TooltipAnimation.slide:
        return 'Slide';
    }
  }
}

/// Toggle switch styles
enum ToggleStyle {
  regular,
  dot,
  morphDot;

  String get displayName {
    switch (this) {
      case ToggleStyle.regular:
        return 'Regular';
      case ToggleStyle.dot:
        return 'Dot';
      case ToggleStyle.morphDot:
        return 'Morph Dot';
    }
  }
}

/// Section GroupBox title location
enum SectionTitleLocation {
  left,
  top;

  String get displayName {
    switch (this) {
      case SectionTitleLocation.left:
        return 'Left';
      case SectionTitleLocation.top:
        return 'Top';
    }
  }
}

/// Game list view mode
enum GameListViewMode {
  grid,
  list;

  String get displayName {
    switch (this) {
      case GameListViewMode.grid:
        return 'Grid';
      case GameListViewMode.list:
        return 'List';
    }
  }
}

enum ListViewDensityMode {
  regular,
  slim;

  String get displayName {
    switch (this) {
      case ListViewDensityMode.regular:
        return 'Regular';
      case ListViewDensityMode.slim:
        return 'Slim';
    }
  }
}

ListViewDensityMode resolveListViewDensityMode({required bool slimListView}) {
  return slimListView ? ListViewDensityMode.slim : ListViewDensityMode.regular;
}

Map<String, dynamic> listViewDensityModeSettings(ListViewDensityMode mode) {
  switch (mode) {
    case ListViewDensityMode.regular:
      return {SettingsKeys.slimListView: false};
    case ListViewDensityMode.slim:
      return {SettingsKeys.slimListView: true};
  }
}

/// Sort mode for game list
enum GameSortMode {
  deadlineFirst,
  titleAZ,
  titleZA,
  platformAZ,
  platformZA,
  dateNewest,
  dateOldest,
  ratingHigh,
  ratingLow;

  String get displayName {
    switch (this) {
      case GameSortMode.deadlineFirst:
        return 'Deadline First';
      case GameSortMode.titleAZ:
        return 'Title A-Z';
      case GameSortMode.titleZA:
        return 'Title Z-A';
      case GameSortMode.platformAZ:
        return 'Platform A-Z';
      case GameSortMode.platformZA:
        return 'Platform Z-A';
      case GameSortMode.dateNewest:
        return 'Date Added (Newest)';
      case GameSortMode.dateOldest:
        return 'Date Added (Oldest)';
      case GameSortMode.ratingHigh:
        return 'Rating (Highest first)';
      case GameSortMode.ratingLow:
        return 'Rating (Lowest first)';
    }
  }
}

/// All app settings with their keys
class SettingsKeys {
  SettingsKeys._();

  // Updates
  static const String autoUpdateCheck = 'auto_update_check';
  static const String updateRepo = 'update_repo';
  static const String includePreReleases = 'include_pre_releases';
  static const String autoCheckIntervalMinutes = 'auto_check_interval_minutes';
  static const String skippedVersions = 'skipped_versions';
  static const String githubApiToken = 'github_api_token';

  // Theme & UI
  static const String activeTheme = 'active_theme';
  static const String customThemes = 'custom_themes';

  // Navigation
  static const String navBarPosition = 'nav_bar_position';
  static const String navBarAppearance = 'nav_bar_appearance';
  static const String navBarCollapsed = 'nav_bar_collapsed';
  static const String navBarButtonAlignment = 'nav_bar_button_alignment';
  static const String navBarCenterButtons = 'nav_bar_center_buttons';
  static const String navPanelGradientBar = 'nav_panel_gradient_bar';
  static const String navBarCombineButtons = 'nav_bar_split_buttons';

  /// Arrangement for horizontal nav panel (top or bottom position).
  static const String navButtonArrangementH = 'nav_button_arrangement_h';

  /// Arrangement for vertical nav panel (left or right position).
  static const String navButtonArrangementV = 'nav_button_arrangement_v';
  static const String navPanelOverlayStyle = 'nav_panel_overlay_style';
  static const String settingsSectionPanelCollapsed =
      'settings_section_panel_collapsed';

  // Animations
  static const String gradientAnimation = 'gradient_animation';
  static const String tooltipAnimation = 'tooltip_animation';
  static const String tooltipShowDelay = 'tooltip_show_delay';
  // When true, gradient bars will swap the theme primary and accent colors
  static const String swapGradientColors = 'swap_gradient_colors';

  // Game List
  static const String gameListViewMode = 'game_list_view_mode';
  static const String gameSortMode = 'game_sort_mode';
  static const String viewedNewGameIds = 'viewed_new_game_ids';

  // Game Card Visual
  static const String showTitleChip = 'show_title_chip';
  static const String showTitleOnNoPicture = 'show_title_on_no_picture';
  static const String showPlatformChip = 'show_platform_chip';
  static const String showTagsChip = 'show_tags_chip';
  static const String showTagsOnHoverOnly = 'show_tags_on_hover_only';
  static const String showDeadlineChip = 'show_deadline_chip';
  static const String compactListView = 'compact_list_view';
  static const String slimListView = 'slim_list_view';

  // Toggle & Section Style
  static const String toggleStyle = 'toggle_style';
  static const String useThemeToggleRadius = 'use_theme_toggle_radius';
  static const String sectionTitleLocation = 'section_title_location';

  // Backup
  static const String autoBackupEnabled = 'auto_backup_enabled';
  static const String autoBackupIntervalMinutes =
      'auto_backup_interval_minutes';
  static const String backupMaxCount = 'backup_max_count';

  // Database
  static const String databasePath = 'database_path';
  static const String isEncrypted = 'is_encrypted';
  static const String recentDatabasePaths = 'recent_database_paths';

  // Device Sync
  static const String syncEnabled = 'sync_enabled';
  static const String syncAutoOnStartup = 'sync_auto_on_startup';
  static const String syncDeviceId = 'sync_device_id';
  static const String syncTrustedPeersJson = 'sync_trusted_peers_json';
  static const String syncLastTrustedPeerId = 'sync_last_trusted_peer_id';
  static const String syncLastSyncAtIso = 'sync_last_sync_at_iso';
  static const String syncDbRevisionId = 'sync_db_revision_id';
  static const String syncDbTimestampMillis = 'sync_db_timestamp_millis';
  static const String syncStaticPrivateKey = 'sync_static_private_key';
  static const String syncStaticPublicKey = 'sync_static_public_key';

  // Additional UI Settings (used by settings page)
  static const String currentTheme = 'current_theme';
  static const String showPlatformBadges = 'show_platform_badges';
  static const String showTagChips = 'show_tag_chips';
  static const String showRatings = 'show_ratings';

  // Notifications
  static const String notificationsEnabled = 'notifications_enabled';
  static const String deadlineReminders = 'deadline_reminders';
  static const String updateNotifications = 'update_notifications';

  // Security
  static const String encryptionEnabled = 'encryption_enabled';
  static const String maskKeys = 'mask_keys';
  static const String autoHideKeys = 'auto_hide_keys';

  // Debug
  static const String developerMode = 'developer_mode';
  static const String showStatusBar = 'show_status_bar';
  static const String showFpsCounter = 'show_fps_counter';
  static const String showGameDetailsSkmId = 'show_game_details_skm_id';

  // Window
  static const String windowWidth = 'window_width';
  static const String windowHeight = 'window_height';
  static const String windowX = 'window_x';
  static const String windowY = 'window_y';
  static const String windowMaximized = 'window_maximized';

  // Maintenance
  static const String legacyDefaultTagsCleanupDone =
      'legacy_default_tags_cleanup_done';

  /// Settings eligible to be synchronized across devices.
  ///
  /// Keep this list explicit to avoid accidentally syncing device-local values
  /// like window geometry or file paths.
  static const Set<String> syncableSettingsKeys = {
    activeTheme,
    currentTheme,
    customThemes,
    navBarPosition,
    navBarAppearance,
    navBarCollapsed,
    navBarButtonAlignment,
    navBarCenterButtons,
    navPanelGradientBar,
    navBarCombineButtons,
    navButtonArrangementH,
    navButtonArrangementV,
    navPanelOverlayStyle,
    settingsSectionPanelCollapsed,
    gradientAnimation,
    tooltipAnimation,
    tooltipShowDelay,
    swapGradientColors,
    gameListViewMode,
    gameSortMode,
    viewedNewGameIds,
    showTitleChip,
    showTitleOnNoPicture,
    showPlatformChip,
    showTagsChip,
    showTagsOnHoverOnly,
    showDeadlineChip,
    slimListView,
    toggleStyle,
    useThemeToggleRadius,
    sectionTitleLocation,
    autoBackupEnabled,
    autoBackupIntervalMinutes,
    backupMaxCount,
    notificationsEnabled,
    deadlineReminders,
    updateNotifications,
    encryptionEnabled,
    maskKeys,
    autoHideKeys,
    showStatusBar,
    showFpsCounter,
    showGameDetailsSkmId,
  };

  /// Keys that are always device-local and must never be synced.
  static const Set<String> syncExcludedKeys = {
    databasePath,
    isEncrypted,
    recentDatabasePaths,
    githubApiToken,
    updateRepo,
    skippedVersions,
    developerMode,
    windowWidth,
    windowHeight,
    windowX,
    windowY,
    windowMaximized,
    legacyDefaultTagsCleanupDone,
    syncEnabled,
    syncAutoOnStartup,
    syncDeviceId,
    syncTrustedPeersJson,
    syncLastTrustedPeerId,
    syncLastSyncAtIso,
    syncDbRevisionId,
    syncDbTimestampMillis,
    syncStaticPrivateKey,
    syncStaticPublicKey,
  };
}

/// Default settings values
class DefaultSettings {
  DefaultSettings._();

  // Updates
  static const bool autoUpdateCheck = true;
  static const String updateRepo = 'AbelSniffel/UniKM';
  static const bool includePreReleases = false;
  static const int autoCheckIntervalMinutes = kDefaultAutoUpdateIntervalMinutes;
  static const String githubApiToken = '';

  // Theme & UI
  static const String activeTheme = 'Dark';

  // Navigation
  static const NavBarPosition navBarPosition = NavBarPosition.bottom;
  static const NavBarAppearance navBarAppearance = NavBarAppearance.iconAndText;
  static const bool navBarCollapsed = true;
  static const NavBarButtonAlignment navBarButtonAlignment =
      NavBarButtonAlignment.center;
  static const bool navBarCenterButtons = true;
  static const bool navPanelGradientBar = true;
  static const bool navBarCombineButtons = false;
  static const NavPanelOverlayStyle navPanelOverlayStyle =
      NavPanelOverlayStyle.none;
  static const bool settingsSectionPanelCollapsed = false;
  static const NavButtonArrangement navButtonArrangementH =
      NavButtonArrangement.split;
  static const NavButtonArrangement navButtonArrangementV =
      NavButtonArrangement.split;

  // Animations
  static const GradientAnimation gradientAnimation = GradientAnimation.scroll;
  static const TooltipAnimation tooltipAnimation = TooltipAnimation.slide;
  static const int tooltipShowDelay = 600;
  // Swap primary & accent used by gradient bars (off by default)
  static const bool swapGradientColors = false;

  // Game List
  static const GameListViewMode gameListViewMode = GameListViewMode.list;
  static const GameSortMode gameSortMode = GameSortMode.deadlineFirst;

  // Game Card Visual
  static const bool showTitleChip = true;
  static const bool showTitleOnNoPicture = true;
  static const bool showPlatformChip = true;
  static const bool showTagsChip = true;
  static const bool showTagsOnHoverOnly = true;
  static const bool showDeadlineChip = true;
  static bool get slimListView => Platform.isAndroid || Platform.isIOS;
  static const bool showRatings =
      true; // Lives in "additional UI" section but included here for convenience

  // Toggle & Section Style
  static const ToggleStyle toggleStyle = ToggleStyle.morphDot;
  static const bool useThemeToggleRadius = false;
  static const SectionTitleLocation sectionTitleLocation =
      SectionTitleLocation.top;

  // Backup
  static const bool autoBackupEnabled = true;
  static const int autoBackupIntervalMinutes = 5;
  static const int backupMaxCount = 10;

  // Device Sync
  static const bool syncEnabled = false;
  static const bool syncAutoOnStartup = false;
  static const String syncDeviceId = '';
  static const String syncTrustedPeersJson = '[]';
  static const String syncLastTrustedPeerId = '';
  static const String syncLastSyncAtIso = '';
  static const String syncDbRevisionId = '';
  static const int syncDbTimestampMillis = 0;
  static const String syncStaticPrivateKey = '';
  static const String syncStaticPublicKey = '';

  // Debug
  static const bool developerMode = false;
  static const bool showStatusBar = false;
  static const bool showFpsCounter = true;
  static const bool showGameDetailsSkmId = false;

  // Maintenance
  static const bool legacyDefaultTagsCleanupDone = false;

  // Window
  static const double windowWidth = 1300;
  static const double windowHeight = 800;
}

/// Typed view of settings used by `GameCard`.
///
/// This keeps UI code smaller and lets Riverpod only rebuild cards when one of
/// these fields actually changes.
class GameCardSettings {
  const GameCardSettings({
    required this.showTitle,
    required this.showTitleOnNoPicture,
    required this.showPlatform,
    required this.showTags,
    required this.showTagsOnHoverOnly,
    required this.showDeadline,
    required this.showRatings,
    required this.slimListView,
  });

  factory GameCardSettings.fromMap(Map<String, dynamic> settings) {
    final slimListView =
        (settings[SettingsKeys.slimListView] as bool?) ??
        DefaultSettings.slimListView;

    return GameCardSettings(
      showTitle:
          (settings[SettingsKeys.showTitleChip] as bool?) ??
          DefaultSettings.showTitleChip,
      showTitleOnNoPicture:
          (settings[SettingsKeys.showTitleOnNoPicture] as bool?) ??
          DefaultSettings.showTitleOnNoPicture,
      showPlatform:
          (settings[SettingsKeys.showPlatformChip] as bool?) ??
          DefaultSettings.showPlatformChip,
      showTags:
          (settings[SettingsKeys.showTagsChip] as bool?) ??
          DefaultSettings.showTagsChip,
      showTagsOnHoverOnly:
          (settings[SettingsKeys.showTagsOnHoverOnly] as bool?) ??
          DefaultSettings.showTagsOnHoverOnly,
      showDeadline:
          (settings[SettingsKeys.showDeadlineChip] as bool?) ??
          DefaultSettings.showDeadlineChip,
      // Kept as a separate key because it lives in the "additional UI" section.
      showRatings: (settings[SettingsKeys.showRatings] as bool?) ?? true,
      slimListView: slimListView,
    );
  }

  final bool showTitle;
  final bool showTitleOnNoPicture;
  final bool showPlatform;
  final bool showTags;
  final bool showTagsOnHoverOnly;
  final bool showDeadline;
  final bool showRatings;
  final bool slimListView;

  @override
  bool operator ==(Object other) {
    return other is GameCardSettings &&
        other.showTitle == showTitle &&
        other.showTitleOnNoPicture == showTitleOnNoPicture &&
        other.showPlatform == showPlatform &&
        other.showTags == showTags &&
        other.showTagsOnHoverOnly == showTagsOnHoverOnly &&
        other.showDeadline == showDeadline &&
        other.showRatings == showRatings &&
        other.slimListView == slimListView;
  }

  @override
  int get hashCode => Object.hash(
    showTitle,
    showTitleOnNoPicture,
    showPlatform,
    showTags,
    showTagsOnHoverOnly,
    showDeadline,
    showRatings,
    slimListView,
  );
}

class AppearanceSettings {
  const AppearanceSettings({required this.currentTheme});

  factory AppearanceSettings.fromMap(Map<String, dynamic> settings) {
    return AppearanceSettings(
      currentTheme:
          (settings[SettingsKeys.currentTheme] as String?) ??
          (settings[SettingsKeys.activeTheme] as String?) ??
          DefaultSettings.activeTheme,
    );
  }

  final String currentTheme;

  @override
  bool operator ==(Object other) =>
      other is AppearanceSettings && other.currentTheme == currentTheme;

  @override
  int get hashCode => currentTheme.hashCode;
}

class LibrarySettings {
  const LibrarySettings({
    required this.showPlatformBadges,
    required this.showTagChips,
    required this.showRatings,
  });

  factory LibrarySettings.fromMap(Map<String, dynamic> settings) {
    return LibrarySettings(
      showPlatformBadges:
          (settings[SettingsKeys.showPlatformBadges] as bool?) ?? true,
      showTagChips: (settings[SettingsKeys.showTagChips] as bool?) ?? true,
      showRatings: (settings[SettingsKeys.showRatings] as bool?) ?? true,
    );
  }

  final bool showPlatformBadges;
  final bool showTagChips;
  final bool showRatings;

  @override
  bool operator ==(Object other) {
    return other is LibrarySettings &&
        other.showPlatformBadges == showPlatformBadges &&
        other.showTagChips == showTagChips &&
        other.showRatings == showRatings;
  }

  @override
  int get hashCode =>
      Object.hash(showPlatformBadges, showTagChips, showRatings);
}

class NotificationsSettings {
  const NotificationsSettings({
    required this.deadlineReminders,
    required this.updateNotifications,
  });

  factory NotificationsSettings.fromMap(Map<String, dynamic> settings) {
    return NotificationsSettings(
      deadlineReminders:
          (settings[SettingsKeys.deadlineReminders] as bool?) ?? true,
      updateNotifications:
          (settings[SettingsKeys.updateNotifications] as bool?) ?? true,
    );
  }

  final bool deadlineReminders;
  final bool updateNotifications;

  @override
  bool operator ==(Object other) {
    return other is NotificationsSettings &&
        other.deadlineReminders == deadlineReminders &&
        other.updateNotifications == updateNotifications;
  }

  @override
  int get hashCode => Object.hash(deadlineReminders, updateNotifications);
}

class UpdatesSettings {
  const UpdatesSettings({
    required this.autoCheckEnabled,
    required this.autoCheckIntervalMinutes,
    required this.includePrerelease,
    required this.skippedVersions,
    required this.updateRepo,
    required this.githubApiToken,
  });

  factory UpdatesSettings.fromMap(Map<String, dynamic> settings) {
    return UpdatesSettings(
      autoCheckEnabled:
          (settings[SettingsKeys.autoUpdateCheck] as bool?) ??
          DefaultSettings.autoUpdateCheck,
      autoCheckIntervalMinutes: kDefaultAutoUpdateIntervalMinutes,
      includePrerelease:
          (settings[SettingsKeys.includePreReleases] as bool?) ??
          DefaultSettings.includePreReleases,
      skippedVersions:
          (settings[SettingsKeys.skippedVersions] as List<String>?) ??
          const <String>[],
      updateRepo:
          (settings[SettingsKeys.updateRepo] as String?) ??
          DefaultSettings.updateRepo,
      githubApiToken:
          (settings[SettingsKeys.githubApiToken] as String?) ??
          DefaultSettings.githubApiToken,
    );
  }

  final bool autoCheckEnabled;
  final int autoCheckIntervalMinutes;
  final bool includePrerelease;
  final List<String> skippedVersions;
  final String updateRepo;
  final String githubApiToken;

  @override
  bool operator ==(Object other) {
    return other is UpdatesSettings &&
        other.autoCheckEnabled == autoCheckEnabled &&
        other.autoCheckIntervalMinutes == autoCheckIntervalMinutes &&
        other.includePrerelease == includePrerelease &&
        _listEquals(other.skippedVersions, skippedVersions) &&
        other.updateRepo == updateRepo &&
        other.githubApiToken == githubApiToken;
  }

  @override
  int get hashCode => Object.hash(
    autoCheckEnabled,
    autoCheckIntervalMinutes,
    includePrerelease,
    Object.hashAll(skippedVersions),
    updateRepo,
    githubApiToken,
  );

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class SecuritySettings {
  const SecuritySettings({
    required this.maskKeys,
    required this.autoHideKeys,
    required this.encryptionEnabled,
    required this.recentDatabasePaths,
  });

  factory SecuritySettings.fromMap(Map<String, dynamic> settings) {
    return SecuritySettings(
      maskKeys: (settings[SettingsKeys.maskKeys] as bool?) ?? true,
      autoHideKeys: (settings[SettingsKeys.autoHideKeys] as bool?) ?? true,
      encryptionEnabled:
          (settings[SettingsKeys.encryptionEnabled] as bool?) ?? false,
      recentDatabasePaths:
          (settings[SettingsKeys.recentDatabasePaths] as List<String>?) ??
          const <String>[],
    );
  }

  final bool maskKeys;
  final bool autoHideKeys;
  final bool encryptionEnabled;
  final List<String> recentDatabasePaths;

  @override
  bool operator ==(Object other) {
    return other is SecuritySettings &&
        other.maskKeys == maskKeys &&
        other.autoHideKeys == autoHideKeys &&
        other.encryptionEnabled == encryptionEnabled &&
        _listEquals(other.recentDatabasePaths, recentDatabasePaths);
  }

  @override
  int get hashCode => Object.hash(
    maskKeys,
    autoHideKeys,
    encryptionEnabled,
    Object.hashAll(recentDatabasePaths),
  );

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class AppShellSettings {
  const AppShellSettings({
    required this.navBarPosition,
    required this.navBarAppearance,
    required this.gradientAnimation,
    required this.navBarCollapsed,
    required this.navPanelGradientBar,
    required this.navBarCombineButtons,
    required this.settingsSectionPanelCollapsed,
    required this.autoBackupEnabled,
    required this.autoBackupIntervalMinutes,
    required this.developerMode,
    required this.windowWidth,
    required this.windowHeight,
    required this.windowX,
    required this.windowY,
    required this.windowMaximized,
  });

  factory AppShellSettings.fromMap(Map<String, dynamic> settings) {
    return AppShellSettings(
      navBarPosition:
          (settings[SettingsKeys.navBarPosition] as NavBarPosition?) ??
          DefaultSettings.navBarPosition,
      navBarAppearance:
          (settings[SettingsKeys.navBarAppearance] as NavBarAppearance?) ??
          DefaultSettings.navBarAppearance,
      gradientAnimation:
          (settings[SettingsKeys.gradientAnimation] as GradientAnimation?) ??
          DefaultSettings.gradientAnimation,
      navBarCollapsed:
          (settings[SettingsKeys.navBarCollapsed] as bool?) ??
          DefaultSettings.navBarCollapsed,
      navPanelGradientBar:
          (settings[SettingsKeys.navPanelGradientBar] as bool?) ??
          DefaultSettings.navPanelGradientBar,
      navBarCombineButtons:
          (settings[SettingsKeys.navBarCombineButtons] as bool?) ??
          DefaultSettings.navBarCombineButtons,
      settingsSectionPanelCollapsed:
          (settings[SettingsKeys.settingsSectionPanelCollapsed] as bool?) ??
          DefaultSettings.settingsSectionPanelCollapsed,
      autoBackupEnabled:
          (settings[SettingsKeys.autoBackupEnabled] as bool?) ??
          DefaultSettings.autoBackupEnabled,
      autoBackupIntervalMinutes:
          (settings[SettingsKeys.autoBackupIntervalMinutes] as int?) ??
          DefaultSettings.autoBackupIntervalMinutes,
      developerMode:
          (settings[SettingsKeys.developerMode] as bool?) ??
          DefaultSettings.developerMode,
      windowWidth:
          (settings[SettingsKeys.windowWidth] as double?) ??
          DefaultSettings.windowWidth,
      windowHeight:
          (settings[SettingsKeys.windowHeight] as double?) ??
          DefaultSettings.windowHeight,
      windowX: settings[SettingsKeys.windowX] as double?,
      windowY: settings[SettingsKeys.windowY] as double?,
      windowMaximized:
          (settings[SettingsKeys.windowMaximized] as bool?) ?? false,
    );
  }

  final NavBarPosition navBarPosition;
  final NavBarAppearance navBarAppearance;
  final GradientAnimation gradientAnimation;
  final bool navBarCollapsed;
  final bool navPanelGradientBar;
  final bool navBarCombineButtons;
  final bool settingsSectionPanelCollapsed;
  final bool autoBackupEnabled;
  final int autoBackupIntervalMinutes;
  final bool developerMode;
  final double windowWidth;
  final double windowHeight;
  final double? windowX;
  final double? windowY;
  final bool windowMaximized;

  @override
  bool operator ==(Object other) {
    return other is AppShellSettings &&
        other.navBarPosition == navBarPosition &&
        other.navBarAppearance == navBarAppearance &&
        other.gradientAnimation == gradientAnimation &&
        other.navBarCollapsed == navBarCollapsed &&
        other.navPanelGradientBar == navPanelGradientBar &&
        other.navBarCombineButtons == navBarCombineButtons &&
        other.settingsSectionPanelCollapsed == settingsSectionPanelCollapsed &&
        other.autoBackupEnabled == autoBackupEnabled &&
        other.autoBackupIntervalMinutes == autoBackupIntervalMinutes &&
        other.developerMode == developerMode &&
        other.windowWidth == windowWidth &&
        other.windowHeight == windowHeight &&
        other.windowX == windowX &&
        other.windowY == windowY &&
        other.windowMaximized == windowMaximized;
  }

  @override
  int get hashCode => Object.hash(
    navBarPosition,
    navBarAppearance,
    gradientAnimation,
    navBarCollapsed,
    navPanelGradientBar,
    navBarCombineButtons,
    settingsSectionPanelCollapsed,
    autoBackupEnabled,
    autoBackupIntervalMinutes,
    developerMode,
    windowWidth,
    windowHeight,
    windowX,
    windowY,
    windowMaximized,
  );
}

class TooltipSettings {
  const TooltipSettings({required this.animation, required this.showDelay});

  factory TooltipSettings.fromMap(Map<String, dynamic> settings) {
    return TooltipSettings(
      animation:
          (settings[SettingsKeys.tooltipAnimation] as TooltipAnimation?) ??
          DefaultSettings.tooltipAnimation,
      showDelay:
          (settings[SettingsKeys.tooltipShowDelay] as int?) ??
          DefaultSettings.tooltipShowDelay,
    );
  }

  final TooltipAnimation animation;
  final int showDelay;

  @override
  bool operator ==(Object other) {
    return other is TooltipSettings &&
        other.animation == animation &&
        other.showDelay == showDelay;
  }

  @override
  int get hashCode => Object.hash(animation, showDelay);
}

class BackupSettings {
  const BackupSettings({required this.maxCount});

  factory BackupSettings.fromMap(Map<String, dynamic> settings) {
    return BackupSettings(
      maxCount:
          (settings[SettingsKeys.backupMaxCount] as int?) ??
          DefaultSettings.backupMaxCount,
    );
  }

  final int maxCount;

  @override
  bool operator ==(Object other) {
    return other is BackupSettings && other.maxCount == maxCount;
  }

  @override
  int get hashCode => maxCount.hashCode;
}
