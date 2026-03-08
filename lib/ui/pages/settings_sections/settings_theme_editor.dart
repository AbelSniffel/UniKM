/// Theme editor dialog for creating and editing custom themes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/services/screen_color_picker_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/color_utils.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/notification_system.dart';

/// Theme editor dialog - for creating and editing custom themes
class ThemeEditorDialog extends ConsumerStatefulWidget {
  const ThemeEditorDialog({super.key, required this.theme, this.existingTheme});

  final AppThemeData theme;
  final AppThemeData? existingTheme;

  @override
  ConsumerState<ThemeEditorDialog> createState() => _ThemeEditorDialogState();
}

class _ThemeEditorDialogState extends ConsumerState<ThemeEditorDialog> {
  final _nameController = TextEditingController();

  final _availableColors = const [
    '#0F172A',
    '#1F2937',
    '#111827',
    '#0E7490',
    '#0F766E',
    '#1D4ED8',
    '#2563EB',
    '#7C3AED',
    '#C026D3',
    '#DC2626',
    '#EA580C',
    '#D97706',
    '#16A34A',
    '#059669',
    '#10B981',
    '#0891B2',
    '#14B8A6',
  ];

  /// Available icons for theme selection
  static const _availableIcons = [
    (Icons.palette, 'Palette'),
    (Icons.dark_mode, 'Dark Mode'),
    (Icons.light_mode, 'Light Mode'),
    (Icons.auto_awesome, 'Sparkle'),
    (Icons.wb_twilight, 'Twilight'),
    (Icons.water, 'Water'),
    (Icons.forest, 'Forest'),
    (Icons.local_fire_department, 'Fire'),
    (Icons.ac_unit, 'Snow'),
    (Icons.sunny, 'Sunny'),
    (Icons.nightlight, 'Night'),
    (Icons.star, 'Star'),
    (Icons.favorite, 'Heart'),
    (Icons.bolt, 'Bolt'),
    (Icons.diamond, 'Diamond'),
    (Icons.eco, 'Eco'),
  ];

  late String _backgroundHex;
  late String _primaryHex;
  late String _accentHex;
  late String _workingThemeId;
  int? _selectedIconCodePoint;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.existingTheme != null;
    _workingThemeId =
        widget.existingTheme?.id ?? AppThemeData.generateThemeId();

