import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/surface_depth.dart';
import 'section_groupbox.dart';

/// A settings section: its header on top of a panel of groups, which show
/// as plain headings. One rounded border and shadow surround both.
class SettingsSectionFamily extends StatelessWidget {
  const SettingsSectionFamily({
    super.key,
    required this.theme,
    required this.header,
    required this.child,
  });

  final AppThemeData theme;
  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(theme.cornerRadius);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: SurfaceDepth.gradient(theme.surface, highlight: 0.085),
        borderRadius: radius,
        boxShadow: [SurfaceDepth.shadow(isDark: theme.isDark)],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          // The groups' controls draw their ink on this.
          Material(
            type: MaterialType.transparency,
            textStyle: DefaultTextStyle.of(context).style,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SpacedSettingsGroups(child: child),
            ),
          ),
        ],
      ),
    );
  }
}
