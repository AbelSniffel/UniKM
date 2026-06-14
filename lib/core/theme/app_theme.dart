/// Theme system for UniKM
/// Implements the 3 base colors → computed palette system from the Python app
library;

import 'dart:math' as math;
import 'dart:ui' show Size, lerpDouble;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import '../settings/settings_model.dart';
import '../utils/color_utils.dart';

/// App theme configuration with 3 base colors
class AppThemeData {
  const AppThemeData({
    this.id = '',
    required this.name,
    required this.baseBackground,
    required this.baseSecondary,
    required this.baseAccent,
    this.iconData,
    this.cornerRadius = 8.0,
    this.useThemeToggleRadius = false,
    this.scrollbarRadius = 8.0,
    this.inputPaddingVertical = 10.0,
    this.inputPaddingHorizontal = 12.0,
    this.progressIndicatorStrokeWidth = 3.0,
    this.navPanelOverlayStyle = NavPanelOverlayStyle.none,
  });

  final String id;
  final String name;
  final Color baseBackground;
  final Color baseSecondary;
  final Color baseAccent;
  final IconData? iconData;
  final double cornerRadius;
  final bool useThemeToggleRadius;
  final double scrollbarRadius;
  final double inputPaddingHorizontal;
  final double inputPaddingVertical;
  final double progressIndicatorStrokeWidth;
  final NavPanelOverlayStyle navPanelOverlayStyle;

  /// Get the icon for this theme
  IconData get icon => iconData ?? Icons.palette;

  /// Create theme from JSON map
  factory AppThemeData.fromJson(Map<String, dynamic> json) {
    final fallbackName = (json['name'] as String?) ?? 'Custom';
    final fallbackBackground =
        (json['base_background'] as String?) ?? '#141414';
    final fallbackSecondary = (json['base_primary'] as String?) ?? '#3F5485';
    final fallbackAccent = (json['base_accent'] as String?) ?? '#5F92FF';

    final parsedId = (json['id'] as String?)?.trim();
    final id = (parsedId != null && parsedId.isNotEmpty)
        ? parsedId
        : _legacyIdFromFields(
            name: fallbackName,
            baseBackgroundHex: fallbackBackground,
            baseSecondaryHex: fallbackSecondary,
            baseAccentHex: fallbackAccent,
          );

    return AppThemeData(
      id: id,
      name: fallbackName,
      baseBackground: parseHexColor(fallbackBackground),
      baseSecondary: parseHexColor(fallbackSecondary),
      baseAccent: parseHexColor(fallbackAccent),
      iconData: json['icon_code_point'] != null
          ? IconData(
              json['icon_code_point'] as int,
              fontFamily: 'MaterialIcons',
            )
          : null,
      cornerRadius: (json['corner_radius'] as num?)?.toDouble() ?? 8.0,
      useThemeToggleRadius: (json['use_theme_toggle_radius'] as bool?) ?? false,
      scrollbarRadius: (json['scrollbar_radius'] as num?)?.toDouble() ?? 8.0,
      navPanelOverlayStyle: NavPanelOverlayStyle.values.firstWhere(
        (style) =>
            style.name == (json['nav_panel_overlay_style'] as String? ?? ''),
        orElse: () => NavPanelOverlayStyle.none,
      ),
    );
  }

