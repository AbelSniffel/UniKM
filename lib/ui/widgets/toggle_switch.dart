/// Theme-colored toggle switches with sliding and dot styles
/// Matches the original Python toggle switch styles
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unikm/core/constants/app_constants.dart';

import '../../core/settings/settings_model.dart';
import 'hover_builder.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';

double _resolveToggleRadius({
  required AppThemeData theme,
  required double extent,
  required bool useThemeToggleRadius,
}) {
  if (!useThemeToggleRadius) return extent / 2;
  return theme.cornerRadius.clamp(0.0, extent / 2);
}

/// Custom toggle switch with multiple styles
class AppToggleSwitch extends ConsumerWidget {
  static const double _regularSwitchWidth = 50.0;
  static const double _regularSwitchHeight = kElementHeight;
  const AppToggleSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.theme,
    this.style,
    this.label,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final AppThemeData theme;

  /// Optional override. When null, uses the global `SettingsKeys.toggleStyle`.
  final ToggleStyle? style;
  final String? label;

  /// Whether the toggle is disabled (onChanged is null)
  bool get isDisabled => onChanged == null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ToggleStyle effectiveStyle = style ?? ref.watch(toggleStyleProvider);

    final toggle = switch (effectiveStyle) {
      ToggleStyle.regular => SizedBox(
        width: _regularSwitchWidth,
        height: _regularSwitchHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_regularSwitchHeight / 2),
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.centerRight,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: theme.accent,
              inactiveThumbColor: theme.textHint,
              inactiveTrackColor: theme.surface,
              trackOutlineColor: WidgetStateProperty.resolveWith<Color?>(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.transparent
                    : theme.border,
              ),
              trackOutlineWidth: WidgetStateProperty.all(2),
            ),
          ),
        ),
      ),
      ToggleStyle.dot || ToggleStyle.morphDot => _DotToggle(
        value: value,
        onChanged: onChanged,
        theme: theme,
        useThemeToggleRadius: effectiveStyle == ToggleStyle.morphDot,
      ),
    };

    final displayLabel =
        label ??
        (isDisabled
            ? 'Disabled'
            : value
            ? 'On'
            : 'Off');
    if (displayLabel.isEmpty) return toggle;
    final labelStyle = TextStyle(
      fontWeight: FontWeight.w500,
      color: value && !isDisabled ? theme.accent : theme.textSecondary,
    );
    final labelWidget = isDisabled
        ? Text(displayLabel, style: labelStyle)
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onChanged?.call(!value),
              child: Text(displayLabel, style: labelStyle),
            ),
          );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [labelWidget, const SizedBox(width: 6), toggle],
    );
  }
}

class _DotToggle extends StatefulWidget {
  const _DotToggle({
    required this.value,
    required this.onChanged,
    required this.theme,
    required this.useThemeToggleRadius,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final AppThemeData theme;
  final bool useThemeToggleRadius;

  bool get isDisabled => onChanged == null;

  @override
  State<_DotToggle> createState() => _DotToggleState();
}

class _DotToggleState extends State<_DotToggle> with TickerProviderStateMixin {
  static const double _containerSize = kElementHeight;
  static const double _outerSize = 28.0;

  static const double _offDotSize = 14.0;
  static const double _offDotHoverSize = 17.0;
  static const double _onDotSize = 20.0;
  static const double _onDotHoverSize = 22.0;

  static const Duration _hoverDuration = Duration(milliseconds: 125);

  static const _springCurve = _OnSpringCurve();
  static const _reverseSpringCurve = _OffSpringCurve();

  late final AnimationController _toggleController;
  late final Animation<double> _toggleScale;
  late final AnimationController _hoverController;
  late final Animation<double> _hoverAnim;

  @override
  void initState() {
    super.initState();
    _toggleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 250),
      vsync: this,
      value: widget.value ? 1.0 : 0.0,
    );
    _toggleScale = CurvedAnimation(
      parent: _toggleController,
      curve: _springCurve,
      reverseCurve: _reverseSpringCurve,
    );
    _hoverController = AnimationController(
      duration: _hoverDuration,
      reverseDuration: _hoverDuration,
      vsync: this,
    );
    _hoverAnim = CurvedAnimation(
      parent: _hoverController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
  }

  @override
  void didUpdateWidget(covariant _DotToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      widget.value ? _toggleController.forward() : _toggleController.reverse();
    }
  }

  @override
  void dispose() {
    _toggleController.dispose();
    _hoverController.dispose();
    super.dispose();
  }

  void _toggle() => widget.onChanged?.call(!widget.value);

  double _dotRadius({
    required double toggleLinear,
    required double toggleSpring,
    required double hoverProgress,
  }) {
    const double offRestRadius = _offDotSize / 2;
    const double onRestRadius = _onDotSize / 2;
    const double offHoverDelta = (_offDotHoverSize - _offDotSize) / 2;
    const double onHoverDelta = (_onDotHoverSize - _onDotSize) / 2;

    final double t = toggleLinear.clamp(0.0, 1.0);
    final double baseRadius =
        offRestRadius + (onRestRadius - offRestRadius) * toggleSpring;
    final double hoverDelta =
        offHoverDelta + (onHoverDelta - offHoverDelta) * t;
    return (baseRadius + hoverDelta * hoverProgress).clamp(
      0.5,
      double.infinity,
    );
  }

