/// Application-wide constants matching the original UniKM Python app
library;

import 'package:flutter/animation.dart';

// =============================================================================
// APP INFO
// =============================================================================
const String kAppName = 'UniKM';
const String kAppVersion = '1.4.0';
const String kGitHubRepo = 'AbelSniffel/UniKM';

// =============================================================================
// DIMENSIONS - UI ELEMENTS
// =============================================================================
const double kNavigationPanelHorizontalExtent = 64.0;
const double kElementHeight =
    36.0; // Standard height for buttons, input fields, and dropdowns
const double kElementHSpacing =
    5.0; // General spacing between elements, used by SizedBox widgets
const double kElementVSpacing =
    5.0; // General vertical spacing between elements, used by SizedBox widgets
/// Shared gap below family titles and between their groupboxes.
const double kGroupBoxSpacing = 12.0;
const double kButtonPaddingHorizontal = 8.0;
const double kTextButtonPaddingHorizontal = 14.0;
const double kIconSize = 24.0;
const double kDropdownMenuMaxHeight = 320.0;
const double kVeryNarrowLayoutBreakpoint = 720.0;

/// Width range for settings toggle, choice, action, and preview cards. Rows
/// that cannot fit two minimum-width cards use the full width instead.
const double kInteractionCardMinWidth = 240.0;
const double kInteractionCardMaxWidth = 360.0;

/// Available settings content width for full-width cards and stacked header actions.
const double kSettingsCompactLayoutBreakpoint = 420.0;
const double kSliderTrackHeight = 18.0;
const double kSliderHandleSize = 28.0;
const double kSliderHandleGap = 3.0;

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
// DIMENSIONS - WINDOW
// =============================================================================
const double kDefaultWindowWidth = 1300.0;
const double kDefaultWindowHeight = 900.0;
const double kMinWindowWidth = 415.0;
const double kMinWindowHeight = 560.0;

// =============================================================================
// ANIMATION DURATIONS
// =============================================================================
const Duration kVeryFastAnimation = Duration(milliseconds: 100);
const Duration kFastAnimation = Duration(milliseconds: 160);
const Duration kMediumAnimation = Duration(milliseconds: 250);

/// Shared timing for tab selection, tab content, and main-page navigation.
const Duration kTabTransition = Duration(milliseconds: 350);
const Curve kTabTransitionCurve = Curves.easeInOutCubic;
const Duration kFilterExpandAnimation = Duration(milliseconds: 400);
const Duration kFilterCollapseAnimation = Duration(milliseconds: 350);
const Curve kFilterPanelCurve = Curves.easeInOutCubic;
const Duration kPageTransition = kTabTransition;
const Curve kPageTransitionCurve = kTabTransitionCurve;
const Duration kNavPanelMotionAnimation = Duration(milliseconds: 250);
const Curve kNavPanelMotionCurve = Curves.easeInOutCubic;
const Duration kNavButtonExpandAnimation = Duration(milliseconds: 200);
const Curve kNavButtonExpandCurve = Curves.easeInOutCubic;

// =============================================================================
// DATABASE
// =============================================================================
const String kDatabaseName = 'keys.db';

// =============================================================================
// BACKUP
// =============================================================================
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

String get kSteamStoreBase =>
    kSteamStoreApiBase.replaceFirst(RegExp(r'/api/?$'), '');
String steamStoreApiUrl(String path) => '$kSteamStoreApiBase/$path';
String steamStoreUrl(String path) => '$kSteamStoreBase/$path';
String steamAppPageUrl(String appId) => steamStoreUrl('app/$appId');
String steamSearchPageUrl(String term) =>
    steamStoreUrl('search/?term=${Uri.encodeComponent(term)}');
String steamRegisterKeyPageUrl(String key) =>
    steamStoreUrl('account/registerkey?key=${Uri.encodeComponent(key)}');

/// The store page that redeems [key] on [platform], or null when that store
/// has no such link.
String? redeemPageUrl(String platform, String key) => key.isEmpty
    ? null
    : switch (platform) {
        'Steam' => steamRegisterKeyPageUrl(key),
        'GOG' => 'https://www.gog.com/redeem/${Uri.encodeComponent(key)}',
        _ => null,
      };
String steamCdnAppImageUrl(String appId, String assetName) =>
    '$kSteamCdnBase/steam/apps/$appId/$assetName';
