import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';

/// Shared footer for the navigation picker and the Appearance theme group.
/// Edit and Delete slide in and out beside Create as callers enable them.
class const ThemePickerActions({
  super.key,
  required final VoidCallback onCreate,
  final VoidCallback? onEdit,
  final VoidCallback? onDelete,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
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
    List<Widget> iconButton(String message, VoidCallback? run, IconData icon) =>
        [
          if (run != null) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: message,
              child: ElevatedButton(
                onPressed: run,
                style: iconStyle,
                child: Icon(icon, size: 18),
              ),
            ),
          ],
        ];
    final manage = onEdit == null && onDelete == null
        ? const SizedBox.shrink(key: ValueKey('theme-manage-hidden'))
        : Row(
            key: const ValueKey('theme-manage'),
            mainAxisSize: MainAxisSize.min,
            children: [
              ...iconButton('Edit current theme', onEdit, Icons.edit_outlined),
              ...iconButton(
                'Delete current theme',
                onDelete,
                Icons.delete_outline,
              ),
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
                textStyle: Theme.of(context).textTheme.labelLarge!
                    .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
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
          duration: context.motion(kTabTransition),
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