  /// Convert theme to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'base_background': colorToHex(baseBackground),
      'base_primary': colorToHex(baseSecondary),
      'base_accent': colorToHex(baseAccent),
      if (iconData != null) 'icon_code_point': iconData!.codePoint,
      'corner_radius': cornerRadius,
      'use_theme_toggle_radius': useThemeToggleRadius,
      'scrollbar_radius': scrollbarRadius,
      'nav_panel_overlay_style': navPanelOverlayStyle.name,
    };
  }

  /// Copy with new values
  AppThemeData copyWith({
    String? id,
    String? name,
    Color? baseBackground,
    Color? baseSecondary,
    Color? baseAccent,
    IconData? iconData,
    bool clearIcon = false,
    double? cornerRadius,
    bool? useThemeToggleRadius,
    double? scrollbarRadius,
    double? inputPaddingHorizontal,
    double? inputPaddingVertical,
    double? progressIndicatorStrokeWidth,
    NavPanelOverlayStyle? navPanelOverlayStyle,
  }) {
    return AppThemeData(
      id: id ?? this.id,
      name: name ?? this.name,
      baseBackground: baseBackground ?? this.baseBackground,
      baseSecondary: baseSecondary ?? this.baseSecondary,
      baseAccent: baseAccent ?? this.baseAccent,
      iconData: clearIcon ? null : (iconData ?? this.iconData),
      cornerRadius: cornerRadius ?? this.cornerRadius,
      useThemeToggleRadius: useThemeToggleRadius ?? this.useThemeToggleRadius,
      scrollbarRadius: scrollbarRadius ?? this.scrollbarRadius,
      inputPaddingHorizontal:
          inputPaddingHorizontal ?? this.inputPaddingHorizontal,
      inputPaddingVertical: inputPaddingVertical ?? this.inputPaddingVertical,
      progressIndicatorStrokeWidth:
          progressIndicatorStrokeWidth ?? this.progressIndicatorStrokeWidth,
      navPanelOverlayStyle: navPanelOverlayStyle ?? this.navPanelOverlayStyle,
    );
  }

  /// Static getter for built-in themes
  static List<AppThemeData> get builtInThemes => kBuiltInThemes;

  static String generateThemeId() => const Uuid().v4();

  static String _legacyIdFromFields({
    required String name,
    required String baseBackgroundHex,
    required String baseSecondaryHex,
    required String baseAccentHex,
  }) {
    String normalize(String value) => value.trim().toLowerCase();
    return 'legacy:${normalize(name)}:${normalize(baseBackgroundHex)}:${normalize(baseSecondaryHex)}:${normalize(baseAccentHex)}';
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
      blendColors(baseBackground, isDark ? Colors.white : Colors.black, 0.08);

  /// Surface variant (slightly different surface)
  Color get surfaceVariant =>
      blendColors(baseBackground, isDark ? Colors.white : Colors.black, 0.12);

  /// Elevated surface (for elevated cards)
  Color get surfaceElevated =>
      blendColors(baseBackground, isDark ? Colors.white : Colors.black, 0.16);

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

  /// Secondary color (alias for baseSecondary)
  Color get secondary => baseSecondary;

  /// Primary button background
  Color get primaryButton => baseAccent;

  /// Primary button hover
  Color get primaryButtonHover => blendColors(baseAccent, Colors.white, 0.1);

  /// Primary button pressed
  Color get primaryButtonPressed => blendColors(baseAccent, Colors.black, 0.1);

  /// Primary button background when disabled.
  ///
  /// Keep a visible accent tint instead of falling back to Flutter's generic
  /// grey so disabled actions still feel attached to the active theme.
  Color get primaryButtonDisabled =>
      blendColors(baseAccent, surface, isDark ? 0.72 : 0.8);

  /// Primary button text
  Color get primaryButtonText => contrastColor(baseSecondary);

  /// Primary button foreground when disabled.
  Color get primaryButtonDisabledText =>
      contrastColor(primaryButtonDisabled).withValues(alpha: 0.78);

  /// Accent color (for highlights, links)
  Color get accent => baseAccent;

  /// Accent hover
  Color get accentHover => blendColors(baseAccent, Colors.white, 0.15);

  /// Shared tab indicator with a taller silhouette and flared base.
  Decoration get tabIndicator => FlaredTabIndicator(color: accent);

  /// Input field background
  Color get inputBackground => surface.withValues(alpha: 0.0);

  /// Input field focused border
  Color get inputFocusedBorder => baseAccent;

  /// Input field hover border.
  Color get inputHoverBorder => accent.withValues(alpha: 0.8);

  /// Input field focus glow color.
  Color get inputFocusGlow => accent.withValues(alpha: isDark ? 0.34 : 0.24);

  /// Input field hover glow color.
  Color get inputHoverGlow => accent.withValues(alpha: isDark ? 0.18 : 0.12);

  /// Input field default wrap-around amount.
  double get inputBorderWrapDefault => cornerRadius * 0.20;

  /// Input field hover wrap-around amount.
  double get inputBorderWrapHover => cornerRadius * 0.42;

  /// Input field focus wrap-around amount.
  double get inputBorderWrapFocus => cornerRadius * 0.62;

  /// Scrollbar color
  Color get scrollbar => accent;

  /// Scrollbar hover color
  Color get scrollbarHover => accentHover;

  /// Scrollbar track color.
  Color get scrollbarTrack => accent.withValues(alpha: isDark ? 0.05 : 0.05);

  /// Scrollbar track hover color.
  Color get scrollbarTrackHover =>
      accent.withValues(alpha: isDark ? 0.28 : 0.22);

  /// Navigation panel background
  Color get navBackground => blendColors(baseBackground, baseAccent, 0.035);

  /// Navigation item hover
  Color get navItemHover => baseAccent.withValues(alpha: 0.30);

  /// Navigation item selected
  Color get navItemSelected => baseAccent.withValues(alpha: 0.40);

  /// Selected popup menu item background
  Color get popupMenuItemSelected => baseAccent.withValues(alpha: 0.16);

  /// Game card background
  Color get cardBackground => surface;

  /// Game card cover placeholder background (no image / loading error)
  Color get cardCoverPlaceholder =>
      blendColors(baseBackground, isDark ? Colors.white : Colors.black, 0.10);

  /// Game card hover
  Color get cardHover => surface;

  /// Game card selected
  Color get cardSelected => blendColors(surface, baseAccent, 0.2);

  /// Tag chip background
  Color get tagBackground => surface;

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
    final tagChipDefaultColor = baseBgHsl.saturation < satThreshold
        ? Color.lerp(
            baseBg,
            _applySaturation(baseAccent, 1.05).withValues(alpha: 0.95),
            0.72,
          )!
        : baseBg;

    return _AppThemeCache(
      listCardDefaultGradient: [
        baseAccent.withValues(alpha: 0.40),
        baseSecondary.withValues(alpha: 0.50),
      ],
      listCardHoverGradient: [
        baseAccent.withValues(alpha: 0.80),
        baseSecondary.withValues(alpha: 0.90),
      ],
      listCardSelectedGradient: [
        baseAccent.withValues(alpha: 1),
        baseSecondary.withValues(alpha: 1),
      ],

      tagChipDefaultColor: tagChipDefaultColor,
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

  /// Default tag chip background color for the theme (no tag-color override).
  /// Pre-computed once per theme via HSL saturation check, same logic as
  /// GameCard._buildTagChip's else-branch.
  Color get tagChipDefaultColor => _cachedGradients.tagChipDefaultColor;

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
    final inputBorder = resolveInputBorder(showTopBorder: false);

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,

      // Colors
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: baseSecondary,
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
      highlightColor: popupMenuItemSelected,

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
          foregroundColor:
              primaryButtonText, // add shadow for the text to improve contrast
          disabledBackgroundColor: primaryButtonDisabled,
          disabledForegroundColor: primaryButtonDisabledText,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cornerRadius),
          ),
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: kButtonPaddingHorizontal,
            vertical: 0,
          ),
          fixedSize: const Size.fromHeight(kElementHeight),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
            horizontal: kButtonPaddingHorizontal,
            vertical: 0,
          ),
          fixedSize: const Size.fromHeight(kElementHeight),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cornerRadius),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: kButtonPaddingHorizontal,
            vertical: 0,
          ),
          fixedSize: const Size.fromHeight(kElementHeight),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          iconSize: 26,
          padding: const EdgeInsets.all(8),
          minimumSize: const Size(kElementHeight, kElementHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cornerRadius),
          ),
        ),
      ),

      // Input fields
      inputDecorationTheme: InputDecorationTheme(
        //constraints: const BoxConstraints(maxHeight: kElementHeight),
        isDense: true,
        filled: true,
        fillColor: inputBackground,
        border: inputBorder,
        suffixIconConstraints: const BoxConstraints(
          minWidth: 42,
          minHeight: kElementHeight,
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
          color: surface,
          borderRadius: BorderRadius.circular(cornerRadius),
          border: Border.all(color: border),
        ),
        textStyle: TextStyle(color: textPrimary),
        exitDuration: Duration.zero,
      ),

      // Scrollbar
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged) ||
              states.contains(WidgetState.hovered)) {
            return scrollbarHover;
          }
          return scrollbar;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged) ||
              states.contains(WidgetState.hovered)) {
            return scrollbarTrackHover;
          }
          return scrollbarTrack;
        }),
        trackBorderColor: WidgetStateProperty.all(Colors.transparent),
        radius: Radius.circular(cornerRadius),
        thickness: WidgetStateProperty.all(10),
        minThumbLength: 44,
        mainAxisMargin: 2,
        crossAxisMargin: 2,
        thumbVisibility: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.dragged),
        ),
        trackVisibility: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.dragged) ||
              states.contains(WidgetState.hovered),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        circularTrackColor: accent.withValues(alpha: 0.15),
        linearTrackColor: surface,
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
          constraints: const BoxConstraints(maxHeight: kElementHeight),
          //isDense: false,
          filled: true,
          fillColor: inputBackground,
          border: inputBorder,
          contentPadding: EdgeInsets.symmetric(
            horizontal: inputPaddingHorizontal,
            vertical: inputPaddingVertical,
          ),
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        elevation: 12,
        menuPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
          side: BorderSide(color: border),
        ),
      ),

      switchTheme: SwitchThemeData(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        splashRadius: 14,
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: border.withValues(alpha: 0.35),
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.18),
        activeTickMarkColor: Colors.transparent,
        inactiveTickMarkColor: Colors.transparent,
        valueIndicatorColor: accent,
        valueIndicatorTextStyle: TextStyle(
          color: contrastColor(baseAccent),
          fontWeight: FontWeight.w600,
        ),
        trackHeight: kSliderTrackHeight,
        thumbShape: RoundSliderThumbShape(
          enabledThumbRadius: kSliderIndicatorInnerDiameter / 2,
          disabledThumbRadius: kSliderIndicatorInnerDiameter / 2,
        ),
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

  WidgetStateInputBorder resolveInputBorder({bool showTopBorder = false}) {
    return WidgetStateInputBorder.resolveWith(
      (states) => buildInputBorder(states, showTopBorder: showTopBorder),
    );
  }

  InputBorder buildInputBorder(
    Set<WidgetState> states, {
    bool showTopBorder = false,
  }) {
    final isFocused = states.contains(WidgetState.focused);
    final isHovered = states.contains(WidgetState.hovered);

    return BottomGlowInputBorder(
      borderRadius: BorderRadius.circular(cornerRadius),
      borderSide: BorderSide(
        color: isFocused
            ? inputFocusedBorder
            : isHovered
            ? inputHoverBorder
            : border,
        width: isFocused
            ? 2.5
            : isHovered
            ? 1.5
            : 1.0,
      ),
      glowColor: isFocused
          ? inputFocusGlow
          : isHovered
          ? inputHoverGlow
          : Colors.transparent,
      glowExtent: isFocused
          ? 18.0
          : isHovered
          ? 12.0
          : 0.0,
      wrapExtent: isFocused
          ? inputBorderWrapFocus
          : isHovered
          ? inputBorderWrapHover
          : inputBorderWrapDefault,
      showTopBorder: showTopBorder,
    );
  }
}

