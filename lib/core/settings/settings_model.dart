/// Settings model and default values
/// Matches the 25+ settings from the original Python app
library;

import 'dart:io';

import 'package:collection/collection.dart';

import '../constants/app_constants.dart';

/// Navigation bar position options
enum NavBarPosition {
  left('Left'),
  right('Right'),
  top('Top'),
  bottom('Bottom');

  const NavBarPosition(this.displayName);

  final String displayName;
}

/// Page-button placement around the navigation gradient bar.
enum NavButtonArrangement {
  start,
  split,
  end;

  String displayName({required bool isHorizontal}) => switch (this) {
    start => isHorizontal ? 'Left' : 'Top',
    split => 'Split',
    end => isHorizontal ? 'Right' : 'Bottom',
  };
}

/// How page-button labels are shown in the navigation panel.
enum NavExpansionMode {
  automatic('Dynamic'),
  expanded('Expanded'),
  collapsed('Collapsed');

  const NavExpansionMode(this.displayName);

  final String displayName;

  NavExpansionMode get next => values[(index + 1) % values.length];
}

/// Navigation bar appearance options
enum NavBarAppearance {
  iconAndText('Icon & Text'),
  iconOnly('Icon Only'),
  textOnly('Text Only');

  const NavBarAppearance(this.displayName);

  final String displayName;
}

/// Decorative overlay styles applied to the navigation panel background.
enum NavPanelOverlayStyle {
  none('None'),
  gradient('Gradient'),
  diagonalStripes('Diagonal'),
  crosshatch('Crosshatch'),
  hexPattern('Hex Pattern'),
  ripple('Ripple');

  const NavPanelOverlayStyle(this.displayName);

  final String displayName;
}

/// Gradient animation styles
enum GradientAnimation {
  solid('Solid', 'No animation, solid primary color'),
  scroll('Scroll', 'Smooth scrolling gradient'),
  pulse('Pulse', 'Gentle breathing pulse'),
  heart('Heart', 'Expanding heartbeat pulse'),
  scanner('Scanner', 'Bouncing scanner beam'),
  wave('Wave', 'Layered wave bands flowing across the bar'),
  barberPole(
    'Barber Pole',
    'Moving diagonal theme colors with softly rounded shading',
  ),
  spiral('Spiral', 'Raised theme-color ribbons rotating around the bar axis'),
  helix(
    'Helix',
    'Two twisting ribbons alternate over and under around a shared axis',
  );

  const GradientAnimation(this.displayName, this.description);

  final String displayName;
  final String description;
}

/// Shared multiplier applied to each gradient effect's own base speed.
enum GradientAnimationSpeed {
  slow('Slow', 0.5),
  standard('Default', 1.0),
  fast('Fast', 1.5);

  const GradientAnimationSpeed(this.displayName, this.multiplier);

  final String displayName;
  final double multiplier;
}

/// Tooltip animation styles
enum TooltipAnimation {
  fade('Fade'),
  slide('Slide');

  const TooltipAnimation(this.displayName);

  final String displayName;
}

/// Toggle switch styles
enum ToggleStyle {
  regular('Regular', 'Sliding switch with an on/off thumb.'),
  dot('Dot', 'Round dot that grows when enabled.'),
  morphDot('Morph Dot', 'Dot toggle that follows the theme’s corner radius.'),
  segmented('OFF / ON', 'Two-part OFF / ON switch with a sliding highlight.');

  const ToggleStyle(this.displayName, this.description);

  final String displayName;
  final String description;
}

/// Status controls used only by interaction settings cards.
enum SettingsCardIndicatorStyle {
  switchControl('Switch', 'Use the selected app switch inside the card.'),
  retroSquare('Retro Square', 'A glowing recessed display with retro texture.');

  const SettingsCardIndicatorStyle(this.displayName, this.description);

  final String displayName;
  final String description;
}

/// Section GroupBox title location
enum SectionTitleLocation {
  left('Left'),
  top('Top');

  const SectionTitleLocation(this.displayName);

  final String displayName;
}

/// Game list view mode
enum GameListViewMode {
  grid('Grid'),
  list('List');

  const GameListViewMode(this.displayName);

  final String displayName;
}

enum ListViewDensityMode {
  regular('Regular'),
  slim('Slim');

  const ListViewDensityMode(this.displayName);

  final String displayName;
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
  deadlineFirst('Deadline First'),
  titleAZ('Title A-Z'),
  titleZA('Title Z-A'),
  platformAZ('Platform A-Z'),
  platformZA('Platform Z-A'),
  dateNewest('Date Added (Newest)'),
  dateOldest('Date Added (Oldest)'),
  ratingHigh('Rating (Highest first)'),
  ratingLow('Rating (Lowest first)');

  const GameSortMode(this.displayName);

  final String displayName;
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
  static const String navExpansionMode = 'nav_expansion_mode';

  /// Arrangement for horizontal nav panel (top or bottom position).
  static const String navButtonArrangementH = 'nav_button_arrangement_h';

