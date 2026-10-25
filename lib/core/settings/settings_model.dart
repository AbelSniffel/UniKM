/// Settings model and default values
/// Matches the 25+ settings from the original Python app
library;

import 'dart:io';

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
  morphDot('Morph Dot', 'Dot toggle that follows the theme’s corner radius.');

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
  static const bool showRatings = true;

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

// Typed settings slices. Records give each slice value equality, so a slice
// provider notifies only when one of its own fields changes. List fields
// compare by identity; saving a list with equal contents keeps its instance.

/// Typed view of settings used by `GameCard`.
typedef GameCardSettings = ({
  bool showTitle,
  bool showTitleOnNoPicture,
  bool showPlatform,
  bool showTags,
  bool showTagsOnHoverOnly,
  bool showPlatformOnHoverOnly,
  bool showDeadline,
  bool showRatings,
  bool slimListView,
});

T _settingOr<T>(Map<String, dynamic> settings, String key, T fallback) =>
    (settings[key] as T?) ?? fallback;

GameCardSettings gameCardSettingsFromMap(Map<String, dynamic> settings) => (
  showTitle: _settingOr(
    settings,
    SettingsKeys.showTitleChip,
    DefaultSettings.showTitleChip,
  ),
  showTitleOnNoPicture: _settingOr(
    settings,
    SettingsKeys.showTitleOnNoPicture,
    DefaultSettings.showTitleOnNoPicture,
  ),
  showPlatform: _settingOr(
    settings,
    SettingsKeys.showPlatformChip,
    DefaultSettings.showPlatformChip,
  ),
  showTags: _settingOr(
    settings,
    SettingsKeys.showTagsChip,
    DefaultSettings.showTagsChip,
  ),
  showTagsOnHoverOnly: _settingOr(
    settings,
    SettingsKeys.showTagsOnHoverOnly,
    DefaultSettings.showTagsOnHoverOnly,
  ),
  showPlatformOnHoverOnly: _settingOr(
    settings,
    SettingsKeys.showPlatformOnHoverOnly,
    DefaultSettings.showPlatformOnHoverOnly,
  ),
  showDeadline: _settingOr(
    settings,
    SettingsKeys.showDeadlineChip,
    DefaultSettings.showDeadlineChip,
  ),
  showRatings: _settingOr(
    settings,
    SettingsKeys.showRatings,
    DefaultSettings.showRatings,
  ),
  slimListView: _settingOr(
    settings,
    SettingsKeys.slimListView,
    DefaultSettings.slimListView,
  ),
);

typedef NotificationsSettings = ({
  bool deadlineReminders,
  bool updateNotifications,
});

NotificationsSettings notificationsSettingsFromMap(
  Map<String, dynamic> settings,
) => (
  deadlineReminders: _settingOr(settings, SettingsKeys.deadlineReminders, true),
  updateNotifications: _settingOr(
    settings,
    SettingsKeys.updateNotifications,
    true,
  ),
);

typedef UpdatesSettings = ({
  bool autoCheckEnabled,
  int autoCheckIntervalMinutes,
  bool includePrerelease,
  List<String> skippedVersions,
  String updateRepo,
  String githubApiToken,
});

UpdatesSettings updatesSettingsFromMap(Map<String, dynamic> settings) => (
  autoCheckEnabled: _settingOr(
    settings,
    SettingsKeys.autoUpdateCheck,
    DefaultSettings.autoUpdateCheck,
  ),
  autoCheckIntervalMinutes: DefaultSettings.autoCheckIntervalMinutes,
  includePrerelease: _settingOr(
    settings,
    SettingsKeys.includePreReleases,
    DefaultSettings.includePreReleases,
  ),
  skippedVersions: _settingOr(
    settings,
    SettingsKeys.skippedVersions,
    const <String>[],
  ),
  updateRepo: _settingOr(
    settings,
    SettingsKeys.updateRepo,
    DefaultSettings.updateRepo,
  ),
  githubApiToken: _settingOr(
    settings,
    SettingsKeys.githubApiToken,
    DefaultSettings.githubApiToken,
  ),
);

typedef SecuritySettings = ({
  bool maskKeys,
  bool autoHideKeys,
  bool encryptionEnabled,
  List<String> recentDatabasePaths,
});

SecuritySettings securitySettingsFromMap(Map<String, dynamic> settings) => (
  maskKeys: _settingOr(settings, SettingsKeys.maskKeys, true),
  autoHideKeys: _settingOr(settings, SettingsKeys.autoHideKeys, true),
  encryptionEnabled: _settingOr(
    settings,
    SettingsKeys.encryptionEnabled,
    false,
  ),
  recentDatabasePaths: _settingOr(
    settings,
    SettingsKeys.recentDatabasePaths,
    const <String>[],
  ),
);

typedef AppShellSettings = ({
  NavBarPosition navBarPosition,
  NavBarAppearance navBarAppearance,
  NavExpansionMode navExpansionMode,
  GradientAnimation gradientAnimation,
  bool settingsSectionPanelCollapsed,
  bool autoBackupEnabled,
  int autoBackupIntervalMinutes,
  bool developerMode,
  double windowWidth,
  double windowHeight,
  double? windowX,
  double? windowY,
  bool windowMaximized,
});

AppShellSettings appShellSettingsFromMap(Map<String, dynamic> settings) => (
  navBarPosition: _settingOr(
    settings,
    SettingsKeys.navBarPosition,
    DefaultSettings.navBarPosition,
  ),
  navBarAppearance: _settingOr(
    settings,
    SettingsKeys.navBarAppearance,
    DefaultSettings.navBarAppearance,
  ),
  navExpansionMode: _settingOr(
    settings,
    SettingsKeys.navExpansionMode,
    DefaultSettings.navExpansionMode,
  ),
  gradientAnimation: _settingOr(
    settings,
    SettingsKeys.gradientAnimation,
    DefaultSettings.gradientAnimation,
  ),
  settingsSectionPanelCollapsed: _settingOr(
    settings,
    SettingsKeys.settingsSectionPanelCollapsed,
    DefaultSettings.settingsSectionPanelCollapsed,
  ),
  autoBackupEnabled: _settingOr(
    settings,
    SettingsKeys.autoBackupEnabled,
    DefaultSettings.autoBackupEnabled,
  ),
  autoBackupIntervalMinutes: _settingOr(
    settings,
    SettingsKeys.autoBackupIntervalMinutes,
    DefaultSettings.autoBackupIntervalMinutes,
  ),
  developerMode: _settingOr(
    settings,
    SettingsKeys.developerMode,
    DefaultSettings.developerMode,
  ),
  windowWidth: _settingOr(
    settings,
    SettingsKeys.windowWidth,
    DefaultSettings.windowWidth,
  ),
  windowHeight: _settingOr(
    settings,
    SettingsKeys.windowHeight,
    DefaultSettings.windowHeight,
  ),
  windowX: settings[SettingsKeys.windowX] as double?,
  windowY: settings[SettingsKeys.windowY] as double?,
  windowMaximized: _settingOr(settings, SettingsKeys.windowMaximized, false),
);

typedef BackupSettings = ({int maxCount});

BackupSettings backupSettingsFromMap(Map<String, dynamic> settings) => (
  maxCount: _settingOr(
    settings,
    SettingsKeys.backupMaxCount,
    DefaultSettings.backupMaxCount,
  ),
);
