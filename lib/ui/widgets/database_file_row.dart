import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Shared database and backup row, with an encryption icon and optional
/// actions, tinted like the Tinted Tile dialogs' tiles. Missing files are
/// tinted orange; the [highlighted] row is tinted more strongly and outlined.
class DatabaseFileRow extends StatelessWidget {
  const DatabaseFileRow({
    super.key,
    required this.theme,
    required this.title,
    required this.subtitle,
    required this.isEncrypted,
    this.available = true,
    this.highlighted = false,
    this.onTap,
    this.actions = const [],
    this.margin = const EdgeInsets.only(bottom: 8),
  });

  final AppThemeData theme;
  final String title;
  final String subtitle;
  final bool isEncrypted;
  final bool available;
  final bool highlighted;
  final VoidCallback? onTap;
  final List<Widget> actions;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final color = available ? theme.accent : Colors.orange;
    final radius = BorderRadius.circular(theme.cornerRadius);
    return Padding(
      padding: margin,
      child: Material(
        color: color.withValues(alpha: highlighted ? 0.16 : 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: highlighted ? color : Colors.transparent),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: available ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              spacing: 12,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: radius,
                  ),
                  child: Icon(
                    !available
                        ? Icons.warning_amber
                        : isEncrypted
                        ? Icons.lock
                        : Icons.lock_open,
                    color: color,
                    size: 20,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    spacing: 2,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Tooltip(
                        message: subtitle,
                        child: Text(
                          subtitle,
                          style: TextStyle(
                            color: theme.textSecondary,
                            fontSize: 12,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (actions.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: actions),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
