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
  static const double _regularSwitchWidth = 50.0;
  static const double _regularSwitchHeight = 30.0;
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
      ToggleStyle.regular => SizedBox(
          width: _regularSwitchWidth,
          height: _regularSwitchHeight,
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
      ToggleStyle.dot => _DotToggle(
          value: value,
          onChanged: onChanged,
          theme: theme,
        ),
    };

    if (label == null) return toggle;

    final labelText = Text(label!, style: TextStyle(color: theme.textPrimary));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: labelPosition == ToggleLabelPosition.left
          ? [labelText, const SizedBox(width: 12), toggle]
          : [toggle, const SizedBox(width: 12), labelText],
    );
  }
}

/// Draws a centered, anti-aliased filled circle using [Canvas.drawCircle].
/// Unlike [BoxDecoration] with [BoxShape.circle], this guarantees smooth edges
/// at all radii including sub-pixel and very small values.
class _CirclePainter extends CustomPainter {
  const _CirclePainter({required this.radius, required this.color});
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (radius <= 0) return;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      radius,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_CirclePainter old) =>
      old.radius != radius || old.color != color;
}

enum ToggleLabelPosition { left, right }

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

class _DotToggleState extends State<_DotToggle>
    with TickerProviderStateMixin {
  static const double _containerSize = 26.0;
  static const double _outerSize = 26.0;

  static const double _offDotSize = 12.0;
  static const double _offDotHoverSize = 14.0;
  static const double _onDotSize = 17.0;
  static const double _onDotHoverSize = 19.0;

  // speed factors for border/background relative to dot animation.
  // 1.0 = same speed as dot; <1.0 = slower; >1.0 = faster.
  static const double _borderSyncFactor = 0.6;
  static const double _backgroundSyncFactor = 0.6;

  static const Duration _hoverDuration = Duration(milliseconds: 125);

  static const _springCurve = Cubic(0.3, 1.5, 0.7, 1.0);
  static const _reverseSpringCurve = _OffSpringCurve();

  late final AnimationController _toggleController;
  late final Animation<double> _toggleScale;
  late final AnimationController _hoverController;
  late final Animation<double> _hoverAnim;

  @override
  void initState() {
    super.initState();
    _toggleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 200),
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

  void _toggle() {
    if (widget.isDisabled) return;
    widget.onChanged?.call(!widget.value);
  }

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
    final double hoverDelta = offHoverDelta + (onHoverDelta - offHoverDelta) * t;
    return (baseRadius + hoverDelta * hoverProgress).clamp(0.5, double.infinity);
  }

  Color _dotColor({
    required Color offColorBase,
    required double toggleLinear,
    required double hoverProgress,
    required double opacity,
  }) {
    final double t = toggleLinear.clamp(0.0, 1.0);
    final double colorProgress = hoverProgress + (1.0 - hoverProgress) * t;
    const double offRestAlpha = 0.65;
    final double stateAlpha =
        1.0 - ((1.0 - offRestAlpha) * (1.0 - t) * (1.0 - hoverProgress));
    return Color.lerp(offColorBase, widget.theme.accent, colorProgress)!
        .withValues(alpha: (opacity * stateAlpha).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final double opacity = widget.isDisabled ? 0.4 : 1.0;
    final offColorBase =
        Color.alphaBlend(widget.theme.textHint, widget.theme.surface);

    return HoverBuilder(
      enabled: !widget.isDisabled,
      cursor: SystemMouseCursors.click,
      onEnter: () => _hoverController.forward(),
      onExit: () => _hoverController.reverse(),
      builder: (context, _) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: SizedBox(
            width: _containerSize,
            height: _containerSize,
            child: AnimatedBuilder(
              animation:
                  Listenable.merge([_toggleController, _hoverController]),
              builder: (context, _) {
                final double hoverProgress =
                    widget.isDisabled ? 0.0 : _hoverAnim.value;
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

                final double switchProgress = toggleSpring.clamp(0.0, 1.0);
                final double rawBorderProgress = (switchProgress * _borderSyncFactor).clamp(0.0, 1.0);
                final double rawBackgroundProgress = (switchProgress * _backgroundSyncFactor).clamp(0.0, 1.0);
                final double borderProgress = Curves.easeInOut.transform(rawBorderProgress);
                final double backgroundProgress =
                    Curves.easeInOut.transform(rawBackgroundProgress);

                final double offBorderAlpha = (0.20 - 0.14 * hoverProgress).clamp(0.0, 0.4);
                final double borderAlpha = (offBorderAlpha * (1.0 - borderProgress)).clamp(0.0, 0.4);

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: _outerSize,
                      height: _outerSize,
                      decoration: BoxDecoration(
                        color: Color.lerp(
                          Color.lerp(
                            Colors.transparent,
                            widget.theme.accent.withValues(alpha: 0.40),
                            backgroundProgress,
                          ),
                          widget.theme.accent.withValues(alpha: 0.25),
                          hoverProgress * (1.0 - backgroundProgress),
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.theme.border.withValues(alpha: borderAlpha),
                          width: 1.5,
                        ),
                      ),
                    ),
                    if (dotRadius > 0)
                      CustomPaint(
                        size: const Size(_outerSize, _outerSize),
                        painter: _CirclePainter(radius: dotRadius, color: dotColor),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
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
    } else {
      final double q = 1.0 - t / _peakV;
      final double s = q * q * (3.0 - 2.0 * q);
      return _undershootD * (1.0 - s);
    }
  }
}
