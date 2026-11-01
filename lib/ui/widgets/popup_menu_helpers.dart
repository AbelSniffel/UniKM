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

/// The app's anchored dropdown menu: every dropdown, select card and toolbar
/// menu opens through this. [width] pins the menu to a fixed width (a select
/// control's own); otherwise it sizes to its items. It never outgrows the
/// screen, and scrolls past [maxHeight].
class AppMenuAnchor extends StatelessWidget {
  const AppMenuAnchor({
    super.key,
    required this.theme,
    required this.menuChildren,
    required this.builder,
    this.controller,
    this.childFocusNode,
    this.onOpen,
    this.onClose,
    this.alignment = Alignment.bottomLeft,
    this.alignmentOffset = const Offset(0, 4),
    this.width,
    this.maxHeight,
  });

  final AppThemeData theme;
  final List<Widget> menuChildren;
  final MenuAnchorChildBuilder builder;
  final MenuController? controller;
  final FocusNode? childFocusNode;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;

  /// Where the menu sits against its anchor; bottom aligns open downward.
  final Alignment alignment;
  final Offset alignmentOffset;
  final double? width;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final maxSize = anchoredMenuSize(
      MediaQuery.of(context),
      Size(width ?? double.infinity, maxHeight ?? double.infinity),
    );
    return MenuAnchor(
      controller: controller,
      childFocusNode: childFocusNode,
      onOpen: onOpen,
      onClose: onClose,
      animated: !MediaQuery.disableAnimationsOf(context),
      // A pinned width must size the menu itself, not an unconstrained box.
      crossAxisUnconstrained: width == null,
      clipBehavior: Clip.antiAlias,
      consumeOutsideTap: true,
      useRootOverlay: true,
      reservedPadding: const EdgeInsets.all(8),
      alignmentOffset: alignmentOffset,
      style: appMenuStyle(theme, alignment: alignment).copyWith(
        minimumSize: width == null
            ? null
            : WidgetStatePropertyAll(Size(maxSize.width, 0)),
        maximumSize: WidgetStatePropertyAll(maxSize),
      ),
      menuChildren: menuChildren,
      builder: builder,
    );
  }
}

/// An [AppMenuAnchor] item: the [selected] one is accent coloured and ticked,
/// and a null [onPressed] dims it.
Widget appMenuItem(
  AppThemeData theme, {
  Key? key,
  required Widget child,
  required VoidCallback? onPressed,
  Widget? leading,
  Widget? trailing,
  bool selected = false,
  Color? color,
}) {
  final textColor =
      color ??
      (onPressed == null
          ? theme.textHint
          : selected
          ? theme.accent
          : theme.textPrimary);
  return Builder(
    // Large text never pushes an item past a narrow screen.
    builder: (context) => MenuItemButton(
      key: key,
      style: MenuItemButton.styleFrom(
        maximumSize: Size(
          math.max(0, MediaQuery.sizeOf(context).width - 16),
          double.infinity,
        ),
      ),
      onPressed: onPressed,
      leadingIcon: leading == null
          ? null
          : IconTheme.merge(
              data: IconThemeData(color: color ?? theme.textPrimary),
              child: leading,
            ),
      trailingIcon:
          trailing ??
          (selected ? Icon(Icons.check, size: 18, color: theme.accent) : null),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: textColor),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        child: child,
      ),
    ),
  );
}

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

/// A popup menu position for [rect], given in global coordinates.
RelativeRect overlayMenuPosition(BuildContext context, Rect rect) =>
    RelativeRect.fromRect(
      rect,
      Offset.zero &
          (Overlay.of(context).context.findRenderObject()! as RenderBox).size,
    );

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
