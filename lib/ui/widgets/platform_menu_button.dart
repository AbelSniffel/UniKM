import 'package:flutter/material.dart';

import '../../providers/ui_state_providers.dart' show kAutoDetectPlatformValue;
import '../../core/constants/platform_patterns.dart';
import '../../core/theme/app_theme.dart';
import 'platform_icon.dart';
import 'app_combo_box.dart';

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
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final platform = widget.value == kAutoDetectPlatformValue
        ? widget.detectedPlatform
        : GamePlatform.fromDisplayName(widget.value);
    return MouseRegion(
      onEnter: widget.onSelected == null
          ? null
          : (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: Material(
          color: theme.navItemHover,
          borderRadius: BorderRadius.circular(theme.cornerRadius),
          clipBehavior: Clip.antiAlias,
          child: AppComboBox<String>(
            initialValue: widget.value,
            theme: theme,
            compact: true,
            isExpanded: false,
            padding: const EdgeInsets.fromLTRB(9, 3, 4, 3),
            menuWidth: 230,
            icon: Icon(
              Icons.arrow_drop_down,
              color: theme.textSecondary,
              size: 18,
            ),
            selectedChild: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: _hovered ? 1.2 : 1.0,
                  duration: const Duration(milliseconds: 100),
                  child: platform == null
                      ? Icon(Icons.auto_fix_high, color: theme.accent, size: 18)
                      : PlatformIcon(
                          platform: platform,
                          color: theme.accent,
                          size: 18,
                        ),
                ),
                const SizedBox(width: 2),
              ],
            ),
            items: [
              if (widget.includeAutoDetect)
                _menuItem(
                  kAutoDetectPlatformValue,
                  'Auto-detect',
                  const Icon(Icons.auto_fix_high, size: 18),
                ),
              for (final choice in GamePlatform.values)
                _menuItem(
                  choice.displayName,
                  choice.displayName,
                  PlatformIcon(
                    platform: choice,
                    color: theme.textPrimary,
                    size: 18,
                  ),
                ),
            ],
            onChanged: widget.onSelected == null
                ? null
                : (selected) {
                    if (selected != null) widget.onSelected!(selected);
                  },
          ),
        ),
      ),
    );
  }

  DropdownMenuItem<String> _menuItem(String value, String label, Widget icon) =>
      DropdownMenuItem(
        value: value,
        child: Row(
          children: [
            icon,
            const SizedBox(width: 10),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
}
