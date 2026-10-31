/// Theme system for UniKM
/// Implements the 3 base colors → computed palette system from the Python app
library;

import 'dart:math' as math;
import 'dart:ui' show Size, lerpDouble;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import 'theme_icons.dart';
import 'app_slider_theme.dart';
import 'button_group_shape.dart';
import 'button_depth.dart';
import 'button_notification_pulse.dart';
import 'package:flutter/foundation.dart';
import '../settings/settings_model.dart';
import '../utils/color_utils.dart';

/// App theme configuration with 3 base colors
class AppThemeData extends ThemeExtension<AppThemeData> {
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

  /// Compact info-style actions, with 3px of padding around their icons.
  /// Leave width flexible so text actions can also share this style.
  ButtonStyle get compactIconButtonStyle => IconButton.styleFrom(
    iconSize: 26,
    minimumSize: const Size.square(42),
    padding: const EdgeInsets.all(3),
    visualDensity: VisualDensity.compact,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(cornerRadius),
    ),
  );

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
          ? themeIconFromCodePoint(json['icon_code_point'] as int)
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
  Map<String, dynamic> toJson() => {
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

  /// Copy with new values
  @override
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
  }) => AppThemeData(
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

  @override
  AppThemeData lerp(covariant AppThemeData? other, double t) {
    if (other == null) return this;
    final discrete = t < 0.5 ? this : other;
    return discrete.copyWith(
      baseBackground: Color.lerp(baseBackground, other.baseBackground, t),
      baseSecondary: Color.lerp(baseSecondary, other.baseSecondary, t),
      baseAccent: Color.lerp(baseAccent, other.baseAccent, t),
      cornerRadius: lerpDouble(cornerRadius, other.cornerRadius, t),
      scrollbarRadius: lerpDouble(scrollbarRadius, other.scrollbarRadius, t),
      inputPaddingHorizontal: lerpDouble(
        inputPaddingHorizontal,
        other.inputPaddingHorizontal,
        t,
      ),
      inputPaddingVertical: lerpDouble(
        inputPaddingVertical,
        other.inputPaddingVertical,
        t,
      ),
      progressIndicatorStrokeWidth: lerpDouble(
        progressIndicatorStrokeWidth,
        other.progressIndicatorStrokeWidth,
        t,
      ),
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
  Color get textSecondary => textPrimary.withValues(alpha: 0.7);

  /// Hint/disabled text color
  Color get textHint => textPrimary.withValues(alpha: 0.5);

  /// Surface color (cards, dialogs)
  Color get surface => blendColors(baseBackground, textPrimary, 0.08);

  /// Border color
  Color get border => textPrimary.withValues(alpha: 0.15);

  /// Divider color
  Color get divider => textPrimary.withValues(alpha: 0.1);

  // Convenience aliases
  /// Background color (alias for baseBackground)
  Color get background => baseBackground;

  /// Secondary color (alias for baseSecondary)
  Color get secondary => baseSecondary;

  /// Primary button background
  Color get primaryButton => tabSelected;

  /// Primary button background when disabled.
  ///
  /// A faint fill makes disabled actions distinct from ready buttons.
  Color get primaryButtonDisabled => primaryButton.withValues(alpha: 0.18);

  /// Text and icons on [primaryButton] (tabs, elevated buttons, accent
  /// fills): black or white, whichever reads on that fill, so light accents
  /// in custom themes stay legible.
  Color get primaryButtonText => contrastColor(primaryButton);

  /// Text and icons on [secondary] (and [error]) fills.
  Color get onSecondaryText => contrastColor(baseSecondary);

  /// Primary button foreground when disabled.
  Color get primaryButtonDisabledText => textSecondary.withValues(alpha: 0.5);

  /// Accent color (for highlights, links)
  Color get accent => baseAccent;

  /// Accent hover
  Color get accentHover => blendColors(baseAccent, Colors.white, 0.15);

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

  /// Selected-card overlay shared by game cards and preview cards: a
  /// secondary tint of [fillAlpha] inside an accent border, faded in by [t].
  BoxDecoration selectionOverlayDecoration(
    double t, {
    double fillAlpha = 0.55,
  }) => BoxDecoration(
    color: secondary.withValues(alpha: fillAlpha * t),
    border: Border.all(color: accent.withValues(alpha: t), width: 3),
    borderRadius: BorderRadius.circular(cornerRadius),
  );

  /// Scrollbar color
  Color get scrollbar => accent;

  /// Scrollbar hover color
  Color get scrollbarHover => accentHover;

  /// Scrollbar track color.
  Color get scrollbarTrack => accent.withValues(alpha: 0.05);

  /// Scrollbar track hover color.
  Color get scrollbarTrackHover =>
      accent.withValues(alpha: isDark ? 0.28 : 0.22);

  /// Navigation panel background
  Color get navBackground => blendColors(baseBackground, baseAccent, 0.035);

  /// Navigation groups' tint over their panel, flattened to an opaque fill.
  /// This can cover a tinted section header without mixing with its color.
  Color get buttonGroupBackground => Color.alphaBlend(
    accent.withValues(alpha: 0.20),
    navBackground.withValues(alpha: 1),
  );

  /// Navigation item hover
  Color get navItemHover => baseAccent.withValues(alpha: 0.30);

  /// Navigation item selected
  Color get navItemSelected => baseAccent.withValues(alpha: 0.40);

  /// Shared active fill for tabs and elevated buttons.
  Color get tabSelected => Color.alphaBlend(
    baseAccent.withValues(alpha: 0.90),
    buttonGroupBackground,
  );

  /// Selected popup menu item background
  Color get popupMenuItemSelected => baseAccent.withValues(alpha: 0.16);

  /// Game card background
  Color get cardBackground => surface;

  /// Game card cover placeholder background (no image / loading error)
  Color get cardCoverPlaceholder =>
      blendColors(baseBackground, textPrimary, 0.10);

  // ===========================================================================
  // PRE-COMPUTED LIST CARD GRADIENT COLORS (for performance)
  // ===========================================================================

  // Expando-based memoization cache. Each AppThemeData instance computes its
  // gradient/overlay values exactly once; the results stay alive as long as
  // the theme object is in use and are GC'd together with it.
  static final _gradientCache =
      Expando<({List<Color> idle, List<Color> hover, List<Color> selected})>();

  /// Returns (and lazily computes) the cached gradient values for this theme.
  ({List<Color> idle, List<Color> hover, List<Color> selected})
  get _cachedGradients => _gradientCache[this] ??= (
    idle: [
      baseAccent.withValues(alpha: 0.40),
      baseSecondary.withValues(alpha: 0.50),
    ],
    hover: [
      baseAccent.withValues(alpha: 0.80),
      baseSecondary.withValues(alpha: 0.90),
    ],
    selected: [
      baseAccent.withValues(alpha: 1),
      baseSecondary.withValues(alpha: 1),
    ],
  );

  /// Gradient colors for list card hover state — memoized, allocated once per theme.
  List<Color> get listCardHoverGradient => _cachedGradients.hover;

  /// Gradient colors for list card selected state — memoized, allocated once per theme.
  List<Color> get listCardSelectedGradient => _cachedGradients.selected;

  /// Gradient colors for list card default state — memoized, allocated once per theme.
  List<Color> get listCardDefaultGradient => _cachedGradients.idle;

  /// Status colors
  Color get success => const Color(0xFF28A745);
  Color get warning => const Color(0xFFFFC107);
  Color get error => secondary;
  Color get info => const Color(0xFF17A2B8);

  /// Used overlays become softer as the live theme background gets lighter.
  Color get usedOverlay => Colors.black.withValues(
    alpha: 0.20 + 0.46 * (1 - baseBackground.computeLuminance()),
  );

  /// Cover-only grid cards need a stronger tint on light backgrounds.
  Color get gridUsedOverlay => Colors.black.withValues(
    alpha: 0.68 + 0.18 * (1 - baseBackground.computeLuminance()),
  );
  Color get slimUsedOverlay => Colors.black.withValues(
    alpha: 0.05 + 0.13 * (1 - baseBackground.computeLuminance()),
  );

  /// Deadline badge colors
  Color get deadlineUrgent => secondary;
  Color get deadlineSoon => Color.lerp(accent, secondary, 0.5)!;
  Color get deadlineNormal => accent;

  // ===========================================================================
  // CONVERT TO FLUTTER ThemeData
  // ===========================================================================

  /// Generate Flutter ThemeData from this app theme
  ThemeData toThemeData() {
    final inputBorder = resolveInputBorder(showTopBorder: false);
    final touch =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final density = touch ? VisualDensity.standard : VisualDensity.compact;
    final targetSize = touch
        ? MaterialTapTargetSize.padded
        : MaterialTapTargetSize.shrinkWrap;
    final controlHeight = touch ? 48.0 : kElementHeight;
    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(cornerRadius),
    );
    bool active(Set<WidgetState> states) =>
        states.contains(WidgetState.dragged) ||
        states.contains(WidgetState.hovered);

    return ThemeData(
      useMaterial3: true,
      extensions: <ThemeExtension<dynamic>>[this],
      visualDensity: density,
      materialTapTargetSize: targetSize,
      brightness: isDark ? Brightness.dark : Brightness.light,

      // Colors
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: baseSecondary,
        onPrimary: onSecondaryText,
        secondary: baseAccent,
        onSecondary: contrastColor(baseAccent),
        error: error,
        onError: onSecondaryText,
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
        shape: rounded,
      ),

      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: withButtonDepth(
          ElevatedButton.styleFrom(
            backgroundColor: primaryButton,
            foregroundColor:
                primaryButtonText, // add shadow for the text to improve contrast
            disabledBackgroundColor: primaryButtonDisabled,
            disabledForegroundColor: primaryButtonDisabledText,
            shape: rounded,
            elevation: 0,
            padding: const EdgeInsets.symmetric(
              horizontal: kButtonPaddingHorizontal,
            ),
            minimumSize: Size(0, controlHeight),
            visualDensity: density,
            tapTargetSize: targetSize,
          ),
          outlined: false,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: withButtonDepth(
          OutlinedButton.styleFrom(
            foregroundColor: textPrimary,
            side: BorderSide(color: border),
            shape: rounded,
            padding: const EdgeInsets.symmetric(
              horizontal: kButtonPaddingHorizontal,
            ),
            minimumSize: Size(0, controlHeight),
            visualDensity: density,
            tapTargetSize: targetSize,
          ),
          outlined: true,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          shape: rounded,
          padding: const EdgeInsets.symmetric(
            horizontal: kTextButtonPaddingHorizontal,
          ),
          minimumSize: Size(0, controlHeight),
          visualDensity: density,
          tapTargetSize: targetSize,
        ),
      ),

      iconButtonTheme: IconButtonThemeData(style: compactIconButtonStyle),

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
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => active(states) ? scrollbarHover : scrollbar,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => active(states) ? scrollbarTrackHover : scrollbarTrack,
        ),
        trackBorderColor: WidgetStateProperty.all(Colors.transparent),
        radius: Radius.circular(cornerRadius),
        thickness: WidgetStateProperty.all(10),
        minThumbLength: 44,
        mainAxisMargin: 2,
        crossAxisMargin: 2,
        thumbVisibility: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.dragged),
        ),
        trackVisibility: WidgetStateProperty.resolveWith(active),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        circularTrackColor: accent.withValues(alpha: 0.15),
        linearTrackColor: surface,
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

      sliderTheme: buildAppSliderTheme(
        accent: accent,
        disabledColor: textSecondary,
        indicatorTextColor: contrastColor(baseAccent),
        cornerRadius: cornerRadius,
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

  WidgetStateInputBorder resolveInputBorder({bool showTopBorder = false}) =>
      WidgetStateInputBorder.resolveWith(
        (states) => buildInputBorder(states, showTopBorder: showTopBorder),
      );

  InputBorder buildInputBorder(
    Set<WidgetState> states, {
    bool showTopBorder = false,
  }) {
    final isFocused = states.contains(WidgetState.focused);
    final (color, width, glowColor, glowExtent, wrapExtent) = isFocused
        ? (inputFocusedBorder, 2.5, inputFocusGlow, 18.0, inputBorderWrapFocus)
        : states.contains(WidgetState.hovered)
        ? (inputHoverBorder, 1.5, inputHoverGlow, 12.0, inputBorderWrapHover)
        : (border, 1.0, Colors.transparent, 0.0, inputBorderWrapDefault);

    return BottomGlowInputBorder(
      borderRadius: BorderRadius.circular(cornerRadius),
      borderSide: BorderSide(color: color, width: width),
      glowColor: glowColor,
      glowExtent: glowExtent,
      wrapExtent: wrapExtent,
      showTopBorder: showTopBorder,
      connection: showTopBorder && isFocused ? 1.0 : 0.0,
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
    this.connection = 0.0,
  });

  final Color glowColor;
  final double glowExtent;
  final double wrapExtent;
  final bool showTopBorder;

  /// Focus joins the two growing edges, including in tall multiline fields.
  final double connection;

  @override
  bool operator ==(Object other) =>
      other is BottomGlowInputBorder &&
      other.borderSide == borderSide &&
      other.borderRadius == borderRadius &&
      other.gapPadding == gapPadding &&
      other.glowColor == glowColor &&
      other.glowExtent == glowExtent &&
      other.wrapExtent == wrapExtent &&
      other.showTopBorder == showTopBorder &&
      other.connection == connection;

  @override
  int get hashCode => Object.hash(
    borderSide,
    borderRadius,
    gapPadding,
    glowColor,
    glowExtent,
    wrapExtent,
    showTopBorder,
    connection,
  );

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
    double? connection,
  }) => BottomGlowInputBorder(
    borderSide: borderSide ?? this.borderSide,
    borderRadius: borderRadius ?? this.borderRadius,
    gapPadding: gapPadding ?? this.gapPadding,
    glowColor: glowColor ?? this.glowColor,
    glowExtent: glowExtent ?? this.glowExtent,
    wrapExtent: wrapExtent ?? this.wrapExtent,
    showTopBorder: showTopBorder ?? this.showTopBorder,
    connection: connection ?? this.connection,
  );

  @override
  BottomGlowInputBorder scale(double t) => BottomGlowInputBorder(
    borderSide: borderSide.scale(t),
    borderRadius: borderRadius * t,
    gapPadding: gapPadding * t,
    glowColor: glowColor.withValues(alpha: glowColor.a * t),
    glowExtent: glowExtent * t,
    wrapExtent: wrapExtent * t,
    showTopBorder: showTopBorder,
    connection: connection * t,
  );

  /// A plain outline border as a glow border with no glow, so both lerp
  /// directions share one interpolation.
  BottomGlowInputBorder _asGlowBorder(OutlineInputBorder border) =>
      border is BottomGlowInputBorder
      ? border
      : BottomGlowInputBorder(
          borderSide: border.borderSide,
          borderRadius: border.borderRadius,
          gapPadding: border.gapPadding,
          glowColor: Colors.transparent,
          showTopBorder: showTopBorder,
        );

  static BottomGlowInputBorder _lerp(
    BottomGlowInputBorder a,
    BottomGlowInputBorder b,
    double t,
  ) => BottomGlowInputBorder(
    borderSide: BorderSide.lerp(a.borderSide, b.borderSide, t),
    borderRadius: BorderRadius.lerp(a.borderRadius, b.borderRadius, t)!,
    gapPadding: lerpDouble(a.gapPadding, b.gapPadding, t)!,
    glowColor: Color.lerp(a.glowColor, b.glowColor, t)!,
    glowExtent: lerpDouble(a.glowExtent, b.glowExtent, t)!,
    wrapExtent: lerpDouble(a.wrapExtent, b.wrapExtent, t)!,
    showTopBorder: t < 0.5 ? a.showTopBorder : b.showTopBorder,
    connection: lerpDouble(a.connection, b.connection, t)!,
  );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is OutlineInputBorder
      ? _lerp(_asGlowBorder(a), this, t)
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is OutlineInputBorder
      ? _lerp(this, _asGlowBorder(b), t)
      : super.lerpTo(b, t);

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
    final effectiveWrapExtent = lerpDouble(
      math.max(wrapExtent, borderSide.width),
      math.max(rect.height / 2, wrapExtent),
      showTopBorder ? connection : 0.0,
    )!;

    final borderPaint = borderSide.toPaint();
    final strokeInset = borderSide.width / 2;
    final strokeRRect = outerRRect.deflate(strokeInset);
    final clipTop = rect.bottom - effectiveWrapExtent - borderSide.width;

    final edgeClip = Path()
      ..addRect(
        Rect.fromLTRB(
          rect.left - borderSide.width,
          clipTop,
          rect.right + borderSide.width,
          rect.bottom + borderSide.width,
        ),
      );
    if (showTopBorder) {
      final clipBottom = rect.top + effectiveWrapExtent + borderSide.width;
      edgeClip.addRect(
        Rect.fromLTRB(
          rect.left - borderSide.width,
          rect.top - borderSide.width,
          rect.right + borderSide.width,
          clipBottom,
        ),
      );
    }

    if (glowExtent > 0.0 && glowColor.a > 0.0) {
      final clampedGlowExtent = math.min(glowExtent, rect.height);
      final glowRect = Rect.fromLTRB(
        rect.left,
        rect.bottom - clampedGlowExtent,
        rect.right,
        rect.bottom,
      );
      // A vertical glow over [rect]; [alphas] are scaled by 1 - connection.
      Paint glowPaint(Rect rect, List<double> alphas, List<double> stops) =>
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                for (final alpha in alphas)
                  glowColor.withValues(alpha: alpha * (1 - connection)),
              ],
              stops: stops,
            ).createShader(rect)
            ..style = PaintingStyle.fill;

      canvas.save();
      final innerRRect = outerRRect.deflate(borderSide.width);
      canvas.clipRRect(innerRRect);
      canvas.drawRect(
        glowRect,
        glowPaint(glowRect, const [0.0, 0.15, 0.25], const [0.0, 0.6, 1.0]),
      );

      if (showTopBorder) {
        final topGlowRect = Rect.fromLTRB(
          rect.left,
          rect.top,
          rect.right,
          rect.top + clampedGlowExtent,
        );
        canvas.drawRect(
          topGlowRect,
          glowPaint(
            topGlowRect,
            const [0.25, 0.15, 0.0],
            const [0.0, 0.45, 1.0],
          ),
        );

        // Inset rounded contours keep the connected glow rounded as well.
        if (connection > 0) {
          final depth = math.min(
            clampedGlowExtent,
            math.min(innerRRect.width, innerRRect.height) / 2,
          );
          for (var inset = 0.5; inset < depth; inset += 1) {
            final alpha = 0.25 * connection * math.pow(1 - inset / depth, 2);
            Radius contour(Radius r) => Radius.elliptical(
              math.max(r.x - inset * 0.35, r.x * 0.5),
              math.max(r.y - inset * 0.35, r.y * 0.5),
            );
            canvas.drawRRect(
              RRect.fromRectAndCorners(
                innerRRect.outerRect.deflate(inset),
                topLeft: contour(innerRRect.tlRadius),
                topRight: contour(innerRRect.trRadius),
                bottomLeft: contour(innerRRect.blRadius),
                bottomRight: contour(innerRRect.brRadius),
              ),
              Paint()
                ..color = glowColor.withValues(alpha: alpha)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.0,
            );
          }
        }
      }

      canvas.restore();
    }

    canvas.save();
    canvas.clipPath(edgeClip);
    canvas.drawRRect(strokeRRect, borderPaint);
    canvas.restore();
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
    this.minWidth = 40,
    this.minHeight = 26,
    this.horizontalSpacing = 6,
    this.horizontalMainAxisSize = MainAxisSize.min,
    this.horizontalMainAxisAlignment = MainAxisAlignment.center,
    this.duration = Duration.zero,
    this.variant = AppNavigationButtonVariant.navigation,
    this.iconSize = kIconSize,
    this.labelVisible = true,
    this.labelFadeDuration = Duration.zero,
    this.labelFadeCurve = Curves.easeOut,
    this.hideIconWithLabel = false,
    this.hasNotification = false,
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
  final double minWidth;
  final double minHeight;
  final double horizontalSpacing;
  final MainAxisSize horizontalMainAxisSize;
  final MainAxisAlignment horizontalMainAxisAlignment;
  final Duration duration;
  final AppNavigationButtonVariant variant;
  final double iconSize;
  final bool labelVisible;
  final Duration labelFadeDuration;
  final Curve labelFadeCurve;

  /// Shrinks the icon away as the label grows in, for text-only buttons that
  /// still show an icon while collapsed.
  final bool hideIconWithLabel;
  final bool hasNotification;

  @override
  State<AppNavigationButton> createState() => _AppNavigationButtonState();
}