class BottomGlowInputBorder extends OutlineInputBorder {
  const BottomGlowInputBorder({
    super.borderSide = const BorderSide(),
    super.borderRadius = const BorderRadius.all(Radius.circular(4.0)),
    super.gapPadding = 4.0,
    required this.glowColor,
    this.glowExtent = 0.0,
    this.wrapExtent = 0.0,
    this.showTopBorder = false,
  });

  final Color glowColor;
  final double glowExtent;
  final double wrapExtent;
  final bool showTopBorder;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.only(
    top: showTopBorder ? borderSide.width : 0.0,
    bottom: borderSide.width,
  );

  @override
  BottomGlowInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
    Color? glowColor,
    double? glowExtent,
    double? wrapExtent,
    bool? showTopBorder,
  }) {
    return BottomGlowInputBorder(
      borderSide: borderSide ?? this.borderSide,
      borderRadius: borderRadius ?? this.borderRadius,
      gapPadding: gapPadding ?? this.gapPadding,
      glowColor: glowColor ?? this.glowColor,
      glowExtent: glowExtent ?? this.glowExtent,
      wrapExtent: wrapExtent ?? this.wrapExtent,
      showTopBorder: showTopBorder ?? this.showTopBorder,
    );
  }

  @override
  BottomGlowInputBorder scale(double t) {
    return BottomGlowInputBorder(
      borderSide: borderSide.scale(t),
      borderRadius: borderRadius * t,
      gapPadding: gapPadding * t,
      glowColor: glowColor.withValues(alpha: glowColor.a * t),
      glowExtent: glowExtent * t,
      wrapExtent: wrapExtent * t,
      showTopBorder: showTopBorder,
    );
  }

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is BottomGlowInputBorder) {
      return BottomGlowInputBorder(
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
        gapPadding: lerpDouble(a.gapPadding, gapPadding, t)!,
        glowColor: Color.lerp(a.glowColor, glowColor, t)!,
        glowExtent: lerpDouble(a.glowExtent, glowExtent, t)!,
        wrapExtent: lerpDouble(a.wrapExtent, wrapExtent, t)!,
        showTopBorder: t < 0.5 ? a.showTopBorder : showTopBorder,
      );
    }
    if (a is OutlineInputBorder) {
      return BottomGlowInputBorder(
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
        gapPadding: lerpDouble(a.gapPadding, gapPadding, t)!,
        glowColor: Color.lerp(Colors.transparent, glowColor, t)!,
        glowExtent: lerpDouble(0.0, glowExtent, t)!,
        wrapExtent: lerpDouble(0.0, wrapExtent, t)!,
        showTopBorder: showTopBorder,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is BottomGlowInputBorder) {
      return BottomGlowInputBorder(
        borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
        borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
        gapPadding: lerpDouble(gapPadding, b.gapPadding, t)!,
        glowColor: Color.lerp(glowColor, b.glowColor, t)!,
        glowExtent: lerpDouble(glowExtent, b.glowExtent, t)!,
        wrapExtent: lerpDouble(wrapExtent, b.wrapExtent, t)!,
        showTopBorder: t < 0.5 ? showTopBorder : b.showTopBorder,
      );
    }
    if (b is OutlineInputBorder) {
      return BottomGlowInputBorder(
        borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
        borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
        gapPadding: lerpDouble(gapPadding, b.gapPadding, t)!,
        glowColor: Color.lerp(glowColor, Colors.transparent, t)!,
        glowExtent: lerpDouble(glowExtent, 0.0, t)!,
        wrapExtent: lerpDouble(wrapExtent, 0.0, t)!,
        showTopBorder: showTopBorder,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    final resolvedRadius = borderRadius.resolve(textDirection);
    final outerRRect = resolvedRadius.toRRect(rect);
    final effectiveWrapExtent = math.max(wrapExtent, borderSide.width);

    final borderPaint = borderSide.toPaint();
    final strokeInset = borderSide.width / 2;
    final strokeRRect = outerRRect.deflate(strokeInset);
    final clipTop = rect.bottom - effectiveWrapExtent - borderSide.width;

    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        rect.left - borderSide.width,
        clipTop,
        rect.right + borderSide.width,
        rect.bottom + borderSide.width,
      ),
    );
    canvas.drawRRect(strokeRRect, borderPaint);
    canvas.restore();

    if (showTopBorder) {
      final clipBottom = rect.top + effectiveWrapExtent + borderSide.width;
      canvas.save();
      canvas.clipRect(
        Rect.fromLTRB(
          rect.left - borderSide.width,
          rect.top - borderSide.width,
          rect.right + borderSide.width,
          clipBottom,
        ),
      );
      canvas.drawRRect(strokeRRect, borderPaint);
      canvas.restore();
    }

    if (glowExtent > 0.0 && glowColor.a > 0.0) {
      final clampedGlowExtent = math.min(glowExtent, rect.height);
      final glowRect = Rect.fromLTRB(
        rect.left,
        rect.bottom - clampedGlowExtent,
        rect.right,
        rect.bottom,
      );
      final glowPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            glowColor.withValues(alpha: 0.0),
            glowColor.withValues(alpha: 0.15),
            glowColor.withValues(alpha: 0.25),
          ],
          stops: const [0.0, 0.6, 1.0],
        ).createShader(glowRect)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.clipRRect(outerRRect);
      canvas.drawRect(glowRect, glowPaint);

      if (showTopBorder) {
        final topGlowRect = Rect.fromLTRB(
          rect.left,
          rect.top,
          rect.right,
          rect.top + clampedGlowExtent,
        );
        final topGlowPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              glowColor.withValues(alpha: 0.25),
              glowColor.withValues(alpha: 0.15),
              glowColor.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.45, 1.0],
          ).createShader(topGlowRect)
          ..style = PaintingStyle.fill;
        canvas.drawRect(topGlowRect, topGlowPaint);
      }

      canvas.restore();
    }
  }
}

