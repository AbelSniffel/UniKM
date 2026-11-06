import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/surface_depth.dart';
import '../../providers/app_providers.dart';
import 'section_groupbox.dart';

/// A settings section: its header on top of a panel of groups, which show
/// as plain headings. One rounded border surrounds both, on a group box's
/// background and, while it is raised, its shadow.
class SettingsSectionFamily extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final radius = BorderRadius.circular(theme.cornerRadius);
    final tinted = ref.watch(pagePatternProvider);
    final color = SectionGroupBox.background(theme, tinted: tinted);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color,
        gradient: SectionGroupBox.gradient(color, highlight: 0.05),
        borderRadius: radius,
        boxShadow: [if (!tinted) SurfaceDepth.shadow(isDark: theme.isDark)],
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