    if (widget.existingTheme != null) {
      _nameController.text = widget.existingTheme!.name;
      _backgroundHex = colorToHex(widget.existingTheme!.baseBackground);
      _primaryHex = colorToHex(widget.existingTheme!.basePrimary);
      _accentHex = colorToHex(widget.existingTheme!.baseAccent);
      _selectedIconCodePoint = widget.existingTheme!.iconData?.codePoint;
    } else {
      _backgroundHex = colorToHex(widget.theme.baseBackground);
      _primaryHex = colorToHex(widget.theme.basePrimary);
      _accentHex = colorToHex(widget.theme.baseAccent);
      _selectedIconCodePoint = widget.theme.icon.codePoint;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _updatePreview() {
    final themeNotifier = ref.read(themeProvider.notifier);
    final previewTheme = AppThemeData(
      id: _workingThemeId,
      name: _nameController.text.isEmpty ? 'Preview' : _nameController.text,
      baseBackground: parseHexColor(_backgroundHex),
      basePrimary: parseHexColor(_primaryHex),
      baseAccent: parseHexColor(_accentHex),
      iconData: _selectedIconCodePoint != null
          ? IconData(_selectedIconCodePoint!, fontFamily: 'MaterialIcons')
          : null,
    );
    themeNotifier.startPreview(previewTheme);
  }

  void _swapPrimaryAndAccent() {
    setState(() {
      final previousPrimary = _primaryHex;
      _primaryHex = _accentHex;
      _accentHex = previousPrimary;
    });
    _updatePreview();
  }

  Widget _iconPickerRow({
    required String label,
    required int? selectedCodePoint,
    required ValueChanged<int?> onSelect,
  }) {
    final theme = ref.watch(themeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: theme.textSecondary, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _availableIcons.map((iconData) {
            final icon = iconData.$1;
            final tooltip = iconData.$2;
            final isSelected = icon.codePoint == selectedCodePoint;
            return Tooltip(
              message: tooltip,
              child: GestureDetector(
                onTap: () => onSelect(isSelected ? null : icon.codePoint),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.accent.withValues(alpha: 0.2)
                        : theme.surface,
                    borderRadius: BorderRadius.circular(theme.cornerRadius),
                    border: Border.all(
                      color: isSelected ? theme.accent : theme.border,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: isSelected ? theme.accent : theme.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _colorPickerRow({
    required String label,
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    final theme = ref.watch(themeProvider);
    final selectedColor = parseHexColor(selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(color: theme.textSecondary, fontSize: 12),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _openAdvancedColorPicker(
                label: label,
                currentColor: selectedColor,
                onColorSelected: onSelect,
              ),
              child: Container(
                width: 32,
                height: 20,
                decoration: BoxDecoration(
                  color: selectedColor,
                  borderRadius: BorderRadius.circular(theme.cornerRadius),
                  border: Border.all(color: theme.border, width: 1),
                ),
                child: Icon(
                  Icons.edit,
                  size: 12,
                  color: selectedColor.computeLuminance() > 0.5
                      ? Colors.black54
                      : Colors.white54,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '#${selected.toUpperCase().replaceFirst('#', '')}',
              style: TextStyle(
                color: theme.textSecondary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _availableColors.map((color) {
            final isSelected = color.toLowerCase() == selected.toLowerCase();
            return GestureDetector(
              onTap: () => onSelect(color),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: parseHexColor(color),
                  borderRadius: BorderRadius.circular(theme.cornerRadius),
                  border: Border.all(
                    color: isSelected ? theme.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _openAdvancedColorPicker({
    required String label,
    required Color currentColor,
    required ValueChanged<String> onColorSelected,
  }) {
    int red = (currentColor.r * 255.0).round();
    int green = (currentColor.g * 255.0).round();
    int blue = (currentColor.b * 255.0).round();
    double brightness = 1.0;
    final hexController = TextEditingController(
      text: colorToHex(currentColor).replaceFirst('#', ''),
    );

    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final theme = ref.watch(themeProvider);

            Color applyBrightness(int r, int g, int b, double factor) {
              final newR = (r * factor).clamp(0, 255).round();
              final newG = (g * factor).clamp(0, 255).round();
              final newB = (b * factor).clamp(0, 255).round();
              return Color.fromARGB(255, newR, newG, newB);
            }

            final previewColor = applyBrightness(red, green, blue, brightness);

            void updateFromSliders() {
              final adjusted = applyBrightness(red, green, blue, brightness);
              hexController.text =
                  ((adjusted.r * 255.0).round())
                      .toRadixString(16)
                      .padLeft(2, '0') +
                  ((adjusted.g * 255.0).round())
                      .toRadixString(16)
                      .padLeft(2, '0') +
                  ((adjusted.b * 255.0).round())
                      .toRadixString(16)
                      .padLeft(2, '0');
            }

            void updateFromHex(String hex) {
              final sanitized = hex.replaceFirst('#', '');
              if (sanitized.length == 6) {
                final parsed = int.tryParse(sanitized, radix: 16);
                if (parsed != null) {
                  setState(() {
                    red = (parsed >> 16) & 0xFF;
                    green = (parsed >> 8) & 0xFF;
                    blue = parsed & 0xFF;
                    brightness = 1.0;
                  });
                }
              }
            }

            return AlertDialog(
              backgroundColor: theme.background,
              title: Row(
                children: [
                  Text(
                    'Pick $label Color',
                    style: TextStyle(color: theme.textPrimary),
                  ),
                  const Spacer(),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: previewColor,
                      borderRadius: BorderRadius.circular(theme.cornerRadius),
                      border: Border.all(color: theme.border, width: 2),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: hexController,
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontFamily: 'monospace',
                      ),
                      decoration: InputDecoration(
                        labelText: 'Hex Color',
                        labelStyle: TextStyle(color: theme.textSecondary),
                        prefixText: '# ',
                        prefixStyle: TextStyle(color: theme.textSecondary),
                        suffixIcon: IconButton(
                          tooltip: 'Pick from screen (Esc to cancel)',
                          icon: Icon(
                            Icons.colorize,
                            color: theme.textSecondary,
                          ),
                          onPressed: () async {
                            final result =
                                await ScreenColorPickerService.pickColor();
                            await windowManager.show();
                            await windowManager.focus();

                            if (!context.mounted) {
                              return;
                            }

                            if (result.wasCancelled) {
                              return;
                            }

                            final picked = result.color;
                            if (picked == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Unable to capture screen color. Click anywhere on your screen after pressing the picker button.',
                                  ),
                                  backgroundColor: theme.basePrimary,
                                ),
                              );
                              return;
                            }

                            setState(() {
                              red = (picked.r * 255.0).round();
                              green = (picked.g * 255.0).round();
                              blue = (picked.b * 255.0).round();
                              brightness = 1.0;
                            });
                            updateFromSliders();
                          },
                        ),
                        filled: true,
                        fillColor: theme.inputBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            theme.cornerRadius,
                          ),
                        ),
                      ),
                      maxLength: 6,
                      onChanged: updateFromHex,
                    ),
                    const SizedBox(height: 16),
                    _buildColorSlider(
                      label: 'Red',
                      value: red,
                      color: Colors.red,
                      theme: theme,
                      onChanged: (value) {
                        setState(() => red = value);
                        updateFromSliders();
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildColorSlider(
                      label: 'Green',
                      value: green,
                      color: Colors.green,
                      theme: theme,
                      onChanged: (value) {
                        setState(() => green = value);
                        updateFromSliders();
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildColorSlider(
                      label: 'Blue',
                      value: blue,
                      color: Colors.blue,
                      theme: theme,
                      onChanged: (value) {
                        setState(() => blue = value);
                        updateFromSliders();
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildBrightnessSlider(
                      label: 'Brightness',
                      value: brightness,
                      theme: theme,
                      onChanged: (value) {
                        setState(() => brightness = value);
                        updateFromSliders();
                      },
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Quick Picks',
                      style: TextStyle(
                        color: theme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ...[
                          'FF0000',
                          'FF6600',
                          'FFCC00',
                          'FFFF00',
                          '99FF00',
                          '00FF00',
                          '00FF99',
                          '00FFFF',
                          '0099FF',
                          '0000FF',
                          '6600FF',
                          'CC00FF',
                          'FF00FF',
                          'FF0099',
                          'FF6699',
                          '000000',
                          '333333',
                          '666666',
                          '999999',
                          'CCCCCC',
                          'FFFFFF',
                          '1A1A2E',
                          '16213E',
                          '0F3460',
                          '533483',
                        ].map(
                          (hex) => GestureDetector(
                            onTap: () {
                              final parsed = int.parse(hex, radix: 16);
                              setState(() {
                                red = (parsed >> 16) & 0xFF;
                                green = (parsed >> 8) & 0xFF;
                                blue = parsed & 0xFF;
                                brightness = 1.0;
                              });
                              updateFromSliders();
                            },
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: Color(int.parse('FF$hex', radix: 16)),
                                borderRadius: BorderRadius.circular(
                                  theme.cornerRadius,
                                ),
                                border: Border.all(
                                  color: theme.border.withValues(alpha: 0.5),
                                  width: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: theme.textSecondary),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    final hex = hexController.text.replaceFirst('#', '');
                    onColorSelected(hex.toLowerCase());
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.accent,
                  ),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildColorSlider({
    required String label,
    required int value,
    required Color color,
    required AppThemeData theme,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: TextStyle(color: theme.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: color,
              inactiveTrackColor: color.withValues(alpha: 0.3),
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.2),
              trackHeight: 8,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: value.toDouble(),
              min: 0,
              max: 255,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toString().padLeft(3),
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBrightnessSlider({
    required String label,
    required double value,
    required AppThemeData theme,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: TextStyle(color: theme.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.amber,
              inactiveTrackColor: Colors.amber.withValues(alpha: 0.3),
              thumbColor: Colors.amber,
              overlayColor: Colors.amber.withValues(alpha: 0.2),
              trackHeight: 8,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: value,
              min: 0.5,
              max: 1.5,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${(value * 100).round()}%',
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewTheme = ref.watch(themeProvider);

    return AlertDialog(
      backgroundColor: previewTheme.background,
      title: Row(
        children: [
          Text(
            _isEditing ? 'Edit Theme' : 'Create Custom Theme',
            style: TextStyle(color: previewTheme.textPrimary),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: previewTheme.accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(previewTheme.cornerRadius),
            ),
            child: Text(
              'LIVE PREVIEW',
              style: TextStyle(
                color: previewTheme.accent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                style: TextStyle(color: previewTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Theme name',
                  labelStyle: TextStyle(color: previewTheme.textSecondary),
                  filled: true,
                  fillColor: previewTheme.inputBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      previewTheme.cornerRadius,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _colorPickerRow(
                label: 'Background',
                selected: _backgroundHex,
                onSelect: (value) {
                  setState(() => _backgroundHex = value);
                  _updatePreview();
                },
              ),
              const SizedBox(height: 12),
              _colorPickerRow(
                label: 'Primary',
                selected: _primaryHex,
                onSelect: (value) {
                  setState(() => _primaryHex = value);
                  _updatePreview();
                },
              ),
              const SizedBox(height: 12),
              _colorPickerRow(
                label: 'Accent',
                selected: _accentHex,
                onSelect: (value) {
                  setState(() => _accentHex = value);
                  _updatePreview();
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _swapPrimaryAndAccent,
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text('Swap Primary/Accent'),
                  style: TextButton.styleFrom(
                    foregroundColor: previewTheme.textSecondary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _iconPickerRow(
                label: 'Theme Icon',
                selectedCodePoint: _selectedIconCodePoint,
                onSelect: (codePoint) {
                  setState(() => _selectedIconCodePoint = codePoint);
                  _updatePreview();
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(themeProvider.notifier).cancelPreview();
            });
          },
          child: Text(
            'Cancel',
            style: TextStyle(color: previewTheme.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: () async {
            final name = _nameController.text.trim();
            if (name.isEmpty) {
              NotificationManager.instance.warning('Please enter a theme name');
              return;
            }

            final customTheme = AppThemeData(
              id: _workingThemeId,
              name: name,
              baseBackground: parseHexColor(_backgroundHex),
              basePrimary: parseHexColor(_primaryHex),
              baseAccent: parseHexColor(_accentHex),
              iconData: _selectedIconCodePoint != null
                  ? IconData(
                      _selectedIconCodePoint!,
                      fontFamily: 'MaterialIcons',
                    )
                  : null,
            );

            await ref.read(themeProvider.notifier).saveCustomTheme(customTheme);
            NotificationManager.instance.success(
              _isEditing ? 'Theme "$name" updated' : 'Theme "$name" saved',
            );
            if (!context.mounted) return;
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(backgroundColor: previewTheme.accent),
          child: Text(_isEditing ? 'Update' : 'Save'),
        ),
      ],
    );
  }
}
