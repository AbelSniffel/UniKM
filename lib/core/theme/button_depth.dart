import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// Shared depth lighting that follows each button's resolved Material shape.
ButtonStyle withButtonDepth(ButtonStyle base, {required bool outlined}) =>
    outlined ? _withOutlinedDepth(base) : _withElevatedDepth(base);

ButtonStyle _withOutlinedDepth(ButtonStyle base) => base.copyWith(
  elevation: WidgetStateProperty.resolveWith(
    (states) =>
        states.contains(WidgetState.disabled) ||
            states.contains(WidgetState.pressed)
        ? 0
        : 0.5,
  ),
  shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.12)),
  surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
  backgroundBuilder: (context, states, child) => ButtonDepthLayer(
    outlined: true,
    pressed: states.contains(WidgetState.pressed),
    disabled: states.contains(WidgetState.disabled),
    shape: _resolveShape(context, states, base),
    textDirection: Directionality.of(context),
    child: base.backgroundBuilder?.call(context, states, child) ?? child,
  ),
);

const _elevatedShadowColor = Color(0x2E000000); // Black at 18%.
const _disabledState = {WidgetState.disabled};

/// Material snaps its fill color and, when an opaque fill turns translucent,
/// holds the old fill until its elevation settles. Elevated buttons therefore
/// paint fill, shadow and label colors themselves and fade them together.
/// Colors resolve live, so theme switches still apply immediately.
ButtonStyle _withElevatedDepth(ButtonStyle base) {
  ButtonStyle? local(BuildContext context) => switch (context.widget) {
    final ButtonStyleButton button => button.style,
    _ => null,
  };
  // Per-button colors win over the theme, matching ButtonStyleButton.
  (Color?, Color?) resolve(
    Set<WidgetState> states,
    WidgetStateProperty<Color?>? Function(ButtonStyle style) pick,
    ButtonStyle? style,
  ) {
    Color? at(Set<WidgetState> s) =>
        (style == null ? null : pick(style)?.resolve(s)) ??
        pick(base)?.resolve(s);
    return (
      at(states.difference(_disabledState)),
      at(states.union(_disabledState)),
    );
  }

  return base.copyWith(
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    foregroundBuilder: (context, states, child) {
      final style = local(context);
      final (text, disabledText) = resolve(
        states,
        (s) => s.foregroundColor,
        style,
      );
      final (icon, disabledIcon) = resolve(
        states,
        (s) => s.iconColor ?? s.foregroundColor,
        style,
      );
      return _AnimatedButtonForeground(
        disabled: states.contains(WidgetState.disabled),
        text: text,
        disabledText: disabledText,
        icon: icon,
        disabledIcon: disabledIcon,
        child: child!,
      );
    },
    backgroundBuilder: (context, states, child) {
      final style = local(context);
      final (fill, disabledFill) = resolve(
        states,
        (s) => s.backgroundColor,
        style,
      );
      final shape = _resolveShape(context, states, base);
      final textDirection = Directionality.of(context);
      return _AnimatedButtonSurface(
        disabled: states.contains(WidgetState.disabled),
        pressed: states.contains(WidgetState.pressed),
        fill: fill,
        disabledFill: disabledFill,
        // A per-button elevation keeps Material's own shadow.
        shadow: style?.elevation == null,
        shape: shape,
        textDirection: textDirection,
        child: ButtonDepthLayer(
          outlined: false,
          pressed: states.contains(WidgetState.pressed),
          disabled: states.contains(WidgetState.disabled),
          shape: shape,
          textDirection: textDirection,
          child: base.backgroundBuilder?.call(context, states, child) ?? child,
        ),
      );
    },
  );
}

OutlinedBorder _resolveShape(
  BuildContext context,
  Set<WidgetState> states,
  ButtonStyle base,
) {
  // The layer builder receives the button's own context. Respect local shape
  // overrides and the live button theme, including connected button edges.
  final button = context.widget;
  if (button is ButtonStyleButton) {
    final themedStyle = switch (button) {
      ElevatedButton() => ElevatedButtonTheme.of(context).style,
      OutlinedButton() => OutlinedButtonTheme.of(context).style,
      _ => base,
    };
    return button.style?.shape?.resolve(states) ??
        themedStyle?.shape?.resolve(states) ??
        const StadiumBorder();
  }
  return base.shape?.resolve(states) ?? const StadiumBorder();
}

/// Raised lighting that can stay mounted while a toggle shows inset lighting.
class ButtonDepthLayer extends StatelessWidget {
  const ButtonDepthLayer({
    super.key,
    required this.outlined,
    required this.pressed,
    required this.disabled,
    required this.shape,
    required this.textDirection,
    required this.child,
  });

