/// Theme system for UniKM
/// Implements the 3 base colors → computed palette system from the Python app
library;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../utils/color_utils.dart';

/// App theme configuration with 3 base colors
class AppThemeData {
  const AppThemeData({
    this.id = '',
    required this.name,
    required this.baseBackground,
    required this.basePrimary,
    required this.baseAccent,
    this.iconData,
    this.cornerRadius = 16.0,
    this.scrollbarRadius = 8.0,
    this.inputPaddingVertical = 12.0,
    this.inputPaddingHorizontal = 10.0,
    this.controlPaddingVertical = 10.0,
    this.controlPaddingHorizontal = 10.0,
  });

  final String id;
  final String name;
  final Color baseBackground;
  final Color basePrimary;
  final Color baseAccent;
  final IconData? iconData;
  final double cornerRadius;
  final double scrollbarRadius;
  final double controlPaddingHorizontal;
  final double controlPaddingVertical;
  final double inputPaddingHorizontal;
  final double inputPaddingVertical;
  EdgeInsets get controlPadding => EdgeInsets.symmetric(
    horizontal: controlPaddingHorizontal,
    vertical: controlPaddingVertical,
  );

  /// Get the icon for this theme
  IconData get icon => iconData ?? Icons.palette;

  /// Create theme from JSON map
  factory AppThemeData.fromJson(Map<String, dynamic> json) {
    final fallbackName = (json['name'] as String?) ?? 'Custom';
    final fallbackBackground =
        (json['base_background'] as String?) ?? '#141414';
    final fallbackPrimary = (json['base_primary'] as String?) ?? '#3F5485';
    final fallbackAccent = (json['base_accent'] as String?) ?? '#5F92FF';

    final parsedId = (json['id'] as String?)?.trim();
    final id = (parsedId != null && parsedId.isNotEmpty)
        ? parsedId
        : _legacyIdFromFields(
            name: fallbackName,
            baseBackgroundHex: fallbackBackground,
            basePrimaryHex: fallbackPrimary,
            baseAccentHex: fallbackAccent,
          );

    return AppThemeData(
      id: id,
      name: fallbackName,
      baseBackground: parseHexColor(fallbackBackground),
      basePrimary: parseHexColor(fallbackPrimary),
      baseAccent: parseHexColor(fallbackAccent),
      iconData: json['icon_code_point'] != null
          ? IconData(
              json['icon_code_point'] as int,
              fontFamily: 'MaterialIcons',
            )
          : null,
      cornerRadius: (json['corner_radius'] as num?)?.toDouble() ?? 8.0,
      scrollbarRadius: (json['scrollbar_radius'] as num?)?.toDouble() ?? 8.0,
      controlPaddingHorizontal:
          (json['control_padding_horizontal'] as num?)?.toDouble() ?? 12.0,
      controlPaddingVertical:
          (json['control_padding_vertical'] as num?)?.toDouble() ?? 12.0,
      inputPaddingHorizontal:
          (json['input_padding_horizontal'] as num?)?.toDouble() ?? 12.0,
      inputPaddingVertical:
          (json['input_padding_vertical'] as num?)?.toDouble() ?? 12.0,
    );
  }

