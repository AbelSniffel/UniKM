import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/surface_depth.dart';
import 'search_highlight.dart';

/// Shared inset title pill for groupbox families throughout the GUI.
class GroupBoxFamilyTitle extends StatelessWidget {
  const GroupBoxFamilyTitle({
    super.key,
    required this.theme,
    required this.title,
    required this.icon,
    this.searchQuery = '',
    this.isSearchMatch = false,
    this.trailingBuilder,
  });

  final Widget Function(bool expanded)? trailingBuilder;
  final AppThemeData theme;
  final String title;
  final IconData icon;
  final String searchQuery;
  final bool isSearchMatch;

  @override
  Widget build(BuildContext context) {
    return SearchHighlight(
      query: searchQuery,
      isMatch: isSearchMatch,
      builder: (context, highlightValue) {
        final backgroundColor = Color.lerp(
          theme.accent,
          theme.secondary,
          0.15 * highlightValue,
        )!;
        final iconAndTextColor =
            ThemeData.estimateBrightnessForColor(backgroundColor) ==
                Brightness.dark
            ? Colors.white
            : Colors.black87;

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            gradient: SurfaceDepth.gradient(backgroundColor),
            borderRadius: BorderRadius.circular(theme.cornerRadius),
            border: Border.all(
              color: Color.lerp(backgroundColor, Colors.black, 0.22)!,
            ),
            boxShadow: [
              SurfaceDepth.shadow(isDark: theme.isDark),
              if (highlightValue > 0)
                BoxShadow(
                  color: theme.accent.withValues(alpha: 0.18 * highlightValue),
                  blurRadius: 14,
                  spreadRadius: 1.5,
                ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Keep header action stacking aligned with the inset body width.
              final contentWidth = constraints.maxWidth + 2;
              final stacked =
                  trailingBuilder != null &&
                  contentWidth <= kSettingsCompactLayoutBreakpoint;
              final titleRow = Row(
                children: [
                  Icon(icon, size: 20, color: iconAndTextColor),
                  const SizedBox(width: kElementHSpacing),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: iconAndTextColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (!stacked && trailingBuilder != null) ...[
                    const SizedBox(width: 12),
                    trailingBuilder!(false),
                  ],
                ],
              );
              if (!stacked) return titleRow;
              return Column(
                children: [
                  titleRow,
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: trailingBuilder!(true),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
