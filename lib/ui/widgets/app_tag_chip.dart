library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/game.dart';

/// Shared tag chip used across filters, selectors, and tag management.
class AppTagChip extends StatefulWidget {
  const AppTagChip({
    super.key,
    required this.tag,
    required this.theme,
    this.isSelected = false,
    this.onTap,
    this.onDelete,
  });

  final Tag tag;
  final AppThemeData theme;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  State<AppTagChip> createState() => _AppTagChipState();
}

class _AppTagChipState extends State<AppTagChip> {
  bool _isHovered = false;
  bool _isDeleteHovered = false;

  @override
  Widget build(BuildContext context) {
    final isInteractive = widget.onTap != null || widget.onDelete != null;
    final baseColor = widget.tag.isSteamTag
        ? widget.theme.accent
        : widget.theme.primary;
    final backgroundColor = widget.isSelected
        ? baseColor.withValues(alpha: _isHovered ? 0.45 : 0.35)
        : _isHovered
        ? baseColor.withValues(alpha: 0.12)
        : Colors.transparent;
    final borderColor = widget.isSelected
        ? baseColor.withValues(alpha: _isHovered ? 0.7 : 0.5)
        : _isHovered
        ? baseColor.withValues(alpha: 0.28)
        : baseColor.withValues(alpha: 0.0);
    final dotColor = widget.isSelected || _isHovered
        ? baseColor
        : baseColor.withValues(alpha: 0.4);
    final deleteIconColor = _isDeleteHovered
        ? baseColor
        : widget.theme.textSecondary;
    final deleteBackgroundColor = _isDeleteHovered
        ? baseColor.withValues(alpha: 0.12)
        : Colors.transparent;

    return MouseRegion(
      onEnter: isInteractive ? (_) => setState(() => _isHovered = true) : null,
      onExit: isInteractive ? (_) => setState(() => _isHovered = false) : null,
      cursor: isInteractive
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          key: ValueKey('app_tag_chip_${widget.tag.id}'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.tag.name,
                style: TextStyle(
                  color: widget.theme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (widget.onDelete != null) ...[
                const SizedBox(width: 8),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _isDeleteHovered = true),
                  onExit: (_) => setState(() => _isDeleteHovered = false),
                  child: GestureDetector(
                    onTap: widget.onDelete,
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: deleteBackgroundColor,
                        borderRadius: BorderRadius.circular(
                          widget.theme.cornerRadius,
                        ),
                      ),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: deleteIconColor,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
