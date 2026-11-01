import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The rounded, accent-tinted container that holds a run of
/// [AppNavigationButton]s, in a row or a column. The navigation panel and the
/// settings page's section list both group their buttons with it.
class NavButtonGroup extends StatelessWidget {
  const NavButtonGroup({
    super.key,
    required this.theme,
    required this.isHorizontal,
    required this.children,
  });

  /// Space between the group's edge and its buttons.
  static const double padding = 4;

  final AppThemeData theme;
  final bool isHorizontal;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(padding),
    decoration: BoxDecoration(
      color: theme.accent.withValues(alpha: 0.20),
      borderRadius: BorderRadius.circular(theme.cornerRadius * 1.5),
    ),
    child: isHorizontal
        ? Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: children)
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 4,
            children: children,
          ),
  );
}
