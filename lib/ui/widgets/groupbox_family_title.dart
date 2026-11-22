import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import 'search_highlight.dart';

/// A settings panel's header, on top of its groups: the accent glows in
/// behind its icon and fades out across the title, and an accent line under
/// it fades into the border colour, so the colour stays with the title and
/// the groups below hold the eye. A larger title than the groups' headings,
/// in the accent like its icon, with it and any [trailing] actions lined up
/// with the groups' icons and actions.
class const GroupBoxFamilyTitle({
  super.key,
  required final AppThemeData theme,
  required final String title,
  required final IconData icon,
  final Widget? trailing,
}) extends StatelessWidget {
  /// The panel's padding around its groups, so the title and its actions
  /// share their edges.
  static const double _inset = 12;

  /// How strongly the accent tints the header at its icon end.
  static const double _tint = 0.22;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.accent.withValues(alpha: _tint),
              theme.accent.withValues(alpha: 0),
            ],
            stops: const [0, 0.75],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _inset, vertical: 8),
          child: Row(
            children: [
              // As tall as the header actions, so every header is the same
              // height.
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 36),
                  child: Row(
                    children: [
                      Icon(icon, size: 22, color: theme.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        // A settings search marks its words in the title.
                        child: Text.rich(
                          searchHighlightSpan(
                            title,
                            SettingsSearchScope.queryOf(context),
                            TextStyle(
                              color: theme.accent,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                            searchMarkStyle(theme.accent),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (trailing case final trailing?) ...[
                const SizedBox(width: 12),
                trailing,
              ],
            ],
          ),
        ),
      ),
      // The line under it, strongest under the icon.
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [theme.accent.withValues(alpha: 0.6), theme.border],
            stops: const [0, 0.75],
          ),
        ),
        child: const SizedBox(height: 1),
      ),
    ],
  );
}