  /// Arrangement for vertical nav panel (left or right position).
  static const String navButtonArrangementV = 'nav_button_arrangement_v';
  static const String navPanelOverlayStyle = 'nav_panel_overlay_style';
  static const String settingsSectionPanelCollapsed =
      'settings_section_panel_collapsed';

  // Animations
  static const String gradientAnimation = 'gradient_animation';
  static const String gradientAnimationSpeed = 'gradient_animation_speed';
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
  static const String showPlatformOnHoverOnly = 'show_platform_on_hover_only';
  static const String showDeadlineChip = 'show_deadline_chip';
  static const String slimListView = 'slim_list_view';

  // Toggle & Section Style
  static const String toggleStyle = 'toggle_style';
  static const String settingsCardIndicatorStyle =
      'settings_card_indicator_style';
  static const String useThemeToggleRadius = 'use_theme_toggle_radius';
  static const String sectionTitleLocation = 'section_title_location';

  // Experimental Settings Layout
  static const String experimentalInteractionCards =
      'experimental_interaction_cards';

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
  static const String syncRevokedPeersJson = 'sync_revoked_peers_json';
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
  static const String showSyncDeviceId = 'show_sync_device_id';

  // Display
  static const String frameRatePreference = 'frame_rate_preference';

  // Window
  static const String windowWidth = 'window_width';
  static const String windowHeight = 'window_height';
  static const String windowX = 'window_x';
  static const String windowY = 'window_y';
  static const String windowMaximized = 'window_maximized';

  // Maintenance
  static const String legacyDefaultTagsCleanupDone =
      'legacy_default_tags_cleanup_done';
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
  static const NavExpansionMode navExpansionMode = NavExpansionMode.automatic;
  static const NavPanelOverlayStyle navPanelOverlayStyle =
      NavPanelOverlayStyle.none;
  static const bool settingsSectionPanelCollapsed = false;
  static const NavButtonArrangement navButtonArrangementH =
      NavButtonArrangement.split;
  static const NavButtonArrangement navButtonArrangementV =
      NavButtonArrangement.split;

  // Animations
  static const GradientAnimation gradientAnimation = GradientAnimation.scroll;
  static const GradientAnimationSpeed gradientAnimationSpeed =
      GradientAnimationSpeed.standard;
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
  static const bool showPlatformOnHoverOnly = false;
  static const bool showDeadlineChip = true;
  static bool get slimListView => Platform.isAndroid || Platform.isIOS;
  static const bool showRatings =
      true; // Lives in "additional UI" section but included here for convenience

  // Toggle & Section Style
  static const ToggleStyle toggleStyle = ToggleStyle.morphDot;
  static const SettingsCardIndicatorStyle settingsCardIndicatorStyle =
      SettingsCardIndicatorStyle.switchControl;
  static const bool useThemeToggleRadius = false;
  static const SectionTitleLocation sectionTitleLocation =
      SectionTitleLocation.top;

  // Experimental Settings Layout
  static const bool experimentalInteractionCards = true;

  // Backup
  static const bool autoBackupEnabled = true;
  static const int autoBackupIntervalMinutes = 5;
  static const int backupMaxCount = 10;

  // Device Sync
  static const bool syncEnabled = false;
  static const bool syncAutoOnStartup = false;
  static const String syncDeviceId = '';
  static const String syncTrustedPeersJson = '[]';
  static const String syncRevokedPeersJson = '[]';
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
  static const bool showSyncDeviceId = false;

  // Display
  static const String frameRatePreference = 'auto';

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
    required this.showPlatformOnHoverOnly,
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
      showPlatformOnHoverOnly:
          (settings[SettingsKeys.showPlatformOnHoverOnly] as bool?) ??
          DefaultSettings.showPlatformOnHoverOnly,
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
  final bool showPlatformOnHoverOnly;
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
        other.showPlatformOnHoverOnly == showPlatformOnHoverOnly &&
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
    showPlatformOnHoverOnly,
    showDeadline,
    showRatings,
    slimListView,
  );
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
        const ListEquality<String>().equals(
          other.skippedVersions,
          skippedVersions,
        ) &&
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
        const ListEquality<String>().equals(
          other.recentDatabasePaths,
          recentDatabasePaths,
        );
  }

  @override
  int get hashCode => Object.hash(
    maskKeys,
    autoHideKeys,
    encryptionEnabled,
    Object.hashAll(recentDatabasePaths),
  );
}

class AppShellSettings {
  const AppShellSettings({
    required this.navBarPosition,
    required this.navBarAppearance,
    required this.navExpansionMode,
    required this.gradientAnimation,
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
      navExpansionMode:
          (settings[SettingsKeys.navExpansionMode] as NavExpansionMode?) ??
          DefaultSettings.navExpansionMode,
      gradientAnimation:
          (settings[SettingsKeys.gradientAnimation] as GradientAnimation?) ??
          DefaultSettings.gradientAnimation,
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
  final NavExpansionMode navExpansionMode;
  final GradientAnimation gradientAnimation;
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
        other.navExpansionMode == navExpansionMode &&
        other.gradientAnimation == gradientAnimation &&
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
    navExpansionMode,
    gradientAnimation,
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
