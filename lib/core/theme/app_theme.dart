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

  /// Primary color (alias for basePrimary)
  Color get primary => basePrimary;

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
  Color get primaryButtonText => contrastColor(basePrimary);

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
  Color get navBackground => blendColors(baseBackground, baseAccent, 0.035);

  /// Navigation item hover
  Color get navItemHover => baseAccent.withValues(alpha: 0.20);

  /// Navigation item selected
  Color get navItemSelected => baseAccent.withValues(alpha: 0.35);

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
          foregroundColor:
              primaryButtonText, // add shadow for the text to improve contrast
          disabledBackgroundColor: primaryButtonDisabled,
          disabledForegroundColor: primaryButtonDisabledText,
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
          color: surface,
          borderRadius: BorderRadius.circular(cornerRadius),
          border: Border.all(color: border),
        ),
        textStyle: TextStyle(color: textPrimary),      ),

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

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
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

enum AppNavigationButtonVariant {
  navigation,
  settingsSection,
}

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
    this.minWidth = 45,
    this.minHeight = 25,
    this.horizontalSpacing = 8,
    this.verticalSpacing = 0,
    this.horizontalMainAxisSize = MainAxisSize.min,
    this.horizontalMainAxisAlignment = MainAxisAlignment.center,
    this.duration = const Duration(milliseconds: 1000),
    this.variant = AppNavigationButtonVariant.navigation,
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
  final Widget Function(BuildContext context, Color color, double size)? iconBuilder;
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
  final bool labelVisible;
  final bool reserveLabelSpace;
  final Duration labelFadeDuration;
  final Curve labelFadeCurve;

  @override
  State<AppNavigationButton> createState() => _AppNavigationButtonState();
}

class _AppNavigationButtonState extends State<AppNavigationButton> {
  bool _hovered = false;

  static const double _iconSize = 24;

  Color get _iconColor => !widget.isEnabled
      ? widget.theme.textSecondary.withValues(alpha: 0.5)
      : (widget.isSelected ? widget.theme.accent : widget.theme.textSecondary);

  TextStyle get _labelStyle {
    return TextStyle(
      color: !widget.isEnabled
          ? widget.theme.textSecondary.withValues(alpha: 0.5)
          : (widget.isSelected ? widget.theme.textPrimary : widget.theme.textSecondary),
      fontSize: 13,
      fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.normal,
    );
  }

  Widget? _buildIcon() {
    if (widget.iconBuilder != null) {
      return widget.iconBuilder!(context, _iconColor, _iconSize);
    }
    final iconData = widget.iconData;
    if (iconData == null) {
      return null;
    }
    return Icon(iconData, color: _iconColor, size: _iconSize);
  }

  Widget? _buildLabel() {
    final labelText = widget.labelText;
    if (labelText == null || !widget.reserveLabelSpace) {
      return null;
    }

    final label = Text(
      labelText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _labelStyle,
    );

    if (widget.labelFadeDuration == Duration.zero) {
      return widget.labelVisible ? label : null;
    }

    return IgnorePointer(
      ignoring: !widget.labelVisible,
      child: AnimatedOpacity(
        opacity: widget.labelVisible ? 1 : 0,
        duration: widget.labelFadeDuration,
        curve: widget.labelFadeCurve,
        child: label,
      ),
    );
  }

  Widget _buildContent() {
    final icon = _buildIcon();
    final label = _buildLabel();
    final iconChildren = icon == null ? null : <Widget>[icon];
    final horizontalLabelChildren = label == null
        ? null
        : <Widget>[
            Flexible(
              fit: FlexFit.loose,
              child: Padding(
                padding: EdgeInsets.only(
                  left: icon == null ? 0 : widget.horizontalSpacing,
                ),
                child: label,
              ),
            ),
          ];
    final verticalLabelChildren = label == null
        ? null
        : <Widget>[
            Padding(
              padding: EdgeInsets.only(
                top: icon == null ? 0 : widget.verticalSpacing,
              ),
              child: label,
            ),
          ];

    if (widget.isHorizontal) {
      return Row(
        mainAxisSize: widget.horizontalMainAxisSize,
        mainAxisAlignment: widget.horizontalMainAxisAlignment,
        children: [
          ...?iconChildren,
          ...?horizontalLabelChildren,
        ],
      );
    } else {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ...?iconChildren,
          ...?verticalLabelChildren,
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectivePadding =
        widget.padding ??
        EdgeInsets.symmetric(
          horizontal: widget.labelText == null ? 8 : 12,
          vertical: 8,
        );

    final backgroundColor = !widget.isEnabled
        ? (widget.disabledBackgroundColor ??
              Colors.transparent)
        : widget.isSelected
        ? (widget.selectedBackgroundColor ?? widget.theme.navItemSelected)
        : (_hovered
              ? (widget.hoverBackgroundColor ?? widget.theme.navItemHover)
              : Colors.transparent);

    final borderRadius = BorderRadius.circular(
      widget.theme.cornerRadius * widget.borderRadiusMultiplier,
    );

    final button = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
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
          child: Padding(
            padding: effectivePadding,
            child: Align(
              alignment: widget.alignment,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                ),
                child: _buildContent(),
              ),
            ),
          ),
        ),
      ),
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
    this.minHeight = 20,
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
                  style: labelStyle ??
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
  baseBackground: Color(0xFF141414),
  basePrimary: Color.fromARGB(255, 32, 79, 197),
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
  basePrimary: Color.fromARGB(255, 226, 121, 0),
  baseAccent: Color.fromARGB(255, 255, 167, 14),
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
  basePrimary: Color.fromARGB(255, 31, 179, 50),
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
