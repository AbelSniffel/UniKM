library;

import 'package:flutter/material.dart';

Future<T?> showAppMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  T? initialValue,
  Color? color,
  double? elevation,
  ShapeBorder? shape,
  BoxConstraints? constraints,
  AnimationStyle? popUpAnimationStyle,
}) {
  return showMenu<T>(
    context: context,
    position: position,
    items: items,
    initialValue: initialValue,
    color: color,
    elevation: elevation,
    shape: shape,
    constraints: constraints,
    popUpAnimationStyle: popUpAnimationStyle,
    clipBehavior: Clip.antiAlias,
  );
}