library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import '../../core/constants/app_constants.dart';

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
  @override
  Widget build(BuildContext context) {
    final baseColor = widget.tag.isSteamTag
        ? widget.theme.accent
        : widget.theme.secondary;
    return _AppChipShell(
      theme: widget.theme,
      label: widget.tag.name,
      baseColor: baseColor,
      isSelected: widget.isSelected,
      onTap: widget.onTap,
      onDelete: widget.onDelete,
      chipKey: ValueKey('app_tag_chip_${widget.tag.id}'),
      leadingBuilder: (isHovered) => _ChipDot(
        color: baseColor,
        isSelected: widget.isSelected,
        isHovered: isHovered,
      ),
      leadingSpacing: kElementHSpacing,
    );
  }
}

class AppOptionChip extends StatefulWidget {
  const AppOptionChip({
    super.key,
    required this.label,
    required this.theme,
    this.isSelected = false,
    this.onTap,
    this.activeColor,
    this.selectedIcon = Icons.check_box,
    this.unselectedIcon = Icons.check_box_outline_blank,
  });

  final String label;
  final AppThemeData theme;
  final bool isSelected;
  final VoidCallback? onTap;
  final Color? activeColor;
  final IconData selectedIcon;
  final IconData unselectedIcon;

  @override
  State<AppOptionChip> createState() => _AppOptionChipState();
}

class _AppOptionChipState extends State<AppOptionChip> {
  @override
  Widget build(BuildContext context) {
    final baseColor = widget.activeColor ?? widget.theme.accent;
    return _AppChipShell(
      theme: widget.theme,
      label: widget.label,
      baseColor: baseColor,
      isSelected: widget.isSelected,
      onTap: widget.onTap,
      leadingBuilder: (isHovered) => _ChipIcon(
        color: baseColor,
        isSelected: widget.isSelected,
        isHovered: isHovered,
        selectedIcon: widget.selectedIcon,
        unselectedIcon: widget.unselectedIcon,
      ),
      leadingSpacing: 6,
      buttonSized: true,
    );
  }
}

class _AppChipShell extends StatefulWidget {
  const _AppChipShell({
    required this.theme,
    required this.label,
    required this.baseColor,
    required this.isSelected,
    required this.leadingBuilder,
    required this.leadingSpacing,
    this.onTap,
    this.onDelete,
    this.chipKey,
    this.buttonSized = false,
  });

  final AppThemeData theme;
  final String label;
  final Color baseColor;
  final bool isSelected;
  final Widget Function(bool isHovered) leadingBuilder;
  final double leadingSpacing;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final Key? chipKey;
  final bool buttonSized;

  @override
  State<_AppChipShell> createState() => _AppChipShellState();
}

class _AppChipShellState extends State<_AppChipShell> {
  bool _isHovered = false;
  bool _isDeleteHovered = false;

  @override
  Widget build(BuildContext context) {
    final isInteractive = widget.onTap != null || widget.onDelete != null;
    final backgroundColor = widget.isSelected
        ? widget.baseColor.withValues(alpha: _isHovered ? 0.45 : 0.35)
        : _isHovered
        ? widget.baseColor.withValues(alpha: 0.12)
        : Colors.transparent;
    final borderColor = widget.isSelected
        ? widget.baseColor.withValues(alpha: _isHovered ? 0.7 : 0.5)
        : _isHovered
        ? widget.baseColor.withValues(alpha: 0.28)
        : widget.baseColor.withValues(alpha: 0.0);
    final deleteIconColor = _isDeleteHovered
        ? widget.baseColor
        : widget.theme.textSecondary;
    final deleteBackgroundColor = _isDeleteHovered
        ? widget.baseColor.withValues(alpha: 0.12)
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
          key: widget.chipKey,
          constraints: widget.buttonSized
              ? const BoxConstraints(minHeight: kElementHeight)
              : null,
          padding: widget.buttonSized
              ? const EdgeInsets.symmetric(
                  horizontal: kButtonPaddingHorizontal,
                  vertical: 0,
                )
              : const EdgeInsets.symmetric(
                  horizontal: kTagChipPaddingHorizontal,
                  vertical: kTagChipPaddingVertical,
                ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              widget.leadingBuilder(_isHovered),
              SizedBox(width: widget.leadingSpacing),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.theme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (widget.onDelete != null) ...[
                const SizedBox(width: kElementHSpacing),
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

class _ChipDot extends StatelessWidget {
  const _ChipDot({
    required this.color,
    required this.isSelected,
    required this.isHovered,
  });

  final Color color;
  final bool isSelected;
  final bool isHovered;

  @override
  Widget build(BuildContext context) {
    final dotColor = isSelected || isHovered
        ? color
        : color.withValues(alpha: 0.4);

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: dotColor,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _ChipIcon extends StatelessWidget {
  const _ChipIcon({
    required this.color,
    required this.isSelected,
    required this.isHovered,
    required this.selectedIcon,
    required this.unselectedIcon,
  });

  final Color color;
  final bool isSelected;
  final bool isHovered;
  final IconData selectedIcon;
  final IconData unselectedIcon;

  @override
  Widget build(BuildContext context) {
    return Icon(
      isSelected ? selectedIcon : unselectedIcon,
      color: isSelected
          ? color
          : (isHovered
                ? color.withValues(alpha: 0.55)
                : color.withValues(alpha: 0.4)),
      size: 20,
    );
  }
}
