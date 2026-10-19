import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/surface_depth.dart';

/// Shared database and backup row, with an encryption icon and optional actions.
class DatabaseFileRow extends StatefulWidget {
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
  State<DatabaseFileRow> createState() => _DatabaseFileRowState();
}

class _DatabaseFileRowState extends State<DatabaseFileRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final iconColor = widget.available ? theme.accent : Colors.orange;
    return Padding(
      padding: widget.margin,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          borderRadius: BorderRadius.circular(theme.cornerRadius),
          onHover: (value) => setState(() => _hovering = value),
          onTap: widget.available ? widget.onTap : null,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: SurfaceDepth.gradient(theme.surface, highlight: 0.085),
              boxShadow: [SurfaceDepth.shadow(isDark: theme.isDark)],
              borderRadius: BorderRadius.circular(theme.cornerRadius),
              border: Border.all(
                color: _hovering || widget.highlighted
                    ? theme.accent
                    : theme.border,
                width: widget.highlighted ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    !widget.available
                        ? Icons.warning_amber
                        : widget.isEncrypted
                        ? Icons.lock
                        : Icons.lock_open,
                    color: iconColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Tooltip(
                        message: widget.subtitle,
                        child: Text(
                          widget.subtitle,
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
                if (widget.actions.isNotEmpty) ...[
                  const SizedBox(width: 5),
                  Row(mainAxisSize: MainAxisSize.min, children: widget.actions),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
