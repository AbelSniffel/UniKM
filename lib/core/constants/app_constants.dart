/// Application-wide constants matching the original UniKM Python app
library;

import 'package:flutter/animation.dart';

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
const String kAppVersion = '1.3.0';
const String kGitHubRepo = 'AbelSniffel/UniKM';

// =============================================================================
// DIMENSIONS - UI ELEMENTS
// =============================================================================
const double kElementHeight = 36.0; // Standard height for buttons, input fields, and dropdowns
const double kElementHSpacing = 5.0; // General spacing between elements, used by SizedBox widgets
const double kElementVSpacing = 5.0; // General vertical spacing between elements, used by SizedBox widgets
const double kElementPaddingVertical = 4.0;
const double kPageNavButtonHeight = 34.0;
const double kButtonPaddingHorizontal = 14.0;
const double kTagChipPaddingHorizontal = 10.0;
const double kTagChipPaddingVertical = 5.5;
const double kIconSize = 24.0;
const double kIconSizeHeader = 28.0;
const double kDeadlineSelectorWidth = 150.0;
const double kPageTitleHeight = 40.0;
const double kScrollbarWidth = 22.0;
const double kDropdownMenuMaxHeight = 320.0;
const double kVeryNarrowLayoutBreakpoint = 605.0;
const double kSliderTrackHeight = 16.0;
const double kSliderIndicatorOuterDiameter = 24.0;
const double kSliderIndicatorInnerDiameter = 20.0;

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

// Slim List View
const double kSlimListCardHeight = 44.0;
const double kSlimListCardSpacing = 0.0;

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
const double kMinWindowWidth = 415.0;
const double kMinWindowHeight = 560.0;

// =============================================================================
// ANIMATION DURATIONS
// =============================================================================
const Duration kHoverCardAnimation = Duration(milliseconds: 120);
const Duration kVeryFastAnimation = Duration(milliseconds: 100);
const Duration kFastAnimation = Duration(milliseconds: 160);
const Duration kMediumAnimation = Duration(milliseconds: 250);
const Duration kPageTransition = Duration(milliseconds: 200);
const Curve kPageTransitionCurve = Curves.easeInOutCubic;
const Duration kNavPanelMotionAnimation = Duration(milliseconds: 250);
const Curve kNavPanelMotionCurve = Curves.easeInOutCubic;
const Duration kNavButtonExpandAnimation = Duration(milliseconds: 200);
const Curve kNavButtonExpandCurve = Curves.easeInOutCubic;
const Duration kStandardNavPlacementAnimation = Duration(milliseconds: 250);
const Curve kStandardNavPlacementCurve = Curves.easeInOutCubic;

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
// UPDATE
// =============================================================================
const int kDefaultAutoUpdateIntervalMinutes = 10;

// =============================================================================
// STEAM API
// =============================================================================
const String kSteamStoreApiBase = 'https://store.steampowered.com/api';
const String kSteamCdnBase = 'https://steamcdn-a.akamaihd.net';

String get kSteamStoreBase => kSteamStoreApiBase.replaceFirst(RegExp(r'/api/?$'), '');
String steamStoreApiUrl(String path) => '$kSteamStoreApiBase/$path';
String steamStoreUrl(String path) => '$kSteamStoreBase/$path';
String steamAppPageUrl(String appId) => steamStoreUrl('app/$appId');
String steamSearchPageUrl(String term) => steamStoreUrl('search/?term=${Uri.encodeComponent(term)}');
String steamRegisterKeyPageUrl(String key) => steamStoreUrl('account/registerkey?key=${Uri.encodeComponent(key)}');
String steamCdnAppImageUrl(String appId, String assetName) => '$kSteamCdnBase/steam/apps/$appId/$assetName';