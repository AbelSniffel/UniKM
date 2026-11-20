import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/surface_depth.dart';
import 'dialog_helpers.dart';

/// A settings panel's header, on top of its groups with a line between
/// them: an accent tint, titled like a dialog, the icon straight beside the
/// title and any [trailing] actions at the end of the same row.
class const GroupBoxFamilyTitle({
  super.key,
  required final AppThemeData theme,
  required final String title,
  required final IconData icon,
  final Widget? trailing,
}) extends StatelessWidget {
  /// The title sits 6 px in from the groups below, as a dialog's title does
  /// from its content.
  static const _padding = EdgeInsets.fromLTRB(18, 8, 8, 8);

  @override
  Widget build(BuildContext context) => Container(
    padding: _padding,
    decoration: BoxDecoration(
      color: SurfaceDepth.top(
        Color.alphaBlend(theme.accent.withValues(alpha: 0.25), theme.surface),
        highlight: 0.05,
      ),
      border: Border(
        bottom: BorderSide(color: theme.border.withValues(alpha: 0.05)),
      ),
    ),
    child: Row(
      children: [
        // As tall as the header actions, so every header is the same height.
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Align(
              alignment: Alignment.centerLeft,
              child: DialogHeader(icon: icon, title: title),
            ),
          ),
        ),
        if (trailing case final trailing?) ...[
          const SizedBox(width: 12),
          trailing,
        ],
      ],
    ),
  );
}