class _AppNavigationButtonState extends State<AppNavigationButton>
    with TickerProviderStateMixin {
  static const double _hoverIconBoost = 0.2;
  // Keeps the button's state (ink, hover) when a tooltip is added or removed.
  final _buttonKey = GlobalKey();
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
      widget.isSelected
          ? _selectionController.forward()
          : _selectionController.reverse();
    }
    if (oldWidget.isEnabled && !widget.isEnabled) _hoverController.reverse();
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

  /// Secondary text blended toward [selected] by [selectionT], or muted
  /// while disabled.
  Color _foreground(Color selected, double selectionT) => widget.isEnabled
      ? Color.lerp(widget.theme.textSecondary, selected, selectionT)!
      : widget.theme.textSecondary.withValues(alpha: 0.5);

  double _labelVisibilityT() {
    if (widget.labelText == null || widget.labelFadeDuration == Duration.zero) {
      return widget.labelVisible ? 1.0 : 0.0;
    }
    return widget.labelFadeCurve
        .transform(_labelVisibilityController.value)
        .clamp(0.0, 1.0);
  }

  /// [child] grown in along the button's axis by [t], fading with it.
  Widget _reveal(double t, Widget child, {AlignmentGeometry? alignment}) =>
      ClipRect(
        child: Align(
          alignment: alignment ?? Alignment.center,
          widthFactor: widget.isHorizontal ? t : 1,
          heightFactor: widget.isHorizontal ? 1 : t,
          child: Opacity(opacity: t, child: child),
        ),
      );

  Widget _buildContent({
    required Color iconColor,
    required TextStyle labelStyle,
    required double iconScale,
    required double labelVisibilityT,
  }) {
    final iconVisibilityT = widget.hideIconWithLabel
        ? 1 - labelVisibilityT
        : 1.0;
    final iconData = widget.iconData;
    final iconWidget =
        widget.iconBuilder?.call(context, iconColor, widget.iconSize) ??
        (iconData == null
            ? null
            : Icon(iconData, color: iconColor, size: widget.iconSize));
    final scaled = iconWidget == null
        ? null
        : Transform.scale(scale: iconScale, child: iconWidget);
    final icon = scaled == null || iconVisibilityT == 1
        ? scaled
        : _reveal(iconVisibilityT, scaled);

    final labelText = widget.labelText;
    final text = labelText == null
        ? null
        : Text(
            labelText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: labelStyle,
          );
    final label = text == null
        ? null
        : widget.labelFadeDuration == Duration.zero
        ? (widget.labelVisible ? text : null)
        : IgnorePointer(
            ignoring: labelVisibilityT == 0,
            child: _reveal(
              labelVisibilityT,
              text,
              alignment: widget.isHorizontal
                  ? Alignment.centerLeft
                  : Alignment.topCenter,
            ),
          );

    if (!widget.isHorizontal) {
      return Column(mainAxisSize: MainAxisSize.min, children: [?icon, ?label]);
    }
    Widget? spacedLabel = label == null
        ? null
        : Padding(
            padding: EdgeInsets.only(
              left: icon == null
                  ? 0
                  : widget.horizontalSpacing *
                        labelVisibilityT *
                        iconVisibilityT,
            ),
            child: label,
          );
    if (spacedLabel != null &&
        widget.horizontalMainAxisSize == MainAxisSize.max) {
      spacedLabel = Flexible(child: spacedLabel);
    }
    return Row(
      mainAxisSize: widget.horizontalMainAxisSize,
      mainAxisAlignment: widget.horizontalMainAxisAlignment,
      children: [?icon, ?spacedLabel],
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius =
        ButtonGroupShape.maybeOf(context) ??
        BorderRadius.circular(
          widget.theme.cornerRadius * widget.borderRadiusMultiplier,
        );

    final button = AnimatedBuilder(
      key: _buttonKey,
      animation: Listenable.merge([
        _hoverController,
        _selectionController,
        _labelVisibilityController,
      ]),
      builder: (context, child) {
        final selectionT = _selectionController.value;
        final hoverT = _hoverController.value;
        final labelVisibilityT = _labelVisibilityT();
        // Animated buttons start from a padding that already fills the
        // minimum width, so collapsing never clamps and re-centers the icon.
        final collapsedHorizontal = widget.labelFadeDuration == Duration.zero
            ? 6.0
            : math.max(6.0, (widget.minWidth - widget.iconSize) / 2);
        final effectivePadding =
            widget.padding ??
            EdgeInsetsGeometry.lerp(
              EdgeInsets.symmetric(
                horizontal: collapsedHorizontal,
                vertical: 8,
              ),
              EdgeInsets.symmetric(
                horizontal: widget.labelText == null ? 6 : 12,
                vertical: 6,
              ),
              labelVisibilityT,
            )!;
        final backgroundColor = !widget.isEnabled
            ? Colors.transparent
            : Color.lerp(
                    Color.lerp(
                      Colors.transparent,
                      widget.theme.navItemHover,
                      hoverT,
                    ),
                    widget.selectedBackgroundColor ??
                        widget.theme.navItemSelected,
                    selectionT,
                  ) ??
                  Colors.transparent;
        final iconColor = _foreground(widget.theme.accent, selectionT);
        final labelStyle = TextStyle(
          fontSize: 14,
          color: _foreground(widget.theme.textPrimary, selectionT),
        );
        final iconScale = widget.isEnabled
            ? 1 + math.max(selectionT, hoverT) * _hoverIconBoost
            : 1.0;

        return MouseRegion(
          onEnter: (_) => _hoverController.forward(),
          onExit: (_) => _hoverController.reverse(),
          child: Material(
            color: backgroundColor,
            // Hover and selection are animated above. Apply theme geometry
            // directly so radius edits don't trail behind the other controls.
            animationDuration: widget.duration,
            borderRadius: borderRadius,
            child: ButtonNotificationPulse(
              enabled: widget.hasNotification && widget.isEnabled,
              color: widget.theme.secondary,
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
          ),
        );
      },
    );

    final tooltipMessage = widget.tooltipMessage;
    if (tooltipMessage == null || tooltipMessage.isEmpty) return button;

    return Tooltip(message: tooltipMessage, child: button);
  }
}

class AppLinearProgressBar extends StatelessWidget {
  const AppLinearProgressBar({
    super.key,
    required this.theme,
    required this.value,
    this.label,
  });

  final AppThemeData theme;
  final double? value;
  final String? label;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(theme.cornerRadius),
    child: Stack(
      alignment: Alignment.center,
      children: [
        LinearProgressIndicator(
          value: value,
          minHeight: 26,
          backgroundColor: theme.accent.withValues(alpha: 0.35),
          valueColor: AlwaysStoppedAnimation(theme.accent),
        ),
        if (label != null)
          IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  // The centred label sits over the fill from halfway on.
                  color: (value ?? 0) >= 0.5
                      ? contrastColor(theme.accent)
                      : theme.textPrimary,
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
  iconData: Icons.dark_mode,
);

/// Light theme
const kLightTheme = AppThemeData(
  id: 'builtin-light',
  name: 'Light',
  baseBackground: Color(0xFFF5F5F5),
  baseSecondary: Color(0xFF6797FF),
  baseAccent: Color(0xFF8B5CF6),
  iconData: Icons.light_mode,
);

/// Nebula theme (purple)
const kNebulaTheme = AppThemeData(
  id: 'builtin-nebula',
  name: 'Nebula',
  baseBackground: Color(0xFF0E0E29),
  baseSecondary: Color(0xFF7B61FF),
  baseAccent: Color(0xFF3BF2FF),
  iconData: Icons.auto_awesome,
);

/// Sunset theme (orange/warm)
const kSunsetTheme = AppThemeData(
  id: 'builtin-sunset',
  name: 'Sunset',
  baseBackground: Color(0xFF401C27),
  baseSecondary: Color(0xFFB83714),
  baseAccent: Color(0xFFF4A461),
  iconData: Icons.wb_twilight,
);

/// Ocean theme (teal/blue)
const kOceanTheme = AppThemeData(
  id: 'builtin-ocean',
  name: 'Ocean',
  baseBackground: Color(0xFF00203C),
  baseSecondary: Color(0xFF0891FF),
  baseAccent: Color(0xFF15FFF0),
  iconData: Icons.water,
);

/// Forest theme (green)
const kForestTheme = AppThemeData(
  id: 'builtin-forest',
  name: 'Forest',
  baseBackground: Color(0xFF0D1F12),
  baseSecondary: Color(0xFF1FB332),
  baseAccent: Color(0xFF4ADE80),
  iconData: Icons.forest,
);

/// Royal theme (deep blue / violet)
const kRoyalTheme = AppThemeData(
  id: 'builtin-royal',
  name: 'Royal',
  baseBackground: Color(0xFF111827),
  baseSecondary: Color(0xFF14B8A6),
  baseAccent: Color(0xFFF4CBA7),
  iconData: Icons.diamond,
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
