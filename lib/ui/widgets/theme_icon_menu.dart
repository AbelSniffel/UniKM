import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_icons.dart';
import 'popup_menu_helpers.dart';

/// Compact icon selection using the theme menu's native opening/closing motion.
class ThemeIconMenuButton extends StatelessWidget {
  const ThemeIconMenuButton({
    super.key,
    required this.theme,
    required this.selectedIconCodePoint,
    required this.onChanged,
  });

  final AppThemeData theme;
  final int? selectedIconCodePoint;
  final ValueChanged<int?> onChanged;

  Widget _picker(Size size, ScrollController scrollController) {
    return SizedBox.fromSize(
      key: const ValueKey('theme-icon-picker'),
      size: size,
      child: ListView(
        controller: scrollController,
        primary: false,
        padding: const EdgeInsets.all(8),
        children: [
          for (final group in themeIconGroups) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                group.$1,
                style: TextStyle(
                  color: theme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final (icon, label) in group.$2)
                  Semantics(
                    selected: selectedIconCodePoint == icon.codePoint,
                    child: IconButton(
                      key: ValueKey('theme-icon-${icon.codePoint}'),
                      tooltip: label,
                      onPressed: () => onChanged(
                        selectedIconCodePoint == icon.codePoint
                            ? null
                            : icon.codePoint,
                      ),
                      style: IconButton.styleFrom(
                        fixedSize: const Size.square(32),
                        minimumSize: const Size.square(32),
                        maximumSize: const Size.square(32),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.standard,
                        foregroundColor: selectedIconCodePoint == icon.codePoint
                            ? theme.accent
                            : theme.textSecondary,
                        backgroundColor: selectedIconCodePoint == icon.codePoint
                            ? theme.accent.withValues(alpha: 0.2)
                            : Colors.transparent,
                        hoverColor: theme.navItemHover,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            theme.cornerRadius,
                          ),
                        ),
                      ),
                      icon: Icon(icon, size: 20),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = selectedIconCodePoint != null;
    return AnchoredPanelMenu(
      theme: theme,
      maxSize: const Size(280, 320),
      panel: _picker,
      button: (focusNode, toggle) => IconButton(
        focusNode: focusNode,
        tooltip: 'Theme icon',
        onPressed: toggle,
        style: IconButton.styleFrom(
          foregroundColor: selected ? theme.accent : theme.textSecondary,
          backgroundColor: selected
              ? theme.accent.withValues(alpha: 0.15)
              : Colors.transparent,
          hoverColor: theme.navItemHover,
          fixedSize: const Size.square(kElementHeight),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.cornerRadius),
            side: BorderSide(
              color: selected ? theme.accent : theme.border,
              width: selected ? 2 : 1.5,
            ),
          ),
        ),
        icon: Icon(
          selected
              ? themeIconFromCodePoint(selectedIconCodePoint!)
              : Icons.palette,
          size: 20,
        ),
      ),
    );
  }
}
