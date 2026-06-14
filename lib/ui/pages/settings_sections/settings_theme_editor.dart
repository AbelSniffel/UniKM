/// Theme editor dialog for creating and editing custom themes.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/services/screen_color_picker_service.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/color_utils.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/notification_system.dart';
import '../../widgets/dialog_helpers.dart';
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
  final _pickerCancelToken = PickerCancelToken();
  static const double _minCornerRadius = 1.0;
  static const double _maxCornerRadius = kElementHeight / 2;

  // Available theme icons (grouped by category)
  static const _availableIconGroups = <(String, List<(IconData, String)>)>[
    (
      'Nature',
      [
        (Icons.eco, 'Leaf'),
        (Icons.local_florist, 'Flower'),
        (Icons.park, 'Tree'),
        (Icons.forest, 'Forest'),
        (Icons.water, 'Water'),
        (Icons.tsunami, 'Tsunami'),
      ],
    ),
    (
      'Light & Weather',
      [
        (Icons.wb_twilight, 'Twilight'),
        (Icons.light_mode, 'Sun'),
        (Icons.dark_mode, 'Moon'),
        (Icons.cloud, 'Cloud'),
        (Icons.air, 'Air'),
        (Icons.storm, 'Storm'),
        (Icons.bolt, 'Bolt'),
        (Icons.local_fire_department, 'Fire'),
        (Icons.ac_unit, 'Snow'),
      ],
    ),
    (
      'Space & Cosmos',
      [
        (Icons.star, 'Star'),
        (Icons.auto_awesome, 'Stars'),
        (Icons.flare, 'Flare'),
        (Icons.public, 'Globe'),
        (Icons.rocket_launch, 'Rocket'),
      ],
    ),
    (
      'Basic Shapes',
      [
        (Icons.pentagon, 'Pentagon'),
        (Icons.hexagon, 'Hexagon'),
        (Icons.square, 'Square'),
        (Icons.circle, 'Circle'),
      ],
    ),
    (
      'Misc',
      [
        (Icons.palette, 'Palette'),
        (Icons.brush, 'Brush'),
        (Icons.diamond, 'Diamond'),
        (Icons.favorite, 'Heart'),
      ],
    ),
  ];

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
    _isEditing = widget.existingTheme != null;
    _workingThemeId = widget.existingTheme?.id ?? AppThemeData.generateThemeId();

    if (widget.existingTheme != null) {
      _nameController.text = widget.existingTheme!.name;
      _backgroundHex = colorToHex(widget.existingTheme!.baseBackground);
      _secondaryHex = colorToHex(widget.existingTheme!.baseSecondary);
      _accentHex = colorToHex(widget.existingTheme!.baseAccent);
      _navPanelOverlayStyle = widget.existingTheme!.navPanelOverlayStyle;
      _cornerRadius = widget.existingTheme!.cornerRadius.clamp(
        _minCornerRadius,
        _maxCornerRadius,
      );
      _selectedIconCodePoint = widget.existingTheme!.iconData?.codePoint;
    } else {
      _backgroundHex = colorToHex(widget.theme.baseBackground);
      _secondaryHex = colorToHex(widget.theme.baseSecondary);
      _accentHex = colorToHex(widget.theme.baseAccent);
      _navPanelOverlayStyle = widget.theme.navPanelOverlayStyle;
      _cornerRadius = widget.theme.cornerRadius.clamp(
        _minCornerRadius,
        _maxCornerRadius,
      );
      _selectedIconCodePoint = widget.theme.icon.codePoint;
    }

    _hexFocusNode.addListener(() {
      if (!_hexFocusNode.hasFocus) {
        _syncHexController();
      }
    });

    _syncHsvFromActiveSlot();
  }

  @override
  void dispose() {
    _pickerCancelToken.cancel();
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

  void _updatePreview() {
    ref
        .read(themeProvider.notifier)
        .startPreview(
          AppThemeData(
            id: _workingThemeId,
            name: _nameController.text.isEmpty
                ? 'Preview'
                : _nameController.text,
            baseBackground: parseHexColor(_backgroundHex),
            baseSecondary: parseHexColor(_secondaryHex),
            baseAccent: parseHexColor(_accentHex),
            cornerRadius: _cornerRadius,
            navPanelOverlayStyle: _navPanelOverlayStyle,
            iconData: _selectedIconCodePoint != null
                ? IconData(_selectedIconCodePoint!, fontFamily: 'MaterialIcons')
                : null,
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
            ref.read(themeProvider.notifier).cancelPreview();
          });
        }
      },
      child: ThemedAlertDialog(
        theme: previewTheme,
        title: DialogHeader(
          title: _isEditing ? 'Edit Theme' : 'Theme Editor',
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
                    _buildIconCircle(previewTheme),
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: previewTheme.textSecondary),
            ),
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
  // Icon circle (next to theme name)
  // ---------------------------------------------------------------------------

  Widget _buildIconCircle(AppThemeData theme) {
    final selectedIcon = _selectedIconCodePoint != null
        ? IconData(_selectedIconCodePoint!, fontFamily: 'MaterialIcons')
        : Icons.palette;
    final isSelected = _selectedIconCodePoint != null;

    return Tooltip(
      message: 'Theme icon',
      child: IconButton(
        onPressed: () => _openIconPickerDialog(theme),
        icon: Icon(selectedIcon, size: 20),
        style: ButtonStyle(
          iconColor: WidgetStateProperty.all(
            isSelected ? theme.accent : theme.textSecondary,
          ),
          backgroundColor: WidgetStateProperty.all(
            isSelected
                ? theme.accent.withValues(alpha: 0.15)
                : Colors.transparent,
          ),
          overlayColor: WidgetStateProperty.all(theme.navItemHover),
          fixedSize: WidgetStateProperty.all(const Size(kElementHeight, kElementHeight)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(theme.cornerRadius),
              side: BorderSide(
                color: isSelected ? theme.accent : theme.border,
                width: isSelected ? 2 : 1.5,
              ),
            ),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  void _openIconPickerDialog(AppThemeData theme) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setInnerState) {
            final dialogTheme = ref.watch(themeProvider);
            return ThemedAlertDialog(
              theme: dialogTheme,
              title: DialogHeader(title: 'Theme Icon', theme: dialogTheme),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final group in _availableIconGroups) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 6),
                          child: Text(
                            group.$1,
                            style: TextStyle(
                              color: dialogTheme.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: group.$2.map((entry) {
                            final isSel =
                                entry.$1.codePoint == _selectedIconCodePoint;
                            return _HoverableIconTile(
                              icon: entry.$1,
                              tooltip: entry.$2,
                              isSelected: isSel,
                              theme: dialogTheme,
                              onTap: () {
                                setState(() {
                                  _selectedIconCodePoint = isSel
                                      ? null
                                      : entry.$1.codePoint;
                                });
                                setInnerState(() {});
                                _updatePreview();
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: themedFilledButtonStyle(dialogTheme),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
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
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildColorCircle(theme, 'background'),
            const SizedBox(width: 28),
            _buildColorCircle(theme, 'accent'),
            const SizedBox(width: 28),
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

    return DragTarget<_ColorSlot>(
      onWillAcceptWithDetails: (details) => details.data != slot,
      onAcceptWithDetails: (details) => _swapSlots(slot, details.data),
      builder: (context, candidateData, _) {
        final isDropTarget = candidateData.isNotEmpty;
        return Draggable<_ColorSlot>(
          data: slot,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.85,
              child: _circleWidget(
                theme,
                color,
                label,
                highlightBorderColor: highlightBorderColor,
                glowColor: glowColor,
                isActive: false,
                isDropTarget: false,
                isHovered: false,
                size: 72,
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: _circleWidget(
              theme,
              color,
              label,
              highlightBorderColor: highlightBorderColor,
              glowColor: glowColor,
              isActive: false,
              isDropTarget: false,
              isHovered: false,
            ),
          ),
          child: MouseRegion(
            onEnter: (_) => setState(() => _circleHovered[slot] = true),
            onExit: (_) => setState(() => _circleHovered[slot] = false),
            child: GestureDetector(
              onTap: () => setState(() {
                _activeSlot = slot;
                _syncHsvFromActiveSlot();
              }),
              child: _circleWidget(
                theme,
                color,
                label,
                highlightBorderColor: highlightBorderColor,
                glowColor: glowColor,
                isActive: isActive,
                isDropTarget: isDropTarget,
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
    final Widget? centerIcon = isActive
        ? Icon(
            Icons.edit,
            size: 22,
            color: contrastColor(color).withValues(alpha: 0.8),
          )
        : isDropTarget
        ? Icon(
            Icons.swap_horiz,
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
        // Hex input + screen picker button
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
                    (_, {required currentLength, required isFocused, maxLength}) =>
                        null,
                onChanged: _applyHexInput,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Randomize color',
              icon: Icon(Icons.casino, color: theme.textSecondary),
              onPressed: _randomizeColor,
            ),
            IconButton(
              tooltip: 'Pick from screen (Esc to cancel)',
              icon: Icon(Icons.colorize, color: theme.textSecondary),
              onPressed: _pickFromScreen,
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
          trackShape: _HueTrackShape(cornerRadius: theme.cornerRadius),
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
          value: _saturation,
          min: 0,
          max: 1,
          displayText: '${(_saturation * 100).round()}%',
          thumbColor: activeColor,
          trackShape: _GradientTrackShape(
            left: HSVColor.fromAHSV(1, _hue, 0, _value).toColor(),
            right: HSVColor.fromAHSV(1, _hue, 1, _value).toColor(),
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
          value: _value,
          min: 0,
          max: 1,
          displayText: '${(_value * 100).round()}%',
          thumbColor: activeColor,
          trackShape: _GradientTrackShape(
            left: Colors.black,
            right: HSVColor.fromAHSV(1, _hue, _saturation, 1).toColor(),
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
  }) {
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: TextStyle(color: theme.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: kSliderTrackHeight,
              thumbShape: _BorderedThumbShape(
                color: thumbColor,
                radius: theme.cornerRadius,
              ),
              overlayShape: RoundSliderOverlayShape(overlayRadius: theme.cornerRadius),
              trackShape: trackShape,
              thumbColor: thumbColor,
              overlayColor: thumbColor.withValues(alpha: 0.25),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
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
  }

  // ---------------------------------------------------------------------------
  // Icon picker
  // ---------------------------------------------------------------------------

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
          child: DropdownButtonFormField<NavPanelOverlayStyle>(
            initialValue: _navPanelOverlayStyle,
            isExpanded: true,
            borderRadius: BorderRadius.circular(theme.cornerRadius),
            dropdownColor: theme.surface,
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
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(
            'Roundness',
            style: TextStyle(color: theme.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: theme.accent,
              inactiveTrackColor: theme.border.withValues(alpha: 0.4),
              thumbColor: theme.accent,
              overlayColor: theme.accent.withValues(alpha: 0.18),
              trackHeight: kSliderTrackHeight,
              trackShape: _SolidTrackShape(cornerRadius: theme.cornerRadius),
              thumbShape: _BorderedThumbShape(
                color: theme.accent,
                radius: theme.cornerRadius,
                fillColor: theme.accent,
                borderColor: theme.surface,
              ),
              overlayShape: RoundSliderOverlayShape(overlayRadius: theme.cornerRadius),
              activeTickMarkColor: theme.accent.withValues(alpha: 0.18),
              inactiveTickMarkColor: theme.border.withValues(alpha: 0.32),
              tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 1.6),
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
        ),
        SizedBox(
          width: 44,
          child: Text(
            roundedRadius.toStringAsFixed(0),
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
  }

  // ---------------------------------------------------------------------------
  // Randomize color
  // ---------------------------------------------------------------------------

  void _randomizeColor() {
    final rng = math.Random();
    final hue = rng.nextDouble() * 360;
    final saturation = 0.4 + rng.nextDouble() * 0.6;
    final value = 0.5 + rng.nextDouble() * 0.5;
    final hex = colorToHex(HSVColor.fromAHSV(1, hue, saturation, value).toColor());
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
  // Screen color picker
  // ---------------------------------------------------------------------------

  Future<void> _pickFromScreen() async {
    if (!mounted) return;

    final colorNotifier = ValueNotifier<Color?>(null);

    final overlayEntry = OverlayEntry(
      builder: (_) => _PickerHudOverlay(colorNotifier: colorNotifier),
    );

    Overlay.of(context).insert(overlayEntry);

    ScreenColorPickResult result;
    try {
      result = await ScreenColorPickerService.pickColor(
        onCursorColor: (color) => colorNotifier.value = color,
        cancelToken: _pickerCancelToken,
      );
    } finally {
      overlayEntry.remove();
      overlayEntry.dispose();
      // colorNotifier is intentionally not disposed here: ValueListenableBuilder
      // removes its listener when the overlay widget unmounts (next frame after
      // remove()), so disposing now would cause a listener-teardown race in debug.
    }

    // Bring the window back to front, then hand focus to the hex field so
    // the dialog is immediately interactive without any OS-level focus() call.
    await windowManager.show();
    if (mounted) _hexFocusNode.requestFocus();

    if (!mounted) return;
    if (result.wasCancelled) return;

    if (result.color == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Unable to capture screen color.'),
          backgroundColor: ref.read(themeProvider).baseSecondary,
        ),
      );
      return;
    }

    final picked = result.color!;
    final hex = colorToHex(picked);
    final hsv = HSVColor.fromColor(picked);
    setState(() {
      _setHexForSlot(_activeSlot, hex);
      _hue = hsv.hue;
      _saturation = hsv.saturation;
      _value = hsv.value;
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

    final customTheme = AppThemeData(
      id: _workingThemeId,
      name: name,
      baseBackground: parseHexColor(_backgroundHex),
      baseSecondary: parseHexColor(_secondaryHex),
      baseAccent: parseHexColor(_accentHex),
      cornerRadius: _cornerRadius,
      navPanelOverlayStyle: _navPanelOverlayStyle,
      iconData: _selectedIconCodePoint != null
          ? IconData(_selectedIconCodePoint!, fontFamily: 'MaterialIcons')
          : null,
    );

    await ref.read(themeProvider.notifier).saveCustomTheme(customTheme);

    NotificationManager.instance.success(
      _isEditing ? 'Theme "$name" updated' : 'Theme "$name" saved',
    );

    if (!mounted) return;
    _saved = true;
    Navigator.pop(context);
  }
}

// ---------------------------------------------------------------------------
// Screen color picker HUD overlay
// ---------------------------------------------------------------------------

class _PickerHudOverlay extends StatelessWidget {
  const _PickerHudOverlay({required this.colorNotifier});

  final ValueNotifier<Color?> colorNotifier;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: ValueListenableBuilder<Color?>(
            valueListenable: colorNotifier,
            builder: (context, color, _) {
              final cs = Theme.of(context).colorScheme;
              final tt = Theme.of(context).textTheme;
              final hex = color != null
                  ? colorToHex(color).replaceFirst('#', '').toUpperCase()
                  : '------';

              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Color swatch — fixed size, never shifts
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color ?? cs.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Hex value — fixed width prevents layout jumping
                      SizedBox(
                        width: 80,
                        child: Text(
                          '# $hex',
                          textAlign: TextAlign.center,
                          style: tt.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Key hints
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _KeyHint(keyName: 'LMB / Space', label: 'Pick'),
                          const SizedBox(width: 14),
                          _KeyHint(keyName: 'RMB / C', label: 'Cancel'),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _KeyHint extends StatelessWidget {
  const _KeyHint({required this.keyName, required this.label});

  final String keyName;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Chip(
          label: Text(
            keyName,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          padding: EdgeInsets.zero,
          labelPadding: const EdgeInsets.symmetric(horizontal: 6),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Icon picker tile
// ---------------------------------------------------------------------------

class _HoverableIconTile extends StatelessWidget {
  const _HoverableIconTile({
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.theme,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final AppThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        style: ButtonStyle(
          iconColor: WidgetStateProperty.all(
            isSelected ? theme.accent : theme.textSecondary,
          ),
          backgroundColor: WidgetStateProperty.all(
            isSelected ? theme.accent.withValues(alpha: 0.2) : Colors.transparent,
          ),
          overlayColor: WidgetStateProperty.all(theme.navItemHover),
          fixedSize: WidgetStateProperty.all(const Size(kElementHeight, kElementHeight)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(theme.cornerRadius),
              side: BorderSide(
                color: isSelected ? theme.accent : theme.border,
                width: isSelected ? 2 : 1,
              ),
            ),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Custom slider components
// ---------------------------------------------------------------------------

/// Thumb with a white ring so it stays visible against gradient tracks.
class _BorderedThumbShape extends SliderComponentShape {
  const _BorderedThumbShape({
    required this.color,
    this.radius = 10.0,
    this.fillColor,
    this.borderColor,
  });

  final Color color;
  final double radius;
  final Color? fillColor;
  final Color? borderColor;

  static const double _outerDiameter = kSliderIndicatorOuterDiameter;
  static const double _innerDiameter = kSliderIndicatorInnerDiameter;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size(_outerDiameter, _outerDiameter);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final ringColor = borderColor ?? Colors.white.withValues(alpha: 0.85);
    final fill = fillColor ?? color;
    final outerCornerRadius = math.min(radius + 2, _outerDiameter / 2);
    final innerCornerRadius = math.min(radius, _innerDiameter / 2);
    final outerRect = Rect.fromCenter(
      center: center,
      width: _outerDiameter,
      height: _outerDiameter,
    );
    final innerRect = Rect.fromCenter(
      center: center,
      width: _innerDiameter,
      height: _innerDiameter,
    );
    final outerRadius = Radius.circular(outerCornerRadius);
    final innerRadius = Radius.circular(innerCornerRadius);

    canvas.drawRRect(
      RRect.fromRectAndRadius(outerRect, outerRadius),
      Paint()..color = ringColor,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(outerRect, outerRadius),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerRect, innerRadius),
      Paint()..color = fill,
    );
  }
}

// ---------------------------------------------------------------------------
// Custom slider track shapes
// ---------------------------------------------------------------------------

/// Rainbow hue gradient track for the hue slider.
class _HueTrackShape extends SliderTrackShape {
  const _HueTrackShape({required this.cornerRadius});

  final double cornerRadius;

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 4;
    const horizontalPadding = _sliderTrackHorizontalPadding;
    final trackLeft = offset.dx + horizontalPadding;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final trackWidth = parentBox.size.width - horizontalPadding * 2;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );

    final gradient = LinearGradient(
      colors: [
        HSVColor.fromAHSV(1, 0, 1, 1).toColor(),
        HSVColor.fromAHSV(1, 60, 1, 1).toColor(),
        HSVColor.fromAHSV(1, 120, 1, 1).toColor(),
        HSVColor.fromAHSV(1, 180, 1, 1).toColor(),
        HSVColor.fromAHSV(1, 240, 1, 1).toColor(),
        HSVColor.fromAHSV(1, 300, 1, 1).toColor(),
        HSVColor.fromAHSV(1, 360, 1, 1).toColor(),
      ],
    );

    final paint = Paint()
      ..shader = gradient.createShader(trackRect)
      ..style = PaintingStyle.fill;
    final radius = Radius.circular(
      math.min(cornerRadius, trackRect.height / 2),
    );

    context.canvas.drawRRect(RRect.fromRectAndRadius(trackRect, radius), paint);
  }
}

/// Two-color gradient track for saturation and brightness sliders.
class _GradientTrackShape extends SliderTrackShape {
  const _GradientTrackShape({
    required this.left,
    required this.right,
    required this.cornerRadius,
  });

  final Color left;
  final Color right;
  final double cornerRadius;

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 4;
    const horizontalPadding = _sliderTrackHorizontalPadding;
    final trackLeft = offset.dx + horizontalPadding;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final trackWidth = parentBox.size.width - horizontalPadding * 2;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );

    final gradient = LinearGradient(colors: [left, right]);
    final paint = Paint()
      ..shader = gradient.createShader(trackRect)
      ..style = PaintingStyle.fill;
    final radius = Radius.circular(
      math.min(cornerRadius, trackRect.height / 2),
    );

    context.canvas.drawRRect(RRect.fromRectAndRadius(trackRect, radius), paint);
  }
}

const double _sliderTrackHorizontalPadding = 12.0;

/// Solid active/inactive track with the same geometry as gradient sliders.
class _SolidTrackShape extends SliderTrackShape {
  const _SolidTrackShape({required this.cornerRadius});

  final double cornerRadius;

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 4;
    const horizontalPadding = _sliderTrackHorizontalPadding;
    final trackLeft = offset.dx + horizontalPadding;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final trackWidth = parentBox.size.width - horizontalPadding * 2;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );
    final radius = Radius.circular(
      math.min(cornerRadius, trackRect.height / 2),
    );
    final trackRRect = RRect.fromRectAndRadius(trackRect, radius);

    final activeColor =
        sliderTheme.activeTrackColor ?? sliderTheme.thumbColor ?? Colors.blue;
    final inactiveColor =
        sliderTheme.inactiveTrackColor ?? activeColor.withValues(alpha: 0.35);

    final canvas = context.canvas;
    canvas.drawRRect(trackRRect, Paint()..color = inactiveColor);

    final clampedThumbDx = thumbCenter.dx
        .clamp(trackRect.left, trackRect.right)
        .toDouble();
    final activeRect = textDirection == TextDirection.ltr
        ? Rect.fromLTRB(
            trackRect.left,
            trackRect.top,
            clampedThumbDx,
            trackRect.bottom,
          )
        : Rect.fromLTRB(
            clampedThumbDx,
            trackRect.top,
            trackRect.right,
            trackRect.bottom,
          );

    canvas.save();
    canvas.clipRRect(trackRRect);
    canvas.drawRect(activeRect, Paint()..color = activeColor);
    canvas.restore();
  }
}
