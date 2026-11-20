import 'package:material_ui/material_ui.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/surface_depth.dart';
import 'dialog_helpers.dart';

/// Header actions move below the title at this content width or narrower.
/// The short title and compact actions fit inline slightly below the card
/// compact width, so the header stays on one row a little longer.
const double kFamilyTitleStackWidth = kSettingsCompactLayoutBreakpoint - 10;

/// A settings panel's header, on top of its groups with a line between
/// them: an accent tint, titled like a dialog, the icon straight beside the
/// title.
class const GroupBoxFamilyTitle({
  super.key,
  required final AppThemeData theme,
  required final String title,
  required final IconData icon,
  final Widget Function(bool expanded)? trailingBuilder,
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
    child: _buildTitle(),
  );

  // Both layouts are built once per build, outside the layout callback, so a
  // width change only picks one instead of rebuilding the header actions.
  Widget _buildTitle() {
    // As tall as the header actions, so every header is the same height.
    final text = Expanded(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: Align(
          alignment: Alignment.centerLeft,
          child: DialogHeader(icon: icon, title: title),
        ),
      ),
    );
    final trailingBuilder = this.trailingBuilder;
    if (trailingBuilder == null) return Row(children: [text]);
    final inline = Row(
      children: [text, const SizedBox(width: 12), trailingBuilder(false)],
    );
    final stacked = Column(
      children: [
        Row(children: [text]),
        const SizedBox(height: 4),
        SizedBox(width: double.infinity, child: trailingBuilder(true)),
      ],
    );
    // Measured like the groups below, which sit 12 px inside the panel.
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth + _padding.horizontal - 24 <=
              kFamilyTitleStackWidth
          ? stacked
          : inline,
    );
  }
}
