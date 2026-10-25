/// Theme editor dialog for creating and editing custom themes.
library;

import '../../../core/theme/theme_icons.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../widgets/app_combo_box.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_slider_theme.dart';
import '../../../core/utils/color_utils.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/notification_system.dart';
import '../../widgets/dialog_helpers.dart';
import '../../widgets/theme_icon_menu.dart';
import '../../../core/constants/app_constants.dart';

// ---------------------------------------------------------------------------
// Dialog
// ---------------------------------------------------------------------------

/// Theme editor dialog - for creating and editing custom themes.
class ThemeEditorDialog extends ConsumerStatefulWidget {
  const ThemeEditorDialog({super.key, required this.theme, this.existingTheme});

  final AppThemeData theme;
  final AppThemeData? existingTheme;

  @override
  ConsumerState<ThemeEditorDialog> createState() => _ThemeEditorDialogState();
}

typedef _ColorSlot = String; // 'background' | 'secondary' | 'accent'

class _ThemeEditorDialogState extends ConsumerState<ThemeEditorDialog> {
  final _nameController = TextEditingController();
  final _hexController = TextEditingController();
  final _hexFocusNode = FocusNode();
  late final ThemeNotifier _themeNotifier;
  static const double _minCornerRadius = 1.0;
  static const double _maxCornerRadius = kElementHeight / 2;

  // Available theme icons (grouped by category)
  // Theme color slots
  late String _backgroundHex;
  late String _secondaryHex;
  late String _accentHex;
  late String _workingThemeId;
  late NavPanelOverlayStyle _navPanelOverlayStyle;
  late double _cornerRadius;
  int? _selectedIconCodePoint;
  bool _isEditing = false;
  bool _saved = false;
  final _circleHovered = <String, bool>{};

  // Which slot is being edited
  _ColorSlot _activeSlot = 'background';

  // HSV values for the active color
  double _hue = 0;
  double _saturation = 0;
  double _value = 1;

