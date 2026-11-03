import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'nav_button_group.dart';

/// Settings header actions in a navigation-panel style button group, like
/// the library's selection bar: a tinted group of separately highlighted
/// buttons.
class SettingsHeaderActions extends StatelessWidget {
  const SettingsHeaderActions({
    super.key,
    required this.theme,
    required this.children,
    this.expanded = false,
  });

  final AppThemeData theme;
  final List<Widget> children;

  /// Fills the width offered, the buttons sharing it, for a header too narrow
  /// to keep its actions beside the title.
  final bool expanded;

  @override
  Widget build(BuildContext context) => NavButtonGroup(
    theme: theme,
    isHorizontal: true,
    expanded: expanded,
    children: children,
  );
}

class SettingsHeaderAction extends StatelessWidget {
  const SettingsHeaderAction({
    super.key,
    required this.theme,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badgeCount,
  });

  final AppThemeData theme;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  /// A count on the icon, such as how many versions are skipped.
  final int? badgeCount;

  @override
  // A fixed height keeps the button 32 px in headers that offer more.
  Widget build(BuildContext context) => SizedBox(
    height: 32,
    child: AppNavigationButton(
      theme: theme,
      isSelected: false,
      isEnabled: onTap != null,
      isHorizontal: true,
      onTap: onTap,
      iconData: icon,
      iconBuilder: badgeCount == null
          ? null
          : (context, color, size) => Badge.count(
              count: badgeCount!,
              backgroundColor: theme.accent,
              textColor: theme.accent.computeLuminance() > 0.3
                  ? Colors.black
                  : Colors.white,
              child: Icon(icon, color: color, size: size),
            ),
      tooltipMessage: tooltip,
      // 4 px smaller than the selection bar's 36 px buttons.
      iconSize: 20,
      padding: const EdgeInsets.all(6),
      minWidth: 32,
    ),
  );
}
