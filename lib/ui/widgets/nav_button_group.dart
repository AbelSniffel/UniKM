import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import 'section_groupbox.dart';
import 'settings_card_inset.dart';

/// The rounded container, filled like a groupbox, that holds a run of
/// [AppNavigationButton]s, in a row or a column. The navigation panel and the
/// settings page's section list both group their buttons with it.
class const NavButtonGroup({
  super.key,
  required final bool isHorizontal,
  required final List<Widget> children,

  /// A tint for the group instead of the groupbox fill.
  final Color? color,

  /// Tinted with the accent instead, as the navigation panel's groups are.
  final bool accented = false,

  /// A horizontal group that fills the width offered, its buttons sharing it.
  final bool expanded = false,
}) extends ConsumerWidget {
  /// Space between the group's edge and its buttons.
  static const double padding = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.appTheme;
    // See-through like the groupboxes while the pages show the pattern.
    final tinted =
        !RaisedGroupBoxes.isEnabledOf(context) &&
        ref.watch(pagePatternProvider);
    final radius = theme.cornerRadius * 1.5;
    final tint = color ?? (accented ? theme.accent : null);
    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            tint?.withValues(alpha: 0.20) ??
            SectionGroupBox.background(theme, tinted: tinted),
        borderRadius: BorderRadius.circular(radius),
      ),
      // Groupbox-filled groups take the settings cards' depth, under their
      // buttons.
      child: CustomPaint(
        painter: tint != null
            ? null
            : SettingsCardInset.painterFor(
                depth: _depth,
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

/// 1 recessed, -1 raised.
const _depth = 1.0;
