/// The app's toggle switch: a dot in a round frame that springs open when on.
library;

import 'package:flutter/material.dart';
import 'package:unikm/core/constants/app_constants.dart';

import 'hover_builder.dart';
import '../../core/theme/app_theme.dart';

/// A dot toggle with an optional state word before it ("On", "Off" or
/// "Disabled" by default; an empty [label] shows the dot alone).
class AppToggleSwitch extends StatefulWidget {
  const AppToggleSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.theme,
    this.label,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final AppThemeData theme;
  final String? label;

  /// Whether the toggle is disabled (onChanged is null)
  bool get isDisabled => onChanged == null;

  @override
  State<AppToggleSwitch> createState() => _AppToggleSwitchState();
}

class _AppToggleSwitchState extends State<AppToggleSwitch>
    with TickerProviderStateMixin {
  static const double _outerSize = 28.0;

  static const double _offDotSize = 14.0;
  static const double _offDotHoverSize = 17.0;
  static const double _onDotSize = 20.0;
  static const double _onDotHoverSize = 22.0;

  static const Duration _hoverDuration = Duration(milliseconds: 125);

  late final AnimationController _toggleController = AnimationController(
    duration: const Duration(milliseconds: 300),
    reverseDuration: const Duration(milliseconds: 250),
    vsync: this,
    value: widget.value ? 1.0 : 0.0,
  );
  late final Animation<double> _toggleScale = CurvedAnimation(
    parent: _toggleController,
    curve: const _OnSpringCurve(),
    reverseCurve: const _OffSpringCurve(),
  );
  late final AnimationController _hoverController = AnimationController(
    duration: _hoverDuration,
    vsync: this,
  );
  late final Animation<double> _hoverAnim = CurvedAnimation(
    parent: _hoverController,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );

  @override
  void didUpdateWidget(covariant AppToggleSwitch oldWidget) {
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

  /// Springs from the off size to the on size, and grows a little on hover.
  double _dotRadius(double toggleLinear, double toggleSpring, double hover) {
    const offRadius = _offDotSize / 2;
    const onRadius = _onDotSize / 2;
    const offHoverDelta = (_offDotHoverSize - _offDotSize) / 2;
    const onHoverDelta = (_onDotHoverSize - _onDotSize) / 2;
    final hoverDelta =
        offHoverDelta + (onHoverDelta - offHoverDelta) * toggleLinear;
    final radius =
        offRadius + (onRadius - offRadius) * toggleSpring + hoverDelta * hover;
    return radius.clamp(0.5, double.infinity);
  }

  /// The accent while on or hovered, a faded hint colour at rest while off.
  Color _dotColor(Color offColor, double toggleLinear, double hover) {
    final progress = hover + (1.0 - hover) * toggleLinear;
    final alpha = 1.0 - 0.15 * (1.0 - toggleLinear) * (1.0 - hover);
    final opacity = widget.isDisabled ? 0.4 : 1.0;
    return Color.lerp(
      offColor,
      widget.theme.accent,
      progress,
    )!.withValues(alpha: (opacity * alpha).clamp(0.0, 1.0));
  }

  Widget _buildDot() {
    final theme = widget.theme;
    final offColor = Color.alphaBlend(theme.textHint, theme.surface);
    return HoverBuilder(
      enabled: !widget.isDisabled,
      cursor: SystemMouseCursors.click,
      onEnter: () => _hoverController.forward(),
      onExit: () => _hoverController.reverse(),
      builder: (context, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: SizedBox.square(
          dimension: kElementHeight,
          child: AnimatedBuilder(
            animation: Listenable.merge([_toggleController, _hoverController]),
            builder: (context, _) {
              final hover = widget.isDisabled ? 0.0 : _hoverAnim.value;
              final toggleLinear = _toggleController.value.clamp(0.0, 1.0);
              final toggleSpring = _toggleScale.value;
              final dotDiameter =
                  _dotRadius(toggleLinear, toggleSpring, hover) * 2;
              // The frame's outline fades out as the dot springs on.
              final onProgress = toggleSpring.clamp(0.0, 1.0);
              final borderAlpha = ((1.0 - onProgress) * (0.20 - 0.15 * hover))
                  .clamp(0.05, 0.4);
              final backgroundAlpha = widget.value ? 0.45 : 0.25 * hover;
              return Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: _outerSize,
                    height: _outerSize,
                    decoration: BoxDecoration(
                      color: theme.accent.withValues(alpha: backgroundAlpha),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.border.withValues(alpha: borderAlpha),
                        width: 1.5,
                      ),
                    ),
                  ),
                  SizedBox.square(
                    dimension: dotDiameter,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _dotColor(offColor, toggleLinear, hover),
                        shape: BoxShape.circle,
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

  @override
  Widget build(BuildContext context) {
    final dot = _buildDot();
    final disabled = widget.isDisabled;
    final label =
        widget.label ??
        (disabled
            ? 'Disabled'
            : widget.value
            ? 'On'
            : 'Off');
    if (label.isEmpty) return dot;
    final labelStyle = TextStyle(
      fontWeight: FontWeight.w500,
      color: widget.value && !disabled
          ? widget.theme.accent
          : widget.theme.textSecondary,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (disabled)
          Text(label, style: labelStyle)
        else
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _toggle,
              child: Text(label, style: labelStyle),
            ),
          ),
        const SizedBox(width: 6),
        dot,
      ],
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
