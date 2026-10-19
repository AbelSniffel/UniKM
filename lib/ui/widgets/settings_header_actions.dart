import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/button_group_shape.dart';

/// Shared sizing and decoration for settings header action groups.
class SettingsHeaderActions extends StatelessWidget {
  const SettingsHeaderActions({
    super.key,
    required this.theme,
    required this.children,
    this.encapsulated = true,
    this.expanded = false,
  });

  final AppThemeData theme;
  final List<Widget> children;
  final bool encapsulated;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final actions = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        for (final (index, child) in children.indexed)
          if (expanded)
            Expanded(child: _groupButton(context, index, child))
          else
            _groupButton(context, index, child),
      ],
    );
    if (!encapsulated) return actions;
    return Container(
      decoration: BoxDecoration(
        color: theme.buttonGroupBackground,
        borderRadius: BorderRadius.circular(theme.cornerRadius * 1.25),
      ),
      child: actions,
    );
  }

  Widget _groupButton(BuildContext context, int index, Widget child) =>
      ButtonGroupShape(
        borderRadius: buttonGroupBorderRadius(
          index: index,
          count: children.length,
          radius: theme.cornerRadius * 1.25,
          textDirection: Directionality.of(context),
        ),
        child: child,
      );
}

class SettingsHeaderAction extends StatelessWidget {
  const SettingsHeaderAction({
    super.key,
    required this.theme,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final AppThemeData theme;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppNavigationButton(
    theme: theme,
    isSelected: false,
    isEnabled: onTap != null,
    isHorizontal: true,
    onTap: onTap,
    iconData: icon,
    iconSize: 20,
    tooltipMessage: tooltip,
    minWidth: 40,
    minHeight: 36,
  );
}