/// Custom tab indicator with a slim top and wider, flared base.
class FlaredTabIndicator extends Decoration {
  const FlaredTabIndicator({
    required this.color,
    this.height = 5,
    this.topWidthFactor = 0.4,
    this.baseWidthFactor = 0.5,
    this.bottomInset = 0,
  });

  final Color color;
  final double height;
  final double topWidthFactor;
  final double baseWidthFactor;
  final double bottomInset;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    return _FlaredTabIndicatorPainter(this);
  }
}

class _FlaredTabIndicatorPainter extends BoxPainter {
  _FlaredTabIndicatorPainter(this.decoration);

  final FlaredTabIndicator decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;

    final rect = offset & size;
    final maxShapeWidth = (rect.width - 10).clamp(36.0, 112.0);
    final baseWidth = maxShapeWidth * decoration.baseWidthFactor;
    final topWidth = maxShapeWidth * decoration.topWidthFactor;
    final flareDx = (baseWidth - topWidth) / 2;

    final bottom = rect.bottom - decoration.bottomInset;
    final top = bottom - decoration.height;
    final centerX = rect.center.dx;

    final topLeft = Offset(centerX - topWidth / 2, top);
    final topRight = Offset(centerX + topWidth / 2, top);
    final bottomRight = Offset(centerX + baseWidth / 2, bottom - 1);
    final bottomLeft = Offset(centerX - baseWidth / 2, bottom - 1);