  Color _dotColor({
    required Color offColorBase,
    required double toggleLinear,
    required double hoverProgress,
    required double opacity,
  }) {
    final double t = toggleLinear.clamp(0.0, 1.0);
    final double colorProgress = hoverProgress + (1.0 - hoverProgress) * t;
    const double offRestAlpha = 0.85;
    final double stateAlpha =
        1.0 - ((1.0 - offRestAlpha) * (1.0 - t) * (1.0 - hoverProgress));
    return Color.lerp(
      offColorBase,
      widget.theme.accent,
      colorProgress,
    )!.withValues(alpha: (opacity * stateAlpha).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final double opacity = widget.isDisabled ? 0.4 : 1.0;
    final offColorBase = Color.alphaBlend(
      widget.theme.textHint,
      widget.theme.surface,
    );

    return HoverBuilder(
      enabled: !widget.isDisabled,
      cursor: SystemMouseCursors.click,
      onEnter: () => _hoverController.forward(),
      onExit: () => _hoverController.reverse(),
      builder: (context, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: SizedBox(
          width: _containerSize,
          height: _containerSize,
          child: AnimatedBuilder(
            animation: Listenable.merge([_toggleController, _hoverController]),
            builder: (context, _) {
              final double hoverProgress = widget.isDisabled
                  ? 0.0
                  : _hoverAnim.value;
              final double toggleLinear = _toggleController.value;
              final double toggleSpring = _toggleScale.value;
              final double dotRadius = _dotRadius(
                toggleLinear: toggleLinear,
                toggleSpring: toggleSpring,
                hoverProgress: hoverProgress,
              );
              final Color dotColor = _dotColor(
                offColorBase: offColorBase,
                toggleLinear: toggleLinear,
                hoverProgress: hoverProgress,
                opacity: opacity,
              );

              // Centralized constants for easy tuning
              const double offBorderAlphaDefault = 0.20;
              const double onBorderAlphaDefault = 0.0;
              const double borderAlphaMin = 0.05;
              const double borderAlphaMax = 0.4;

              // The border reaches onBorderAlphaDefault fully at the ON state.
              final double onProgress = toggleSpring.clamp(0.0, 1.0);
              final double offBorderAlpha =
                  (offBorderAlphaDefault - 0.15 * hoverProgress).clamp(
                    borderAlphaMin,
                    borderAlphaMax,
                  );
              final double borderAlpha =
                  ((1.0 - onProgress) * offBorderAlpha +
                          onProgress * onBorderAlphaDefault)
                      .clamp(borderAlphaMin, borderAlphaMax);

              // Simple background alpha workflow with fixed reference values.
              const double offBackgroundAlpha = 0.0;
              const double onBackgroundAlpha = 0.45;
              const double hoverBackgroundAlpha = 0.25;

              final double backgroundAlphaFinal = widget.value
                  ? onBackgroundAlpha
                  : (offBackgroundAlpha + hoverProgress * hoverBackgroundAlpha)
                        .clamp(0.0, 1.0);
              final outerRadius = _resolveToggleRadius(
                theme: widget.theme,
                extent: _outerSize,
                useThemeToggleRadius: widget.useThemeToggleRadius,
              );
              final dotDiameter = dotRadius * 2;
              final dotShapeRadius = _resolveToggleRadius(
                theme: widget.theme,
                extent: dotDiameter,
                useThemeToggleRadius: widget.useThemeToggleRadius,
              );

              final Color backgroundColor = widget.theme.accent.withValues(
                alpha: backgroundAlphaFinal,
              );

              return Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: _outerSize,
                    height: _outerSize,
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(outerRadius),
                      border: Border.all(
                        color: widget.theme.border.withValues(
                          alpha: borderAlpha,
                        ),
                        width: 1.5,
                      ),
                    ),
                  ),
                  if (dotRadius > 0)
                    SizedBox(
                      width: dotDiameter,
                      height: dotDiameter,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: dotColor,
                          borderRadius: BorderRadius.circular(dotShapeRadius),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OffSpringCurve extends Curve {
  const _OffSpringCurve();

  static const double _peakV = 0.35;
  static const double _undershootD = -0.20;

  @override
  double transformInternal(double t) {
    if (t >= _peakV) {
      final double p = (t - _peakV) / (1.0 - _peakV);
      return _undershootD + (1.0 - _undershootD) * p * p;
    }
    final double q = 1.0 - t / _peakV;
    final double s = q * q * (3.0 - 2.0 * q);
    return _undershootD * (1.0 - s);
  }
}

class _OnSpringCurve extends Curve {
  const _OnSpringCurve();

  static const double _peakT = 0.58;
  static const double _overshoot = 1.35;

  @override
  double transformInternal(double t) {
    if (t <= _peakT) {
      final double p = t / _peakT;
      final double eased = Curves.easeOutCubic.transform(p);
      return _overshoot * eased;
    }

    final double p = (t - _peakT) / (1.0 - _peakT);
    final double eased = Curves.easeOutCubic.transform(p);
    return _overshoot + (1.0 - _overshoot) * eased;
  }
}