  @override
  void initState() {
    super.initState();
    _themeNotifier = ref.read(themeProvider.notifier);
    _isEditing = widget.existingTheme != null;
    _workingThemeId =
        widget.existingTheme?.id ?? AppThemeData.generateThemeId();

    // A new theme starts from the current one.
    final existing = widget.existingTheme;
    final source = existing ?? widget.theme;
    if (existing != null) _nameController.text = existing.name;
    _backgroundHex = colorToHex(source.baseBackground);
    _secondaryHex = colorToHex(source.baseSecondary);
    _accentHex = colorToHex(source.baseAccent);
    _navPanelOverlayStyle = source.navPanelOverlayStyle;
    _cornerRadius = source.cornerRadius.clamp(
      _minCornerRadius,
      _maxCornerRadius,
    );
    _selectedIconCodePoint = existing != null
        ? existing.iconData?.codePoint
        : source.icon.codePoint;

    _hexFocusNode.addListener(() {
      if (!_hexFocusNode.hasFocus) {
        _syncHexController();
      }
    });

    _syncHsvFromActiveSlot();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hexController.dispose();
    _hexFocusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Color slot helpers
  // ---------------------------------------------------------------------------

  String get _activeHex => _hexForSlot(_activeSlot);

  String _hexForSlot(_ColorSlot slot) => switch (slot) {
    'secondary' => _secondaryHex,
    'accent' => _accentHex,
    _ => _backgroundHex,
  };

  void _setHexForSlot(_ColorSlot slot, String hex) {
    switch (slot) {
      case 'secondary':
        _secondaryHex = hex;
      case 'accent':
        _accentHex = hex;
      default:
        _backgroundHex = hex;
    }
  }

  String _labelForSlot(_ColorSlot slot) => switch (slot) {
    'secondary' => 'Secondary',
    'accent' => 'Accent',
    _ => 'Background',
  };

  void _swapSlots(_ColorSlot a, _ColorSlot b) {
    final hexA = _hexForSlot(a);
    final hexB = _hexForSlot(b);
    setState(() {
      _setHexForSlot(a, hexB);
      _setHexForSlot(b, hexA);
    });
    _syncHsvFromActiveSlot();
    _updatePreview();
  }

  // ---------------------------------------------------------------------------
  // HSV / hex sync
  // ---------------------------------------------------------------------------

  void _syncHsvFromActiveSlot() {
    final color = parseHexColor(_activeHex);
    final hsv = HSVColor.fromColor(color);
    _hue = hsv.hue;
    _saturation = hsv.saturation;
    _value = hsv.value;
    _syncHexController();
  }

  void _syncHexController() {
    _hexController.text = _activeHex.replaceFirst('#', '').toUpperCase();
  }

  Color _hsvToColor() =>
      HSVColor.fromAHSV(1.0, _hue, _saturation, _value).toColor();

  void _applyHsvChange() {
    final color = _hsvToColor();
    final hex = colorToHex(color);
    setState(() => _setHexForSlot(_activeSlot, hex));
    if (!_hexFocusNode.hasFocus) {
      _hexController.text = hex.replaceFirst('#', '').toUpperCase();
    }
    _updatePreview();
  }

  void _applyHexInput(String raw) {
    final sanitized = raw.replaceFirst('#', '');
    if (sanitized.length == 6) {
      final parsed = int.tryParse(sanitized, radix: 16);
      if (parsed != null) {
        final hex = '#${sanitized.toLowerCase()}';
        setState(() {
          _setHexForSlot(_activeSlot, hex);
          final hsv = HSVColor.fromColor(parseHexColor(hex));
          _hue = hsv.hue;
          _saturation = hsv.saturation;
          _value = hsv.value;
        });
        _updatePreview();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Live preview
  // ---------------------------------------------------------------------------

  /// The theme the editor fields currently describe.
  AppThemeData _buildWorkingTheme(String name) => AppThemeData(
    id: _workingThemeId,
    name: name,
    baseBackground: parseHexColor(_backgroundHex),
    baseSecondary: parseHexColor(_secondaryHex),
    baseAccent: parseHexColor(_accentHex),
    cornerRadius: _cornerRadius,
    navPanelOverlayStyle: _navPanelOverlayStyle,
    iconData: _selectedIconCodePoint != null
        ? themeIconFromCodePoint(_selectedIconCodePoint!)
        : null,
  );

  void _updatePreview() {
    if (!mounted) return;
    _themeNotifier.startPreview(
      _buildWorkingTheme(
        _nameController.text.isEmpty ? 'Preview' : _nameController.text,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final previewTheme = ref.watch(themeProvider);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_saved) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _themeNotifier.cancelPreview();
          });
        }
      },
      child: ThemedAlertDialog(
        theme: previewTheme,
        title: DialogHeader(
          icon: _isEditing ? Icons.palette_outlined : Icons.add_circle_outline,
          title: _isEditing ? 'Theme Editor' : 'Create Theme',
          theme: previewTheme,
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Theme name + icon circle
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        style: TextStyle(color: previewTheme.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'Theme name',
                          labelStyle: TextStyle(
                            color: previewTheme.textSecondary,
                          ),
                        ),
                        onChanged: (_) => _updatePreview(),
                      ),
                    ),
                    const SizedBox(width: kElementHSpacing),
                    ThemeIconMenuButton(
                      theme: previewTheme,
                      selectedIconCodePoint: _selectedIconCodePoint,
                      onChanged: (value) {
                        setState(() => _selectedIconCodePoint = value);
                        _updatePreview();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: kDialogSpacing),

                // Color circles — click to select, drag to swap
                _buildColorCirclesRow(previewTheme),
                const SizedBox(height: kDialogSpacing),

                // Shared color editor for the active slot
                _buildActiveColorEditor(previewTheme),
                const SizedBox(height: kDialogSpacing),

                _buildCornerRadiusSlider(previewTheme),
                const SizedBox(height: kDialogSpacing),

                // Nav panel overlay
                _buildOverlayStylePicker(previewTheme),
              ],
            ),
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _saveTheme,
            style: themedFilledButtonStyle(previewTheme),
            child: Text(_isEditing ? 'Save Changes' : 'Create Theme'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Color circles row
  // ---------------------------------------------------------------------------

  Widget _buildColorCirclesRow(AppThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Theme Colors  \u2022  Click to edit  \u2022  Drag to swap',
          style: TextStyle(color: theme.textSecondary, fontSize: 11),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 28,
          runSpacing: 12,
          children: [
            _buildColorCircle(theme, 'background'),
            _buildColorCircle(theme, 'accent'),
            _buildColorCircle(theme, 'secondary'),
          ],
        ),
      ],
    );
  }

  Widget _buildColorCircle(AppThemeData theme, _ColorSlot slot) {
    final isActive = _activeSlot == slot;
    final color = parseHexColor(_hexForSlot(slot));
    final label = _labelForSlot(slot);
    final isHovered = _circleHovered[slot] ?? false;

    // Border shown when circle is active/drop-target
    final highlightBorderColor = switch (slot) {
      'accent' => parseHexColor(_secondaryHex),
      _ => theme.accent,
    };
    // Glow color on hover (background circle's own color is invisible against dialog)
    final glowColor = slot == 'background' ? theme.accent : color;

    Widget circle({
      bool isActive = false,
      bool isDropTarget = false,
      bool isHovered = false,
      double size = 70,
    }) => _circleWidget(
      theme,
      color,
      label,
      highlightBorderColor: highlightBorderColor,
      glowColor: glowColor,
      isActive: isActive,
      isDropTarget: isDropTarget,
      isHovered: isHovered,
      size: size,
    );

    return DragTarget<_ColorSlot>(
      onWillAcceptWithDetails: (details) => details.data != slot,
      onAcceptWithDetails: (details) => _swapSlots(slot, details.data),
      builder: (context, candidateData, _) {
        return Draggable<_ColorSlot>(
          data: slot,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(opacity: 0.85, child: circle(size: 72)),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: circle()),
          child: MouseRegion(
            onEnter: (_) => setState(() => _circleHovered[slot] = true),
            onExit: (_) => setState(() => _circleHovered[slot] = false),
            child: GestureDetector(
              onTap: () => setState(() {
                _activeSlot = slot;
                _syncHsvFromActiveSlot();
              }),
              child: circle(
                isActive: isActive,
                isDropTarget: candidateData.isNotEmpty,
                isHovered: isHovered,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _circleWidget(
    AppThemeData theme,
    Color color,
    String label, {
    required Color highlightBorderColor,
    required Color glowColor,
    required bool isActive,
    required bool isDropTarget,
    required bool isHovered,
    double size = 70,
  }) {
    final highlight = isActive || isDropTarget;
    final Widget? centerIcon = highlight
        ? Icon(
            isDropTarget ? Icons.swap_horiz : Icons.edit,
            size: 22,
            color: contrastColor(color).withValues(alpha: 0.8),
          )
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: kFastAnimation,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(
              math.min(theme.cornerRadius, size / 2),
            ),
            border: Border.all(
              color: highlight ? highlightBorderColor : theme.border,
              width: highlight ? 3 : 2,
            ),
            boxShadow: highlight
                ? [
                    BoxShadow(
                      color: highlightBorderColor.withValues(alpha: 0.8),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ]
                : isHovered
                ? [
                    BoxShadow(
                      color: glowColor.withValues(alpha: 0.60),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
          child: centerIcon,
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: isActive ? theme.textPrimary : theme.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Active color editor (shared picker)
  // ---------------------------------------------------------------------------

  Widget _buildActiveColorEditor(AppThemeData theme) {
    final activeColor = _hsvToColor();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hex input and randomize button
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _hexController,
                focusNode: _hexFocusNode,
                style: TextStyle(
                  color: theme.textPrimary,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  labelText: 'Hex Color',
                  labelStyle: TextStyle(color: theme.textSecondary),
                  prefixText: '# ',
                  prefixStyle: TextStyle(color: theme.textSecondary),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                maxLength: 6,
                buildCounter:
                    (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
                onChanged: _applyHexInput,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Randomize color',
              icon: Icon(Icons.casino, color: theme.textSecondary),
              onPressed: _randomizeColor,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Hue slider with rainbow gradient track
        _buildGradientSlider(
          theme: theme,
          label: 'Hue',
          value: _hue,
          min: 0,
          max: 360,
          displayText: '${_hue.round()}\u00b0',
          thumbColor: HSVColor.fromAHSV(1, _hue, 1, 1).toColor(),
          trackShape: AppSliderTrackShape(
            cornerRadius: theme.cornerRadius,
            colors: const [
              Color(0xffff0000),
              Color(0xffffff00),
              Color(0xff00ff00),
              Color(0xff00ffff),
              Color(0xff0000ff),
              Color(0xffff00ff),
              Color(0xffff0000),
            ],
          ),
          onChanged: (v) {
            setState(() => _hue = v);
            _applyHsvChange();
          },
        ),
        const SizedBox(height: 10),

        // Saturation slider
        _buildGradientSlider(
          theme: theme,
          label: 'Saturation',
          ensureHandleContrast: true,
          value: _saturation,
          min: 0,
          max: 1,
          displayText: '${(_saturation * 100).round()}%',
          thumbColor: activeColor,
          trackShape: AppSliderTrackShape(
            colors: [
              HSVColor.fromAHSV(1, _hue, 0, _value).toColor(),
              HSVColor.fromAHSV(1, _hue, 1, _value).toColor(),
            ],
            cornerRadius: theme.cornerRadius,
          ),
          onChanged: (v) {
            setState(() => _saturation = v);
            _applyHsvChange();
          },
        ),
        const SizedBox(height: 10),

        // Brightness slider
        _buildGradientSlider(
          theme: theme,
          label: 'Brightness',
          ensureHandleContrast: true,
          value: _value,
          min: 0,
          max: 1,
          displayText: '${(_value * 100).round()}%',
          thumbColor: activeColor,
          trackShape: AppSliderTrackShape(
            colors: [
              Colors.black,
              HSVColor.fromAHSV(1, _hue, _saturation, 1).toColor(),
            ],
            cornerRadius: theme.cornerRadius,
          ),
          onChanged: (v) {
            setState(() => _value = v);
            _applyHsvChange();
          },
        ),
      ],
    );
  }

  Widget _buildGradientSlider({
    required AppThemeData theme,
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayText,
    required Color thumbColor,
    required SliderTrackShape trackShape,
    required ValueChanged<double> onChanged,
    bool ensureHandleContrast = false,
  }) {
    return _sliderRow(
      theme,
      label,
      displayText,
      SliderTheme(
        data:
            buildAppSliderTheme(
              accent: theme.accent,
              disabledColor: theme.textSecondary,
              indicatorTextColor: contrastColor(theme.accent),
              cornerRadius: theme.cornerRadius,
            ).copyWith(
              showValueIndicator: ShowValueIndicator.onDrag,
              trackShape: trackShape,
              thumbShape: AppSliderThumbShape(
                cornerRadius: theme.cornerRadius,
                outlineColor: ensureHandleContrast
                    ? contrastColor(theme.surface).withValues(alpha: 0.5)
                    : null,
              ),
              thumbColor: thumbColor,
              overlayColor: ensureHandleContrast
                  ? contrastColor(theme.surface).withValues(alpha: 0.18)
                  : thumbColor.withValues(alpha: 0.14),
            ),
        child: Slider(
          value: value,
          min: min,
          max: max,
          label: displayText,
          onChanged: onChanged,
        ),
      ),
    );
  }

  /// Label, slider and value readout, aligned across the editor's sliders.
  Widget _sliderRow(
    AppThemeData theme,
    String label,
    String displayText,
    Widget slider,
  ) => Row(
    children: [
      SizedBox(
        width: 76,
        child: Text(
          label,
          style: TextStyle(color: theme.textSecondary, fontSize: 12),
        ),
      ),
      Expanded(child: slider),
      SizedBox(
        width: 44,
        child: Text(
          displayText,
          style: TextStyle(
            color: theme.textPrimary,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
          textAlign: TextAlign.right,
        ),
      ),
    ],
  );

  // ---------------------------------------------------------------------------
  // Overlay style picker
  // ---------------------------------------------------------------------------

  Widget _buildOverlayStylePicker(AppThemeData theme) {
    return Row(
      children: [
        Text(
          'Nav Overlay',
          style: TextStyle(color: theme.textSecondary, fontSize: 12),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AppComboBox<NavPanelOverlayStyle>(
            initialValue: _navPanelOverlayStyle,
            theme: theme,
            style: TextStyle(color: theme.textPrimary, fontSize: 13),
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: NavPanelOverlayStyle.values
                .map(
                  (style) => DropdownMenuItem(
                    value: style,
                    child: Text(style.displayName),
                  ),
                )
                .toList(),
            onChanged: (style) {
              if (style == null) return;
              setState(() => _navPanelOverlayStyle = style);
              _updatePreview();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCornerRadiusSlider(AppThemeData theme) {
    final roundedRadius = _cornerRadius.roundToDouble();
    return _sliderRow(
      theme,
      'Roundness',
      roundedRadius.toStringAsFixed(0),
      SliderTheme(
        data: buildAppSliderTheme(
          accent: theme.accent,
          disabledColor: theme.textSecondary,
          indicatorTextColor: contrastColor(theme.accent),
          cornerRadius: theme.cornerRadius,
        ),
        child: Slider(
          value: roundedRadius,
          min: _minCornerRadius,
          max: _maxCornerRadius,
          divisions: (_maxCornerRadius - _minCornerRadius).round(),
          label: roundedRadius.toStringAsFixed(0),
          onChanged: (value) {
            setState(() => _cornerRadius = value);
            _updatePreview();
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Randomize color
  // ---------------------------------------------------------------------------

  void _randomizeColor() {
    final rng = math.Random();
    final hue = rng.nextDouble() * 360;
    final saturation = 0.4 + rng.nextDouble() * 0.6;
    final value = 0.5 + rng.nextDouble() * 0.5;
    final hex = colorToHex(
      HSVColor.fromAHSV(1, hue, saturation, value).toColor(),
    );
    setState(() {
      _setHexForSlot(_activeSlot, hex);
      _hue = hue;
      _saturation = saturation;
      _value = value;
    });
    _hexController.text = hex.replaceFirst('#', '').toUpperCase();
    _updatePreview();
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  Future<void> _saveTheme() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      NotificationManager.instance.warning('Please enter a theme name');
      return;
    }

    final customTheme = _buildWorkingTheme(name);

    await _themeNotifier.saveCustomTheme(customTheme);

    NotificationManager.instance.success(
      _isEditing ? 'Theme "$name" updated' : 'Theme "$name" saved',
    );

    if (!mounted) return;
    _saved = true;
    Navigator.pop(context);
  }
}