    final path = Path()
      ..moveTo(topLeft.dx, topLeft.dy)
      ..lineTo(topRight.dx, topRight.dy)
      ..quadraticBezierTo(
        topRight.dx + flareDx * 0.9,
        top + decoration.height * 0.52,
        bottomRight.dx,
        bottomRight.dy,
      )
      ..lineTo(bottomLeft.dx, bottomLeft.dy)
      ..quadraticBezierTo(
        topLeft.dx - flareDx * 0.9,
        top + decoration.height * 0.52,
        topLeft.dx,
        topLeft.dy,
      )
      ..close();

    final fillPaint = Paint()
      ..color = decoration.color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(path, fillPaint);

    final rimPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
    canvas.drawLine(topLeft, topRight, rimPaint);
  }
}

enum AppNavigationButtonVariant { navigation, settingsSection }

class AppNavigationButton extends StatefulWidget {
  const AppNavigationButton({
    super.key,
    required this.theme,
    required this.isSelected,
    required this.isEnabled,
    required this.isHorizontal,
    required this.onTap,
    this.iconData,
    this.labelText,
    this.iconBuilder,
    this.tooltipMessage,
    this.padding,
    this.alignment = Alignment.center,
    this.borderRadiusMultiplier = 1.25,
    this.selectedBackgroundColor,
    this.hoverBackgroundColor,
    this.disabledBackgroundColor,
    this.minWidth = 40,
    this.minHeight = 26,
    this.horizontalSpacing = 6,
    this.verticalSpacing = 0,
    this.horizontalMainAxisSize = MainAxisSize.min,
    this.horizontalMainAxisAlignment = MainAxisAlignment.center,
    this.duration = const Duration(milliseconds: 1000),
    this.variant = AppNavigationButtonVariant.navigation,
    this.iconSize = kIconSize,
    this.labelVisible = true,
    this.reserveLabelSpace = true,
    this.labelFadeDuration = Duration.zero,
    this.labelFadeCurve = Curves.easeOut,
  });

