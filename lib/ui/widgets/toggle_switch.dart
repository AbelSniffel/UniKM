/// Toggle switch widget with regular and dot styles
/// Matches the original Python toggle switch styles
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_model.dart';
import 'hover_builder.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';

/// Custom toggle switch with multiple styles
class AppToggleSwitch extends ConsumerWidget {
  static const double _visualScale = 0.80;
  const AppToggleSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.theme,
    this.style,
    this.label,
    this.labelPosition = ToggleLabelPosition.right,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final AppThemeData theme;
  /// Optional override. When null, uses the global `SettingsKeys.toggleStyle`.
  final ToggleStyle? style;
  final String? label;
  final ToggleLabelPosition labelPosition;

  /// Whether the toggle is disabled (onChanged is null)
  bool get isDisabled => onChanged == null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ToggleStyle effectiveStyle = style ?? ref.watch(toggleStyleProvider);

    final toggle = switch (effectiveStyle) {
      ToggleStyle.regular => Transform.scale(
          scale: _visualScale,
          alignment: Alignment.center,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: theme.accent,
            inactiveThumbColor: theme.textHint,
            inactiveTrackColor: theme.surface,
          ),
        ),
      ToggleStyle.dot => _DotToggle(
          value: value,
          onChanged: onChanged,
          theme: theme,
        ),
    }; 

    if (label == null) return toggle;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: labelPosition == ToggleLabelPosition.left
          ? [
              Text(
                label!,
                style: TextStyle(color: theme.textPrimary),
              ),
              SizedBox(width: 12 * _visualScale),
              toggle,
            ]
          : [
              toggle,
              SizedBox(width: 12 * _visualScale),
              Text(
                label!,
                style: TextStyle(color: theme.textPrimary),
              ),
            ],
    );
  }
}

class _DotToggle extends StatefulWidget {
  const _DotToggle({
    required this.value,
    required this.onChanged,
    required this.theme,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final AppThemeData theme;

  bool get isDisabled => onChanged == null;

  @override
  State<_DotToggle> createState() => _DotToggleState();
}

class _DotToggleState extends State<_DotToggle> {
  void _toggle() {
    if (widget.isDisabled) return;
    widget.onChanged?.call(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final trackColor = widget.value
        ? widget.theme.accent.withValues(alpha: widget.isDisabled ? 0.25 : 0.45)
        : widget.theme.surface;

    final borderColor = widget._borderColorFor(trackColor);

    final dotColor = widget.value
        ? widget.theme.accent
        : widget.theme.textHint;

    final dotBgColor = widget.theme.background;

    return HoverBuilder(
      enabled: !widget.isDisabled,
      builder: (context, hovered) => GestureDetector(
        onTap: _toggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 46 * AppToggleSwitch._visualScale,
          height: 24 * AppToggleSwitch._visualScale,
          padding: EdgeInsets.all(3 * AppToggleSwitch._visualScale),
          decoration: BoxDecoration(
            color: trackColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: hovered && !widget.isDisabled
                  ? widget.theme.accent.withValues(alpha: 0.6)
                  : borderColor,
            ),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            alignment: widget.value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 18 * AppToggleSwitch._visualScale,
              height: 18 * AppToggleSwitch._visualScale,
              decoration: BoxDecoration(
                color: dotBgColor,
                shape: BoxShape.circle,
                border: Border.all(color: dotColor.withValues(alpha: 0.8)),
              ),
              child: Center(
                child: Container(
                  width: 8 * AppToggleSwitch._visualScale,
                  height: 8 * AppToggleSwitch._visualScale,
                  decoration: BoxDecoration(
                    color: dotColor.withValues(alpha: widget.isDisabled ? 0.4 : 1),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension on _DotToggle {
  Color _borderColorFor(Color trackColor) {
    // Use a subtle border that still looks good on both dark/light themes.
    return theme.border;
  }
}

enum ToggleLabelPosition { left, right }
