import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../providers/ui_state_providers.dart' show kAutoDetectPlatformValue;
import '../../core/constants/app_constants.dart';
import '../../core/constants/platform_patterns.dart';
import '../../core/theme/app_theme.dart';
import 'platform_icon.dart';
import 'popup_menu_helpers.dart';

/// Compact platform selector shared by game-key fields and batch entry.
class PlatformMenuButton extends StatelessWidget {
  const PlatformMenuButton({
    super.key,
    required this.theme,
    required this.value,
    required this.tooltip,
    required this.onSelected,
    this.detectedPlatform,
    this.includeAutoDetect = true,
  });

  final AppThemeData theme;
  final String value;
  final String tooltip;
  final ValueChanged<String>? onSelected;
  final GamePlatform? detectedPlatform;
  final bool includeAutoDetect;

  @override
  Widget build(BuildContext context) {
    final platform = value == kAutoDetectPlatformValue
        ? detectedPlatform
        : GamePlatform.fromDisplayName(value);
    return IconMenuButton<String>(
      theme: theme,
      value: value,
      tooltip: tooltip,
      onSelected: onSelected,
      icon: (color, size) => platform == null
          ? Icon(Icons.auto_fix_high, color: color, size: size)
          : PlatformIcon(platform: platform, color: color, size: size),
      choices: [
        if (includeAutoDetect)
          (
            kAutoDetectPlatformValue,
            'Auto-detect',
            const Icon(Icons.auto_fix_high, size: 18),
          ),
        for (final choice in GamePlatform.values)
          (
            choice.displayName,
            choice.displayName,
            PlatformIcon(platform: choice, color: theme.textPrimary, size: 18),
          ),
      ],
    );
  }
}

/// A navigation-style button showing the current choice's icon and a chevron,
/// which opens a menu of [choices] (value, label, icon).
class IconMenuButton<T> extends StatefulWidget {
  const IconMenuButton({
    super.key,
    required this.theme,
    required this.value,
    required this.tooltip,
    required this.onSelected,
    required this.icon,
    required this.choices,
    this.menuWidth = 230,
    this.highlighted = false,
  });

  final AppThemeData theme;
  final T value;
  final String tooltip;
  final ValueChanged<T>? onSelected;

  /// The current choice's icon in the given color and size.
  final Widget Function(Color color, double size) icon;
  final List<(T, String, Widget)> choices;
  final double menuWidth;

  /// Shows the button selected, such as while a filter is active.
  final bool highlighted;

  @override
  State<IconMenuButton<T>> createState() => _IconMenuButtonState<T>();
}

class _IconMenuButtonState<T> extends State<IconMenuButton<T>> {
  final _menu = MenuController();
  final _focusNode = FocusNode(skipTraversal: true);

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    if (_menu.isOpen) return _menu.close();
    // Focus lets Escape close the menu again.
    _focusNode.requestFocus();
    _menu.open();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final enabled = widget.onSelected != null;
    return AppMenuAnchor(
      theme: theme,
      controller: _menu,
      childFocusNode: _focusNode,
      width: widget.menuWidth,
      maxHeight: kDropdownMenuMaxHeight,
      menuChildren: [
        for (final (value, label, icon) in widget.choices)
          appMenuItem(
            theme,
            selected: value == widget.value,
            onPressed: enabled ? () => widget.onSelected!(value) : null,
            child: Row(
              children: [
                icon,
                const SizedBox(width: 10),
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
      ],
      // Down arrow opens the menu, as in other select controls.
      builder: (context, controller, _) => Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowDown): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
              ActivateIntent(),
        },
        child: Focus(
          focusNode: _focusNode,
          child: Semantics(
            expanded: controller.isOpen,
            // The button fills any space it is offered; this keeps it to its
            // content unless the parent sets its size.
            child: IntrinsicWidth(
              child: IntrinsicHeight(
                child: AppNavigationButton(
                  theme: theme,
                  isSelected: widget.highlighted || controller.isOpen,
                  isEnabled: enabled,
                  isHorizontal: true,
                  onTap: _toggleMenu,
                  tooltipMessage: widget.tooltip,
                  selectedBackgroundColor: theme.accent.withValues(alpha: 0.30),
                  // The chevron's glyph has its own side margin, so the icon
                  // side gets more padding to look even.
                  padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                  // The choice keeps the accent; disabled buttons take the muted
                  // color the button gives them.
                  iconBuilder: (context, color, size) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      widget.icon(enabled ? theme.accent : color, size),
                      const SizedBox(width: 1),
                      Icon(
                        Icons.keyboard_arrow_down,
                        color: enabled ? theme.textPrimary : color,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
