import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import 'settings_card_inset.dart';

/// The rounded container that holds a run of [AppNavigationButton]s, in a
/// row or a column. The navigation panel and the settings page's section
/// list both group their buttons with it.
///
/// Untinted, it is a see-through shade, so it takes on the colour of
/// whatever it sits on, a little deeper: a card's, the selection ribbon's or
/// the background pattern's.
class const NavButtonGroup({
  super.key,
  required final bool isHorizontal,
  required final List<Widget> children,

  /// A tint for the group instead of the shade.
  final Color? color,

  /// Tinted with the accent instead, as the navigation panel's groups are.
  final bool accented = false,

  /// A horizontal group that fills the width offered, its buttons sharing it.
  final bool expanded = false,
}) extends StatelessWidget {
  /// Space between the group's edge and its buttons.
  static const double padding = 4;

  /// The shade an untinted group lays over what it sits on: black, light
  /// enough that the colour underneath keeps its hue, only deeper.
  static Color shade(AppThemeData theme) =>
      Colors.black.withValues(alpha: theme.isDark ? 0.18 : 0.06);

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final radius = theme.cornerRadius * 1.5;
    final tint = color ?? (accented ? theme.accent : null);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint?.withValues(alpha: 0.20) ?? shade(theme),
        borderRadius: BorderRadius.circular(radius),
      ),
      // Shaded groups take the settings cards' depth under their buttons,
      // recessed; tinted ones stay flat.
      child: CustomPaint(
        painter: tint != null
            ? null
            : SettingsCardInset.painterFor(
                depth: 1,
                radius: radius,
                surfaceColor: theme.background,
                devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              ),
        child: Padding(
          padding: const EdgeInsets.all(padding),
          child: ConcentricRadius(
            outer: radius,
            gap: padding,
            child: isHorizontal
                ? Row(
                    mainAxisSize: expanded
                        ? MainAxisSize.max
                        : MainAxisSize.min,
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
        ),
      ),
    );
  }
}
