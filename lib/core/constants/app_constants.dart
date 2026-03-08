/// Application-wide constants matching the original UniKM Python app
library;

/// AppConstants class wrapper for easy access
class AppConstants {
  AppConstants._();

  static const String appName = kAppName;
  static const String appTitle = kAppName;
  static const String appVersion = kAppVersion;
  static const String githubRepo = kGitHubRepo;
  static const String releasesUrl = 'https://github.com/$kGitHubRepo/releases';
}

// =============================================================================
// APP INFO
// =============================================================================
const String kAppName = 'UniKM';
const String kAppVersion = '1.1.0';
const String kGitHubRepo = 'AbelSniffel/UniKM';

// =============================================================================
// DIMENSIONS - UI ELEMENTS
// =============================================================================
const double kElementHeight = 28.0;
const double kPageNavButtonHeight = 34.0;
const double kTagButtonHeight = 22.0;
const double kPageTitleHeight = 40.0;
const double kScrollbarWidth = 16.0;
const double kWidgetSpacing = 5.0;
const double kToggleSpacing = 12.0;

// =============================================================================
// DIMENSIONS - GAME CARDS
// =============================================================================
// Grid View
const double kGridCardWidth = 460.0;
const double kGridCardHeight = 215.0;
const double kGridCardSpacing = 6.0;

// List View
const double kListCardHeight = 110.0;
const double kListCardImageWidth = 220.0;
const double kListCardSpacing = 6.0;

// =============================================================================
// DIMENSIONS - TOOLTIPS
// =============================================================================
const double kTooltipOffset = 10.0;
const int kTooltipShowDelay = 600; // milliseconds
const int kTooltipHideDelay = 50; // milliseconds

// =============================================================================
// DIMENSIONS - WINDOW
// =============================================================================
const double kDefaultWindowWidth = 1300.0;
const double kDefaultWindowHeight = 900.0;
const double kMinWindowWidth = 800.0;
const double kMinWindowHeight = 600.0;

// =============================================================================
// ANIMATION DURATIONS
// =============================================================================
const Duration kVeryFastAnimation = Duration(milliseconds: 100);
const Duration kFastAnimation = Duration(milliseconds: 150);
const Duration kMediumAnimation = Duration(milliseconds: 250);
const Duration kSlowAnimation = Duration(milliseconds: 400);
const Duration kPageTransition = Duration(milliseconds: 300);
const Duration kCardHoverAnimation = Duration(milliseconds: 150);

// =============================================================================
// DATABASE
// =============================================================================
const String kDatabaseName = 'keys.db';
const String kEncryptedDatabaseExtension = '.enc';
const int kPbkdf2Iterations = 220000;

// =============================================================================
// BACKUP
// =============================================================================
const int kDefaultAutoBackupIntervalMinutes = 5;
const int kDefaultMaxBackupCount = 10;

// =============================================================================
// STEAM API
// =============================================================================
const String kSteamStoreApiBase = 'https://store.steampowered.com/api';
const String kSteamCdnBase = 'https://steamcdn-a.akamaihd.net';
const Duration kSteamApiCacheDuration = Duration(hours: 24);