  /// Convert theme to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'base_background': colorToHex(baseBackground),
      'base_primary': colorToHex(basePrimary),
      'base_accent': colorToHex(baseAccent),
      if (iconData != null) 'icon_code_point': iconData!.codePoint,
      'corner_radius': cornerRadius,
      'scrollbar_radius': scrollbarRadius,
      'control_padding_horizontal': controlPaddingHorizontal,
      'control_padding_vertical': controlPaddingVertical,
      'input_padding_horizontal': inputPaddingHorizontal,
      'input_padding_vertical': inputPaddingVertical,
    };
  }

  /// Copy with new values
  AppThemeData copyWith({
    String? id,
    String? name,
    Color? baseBackground,
    Color? basePrimary,
    Color? baseAccent,
    IconData? iconData,
    bool clearIcon = false,
    double? cornerRadius,
    double? scrollbarRadius,
    double? controlPaddingHorizontal,
    double? controlPaddingVertical,
    double? inputPaddingHorizontal,
    double? inputPaddingVertical,
  }) {
    return AppThemeData(
      id: id ?? this.id,
      name: name ?? this.name,
      baseBackground: baseBackground ?? this.baseBackground,
      basePrimary: basePrimary ?? this.basePrimary,
      baseAccent: baseAccent ?? this.baseAccent,
      iconData: clearIcon ? null : (iconData ?? this.iconData),
      cornerRadius: cornerRadius ?? this.cornerRadius,
      scrollbarRadius: scrollbarRadius ?? this.scrollbarRadius,
      controlPaddingHorizontal:
          controlPaddingHorizontal ?? this.controlPaddingHorizontal,
      controlPaddingVertical:
          controlPaddingVertical ?? this.controlPaddingVertical,
      inputPaddingHorizontal:
          inputPaddingHorizontal ?? this.inputPaddingHorizontal,
      inputPaddingVertical: inputPaddingVertical ?? this.inputPaddingVertical,
    );
  }

  /// Static getter for built-in themes
  static List<AppThemeData> get builtInThemes => kBuiltInThemes;

  static String generateThemeId() => const Uuid().v4();

  static String _legacyIdFromFields({
    required String name,
    required String baseBackgroundHex,
    required String basePrimaryHex,
    required String baseAccentHex,
  }) {
    String normalize(String value) => value.trim().toLowerCase();
    return 'legacy:${normalize(name)}:${normalize(baseBackgroundHex)}:${normalize(basePrimaryHex)}:${normalize(baseAccentHex)}';
  }

  // ===========================================================================
  // COMPUTED COLORS - Derived from 3 base colors
  // ===========================================================================

  /// Determine if this is a dark theme
  bool get isDark => baseBackground.computeLuminance() < 0.5;

  /// Primary text color (black or white based on background)
  Color get textPrimary => isDark ? Colors.white : Colors.black;

  /// Secondary text color (slightly muted)
  Color get textSecondary => isDark
      ? Colors.white.withValues(alpha: 0.7)
      : Colors.black.withValues(alpha: 0.7);

  /// Hint/disabled text color
  Color get textHint => isDark
      ? Colors.white.withValues(alpha: 0.5)
      : Colors.black.withValues(alpha: 0.5);

  /// Surface color (cards, dialogs)
  Color get surface =>
      blendColors(baseBackground, isDark ? Colors.white : Colors.black, 0.04);

  /// Surface variant (slightly different surface)
  Color get surfaceVariant =>
      blendColors(baseBackground, isDark ? Colors.white : Colors.black, 0.08);

  /// Elevated surface (for elevated cards)
  Color get surfaceElevated =>
      blendColors(baseBackground, isDark ? Colors.white : Colors.black, 0.12);

  /// Border color
  Color get border => isDark
      ? Colors.white.withValues(alpha: 0.15)
      : Colors.black.withValues(alpha: 0.15);

  /// Divider color
  Color get divider => isDark
      ? Colors.white.withValues(alpha: 0.1)
      : Colors.black.withValues(alpha: 0.1);

  // Convenience aliases
  /// Background color (alias for baseBackground)
  Color get background => baseBackground;

  /// Primary color (alias for basePrimary)
  Color get primary => basePrimary;

  /// Primary button background
  Color get primaryButton => baseAccent;

  /// Primary button hover
  Color get primaryButtonHover => blendColors(baseAccent, Colors.white, 0.1);

  /// Primary button pressed
  Color get primaryButtonPressed => blendColors(baseAccent, Colors.black, 0.1);

  /// Primary button text
  Color get primaryButtonText => contrastColor(basePrimary);

  /// Secondary button background
  Color get secondaryButton => surface;

  /// Secondary button hover
  Color get secondaryButtonHover => surfaceVariant;

  /// Accent color (for highlights, links)
  Color get accent => baseAccent;

  /// Accent hover
  Color get accentHover => blendColors(baseAccent, Colors.white, 0.15);

  /// Input field background
  Color get inputBackground => surface;

  /// Input field focused border
  Color get inputFocusedBorder => baseAccent;

  /// Scrollbar color
  Color get scrollbar => isDark
      ? Colors.white.withValues(alpha: 0.3)
      : Colors.black.withValues(alpha: 0.3);

  /// Scrollbar hover color
  Color get scrollbarHover => isDark
      ? Colors.white.withValues(alpha: 0.5)
      : Colors.black.withValues(alpha: 0.5);

  /// Navigation panel background
  Color get navBackground => blendColors(baseBackground, basePrimary, 0.05);

  /// Navigation item hover
  Color get navItemHover => blendColors(navBackground, baseAccent, 0.1);

  /// Navigation item selected
  Color get navItemSelected => blendColors(navBackground, baseAccent, 0.2);

  /// Game card background
  Color get cardBackground => surface;

  /// Game card cover placeholder background (no image / loading error)
  Color get cardCoverPlaceholder => blendColors(baseBackground, isDark ? Colors.white : Colors.black, 0.10);

  /// Game card hover
  Color get cardHover => surfaceVariant;

  /// Game card selected
  Color get cardSelected => blendColors(surface, baseAccent, 0.2);

  /// Tag chip background
  Color get tagBackground => surfaceVariant;

  // ===========================================================================
  // PRE-COMPUTED LIST CARD GRADIENT COLORS (for performance)
  // ===========================================================================

  // Expando-based memoization cache. Each AppThemeData instance computes its
  // gradient/overlay values exactly once; the results stay alive as long as
  // the theme object is in use and are GC'd together with it.
  static final _gradientCache = Expando<_AppThemeCache>();

  /// Returns (and lazily computes) the cached gradient values for this theme.
  _AppThemeCache get _cachedGradients =>
      _gradientCache[this] ??= _buildGradientCache();

  /// Compute all expensive HSL/blend operations once per theme instance.
  _AppThemeCache _buildGradientCache() {
    // Pre-compute the default tag chip color (when no override is provided).
    // Mirrors the logic in GameCard._buildTagChip's else-branch.
    final baseBg = tagBackground.withValues(alpha: 1.0);
    final baseBgHsl = HSLColor.fromColor(baseBg);
    const satThreshold = 0.12;
    final tagChipDefaultColor = baseBgHsl.saturation < satThreshold ? Color.lerp(
            baseBg,_applySaturation(baseAccent, 1.05).withValues(alpha: 0.95), 0.72,)! : baseBg;

    return _AppThemeCache(
      listCardDefaultGradient: [
        baseAccent.withValues(alpha: 0.3),
        basePrimary.withValues(alpha: 0.25),
      ],
      listCardHoverGradient: [
        baseAccent.withValues(alpha: 0.55),
        basePrimary.withValues(alpha: 0.45),
      ],
      listCardSelectedGradient: [
        baseAccent.withValues(alpha: 0.85),
        basePrimary.withValues(alpha: 0.65),
      ],

      gridCardHoverOverlay: baseAccent.withValues(alpha: 0.7),
      gridCardSelectedOverlay: baseAccent.withValues(alpha: 0.7),

      tagChipDefaultColor: tagChipDefaultColor,
      gridCardSelectedGradient: LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [
          baseAccent.withValues(alpha: 0.95),
          Colors.transparent,
          Colors.transparent,
          basePrimary.withValues(alpha: 0.95),
        ],
        stops: const [0.0, 0.45, 0.55, 1.0],
      ),
      gridCardHoverGradient: LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [
          baseAccent.withValues(alpha: 0.9),
          Colors.transparent,
          Colors.transparent,
          basePrimary.withValues(alpha: 0.9),
        ],
        stops: const [0.0, 0.35, 0.65, 1.0],
      ),
    );
  }

  /// Apply saturation to a color
  Color _applySaturation(Color color, double factor) {
    final h = HSLColor.fromColor(color);
    final newS = (h.saturation * factor).clamp(0.0, 1.0);
    return h.withSaturation(newS).toColor();
  }

  /// Gradient colors for list card hover state — memoized, allocated once per theme.
  List<Color> get listCardHoverGradient =>
      _cachedGradients.listCardHoverGradient;

  /// Gradient colors for list card selected state — memoized, allocated once per theme.
  List<Color> get listCardSelectedGradient =>
      _cachedGradients.listCardSelectedGradient;

  /// Gradient colors for list card default state — memoized, allocated once per theme.
  List<Color> get listCardDefaultGradient =>
      _cachedGradients.listCardDefaultGradient;

  /// Gradient overlay color for grid card hover state — memoized.
  Color get gridCardHoverOverlay => _cachedGradients.gridCardHoverOverlay;

  /// Gradient overlay color for grid card selected state — memoized.
  Color get gridCardSelectedOverlay => _cachedGradients.gridCardSelectedOverlay;

  /// Default tag chip background color for the theme (no tag-color override).
  /// Pre-computed once per theme via HSL saturation check, same logic as
  /// GameCard._buildTagChip's else-branch.
  Color get tagChipDefaultColor => _cachedGradients.tagChipDefaultColor;

  /// Pre-computed [LinearGradient] for grid card selected overlay.
  LinearGradient get gridCardSelectedGradient =>
      _cachedGradients.gridCardSelectedGradient;

  /// Pre-computed [LinearGradient] for grid card hover overlay.
  LinearGradient get gridCardHoverGradient =>
      _cachedGradients.gridCardHoverGradient;

  /// Status colors
  Color get success => const Color(0xFF28A745);
  Color get warning => const Color(0xFFFFC107);
  Color get error => const Color(0xFFDC3545);
  Color get info => const Color(0xFF17A2B8);

  /// Used overlay color
  Color get usedOverlay => Colors.black.withValues(alpha: 0.6);

  /// Deadline badge colors
  Color get deadlineUrgent => const Color(0xFFFF4444);
  Color get deadlineSoon => const Color(0xFFFFAA00);
  Color get deadlineNormal => const Color(0xFF44AA44);

  // ===========================================================================
  // CONVERT TO FLUTTER ThemeData
  // ===========================================================================

  /// Generate Flutter ThemeData from this app theme
  ThemeData toThemeData() {
    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,

      // Colors
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: basePrimary,
        onPrimary: primaryButtonText,
        secondary: baseAccent,
        onSecondary: contrastColor(baseAccent),
        error: error,
        onError: Colors.white,
        surface: surface,
        onSurface: textPrimary,
      ),

      scaffoldBackgroundColor: baseBackground,
      canvasColor: baseBackground,
      cardColor: cardBackground,
      dividerColor: divider,

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: baseBackground,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),

      // Cards
      cardTheme: CardThemeData(
        color: cardBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
          side: BorderSide(color: border),
        ),
      ),

      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryButton,
          foregroundColor: primaryButtonText, // add shadow for the text to improve contrast
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cornerRadius),
          ),
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: controlPaddingHorizontal,
            vertical: controlPaddingVertical,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cornerRadius),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: controlPaddingHorizontal,
            vertical: controlPaddingVertical,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cornerRadius),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: controlPaddingHorizontal,
            vertical: controlPaddingVertical,
          ),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(padding: const EdgeInsets.all(6)),
      ),

      // Input fields
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: inputBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
          borderSide: BorderSide(color: border, width: 0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
          borderSide: BorderSide(color: border, width: 0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
          borderSide: BorderSide(color: inputFocusedBorder, width: 2),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: inputPaddingHorizontal,
          vertical: inputPaddingVertical,
        ),
      ),

      // Dialogs
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cornerRadius * 2),
        ),
      ),

      // Tooltips
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: surfaceElevated,
          borderRadius: BorderRadius.circular(cornerRadius),
          border: Border.all(color: border),
        ),
        textStyle: TextStyle(color: textPrimary),
      ),

      // Scrollbar
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return scrollbarHover;
          }
          return scrollbar;
        }),
        radius: Radius.circular(scrollbarRadius),
        thickness: WidgetStateProperty.all(8),
      ),

      // Chips
      chipTheme: ChipThemeData(
        backgroundColor: tagBackground,
        labelStyle: TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
        ),
      ),

      // Dropdown
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          filled: true,
          fillColor: inputBackground,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(cornerRadius),
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: inputPaddingHorizontal,
            vertical: inputPaddingVertical,
          ),
        ),
      ),

      switchTheme: SwitchThemeData(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        splashRadius: 14,
      ),

      // Text
      textTheme: TextTheme(
        displayLarge: TextStyle(color: textPrimary),
        displayMedium: TextStyle(color: textPrimary),
        displaySmall: TextStyle(color: textPrimary),
        headlineLarge: TextStyle(color: textPrimary),
        headlineMedium: TextStyle(color: textPrimary),
        headlineSmall: TextStyle(color: textPrimary),
        titleLarge: TextStyle(color: textPrimary),
        titleMedium: TextStyle(color: textPrimary),
        titleSmall: TextStyle(color: textPrimary),
        bodyLarge: TextStyle(color: textPrimary),
        bodyMedium: TextStyle(color: textPrimary),
        bodySmall: TextStyle(color: textSecondary),
        labelLarge: TextStyle(color: textPrimary),
        labelMedium: TextStyle(color: textSecondary),
        labelSmall: TextStyle(color: textHint),
      ),
    );
  }
}

