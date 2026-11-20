import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/surface_depth.dart';
import '../../providers/app_providers.dart';
import 'section_groupbox.dart';

/// A settings section: its header on top of a panel of groups, which show
/// as plain headings. One rounded border surrounds both, on a group box's
/// background and, while it is raised, its shadow.
class const SettingsSectionFamily({
  super.key,
  required final Widget header,
  required final Widget child,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.appTheme;
    final radius = BorderRadius.circular(theme.cornerRadius);
    final tinted = ref.watch(pagePatternProvider);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: SectionGroupBox.background(theme, tinted: tinted),
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
