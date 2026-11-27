/// Theme editor dialog for creating and editing custom themes.
library;

import '../../../core/theme/theme_icons.dart';

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
class const ThemeEditorDialog({
  super.key,
  required final AppThemeData theme,
  final AppThemeData? existingTheme,
}) extends ConsumerStatefulWidget {
  /// Opens the editor from the nearest navigator's context. A settings page
  /// keeps its own copy of the app theme, which the route would otherwise
  /// take along, and the editor would not show its own live preview. The
  /// theme is read now, as the opener may be gone while the editor is open.
  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    AppThemeData? existing,
  }) {
    final theme = ref.read(themeProvider);
    return showAppDialog<void>(
      context: Navigator.of(context).context,
      builder: (_) => ThemeEditorDialog(theme: theme, existingTheme: existing),
    );
  }

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
  late double _cornerRadius;
  int? _selectedIconCodePoint;
  bool _isEditing = false;
  bool _saved = false;
  bool _previewScheduled = false;
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
    iconData: _selectedIconCodePoint != null
        ? themeIconFromCodePoint(_selectedIconCodePoint!)
        : null,
  );

  /// Previews at most once a frame while a slider is dragged, as the next
  /// frame begins: a preview rebuilds the whole app's theme, and pointer
  /// events can come several times a frame.
  void _throttledPreview() {
    if (_previewScheduled) return;
    _previewScheduled = true;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      _previewScheduled = false;
      _updatePreview();
    });
  }

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
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_saved) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _themeNotifier.cancelPreview(),
          );
        }
      },
      child: ThemedAlertDialog(
        title: DialogHeader(
          icon: _isEditing ? Icons.palette_outlined : Icons.add_circle_outline,
          title: _isEditing ? 'Theme Editor' : 'Create Theme',
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
                          border: previewTheme.resolveInputBorder(
                            labelInside: true,
                          ),
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
                  'Colors',
                  _buildColorCirclesRow(previewTheme),
                  trailing: 'Tap to edit · Drag to swap',
                ),
                // The selected tile's color, picked in place
                _buildActiveColorEditor(previewTheme),
                _buildCornerRadiusRow(previewTheme),
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
  static Widget _section(String title, Widget child, {String? trailing}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          TintedHeading(title: title, trailing: trailing),
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
    final to = dragRect(0)
        .shift(overlayBox.globalToLocal(tileBox.localToGlobal(Offset.zero)));

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

  /// The selected tile's color: its hue on a strip, saturation and
  /// brightness picked on an area below, then its hex code.
  Widget _buildActiveColorEditor(AppThemeData theme) {
    final activeColor = _hsvToColor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        _buildHueSlider(theme),
        _SaturationValueArea(
          hue: _hue,
          saturation: _saturation,
          value: _value,
          radius: theme.cornerRadius + _ColorSwatch.inset,
          onChanged: (saturation, value) => _applyHsvChange(() {
            _saturation = saturation;
            _value = value;
          }),
        ),
        // Hex input, led by a dot of the color, and randomize button
        Row(
          spacing: 6,
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
                buildCounter: (
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
      ],
    );
  }

  /// A rainbow strip whose handle takes the hue at full strength.
  Widget _buildHueSlider(AppThemeData theme) {
    Color hue(double h) => HSVColor.fromAHSV(1, h, 1, 1).toColor();
    final label = '${_hue.round()}°';
    return SliderTheme(
      data: _sliderTheme(theme).copyWith(
        // Spans the color area's width, its handle reaching the edges.
        padding: const EdgeInsets.symmetric(vertical: 8),
        showValueIndicator: ShowValueIndicator.onDrag,
        trackShape: AppSliderTrackShape(
          cornerRadius: theme.cornerRadius,
          colors: [for (var h = 0; h <= 360; h += 60) hue(h.toDouble())],
        ),
        thumbShape: AppSliderThumbShape(cornerRadius: theme.cornerRadius),
        thumbColor: hue(_hue),
        overlayColor: hue(_hue).withValues(alpha: 0.14),
      ),
      child: Slider(
        value: _hue,
        max: 360,
        label: label,
        semanticFormatterCallback: (_) => 'Hue $label',
        onChanged: (v) => _applyHsvChange(() => _hue = v),
      ),
    );
  }

  static SliderThemeData _sliderTheme(AppThemeData theme) =>
      buildAppSliderTheme(
        accent: theme.accent,
        disabledColor: theme.textSecondary,
        indicatorTextColor: contrastColor(theme.accent),
        cornerRadius: theme.cornerRadius,
      );

  // ---------------------------------------------------------------------------
  // Style
  // ---------------------------------------------------------------------------

  /// Roundness on one row, ending in its value.
  Widget _buildCornerRadiusRow(AppThemeData theme) {
    final radius = _cornerRadius.roundToDouble();
    final text = radius.toStringAsFixed(0);
    return Row(
      spacing: 0,
      children: [
        Text(
          'Roundness',
          style: TextStyle(
            color: theme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: _sliderTheme(theme),
            child: Slider(
              value: radius,
              min: _minCornerRadius,
              max: _maxCornerRadius,
              divisions: (_maxCornerRadius - _minCornerRadius).round(),
              label: text,
              onChanged: (value) {
                setState(() => _cornerRadius = value);
                _throttledPreview();
              },
            ),
          ),
        ),
        // Wide enough for two digits, so the slider never shifts.
        SizedBox(
          width: 24,
          child: Text(
            text,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
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
// Saturation and brightness area
// ---------------------------------------------------------------------------

/// Picks saturation (across) and brightness (up) for one [hue]. It claims a
/// pointer as it lands, so a touch drag picks instead of scrolling the dialog.
class const _SaturationValueArea({
  required final double hue,
  required final double saturation,
  required final double value,
  required final double radius,
  required final void Function(double saturation, double value) onChanged,
}) extends StatelessWidget {
  static const double height = 132;

  /// Keeps the handle inside the area at its edges.
  static const double thumbRadius = 9;

  void _pick(Offset position, double width) {
    double along(double offset, double extent) =>
        ((offset - thumbRadius) / (extent - 2 * thumbRadius)).clamp(0.0, 1.0);
    onChanged(along(position.dx, width), 1 - along(position.dy, height));
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Saturation and brightness',
    value:
        '${(saturation * 100).round()}% saturation, '
        '${(value * 100).round()}% brightness',
    child: MouseRegion(
      cursor: SystemMouseCursors.precise,
      child: LayoutBuilder(
        builder: (context, constraints) => RawGestureDetector(
          gestures: {
            EagerGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                  EagerGestureRecognizer.new,
                  (_) {},
                ),
          },
          child: Listener(
            onPointerDown: (e) => _pick(e.localPosition, constraints.maxWidth),
            onPointerMove: (e) => _pick(e.localPosition, constraints.maxWidth),
            child: CustomPaint(
              size: Size(constraints.maxWidth, height),
              painter: _SaturationValuePainter(
                hue: hue,
                saturation: saturation,
                value: value,
                radius: radius,
                border: context.appTheme.border,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class const _SaturationValuePainter({
  required final double hue,
  required final double saturation,
  required final double value,
  required final double radius,
  required final Color border,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    // Both gradients are flattened before the rounded clip edges them, so
    // the hue under the black never shows through the corners' soft edge.
    canvas
      ..save()
      ..clipRRect(shape)
      ..saveLayer(rect, Paint())
      ..drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [Colors.white, HSVColor.fromAHSV(1, hue, 1, 1).toColor()],
          ).createShader(rect),
      )
      ..drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Colors.black],
          ).createShader(rect),
      )
      ..restore()
      ..restore()
      ..drawRRect(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = border,
      );
    // A white ring edged in black reads on any color under it.
    const r = _SaturationValueArea.thumbRadius;
    final center = Offset(
      r + saturation * (size.width - 2 * r),
      r + (1 - value) * (size.height - 2 * r),
    );
    canvas
      ..drawCircle(center, r + 1, Paint()..color = const Color(0x66000000))
      ..drawCircle(center, r, Paint()..color = Colors.white)
      ..drawCircle(
        center,
        r - 2.5,
        Paint()..color = HSVColor.fromAHSV(1, hue, saturation, value).toColor(),
      );
  }

  @override
  bool shouldRepaint(_SaturationValuePainter old) =>
      old.hue != hue ||
      old.saturation != saturation ||
      old.value != value ||
      old.radius != radius ||
      old.border != border;
}

// ---------------------------------------------------------------------------
// Color swatch
// ---------------------------------------------------------------------------

/// A color slot's swatch with its name and hex code; also the drag feedback.
class const _ColorSwatch({
  required final Color color,
  required final String label,
  required final String hex,
  required final double radius,

  /// 0 at rest, 1 hovered, up to 2 while dragged; deepens the shadow.
  required final double lift,
  required final double textOpacity,
  required final IconData? badge,
  required final Duration duration,
}) extends StatelessWidget {
  /// Gap plus ring width between a tile's edge and its swatch.
  static const double inset = 5;
  static const double tileHeight = 94;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
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
