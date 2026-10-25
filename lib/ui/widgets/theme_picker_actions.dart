import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';

/// Shared footer for the navigation picker and the Appearance theme group.
/// Edit and Delete slide in and out beside Create as callers enable them.
class ThemePickerActions extends StatelessWidget {
  const ThemePickerActions({
    super.key,
    required this.theme,
    required this.onCreate,
    this.onEdit,
    this.onDelete,
  });

  final AppThemeData theme;
  final VoidCallback onCreate;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final height = math.max(
      36.0,
      MediaQuery.textScalerOf(context).scale(13) * 1.5 + 16,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(theme.cornerRadius),
    );
    final iconStyle = ElevatedButton.styleFrom(
      minimumSize: Size(height, height),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      shape: shape,
    );
    final manage = onEdit == null && onDelete == null
        ? const SizedBox.shrink(key: ValueKey('theme-manage-hidden'))
        : Row(
            key: const ValueKey('theme-manage'),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onEdit != null) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Edit current theme',
                  child: ElevatedButton(
                    onPressed: onEdit,
                    style: iconStyle,
                    child: const Icon(Icons.edit_outlined, size: 18),
                  ),
                ),
              ],
              if (onDelete != null) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Delete current theme',
                  child: ElevatedButton(
                    onPressed: onDelete,
                    style: iconStyle,
                    child: const Icon(Icons.delete_outline, size: 18),
                  ),
                ),
              ],
            ],
          );
    return Row(
      children: [
        Expanded(
          child: Tooltip(
            message: 'Create Theme',
            child: ElevatedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: 16),
              label: const Text(
                'Create theme',
                overflow: TextOverflow.ellipsis,
              ),
              style: ElevatedButton.styleFrom(
                textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                minimumSize: Size(0, height),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                shape: shape,
              ),
            ),
          ),
        ),
        // Timed with the tab slide, so the buttons arrive with their tab.
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : kTabTransition,
          switchInCurve: kTabTransitionCurve,
          switchOutCurve: kTabTransitionCurve.flipped,
          transitionBuilder: (child, animation) => SizeTransition(
            sizeFactor: animation,
            axis: Axis.horizontal,
            alignment: AlignmentDirectional.centerStart,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: manage,
        ),
      ],
    );
  }
}
