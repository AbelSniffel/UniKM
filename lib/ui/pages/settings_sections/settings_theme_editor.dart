/// Theme editor dialog for creating and editing custom themes.
library;

import '../../../core/theme/theme_icons.dart';
import 'dart:async';
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
import '../../widgets/tinted_tiles.dart';
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

  // Hex color of each slot.
  final _hex = <_ColorSlot, String>{};
  late String _workingThemeId;
  late NavPanelOverlayStyle _navPanelOverlayStyle;
  late double _cornerRadius;
  int? _selectedIconCodePoint;
  bool _isEditing = false;
  bool _saved = false;
  Timer? _previewThrottle;
  final _circleHovered = <String, bool>{};

  // The drag in progress: where its tile was grabbed, the tile's size and
  // how far the feedback has shrunk into a puck (0 → 1).
  Offset _grabOffset = Offset.zero;
  Size _grabSize = Size.zero;
  double _dragT = 0;

  // A swatch dropped outside any tile flying back into [_returningSlot].
  OverlayEntry? _returnEntry;
  _ColorSlot? _returningSlot;

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
    _hex['background'] = colorToHex(source.baseBackground);
    _hex['secondary'] = colorToHex(source.baseSecondary);
    _hex['accent'] = colorToHex(source.baseAccent);
    _navPanelOverlayStyle = source.navPanelOverlayStyle;
    _cornerRadius = source.cornerRadius.clamp(
      _minCornerRadius,
      _maxCornerRadius,
    );
    _selectedIconCodePoint = existing != null
        ? existing.iconData?.codePoint
        : source.icon.codePoint;

    _hexFocusNode.addListener(() {
      if (!_hexFocusNode.hasFocus) _syncHexController();
    });

    _syncHsvFromActiveSlot();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hexController.dispose();
    _hexFocusNode.dispose();
    _clearReturnEntry();
    _previewThrottle?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Color slot helpers
  // ---------------------------------------------------------------------------

  String get _activeHex => _hex[_activeSlot]!;

  void _swapSlots(_ColorSlot a, _ColorSlot b) {
    final hexA = _hex[a]!;
    setState(() {
      _hex[a] = _hex[b]!;
      _hex[b] = hexA;
    });
    _syncHsvFromActiveSlot();
    _updatePreview();
  }

  // ---------------------------------------------------------------------------
  // HSV / hex sync
  // ---------------------------------------------------------------------------

  void _syncHsvFromActiveSlot() {
    _setHsv(HSVColor.fromColor(parseHexColor(_activeHex)));
    _syncHexController();
  }

  void _setHsv(HSVColor hsv) {
    _hue = hsv.hue;
    _saturation = hsv.saturation;
    _value = hsv.value;
  }

  void _syncHexController() =>
      _hexController.text = _activeHex.replaceFirst('#', '').toUpperCase();

  Color _hsvToColor() =>
      HSVColor.fromAHSV(1.0, _hue, _saturation, _value).toColor();

  /// Applies a slider [change] to the HSV values and the active slot.
  void _applyHsvChange(VoidCallback change) {
    setState(() {
      change();
      _hex[_activeSlot] = colorToHex(_hsvToColor());
    });
    if (!_hexFocusNode.hasFocus) _syncHexController();
    _throttledPreview();
  }

  void _applyHexInput(String raw) {
    final sanitized = raw.replaceFirst('#', '');
    if (sanitized.length != 6 || int.tryParse(sanitized, radix: 16) == null) {
      return;
    }
    final hex = '#${sanitized.toLowerCase()}';
    setState(() {
      _hex[_activeSlot] = hex;
      _setHsv(HSVColor.fromColor(parseHexColor(hex)));
    });
    _updatePreview();
  }

  // ---------------------------------------------------------------------------
  // Live preview
  // ---------------------------------------------------------------------------

  /// The theme the editor fields currently describe.
  AppThemeData _buildWorkingTheme(String name) => AppThemeData(
    id: _workingThemeId,
    name: name,
    baseBackground: parseHexColor(_hex['background']!),
    baseSecondary: parseHexColor(_hex['secondary']!),
    baseAccent: parseHexColor(_hex['accent']!),
    cornerRadius: _cornerRadius,
    navPanelOverlayStyle: _navPanelOverlayStyle,
    iconData: _selectedIconCodePoint != null
        ? themeIconFromCodePoint(_selectedIconCodePoint!)
        : null,
  );

  /// Previews at most every 60ms while a slider is dragged: a preview
  /// rebuilds the whole app's theme, so doing it on every slider event lags.
  void _throttledPreview() =>
      _previewThrottle ??= Timer(const Duration(milliseconds: 60), () {
        _previewThrottle = null;
        _updatePreview();
      });

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
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _themeNotifier.cancelPreview(),
          );
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
            // Room for the name field's floating label.
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                // Theme name + icon circle
                Row(
                  spacing: kElementHSpacing,
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
                // Color tiles — click to select, drag to swap
                _section(
                  previewTheme,
                  'Colors',
                  _buildColorCirclesRow(previewTheme),
                  trailing: 'Tap to edit · Drag to swap',
                ),
                // Shared color editor for the active slot
                _section(
                  previewTheme,
                  '${_slotLabel(_activeSlot)} Color',
                  _panel(previewTheme, _buildActiveColorEditor(previewTheme)),
                ),
                _section(
                  previewTheme,
                  'Style',
                  _panel(
                    previewTheme,
                    Column(
                      spacing: 4,
                      children: [
                        _buildCornerRadiusSlider(previewTheme),
                        _buildOverlayStylePicker(previewTheme),
                      ],
                    ),
                  ),
                ),
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

  /// A heading over its [child], as in the other Tinted Tile dialogs.
  static Widget _section(
    AppThemeData theme,
    String title,
    Widget child, {
    String? trailing,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 8,
    children: [
      TintedHeading(theme: theme, title: title, trailing: trailing),
      child,
    ],
  );

  static String _slotLabel(_ColorSlot slot) =>
      '${slot[0].toUpperCase()}${slot.substring(1)}';

  Widget _buildColorCirclesRow(AppThemeData theme) => Row(
    spacing: 8,
    children: [
      for (final slot in ['background', 'accent', 'secondary'])
        Expanded(child: _buildColorCircle(theme, slot)),
    ],
  );

  Widget _buildColorCircle(AppThemeData theme, _ColorSlot slot) {
    final hex = '#${_hex[slot]!.replaceFirst('#', '').toUpperCase()}';
    final isActive = _activeSlot == slot;
    final isHovered = _circleHovered[slot] ?? false;
    // The accent tile is ringed in the secondary color so the ring stands
    // out against its own swatch.
    final ringColor = slot == 'accent'
        ? parseHexColor(_hex['secondary']!)
        : theme.accent;
    final tileRadius = BorderRadius.circular(
      theme.cornerRadius + _ColorSwatch.inset,
    );
    Widget swatch({
      double lift = 0,
      double textOpacity = 1,
      double? radius,
      IconData? badge,
      Duration duration = kFastAnimation,
    }) => _ColorSwatch(
      theme: theme,
      color: parseHexColor(hex),
      label: _slotLabel(slot),
      hex: hex,
      radius: radius ?? theme.cornerRadius,
      lift: lift,
      textOpacity: textOpacity,
      badge: badge,
      duration: duration,
    );

    // The swatch and its rect (in tile coordinates) part-way (t) from the
    // tile's shape to the puck centred on the grab point.
    Widget dragSwatch(double t) => swatch(
      radius: theme.cornerRadius + (28 - theme.cornerRadius) * t,
      lift: 1 + t,
      textOpacity: (1 - t * 2.5).clamp(0.0, 1.0),
      duration: Duration.zero,
    );
    Rect dragRect(double t) => Rect.lerp(
      (Offset.zero & _grabSize).deflate(_ColorSwatch.inset),
      Rect.fromCircle(center: _grabOffset, radius: 28),
      t,
    )!;

    final placeholder = Container(
      height: _ColorSwatch.tileHeight,
      decoration: BoxDecoration(
        color: theme.textHint.withValues(alpha: 0.06),
        borderRadius: tileRadius,
        border: Border.all(
          color: theme.textHint.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
    );

    return DragTarget<_ColorSlot>(
      onWillAcceptWithDetails: (details) => details.data != slot,
      onAcceptWithDetails: (details) => _swapSlots(slot, details.data),
      builder: (context, candidateData, _) {
        final isDropTarget = candidateData.isNotEmpty;
        return Draggable<_ColorSlot>(
          data: slot,
          dragAnchorStrategy: (draggable, context, position) {
            final box = context.findRenderObject()! as RenderBox;
            _grabSize = box.size;
            return _grabOffset = box.globalToLocal(position);
          },
          // The tile is rebuilt elsewhere in the tree, so it never gets the
          // pointer's exit event.
          onDragStarted: () => setState(() => _circleHovered[slot] = false),
          onDraggableCanceled: (_, releasedAt) =>
              _animateReturn(context, slot, releasedAt, dragRect, dragSwatch),
          // Starts on the tile and shrinks into a puck centred on the pointer.
          feedback: Material(
            type: MaterialType.transparency,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) {
                final rect = dragRect(_dragT = t);
                return Transform.translate(
                  offset: rect.topLeft,
                  child: SizedBox.fromSize(
                    size: rect.size,
                    child: dragSwatch(t),
                  ),
                );
              },
            ),
          ),
          childWhenDragging: placeholder,
          child: _returningSlot == slot
              ? placeholder
              : MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _circleHovered[slot] = true),
                  onExit: (_) => setState(() => _circleHovered[slot] = false),
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _activeSlot = slot;
                      _syncHsvFromActiveSlot();
                    }),
                    child: AnimatedScale(
                      scale: isDropTarget ? 1.04 : 1,
                      duration: kFastAnimation,
                      curve: Curves.easeOutBack,
                      child: AnimatedContainer(
                        duration: kFastAnimation,
                        height: _ColorSwatch.tileHeight,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          borderRadius: tileRadius,
                          border: Border.all(
                            color: isActive || isDropTarget
                                ? ringColor
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: swatch(
                          lift: isHovered || isDropTarget ? 1 : 0,
                          badge: isDropTarget
                              ? Icons.swap_horiz
                              : isActive
                              ? Icons.edit
                              : isHovered
                              ? Icons.open_with
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }

  void _clearReturnEntry() {
    _returnEntry
      ?..remove()
      ..dispose();
    _returnEntry = null;
  }

  /// Flies a swatch released outside any tile at [releasedAt] (the feedback's
  /// global origin) back into [slot]'s tile, growing back into its shape.
  void _animateReturn(
    BuildContext tileContext,
    _ColorSlot slot,
    Offset releasedAt,
    Rect Function(double t) dragRect,
    Widget Function(double t) dragSwatch,
  ) {
    final overlay = Overlay.of(tileContext);
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final tileBox = tileContext.findRenderObject()! as RenderBox;
    final startT = _dragT;
    final from = dragRect(startT).shift(overlayBox.globalToLocal(releasedAt));
    final to = dragRect(
      0,
    ).shift(overlayBox.globalToLocal(tileBox.localToGlobal(Offset.zero)));

    void finish() {
      _clearReturnEntry();
      if (mounted) setState(() => _returningSlot = null);
    }

    _clearReturnEntry();
    _returnEntry = OverlayEntry(
      builder: (_) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
        onEnd: finish,
        builder: (_, s, _) => Positioned.fromRect(
          rect: Rect.lerp(from, to, s)!,
          child: IgnorePointer(
            child: Material(
              type: MaterialType.transparency,
              child: dragSwatch(startT * (1 - s)),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_returnEntry!);
    setState(() => _returningSlot = slot);
  }

  // ---------------------------------------------------------------------------
  // Active color editor (shared picker)
  // ---------------------------------------------------------------------------

  /// A softly tinted, outlined panel grouping a section's controls.
  static Widget _panel(AppThemeData theme, Widget child) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: theme.textPrimary.withValues(alpha: 0.035),
      borderRadius: BorderRadius.circular(
        theme.cornerRadius + _ColorSwatch.inset,
      ),
      border: Border.all(color: theme.divider),
    ),
    child: child,
  );

  Widget _buildActiveColorEditor(AppThemeData theme) {
    final activeColor = _hsvToColor();
    Color hsv(double h, double s, double v) =>
        HSVColor.fromAHSV(1, h, s, v).toColor();

    return Column(
      spacing: 4,
      children: [
        // Hex input, led by a dot of the color, and randomize button
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: TextField(
                controller: _hexController,
                focusNode: _hexFocusNode,
                style: TextStyle(
                  color: theme.textPrimary,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'RRGGBB',
                  prefixIcon: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: AnimatedContainer(
                      duration: kFastAnimation,
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: activeColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.border),
                      ),
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(),
                  prefixText: '# ',
                  prefixStyle: TextStyle(color: theme.textHint),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
            IconButton.filledTonal(
              tooltip: 'Randomize color',
              style: IconButton.styleFrom(
                backgroundColor: theme.accent.withValues(alpha: 0.14),
                foregroundColor: theme.accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(theme.cornerRadius),
                ),
              ),
              icon: const Icon(Icons.casino_outlined),
              onPressed: _randomizeColor,
            ),
          ],
        ),
        const SizedBox(height: 4),
        _buildGradientSlider(
          theme: theme,
          label: 'Hue',
          value: _hue,
          max: 360,
          displayText: '${_hue.round()}\u00b0',
          thumbColor: hsv(_hue, 1, 1),
          colors: [for (var h = 0; h <= 360; h += 60) hsv(h.toDouble(), 1, 1)],
          onChanged: (v) => _applyHsvChange(() => _hue = v),
        ),
        _buildGradientSlider(
          theme: theme,
          label: 'Saturation',
          ensureHandleContrast: true,
          value: _saturation,
          displayText: '${(_saturation * 100).round()}%',
          thumbColor: activeColor,
          colors: [hsv(_hue, 0, _value), hsv(_hue, 1, _value)],
          onChanged: (v) => _applyHsvChange(() => _saturation = v),
        ),
        _buildGradientSlider(
          theme: theme,
          label: 'Brightness',
          ensureHandleContrast: true,
          value: _value,
          displayText: '${(_value * 100).round()}%',
          thumbColor: activeColor,
          colors: [Colors.black, hsv(_hue, _saturation, 1)],
          onChanged: (v) => _applyHsvChange(() => _value = v),
        ),
      ],
    );
  }

  Widget _buildGradientSlider({
    required AppThemeData theme,
    required String label,
    required double value,
    double max = 1,
    required String displayText,
    required Color thumbColor,
    required List<Color> colors,
    required ValueChanged<double> onChanged,
    bool ensureHandleContrast = false,
  }) => _labeledRow(
    theme,
    label,
    value: displayText,
    SliderTheme(
      data: _sliderTheme(theme).copyWith(
        showValueIndicator: ShowValueIndicator.onDrag,
        trackShape: AppSliderTrackShape(
          cornerRadius: theme.cornerRadius,
          colors: colors,
        ),
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
        max: max,
        label: displayText,
        onChanged: onChanged,
      ),
    ),
  );

  static SliderThemeData _sliderTheme(AppThemeData theme) =>
      buildAppSliderTheme(
        accent: theme.accent,
        disabledColor: theme.textSecondary,
        indicatorTextColor: contrastColor(theme.accent),
        cornerRadius: theme.cornerRadius,
      );

  /// A label, its control and an optional [value] pill, aligned across the
  /// editor's panels.
  Widget _labeledRow(
    AppThemeData theme,
    String label,
    Widget control, {
    String? value,
  }) => Row(
    spacing: 8,
    children: [
      SizedBox(
        width: 76,
        child: Text(
          label,
          style: TextStyle(
            color: theme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      Expanded(child: control),
      if (value != null)
        Container(
          width: 46,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: theme.textPrimary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(theme.cornerRadius),
          ),
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
    ],
  );

  // ---------------------------------------------------------------------------
  // Style
  // ---------------------------------------------------------------------------

  Widget _buildOverlayStylePicker(AppThemeData theme) => _labeledRow(
    theme,
    'Nav Overlay',
    AppComboBox<NavPanelOverlayStyle>(
      initialValue: _navPanelOverlayStyle,
      theme: theme,
      style: TextStyle(color: theme.textPrimary, fontSize: 13),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: [
        for (final style in NavPanelOverlayStyle.values)
          DropdownMenuItem(value: style, child: Text(style.displayName)),
      ],
      onChanged: (style) {
        if (style == null) return;
        setState(() => _navPanelOverlayStyle = style);
        _updatePreview();
      },
    ),
  );

  Widget _buildCornerRadiusSlider(AppThemeData theme) {
    final roundedRadius = _cornerRadius.roundToDouble();
    return _labeledRow(
      theme,
      'Roundness',
      value: roundedRadius.toStringAsFixed(0),
      SliderTheme(
        data: _sliderTheme(theme),
        child: Slider(
          value: roundedRadius,
          min: _minCornerRadius,
          max: _maxCornerRadius,
          divisions: (_maxCornerRadius - _minCornerRadius).round(),
          label: roundedRadius.toStringAsFixed(0),
          onChanged: (value) {
            setState(() => _cornerRadius = value);
            _throttledPreview();
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
    setState(() {
      _setHsv(
        HSVColor.fromAHSV(
          1,
          rng.nextDouble() * 360,
          0.4 + rng.nextDouble() * 0.6,
          0.5 + rng.nextDouble() * 0.5,
        ),
      );
      _hex[_activeSlot] = colorToHex(_hsvToColor());
    });
    _syncHexController();
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

// ---------------------------------------------------------------------------
// Color swatch
// ---------------------------------------------------------------------------

/// A color slot's swatch with its name and hex code; also the drag feedback.
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.theme,
    required this.color,
    required this.label,
    required this.hex,
    required this.radius,
    required this.lift,
    required this.textOpacity,
    required this.badge,
    required this.duration,
  });

  /// Gap plus ring width between a tile's edge and its swatch.
  static const double inset = 5;
  static const double tileHeight = 94;

  final AppThemeData theme;
  final Color color;
  final String label;
  final String hex;
  final double radius;

  /// 0 at rest, 1 hovered, up to 2 while dragged; deepens the shadow.
  final double lift;
  final double textOpacity;
  final IconData? badge;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final onColor = contrastColor(color);

    return AnimatedContainer(
      duration: duration,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: theme.border),
        // A soft sheen so flat colors read as a physical chip.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, 0.14)!,
            color,
            Color.lerp(color, Colors.black, 0.08)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08 + 0.1 * lift),
            blurRadius: 3 + 9 * lift,
            offset: Offset(0, 1 + 3 * lift),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 10,
            right: 10,
            bottom: 8,
            child: Opacity(
              opacity: textOpacity,
              child: Text.rich(
                maxLines: 2,
                TextSpan(
                  text: '$label\n',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  children: [
                    TextSpan(
                      text: hex,
                      style: TextStyle(
                        color: onColor.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                style: TextStyle(color: onColor),
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: AnimatedSwitcher(
              duration: kFastAnimation,
              child: badge == null
                  ? const SizedBox.shrink()
                  : CircleAvatar(
                      key: ValueKey(badge),
                      radius: 12,
                      backgroundColor: onColor.withValues(alpha: 0.16),
                      child: Icon(badge, size: 14, color: onColor),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
