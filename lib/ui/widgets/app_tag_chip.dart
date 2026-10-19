library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import '../../core/constants/app_constants.dart';

/// Shared tag chip used across filters, selectors, and tag management.
class AppTagChip extends StatelessWidget {
  const AppTagChip({
    super.key,
    required this.tag,
    required this.theme,
    this.isSelected = false,
    this.onTap,
  });

  final Tag tag;
  final AppThemeData theme;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final baseColor = tag.isSteamTag ? theme.accent : theme.secondary;
    return _AppChipShell(
      theme: theme,
      label: tag.name,
      baseColor: baseColor,
      isSelected: isSelected,
      onTap: onTap,
      chipKey: ValueKey('app_tag_chip_${tag.id}'),
      leading: _ChipDot(color: baseColor, isSelected: isSelected),
      leadingSpacing: kElementHSpacing,
    );
  }
}

class AppOptionChip extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final baseColor = activeColor ?? theme.accent;
    return _AppChipShell(
      theme: theme,
      label: label,
      baseColor: baseColor,
      isSelected: isSelected,
      onTap: onTap,
      leading: _ChipIcon(
        color: baseColor,
        isSelected: isSelected,
        selectedIcon: selectedIcon,
        unselectedIcon: unselectedIcon,
      ),
      leadingSpacing: 6,
      optionSized: true,
    );
  }
}

class _AppChipShell extends StatelessWidget {
  const _AppChipShell({
    required this.theme,
    required this.label,
    required this.baseColor,
    required this.isSelected,
    required this.leading,
    required this.leadingSpacing,
    this.onTap,
    this.chipKey,
    this.optionSized = false,
  });

  final AppThemeData theme;
  final String label;
  final Color baseColor;
  final bool isSelected;
  final Widget leading;
  final double leadingSpacing;
  final VoidCallback? onTap;
  final Key? chipKey;
  final bool optionSized;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(theme.cornerRadius),
      side: BorderSide(
        color: isSelected
            ? baseColor.withValues(alpha: 0.5)
            : Colors.transparent,
      ),
    );
    // Material's shape border does not add the old Container's layout inset.
    final padding =
        EdgeInsets.symmetric(
          horizontal: kTagChipPaddingHorizontal,
          vertical: optionSized
              ? kOptionChipPaddingVertical
              : kTagChipPaddingVertical,
        ) +
        const EdgeInsets.all(1);
    return Material(
      key: chipKey,
      color: isSelected
          ? baseColor.withValues(alpha: 0.35)
          : Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        child: Container(
          constraints: optionSized
              ? const BoxConstraints(minHeight: kOptionChipHeight)
              : null,
          padding: padding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              SizedBox(width: leadingSpacing),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipDot extends StatelessWidget {
  const _ChipDot({required this.color, required this.isSelected});

  final Color color;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final dotColor = isSelected ? color : color.withValues(alpha: 0.4);

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
    );
  }
}

class _ChipIcon extends StatelessWidget {
  const _ChipIcon({
    required this.color,
    required this.isSelected,
    required this.selectedIcon,
    required this.unselectedIcon,
  });

  final Color color;
  final bool isSelected;
  final IconData selectedIcon;
  final IconData unselectedIcon;

  @override
  Widget build(BuildContext context) {
    return Icon(
      isSelected ? selectedIcon : unselectedIcon,
      color: isSelected ? color : color.withValues(alpha: 0.4),
      size: 20,
    );
  }
}