  final AppThemeData theme;
  final bool isSelected;
  final bool isEnabled;
  final bool isHorizontal;
  final VoidCallback? onTap;
  final IconData? iconData;
  final String? labelText;
  final Widget Function(BuildContext context, Color color, double size)?
  iconBuilder;
  final String? tooltipMessage;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;
  final double borderRadiusMultiplier;
  final Color? selectedBackgroundColor;
  final Color? hoverBackgroundColor;
  final Color? disabledBackgroundColor;
  final double minWidth;
  final double minHeight;
  final double horizontalSpacing;
  final double verticalSpacing;
  final MainAxisSize horizontalMainAxisSize;
  final MainAxisAlignment horizontalMainAxisAlignment;
  final Duration duration;
  final AppNavigationButtonVariant variant;
  final double iconSize;
  final bool labelVisible;
  final bool reserveLabelSpace;
  final Duration labelFadeDuration;
  final Curve labelFadeCurve;

  @override
  State<AppNavigationButton> createState() => _AppNavigationButtonState();
}

class _AppNavigationButtonState extends State<AppNavigationButton>
    with TickerProviderStateMixin {
  static const double _hoverIconBoost = 0.2;

  late final AnimationController _hoverController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
    reverseDuration: const Duration(milliseconds: 100),
  );
  late final AnimationController _selectionController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
    reverseDuration: const Duration(milliseconds: 100),
    value: widget.isSelected ? 1.0 : 0.0,
  );
  late final AnimationController _labelVisibilityController =
      AnimationController(
        vsync: this,
        duration: widget.labelFadeDuration,
        value: widget.labelVisible ? 1.0 : 0.0,
      );

  @override
  void didUpdateWidget(covariant AppNavigationButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSelected != widget.isSelected) {
      if (widget.isSelected) {
        _selectionController.forward();
      } else {
        _selectionController.reverse();
      }
    }
    if (oldWidget.isEnabled && !widget.isEnabled) {
      _hoverController.reverse();
    }
    if (oldWidget.labelFadeDuration != widget.labelFadeDuration) {
      _labelVisibilityController.duration = widget.labelFadeDuration;
    }
    if (oldWidget.labelVisible != widget.labelVisible ||
        oldWidget.labelFadeDuration != widget.labelFadeDuration) {
      if (widget.labelFadeDuration == Duration.zero) {
        _labelVisibilityController.value = widget.labelVisible ? 1.0 : 0.0;
      } else if (widget.labelVisible) {
        _labelVisibilityController.forward();
      } else {
        _labelVisibilityController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _hoverController.dispose();
    _selectionController.dispose();
    _labelVisibilityController.dispose();
    super.dispose();
  }

  Color _iconColor(double selectionT) {
    if (!widget.isEnabled) {
      return widget.theme.textSecondary.withValues(alpha: 0.5);
    }
    return Color.lerp(
          widget.theme.textSecondary,
          widget.theme.accent,
          selectionT,
        ) ??
        widget.theme.textSecondary;
  }

  TextStyle _labelStyle(double selectionT) {
    if (!widget.isEnabled) {
      return TextStyle(
        color: widget.theme.textSecondary.withValues(alpha: 0.5),
        fontSize: 14,
      );
    }
    return TextStyle.lerp(
          TextStyle(color: widget.theme.textSecondary, fontSize: 14),
          TextStyle(color: widget.theme.textPrimary, fontSize: 14),
          selectionT,
        ) ??
        TextStyle(color: widget.theme.textSecondary, fontSize: 14);
  }

  double _labelVisibilityT() {
    if (widget.labelText == null || !widget.reserveLabelSpace) {
      return widget.labelVisible ? 1.0 : 0.0;
    }
    if (widget.labelFadeDuration == Duration.zero) {
      return widget.labelVisible ? 1.0 : 0.0;
    }
    return widget.labelFadeCurve
        .transform(_labelVisibilityController.value)
        .clamp(0.0, 1.0);
  }

  Widget? _buildIcon({required Color iconColor, required double iconScale}) {
    Widget? icon;
    if (widget.iconBuilder != null) {
      icon = widget.iconBuilder!(context, iconColor, widget.iconSize);
    } else {
      final iconData = widget.iconData;
      if (iconData == null) {
        return null;
      }
      icon = Icon(iconData, color: iconColor, size: widget.iconSize);
    }
    return Transform.scale(scale: iconScale, child: icon);
  }

  Widget? _buildLabel({required TextStyle labelStyle}) {
    final labelText = widget.labelText;
    if (labelText == null || !widget.reserveLabelSpace) {
      return null;
    }

    final label = Text(
      labelText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: labelStyle,
    );

    if (widget.labelFadeDuration == Duration.zero) {
      return widget.labelVisible ? label : null;
    }

    final clampedFactor = _labelVisibilityT();

    return IgnorePointer(
      ignoring: clampedFactor == 0,
      child: ClipRect(
        child: Align(
          alignment: widget.isHorizontal
              ? Alignment.centerLeft
              : Alignment.topCenter,
          widthFactor: widget.isHorizontal ? clampedFactor : 1,
          heightFactor: widget.isHorizontal ? 1 : clampedFactor,
          child: Opacity(opacity: clampedFactor, child: label),
        ),
      ),
    );
  }

  Widget _buildContent({
    required Color iconColor,
    required TextStyle labelStyle,
    required double iconScale,
    required double labelVisibilityT,
  }) {
    final icon = _buildIcon(iconColor: iconColor, iconScale: iconScale);
    final label = _buildLabel(labelStyle: labelStyle);
    final iconChildren = icon == null ? null : <Widget>[icon];
    final horizontalLabel = label == null
        ? null
        : Padding(
            padding: EdgeInsets.only(
              left: icon == null
                  ? 0
                  : widget.horizontalSpacing * labelVisibilityT,
            ),
            child: label,
          );
    final horizontalLabelChildren = label == null
        ? null
        : widget.horizontalMainAxisSize == MainAxisSize.max
        ? <Widget>[Flexible(fit: FlexFit.loose, child: horizontalLabel!)]
        : <Widget>[horizontalLabel!];
    final verticalLabelChildren = label == null
        ? null
        : <Widget>[
            Padding(
              padding: EdgeInsets.only(
                top: icon == null
                    ? 0
                    : widget.verticalSpacing * labelVisibilityT,
              ),
              child: label,
            ),
          ];

    if (widget.isHorizontal) {
      return Row(
        mainAxisSize: widget.horizontalMainAxisSize,
        mainAxisAlignment: widget.horizontalMainAxisAlignment,
        children: [...?iconChildren, ...?horizontalLabelChildren],
      );
    } else {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [...?iconChildren, ...?verticalLabelChildren],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(
      widget.theme.cornerRadius * widget.borderRadiusMultiplier,
    );

    final button = AnimatedBuilder(
      animation: Listenable.merge([
        _hoverController,
        _selectionController,
        _labelVisibilityController,
      ]),
      builder: (context, child) {
        final selectionT = Curves.linear.transform(_selectionController.value);
        final hoverT = Curves.linear.transform(_hoverController.value);
        final labelVisibilityT = _labelVisibilityT();
        final effectivePadding =
            widget.padding ??
            EdgeInsetsGeometry.lerp(
              const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              EdgeInsets.symmetric(
                horizontal: widget.labelText == null ? 6 : 12,
                vertical: 6,
              ),
              labelVisibilityT,
            )!;
        final backgroundColor = !widget.isEnabled
            ? (widget.disabledBackgroundColor ?? Colors.transparent)
            : Color.lerp(
                    Color.lerp(
                      Colors.transparent,
                      widget.hoverBackgroundColor ?? widget.theme.navItemHover,
                      hoverT,
                    ),
                    widget.selectedBackgroundColor ??
                        widget.theme.navItemSelected,
                    selectionT,
                  ) ??
                  Colors.transparent;
        final iconColor = _iconColor(selectionT);
        final labelStyle = _labelStyle(selectionT);
        final iconScale = (1 + (math.max(selectionT, hoverT) * _hoverIconBoost))
            .clamp(1.0, 1.20);

        return MouseRegion(
          onEnter: (_) => _hoverController.forward(),
          onExit: (_) => _hoverController.reverse(),
          child: Material(
            color: backgroundColor,
            animationDuration: widget.duration,
            borderRadius: borderRadius,
            child: InkWell(
              onTap: widget.isEnabled ? widget.onTap : null,
              borderRadius: borderRadius,
              splashColor: widget.theme.navItemHover,
              highlightColor: widget.theme.navItemSelected,
              hoverColor: widget.theme.navItemHover,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: widget.minWidth,
                  minHeight: widget.minHeight,
                ),
                child: Padding(
                  padding: effectivePadding,
                  child: Align(
                    alignment: widget.alignment,
                    child: _buildContent(
                      iconColor: iconColor,
                      labelStyle: labelStyle,
                      iconScale: iconScale,
                      labelVisibilityT: labelVisibilityT,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    final tooltipMessage = widget.tooltipMessage;
    if (tooltipMessage == null || tooltipMessage.isEmpty) {
      return button;
    }

    return Tooltip(message: tooltipMessage, child: button);
  }
}

class AppLinearProgressBar extends StatelessWidget {
  const AppLinearProgressBar({
    super.key,
    required this.theme,
    required this.value,
    this.label,
    this.minHeight = 26,
    this.progressColor,
    this.trackColor,
    this.borderRadius,
    this.labelStyle,
  });

  final AppThemeData theme;
  final double? value;
  final String? label;
  final double minHeight;
  final Color? progressColor;
  final Color? trackColor;
  final BorderRadius? borderRadius;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final barRadius = BorderRadius.circular(theme.cornerRadius);
    final fillColor = progressColor ?? theme.accent;
    final backgroundColor = trackColor ?? theme.accent.withValues(alpha: 0.35);

    return ClipRRect(
      borderRadius: barRadius,
      child: Stack(
        alignment: Alignment.center,
        children: [
          LinearProgressIndicator(
            value: value,
            minHeight: minHeight,
            backgroundColor: backgroundColor,
            valueColor: AlwaysStoppedAnimation(fillColor),
          ),
          if (label != null)
            IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      labelStyle ??
                      TextStyle(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                ),
              ),
            ),
        ],
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
    required this.tagChipDefaultColor,
  });

  final List<Color> listCardHoverGradient;
  final List<Color> listCardSelectedGradient;
  final List<Color> listCardDefaultGradient;
  final Color tagChipDefaultColor;
}

// =============================================================================
// BUILT-IN THEMES
// =============================================================================

/// Dark theme (default)
const kDarkTheme = AppThemeData(
  id: 'builtin-dark',
  name: 'Dark',
  baseBackground: Color(0xFF000000),
  baseSecondary: Color(0xFF965EED),
  baseAccent: Color(0xFFFF8964),
  iconData: Icons.dark_mode, // Icons.dark_mode
);

/// Light theme
const kLightTheme = AppThemeData(
  id: 'builtin-light',
  name: 'Light',
  baseBackground: Color(0xFFF5F5F5),
  baseSecondary: Color(0xFF6797FF),
  baseAccent: Color(0xFF8B5CF6),
  iconData: Icons.light_mode, // Icons.light_mode
);

/// Nebula theme (purple)
const kNebulaTheme = AppThemeData(
  id: 'builtin-nebula',
  name: 'Nebula',
  baseBackground: Color(0xFF0E0E29),
  baseSecondary: Color(0xFF7B61FF),
  baseAccent: Color(0xFF3BF2FF),
  iconData: Icons.auto_awesome, // Icons.auto_awesome
);

/// Sunset theme (orange/warm)
const kSunsetTheme = AppThemeData(
  id: 'builtin-sunset',
  name: 'Sunset',
  baseBackground: Color.fromARGB(255, 64, 28, 39), // convert this value 401C27 to ARGB
  baseSecondary: Color.fromARGB(255, 184, 55, 20), // convert this value B83714 to ARGB
  baseAccent: Color.fromARGB(255, 244, 164, 97), // convert this value F4A461 to ARGB
  iconData: Icons.wb_twilight, // Icons.wb_twilight
);

/// Ocean theme (teal/blue)
const kOceanTheme = AppThemeData(
  id: 'builtin-ocean',
  name: 'Ocean',
  baseBackground: Color(0xFF00203C), // 00203C
  baseSecondary: Color(0xFF0891FF), // 0891FF
  baseAccent: Color(0xFF15FFF0), // 15FFF0
  iconData: Icons.water, // Icons.water
);

/// Forest theme (green)
const kForestTheme = AppThemeData(
  id: 'builtin-forest',
  name: 'Forest',
  baseBackground: Color(0xFF0D1F12),
  baseSecondary: Color.fromARGB(255, 31, 179, 50),
  baseAccent: Color(0xFF4ADE80),
  iconData: Icons.forest, // Icons.forest
);

/// Royal theme (deep blue / violet)
const kRoyalTheme = AppThemeData(
  id: 'builtin-royal',
  name: 'Royal',
  baseBackground: Color(0xFF111827),
  baseSecondary: Color(0xFF14B8A6),
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
