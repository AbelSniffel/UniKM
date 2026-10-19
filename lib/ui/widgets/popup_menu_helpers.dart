library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Shared surface for anchored menus; placement remains specific to each button.
MenuStyle appMenuStyle(
  AppThemeData theme, {
  Alignment alignment = Alignment.bottomRight,
}) => MenuStyle(
  alignment: alignment,
  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
  visualDensity: VisualDensity.standard,
  backgroundColor: WidgetStatePropertyAll(theme.surface),
  surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
  elevation: const WidgetStatePropertyAll(8),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(theme.cornerRadius),
    ),
  ),
  side: WidgetStatePropertyAll(BorderSide(color: theme.border)),
);

/// Clips item feedback to the menu shape, which PopupMenuTheme cannot configure.
class AppPopupMenuButton<T> extends PopupMenuButton<T> {
  const AppPopupMenuButton({
    super.key,
    required super.itemBuilder,
    super.onSelected,
    super.initialValue,
    super.tooltip,
    super.child,
    super.icon,
    super.borderRadius,
    super.color,
    super.elevation,
    super.shape,
    super.constraints,
    super.popUpAnimationStyle,
  }) : super(clipBehavior: Clip.antiAlias, menuPadding: EdgeInsets.zero);
}

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
  final theme = Theme.of(context).extension<AppThemeData>();
  return showMenu<T>(
    context: context,
    position: position,
    items: items,
    menuPadding: EdgeInsets.zero,
    initialValue: initialValue,
    color: color ?? theme?.surface,
    elevation: elevation,
    shape:
        shape ??
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(theme?.cornerRadius ?? 12),
        ),
    constraints: constraints,
    popUpAnimationStyle: popUpAnimationStyle,
    clipBehavior: Clip.antiAlias,
  );
}