/// Cache for expensive, immutable computed values of an [AppThemeData] instance.
/// Created lazily the first time a gradient getter is accessed and retained for
/// the lifetime of the theme object (via an [Expando] keyed on it).
class _AppThemeCache {
  const _AppThemeCache({
    required this.listCardHoverGradient,
    required this.listCardSelectedGradient,
    required this.listCardDefaultGradient,
    required this.gridCardHoverOverlay,
    required this.gridCardSelectedOverlay,
    required this.tagChipDefaultColor,
    required this.gridCardSelectedGradient,
    required this.gridCardHoverGradient,
  });

  final List<Color> listCardHoverGradient;
  final List<Color> listCardSelectedGradient;
  final List<Color> listCardDefaultGradient;
  final Color gridCardHoverOverlay;
  final Color gridCardSelectedOverlay;
  final Color tagChipDefaultColor;
  final LinearGradient gridCardSelectedGradient;
  final LinearGradient gridCardHoverGradient;
}

// =============================================================================
// BUILT-IN THEMES
// =============================================================================

/// Dark theme (default)
const kDarkTheme = AppThemeData(
  id: 'builtin-dark',
  name: 'Dark',
  baseBackground: Color(0xFF141414),
  basePrimary: Color(0xFF3F5485),
  baseAccent: Color(0xFF5F92FF),
  iconData: Icons.dark_mode, // Icons.dark_mode
);

