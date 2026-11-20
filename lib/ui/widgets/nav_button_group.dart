import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';

/// The rounded, accent-tinted container that holds a run of
/// [AppNavigationButton]s, in a row or a column. The navigation panel and the
/// settings page's section list both group their buttons with it.
class const NavButtonGroup({
  super.key,
  required final bool isHorizontal,
  required final List<Widget> children,

  /// The group's tint; the theme's accent by default.
  final Color? color,

  /// A horizontal group that fills the width offered, its buttons sharing it.
  final bool expanded = false,
}) extends StatelessWidget {
  /// Space between the group's edge and its buttons.
  static const double padding = 4;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final radius = theme.cornerRadius * 1.5;
    return Container(
      padding: const EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: (color ?? theme.accent).withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: ConcentricRadius(
        outer: radius,
        gap: padding,
        child: isHorizontal
            ? Row(
                mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
                spacing: 4,
                children: [
                  for (final child in children)
                    expanded ? Expanded(child: child) : child,
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 4,
                children: children,
              ),
      ),
    );
  }
}
