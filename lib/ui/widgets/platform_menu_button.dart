import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../providers/ui_state_providers.dart' show kAutoDetectPlatformValue;
import '../../core/constants/app_constants.dart';
import '../../core/constants/platform_patterns.dart';
import '../../core/theme/app_theme.dart';
import 'platform_icon.dart';
import 'popup_menu_helpers.dart';

/// Compact platform selector shared by game-key fields and batch entry.
class PlatformMenuButton extends StatefulWidget {
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
  State<PlatformMenuButton> createState() => _PlatformMenuButtonState();
}

class _PlatformMenuButtonState extends State<PlatformMenuButton> {
  final _menu = MenuController();
  final _focusNode = FocusNode();
  bool _hovered = false;
  bool _open = false;

  bool get _enabled => widget.onSelected != null;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    if (!_enabled) return;
    if (_menu.isOpen) return _menu.close();
    _focusNode.requestFocus();
    _menu.open();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final platform = widget.value == kAutoDetectPlatformValue
        ? widget.detectedPlatform
        : GamePlatform.fromDisplayName(widget.value);
    final radius = BorderRadius.circular(theme.cornerRadius);
    return MouseRegion(
      onEnter: _enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: Material(
          color: theme.navItemHover,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: AppMenuAnchor(
            theme: theme,
            controller: _menu,
            childFocusNode: _focusNode,
            onOpen: () => setState(() => _open = true),
            onClose: () => setState(() => _open = false),
            width: 230,
            maxHeight: kDropdownMenuMaxHeight,
            menuChildren: [
              for (final (value, label, icon) in [
                if (widget.includeAutoDetect)
                  (
                    kAutoDetectPlatformValue,
                    'Auto-detect',
                    const Icon(Icons.auto_fix_high, size: 18),
                  ),
                for (final choice in GamePlatform.values)
                  (
                    choice.displayName,
                    choice.displayName,
                    PlatformIcon(
                      platform: choice,
                      color: theme.textPrimary,
                      size: 18,
                    ),
                  ),
              ])
                appMenuItem(
                  theme,
                  selected: value == widget.value,
                  onPressed: _enabled ? () => widget.onSelected!(value) : null,
                  child: Row(
                    children: [
                      icon,
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(label, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
            ],
            builder: (context, _, _) => Semantics(
              button: true,
              enabled: _enabled,
              expanded: _open,
              // Down arrow opens the menu, as in other select controls.
              child: Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.arrowDown):
                      ActivateIntent(),
                  SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
                      ActivateIntent(),
                },
                child: Actions(
                  actions: {
                    ActivateIntent: CallbackAction<ActivateIntent>(
                      onInvoke: (_) {
                        _toggleMenu();
                        return null;
                      },
                    ),
                  },
                  child: InkWell(
                    focusNode: _focusNode,
                    onTap: _enabled ? _toggleMenu : null,
                    borderRadius: radius,
                    hoverColor: theme.navItemHover,
                    focusColor: theme.navItemHover,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(9, 3, 4, 3),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: kIconSize),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedScale(
                              scale: _hovered ? 1.2 : 1.0,
                              duration: const Duration(milliseconds: 100),
                              child: platform == null
                                  ? Icon(
                                      Icons.auto_fix_high,
                                      color: theme.accent,
                                      size: 18,
                                    )
                                  : PlatformIcon(
                                      platform: platform,
                                      color: theme.accent,
                                      size: 18,
                                    ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.arrow_drop_down,
                              color: theme.textSecondary,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
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
