import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_icons.dart';
import 'popup_menu_helpers.dart';

/// Compact icon selection using the theme menu's native opening/closing motion.
class ThemeIconMenuButton extends StatefulWidget {
  const ThemeIconMenuButton({
    super.key,
    required this.theme,
    required this.selectedIconCodePoint,
    required this.onChanged,
  });

  final AppThemeData theme;
  final int? selectedIconCodePoint;
  final ValueChanged<int?> onChanged;

  @override
  State<ThemeIconMenuButton> createState() => _ThemeIconMenuButtonState();
}

class _ThemeIconMenuButtonState extends State<ThemeIconMenuButton> {
  final _controller = MenuController();
  final _buttonFocus = FocusNode();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _buttonFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  double _pickerWidth(MediaQueryData media) => math.min(
    280,
    math.max(0, media.size.width - media.padding.horizontal - 16),
  );

  Widget _picker(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = widget.theme;
    return SizedBox(
      key: const ValueKey('theme-icon-picker'),
      width: _pickerWidth(media),
      height: math.min(
        320,
        math.max(
          0,
          media.size.height -
              media.padding.vertical -
              media.viewInsets.vertical -
              16,
        ),
      ),
      child: ListView(
        controller: _scrollController,
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
                    selected: widget.selectedIconCodePoint == icon.codePoint,
                    child: IconButton(
                      key: ValueKey('theme-icon-${icon.codePoint}'),
                      tooltip: label,
                      onPressed: () => widget.onChanged(
                        widget.selectedIconCodePoint == icon.codePoint
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
                        foregroundColor:
                            widget.selectedIconCodePoint == icon.codePoint
                            ? theme.accent
                            : theme.textSecondary,
                        backgroundColor:
                            widget.selectedIconCodePoint == icon.codePoint
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
    final theme = widget.theme;
    final selected = widget.selectedIconCodePoint != null;
    return MenuAnchor(
      controller: _controller,
      animated: !MediaQuery.disableAnimationsOf(context),
      childFocusNode: _buttonFocus,
      consumeOutsideTap: true,
      useRootOverlay: true,
      reservedPadding: const EdgeInsets.all(8),
      alignmentOffset: Offset(
        Directionality.of(context) == TextDirection.ltr
            ? -_pickerWidth(MediaQuery.of(context))
            : 0,
        8,
      ),
      style: appMenuStyle(theme),
      menuChildren: [_picker(context)],
      builder: (context, controller, _) => IconButton(
        focusNode: _buttonFocus,
        tooltip: 'Theme icon',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
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
              ? themeIconFromCodePoint(widget.selectedIconCodePoint!)
              : Icons.palette,
          size: 20,
        ),
      ),
    );
  }
}