/// Light theme
const kLightTheme = AppThemeData(
  id: 'builtin-light',
  name: 'Light',
  baseBackground: Color(0xFFF5F5F5),
  basePrimary: Color.fromARGB(255, 103, 151, 255),
  baseAccent: Color(0xFF8B5CF6),
  iconData: Icons.light_mode, // Icons.light_mode
);

/// Nebula theme (purple)
const kNebulaTheme = AppThemeData(
  id: 'builtin-nebula',
  name: 'Nebula',
  baseBackground: Color(0xFF0E0E29),
  basePrimary: Color(0xFF7B61FF),
  baseAccent: Color(0xFF3BF2FF),
  iconData: Icons.auto_awesome, // Icons.auto_awesome
);

/// Sunset theme (orange/warm)
const kSunsetTheme = AppThemeData(
  id: 'builtin-sunset',
  name: 'Sunset',
  baseBackground: Color(0xFF2A1208),
  basePrimary: Color(0xFFB45309),
  baseAccent: Color(0xFFF59E0B),
  iconData: Icons.wb_twilight, // Icons.wb_twilight
);

/// Ocean theme (teal/blue)
const kOceanTheme = AppThemeData(
  id: 'builtin-ocean',
  name: 'Ocean',
  baseBackground: Color(0xFF00203C), // 00203C
  basePrimary: Color(0xFF0891FF), // 0891FF
  baseAccent: Color(0xFF15FFF0), // 15FFF0
  iconData: Icons.water, // Icons.water
);

/// Forest theme (green)
const kForestTheme = AppThemeData(
  id: 'builtin-forest',
  name: 'Forest',
  baseBackground: Color(0xFF0D1F12),
  basePrimary: Color(0xFF2D5A3D),
  baseAccent: Color(0xFF4ADE80),
  iconData: Icons.forest, // Icons.forest
);

/// Royal theme (deep blue / violet)
const kRoyalTheme = AppThemeData(
  id: 'builtin-royal',
  name: 'Royal',
  baseBackground: Color(0xFF111827),
  basePrimary: Color(0xFF14B8A6),
  baseAccent: Color(0xFFF4CBA7),
  iconData: Icons.diamond, // Icons.diamond
);

/// All built-in themes
const List<AppThemeData> kBuiltInThemes = [
  kDarkTheme,
  kLightTheme,
  kNebulaTheme,
  kSunsetTheme,
  kOceanTheme,
  kForestTheme,
  kRoyalTheme,
];
