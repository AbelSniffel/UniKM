library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'hover_builder.dart';

/// A unified preview card widget used in settings (e.g., ThemeCard, GradientEffectPreview)
class HoverPreviewCard extends StatelessWidget {
  const HoverPreviewCard({
    super.key,
    required this.name,
    required this.theme,
    required this.isSelected,
    required this.backgroundBuilder,
    this.isCustom = false,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onSecondaryTapDown,
    this.icon,
  });

  final String name;
  final AppThemeData theme;
  final bool isSelected;
  final Widget Function(BuildContext context, double innerRadius)
  backgroundBuilder;

  // Custom theme specific features
  final bool isCustom;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final void Function(TapDownDetails)? onSecondaryTapDown;

  // Background icon features
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      builder: (context, isHovered) {
        final borderWidth = (isSelected || isHovered) ? 2.5 : 0.0;
        final borderColor = isSelected
            ? theme.accent
            : isHovered
            ? theme.accent.withValues(alpha: 0.6)
            : theme.border.withValues(alpha: 0.1);

        final innerRadius = theme.cornerRadius > borderWidth
            ? theme.cornerRadius - borderWidth
            : 0.0;

        return InkWell(
          onTap: onTap,
          onSecondaryTapDown: onSecondaryTapDown,
          borderRadius: BorderRadius.circular(theme.cornerRadius),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 75),
            width: 120,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(theme.cornerRadius),
              border: Border.all(color: borderColor, width: borderWidth),
              boxShadow: isSelected || isHovered
                  ? [BoxShadow(color: theme.accent, blurRadius: 3)]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(innerRadius),
              child: Stack(
                children: [
                  backgroundBuilder(context, innerRadius),

                  if (icon != null)
                    // Subtle large background icon for depth
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Icon(
                        icon,
                        size: 45,
                        color: theme.surface.withValues(alpha: 0.25),
                      ),
                    ),

                  // Floating Name Pill
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 100),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(theme.cornerRadius),
                      ),
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                  // Hover controls for custom themes
                  if (isCustom && isHovered)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (onEdit != null)
                            _buildSmallButton(Icons.edit, onEdit!),
                          if (onDelete != null) ...[
                            const SizedBox(width: 4),
                            _buildSmallButton(
                              Icons.delete,
                              onDelete!,
                              color: Colors.redAccent,
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSmallButton(
    IconData iconData,
    VoidCallback onBtnTap, {
    Color color = Colors.white,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(theme.cornerRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onBtnTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(iconData, size: 14, color: color),
        ),
      ),
    );
  }
}