  final bool outlined;
  final bool pressed;
  final bool disabled;
  final OutlinedBorder shape;
  final TextDirection textDirection;
  final Widget? child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(
      end: disabled
          ? 0
          : pressed
          ? -0.45
          : 1,
    ),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 110),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (_, depth, child) => CustomPaint(
      painter: depth == 0
          ? null
          : _ButtonDepthPainter(depth, outlined, shape, textDirection),
      child: child,
    ),
  );
}

/// Inexpensive translucent lighting painted inside the live button outline.
class _ButtonDepthPainter extends CustomPainter {
  const _ButtonDepthPainter(
    this.depth,
    this.outlined,
    this.shape,
    this.textDirection,
  );

  final double depth;
  final bool outlined;
  final OutlinedBorder shape;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final strength = depth.abs();
    final light = Colors.white.withValues(
      alpha: (outlined ? 0.06 : 0.10) * strength,
    );
    final shadow = Colors.black.withValues(
      alpha: (outlined ? 0.08 : 0.12) * strength,
    );
    canvas.drawPath(
      shape.getOuterPath(rect, textDirection: textDirection),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            depth > 0 ? light : shadow,
            (depth > 0 ? Colors.white : Colors.black).withValues(alpha: 0),
            (depth > 0 ? Colors.black : Colors.white).withValues(alpha: 0),
            depth > 0 ? shadow : light,
          ],
          stops: const [0, 0.28, 0.70, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_ButtonDepthPainter oldDelegate) =>
      oldDelegate.depth != depth ||
      oldDelegate.outlined != outlined ||
      oldDelegate.shape != shape ||
      oldDelegate.textDirection != textDirection;
}

Duration _fade(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

/// Fades label and icon colors between their enabled and disabled values.
class _AnimatedButtonForeground extends StatelessWidget {
  const _AnimatedButtonForeground({
    required this.disabled,
    required this.text,
    required this.disabledText,
    required this.icon,
    required this.disabledIcon,
    required this.child,
  });

  final bool disabled;
  final Color? text;
  final Color? disabledText;
  final Color? icon;
  final Color? disabledIcon;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: disabled ? 0 : 1),
    duration: _fade(context, kFastAnimation),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (context, enabled, child) => DefaultTextStyle.merge(
      style: TextStyle(color: Color.lerp(disabledText, text, enabled)),
      child: IconTheme.merge(
        data: IconThemeData(color: Color.lerp(disabledIcon, icon, enabled)),
        child: child!,
      ),
    ),
  );
}

/// Fill on the Material's ink layer, so splashes stay visible above it, and
/// the elevation shadow painted only outside the outline, so it never shows
/// through a translucent disabled fill.
class _AnimatedButtonSurface extends StatelessWidget {
  const _AnimatedButtonSurface({
    required this.disabled,
    required this.pressed,
    required this.fill,
    required this.disabledFill,
    required this.shadow,
    required this.shape,
    required this.textDirection,
    required this.child,
  });

  final bool disabled;
  final bool pressed;
  final Color? fill;
  final Color? disabledFill;
  final bool shadow;
  final OutlinedBorder shape;
  final TextDirection textDirection;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: disabled ? 0 : 1),
    duration: _fade(context, kFastAnimation),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (context, enabled, child) => TweenAnimationBuilder<double>(
      // Matches Material's implicit elevation animation.
      tween: Tween(end: shadow && !disabled && !pressed ? 1 : 0),
      duration: _fade(context, kThemeChangeDuration),
      curve: Curves.fastOutSlowIn,
      child: Ink(
        decoration: ShapeDecoration(
          color: Color.lerp(disabledFill, fill, enabled),
          shape: shape,
        ),
        child: child,
      ),
      builder: (context, elevation, child) => CustomPaint(
        painter: elevation == 0
            ? null
            : _ButtonShadowPainter(elevation, shape, textDirection),
        child: child,
      ),
    ),
  );
}

class _ButtonShadowPainter extends CustomPainter {
  const _ButtonShadowPainter(this.elevation, this.shape, this.textDirection);

  final double elevation;
  final OutlinedBorder shape;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outline = shape.getOuterPath(rect, textDirection: textDirection);
    canvas
      ..save()
      ..clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(rect.inflate(16))
          ..addPath(outline, Offset.zero),
      )
      ..drawShadow(outline, _elevatedShadowColor, elevation, true)
      ..restore();
  }

  @override
  bool shouldRepaint(_ButtonShadowPainter oldDelegate) =>
      oldDelegate.elevation != elevation ||
      oldDelegate.shape != shape ||
      oldDelegate.textDirection != textDirection;
}
