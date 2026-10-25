library;

import 'dart:math' as math;

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

/// The size an anchored menu may take: the screen less its insets and an 8px
/// margin on each side, capped at [max].
Size anchoredMenuSize(MediaQueryData media, Size max) => Size(
  math.min(
    max.width,
    math.max(0, media.size.width - media.padding.horizontal - 16),
  ),
  math.min(
    max.height,
    math.max(
      0,
      media.size.height -
          media.padding.vertical -
          media.viewInsets.vertical -
          16,
    ),
  ),
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
