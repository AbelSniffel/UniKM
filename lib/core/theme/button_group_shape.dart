import 'package:flutter/material.dart';

/// Only the edges at the ends of a connected group have rounded corners.
BorderRadius buttonGroupBorderRadius({
  required int index,
  required int count,
  required double radius,
  required TextDirection textDirection,
  Axis axis = Axis.horizontal,
}) {
  final first = index == 0;
  final last = index == count - 1;
  final corner = Radius.circular(radius);
  if (axis == Axis.vertical) {
    return BorderRadius.vertical(
      top: first ? corner : Radius.zero,
      bottom: last ? corner : Radius.zero,
    );
  }
  return BorderRadiusDirectional.only(
    topStart: first ? corner : Radius.zero,
    bottomStart: first ? corner : Radius.zero,
    topEnd: last ? corner : Radius.zero,
    bottomEnd: last ? corner : Radius.zero,
  ).resolve(textDirection);
}

/// Supplies the same group geometry to a button's surface and interaction ink.
class ButtonGroupShape extends InheritedWidget {
  const ButtonGroupShape({
    super.key,
    required this.borderRadius,
    required super.child,
  });

  final BorderRadius borderRadius;

  static BorderRadius? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ButtonGroupShape>()
      ?.borderRadius;

  @override
  bool updateShouldNotify(ButtonGroupShape oldWidget) =>
      borderRadius != oldWidget.borderRadius;
}
