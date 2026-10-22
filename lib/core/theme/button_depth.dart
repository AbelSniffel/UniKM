import 'package:flutter/material.dart';

/// Shared depth lighting that follows each button's resolved Material shape.
ButtonStyle withButtonDepth(ButtonStyle base, {required bool outlined}) =>
    base.copyWith(
      elevation: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.disabled) ||
                states.contains(WidgetState.pressed)
            ? 0
            : outlined
            ? 0.5
            : 1,
      ),
      shadowColor: WidgetStatePropertyAll(
        Colors.black.withValues(alpha: outlined ? 0.12 : 0.18),
      ),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      backgroundBuilder: (context, states, child) => ButtonDepthLayer(
        outlined: outlined,
        pressed: states.contains(WidgetState.pressed),
        disabled: states.contains(WidgetState.disabled),
        shape: _resolveShape(context, states, base),
        textDirection: Directionality.of(context),
        child: base.backgroundBuilder?.call(context, states, child) ?? child,
      ),
    );

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
