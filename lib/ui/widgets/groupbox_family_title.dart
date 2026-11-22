import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import 'search_highlight.dart';

/// A settings panel's header, on top of its groups: no fill of its own, so
/// the groups below hold the eye. A larger title than the groups' headings,
/// in the accent like its icon, any [trailing] actions lined up with their
/// icons and actions, and a line under it across the groups' width.
class const GroupBoxFamilyTitle({
  super.key,
  required final AppThemeData theme,
  required final String title,
  required final IconData icon,
  final Widget? trailing,
}) extends StatelessWidget {
  /// The panel's padding around its groups, so the title, its actions and
  /// the line under it share their edges.
  static const double _inset = 12;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: _inset),
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
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
  );
}
