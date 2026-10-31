import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/surface_depth.dart';

/// Header actions move below the title at this content width or narrower.
/// The short title and compact actions fit inline slightly below the card
/// compact width, so the header stays on one row a little longer.
const double kFamilyTitleStackWidth = kSettingsCompactLayoutBreakpoint - 10;

/// A settings panel's header, on top of its groups with a line between
/// them: an accent tint with the icon in its own square and the title
/// beside it.
class GroupBoxFamilyTitle extends StatelessWidget {
  const GroupBoxFamilyTitle({
    super.key,
    required this.theme,
    required this.title,
    required this.icon,
    this.trailingBuilder,
  });

  final Widget Function(bool expanded)? trailingBuilder;
  final AppThemeData theme;
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      gradient: SurfaceDepth.gradient(
        Color.alphaBlend(theme.accent.withValues(alpha: 0.25), theme.surface),
        highlight: 0.05,
      ),
      border: Border(bottom: BorderSide(color: theme.border.withValues(alpha: 0.05))),
    ),
    child: _buildTitle(),
  );

  // Both layouts are built once per build, outside the layout callback, so a
  // width change only picks one instead of rebuilding the header actions.
  Widget _buildTitle() {
    final icon = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(theme.cornerRadius),
      ),
      child: Icon(this.icon, size: 20, color: theme.accent),
    );
    final text = Expanded(
      child: Text(
        title,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: theme.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 17,
        ),
      ),
    );
    const gap = SizedBox(width: 12);
    final titleRow = Row(children: [icon, gap, text]);
    final trailingBuilder = this.trailingBuilder;
    if (trailingBuilder == null) return titleRow;
    final inline = Row(
      children: [
        icon,
        gap,
        text,
        const SizedBox(width: 12),
        trailingBuilder(false),
      ],
    );
    final stacked = Column(
      children: [
        titleRow,
        const SizedBox(height: 4),
        SizedBox(width: double.infinity, child: trailingBuilder(true)),
      ],
    );
    // Measured like the groups below, which the panel's padding makes 8px
    // narrower than this header's content.
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth - 8 <= kFamilyTitleStackWidth ? stacked : inline,
    );
  }
}
