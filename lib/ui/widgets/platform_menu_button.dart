import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../providers/ui_state_providers.dart' show kAutoDetectPlatformValue;
import '../../core/constants/app_constants.dart';
import '../../core/constants/platform_patterns.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/surface_depth.dart';
import 'app_tab_bar.dart' show AppTabSurface;
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
    this.expanded = false,
    this.tabStyle = false,
  });

  final AppThemeData theme;
  final T value;
  final String tooltip;
  final ValueChanged<T>? onSelected;

  /// The current choice's icon in the given color and size.
  final Widget Function(Color color, double size) icon;
  final List<(T, String, Widget)> choices;

  /// Fills the width offered, naming the current choice beside its icon
  /// whenever the whole name fits.
  final bool expanded;

  /// A standalone tab, selected while the menu is open, in place of the
  /// navigation style; the icon still grows on hover and while open.
  final bool tabStyle;

  @override
  State<IconMenuButton<T>> createState() => _IconMenuButtonState<T>();
}

class _IconMenuButtonState<T> extends State<IconMenuButton<T>> {
  final _menu = MenuController();
  final _focusNode = FocusNode(skipTraversal: true);
  var _hovered = false;

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
      width: 230,
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
            child: widget.expanded
                ? LayoutBuilder(
                    builder: (context, constraints) =>
                        _button(theme, enabled, controller, constraints),
                  )
                // The button fills any space it is offered; this keeps it to
                // its content unless the parent sets its size.
                : IntrinsicWidth(
                    child: IntrinsicHeight(
                      child: _button(theme, enabled, controller, null),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  /// The navigation-style button. Given [constraints] (expanded), it names
  /// the current choice when the whole name fits.
  Widget _button(
    AppThemeData theme,
    bool enabled,
    MenuController controller,
    BoxConstraints? constraints,
  ) {
    Widget chevron(Color muted) => Icon(
      Icons.keyboard_arrow_down,
      color: enabled ? theme.textPrimary : muted,
      size: 20,
    );
    final label = widget.choices
        .where((choice) => choice.$1 == widget.value)
        .firstOrNull
        ?.$2;
    var named = false;
    if (constraints != null && label != null) {
      final painter = TextPainter(
        // The button's label style, over the inherited one.
        text: TextSpan(
          text: label,
          style: DefaultTextStyle.of(
            context,
          ).style.merge(const TextStyle(fontSize: 14)),
        ),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      // Padding, icon, gap and chevron around the name.
      named =
          painter.width + 10 + kIconSize + 6 + 20 + 6 <= constraints.maxWidth;
      painter.dispose();
    }
    if (widget.tabStyle) {
      final radius = BorderRadius.circular(theme.cornerRadius * 1.25);
      final grow = enabled && (_hovered || controller.isOpen);
      return Tooltip(
        message: widget.tooltip,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [SurfaceDepth.shadow(isDark: theme.isDark)],
          ),
          child: AppTabSurface(
            theme: theme,
            selected: controller.isOpen,
            borderRadius: radius,
            onTap: enabled ? _toggleMenu : null,
            onHover: (hovered) => setState(() => _hovered = hovered),
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            builder: (context, color) => Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TweenAnimationBuilder(
                  tween: Tween(end: grow ? 1.2 : 1.0),
                  duration: const Duration(milliseconds: 100),
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: widget.icon(color, kIconSize),
                ),
                SizedBox(width: named ? 6 : 1),
                if (named)
                  Flexible(
                    child: Text(
                      label!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: color),
                    ),
                  ),
                Icon(Icons.keyboard_arrow_down, color: color, size: 20),
              ],
            ),
          ),
        ),
      );
    }
    return AppNavigationButton(
      theme: theme,
      isSelected: controller.isOpen,
      isEnabled: enabled,
      isHorizontal: true,
      onTap: _toggleMenu,
      tooltipMessage: widget.tooltip,
      selectedBackgroundColor: theme.accent.withValues(alpha: 0.30),
      // The chevron's glyph has its own side margin, so the icon side gets
      // more padding to look even.
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      labelText: named ? label : null,
      trailing: named ? chevron(theme.textHint) : null,
      // The choice keeps the accent; disabled buttons take the muted color
      // the button gives them.
      iconBuilder: (context, color, size) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          widget.icon(enabled ? theme.accent : color, size),
          if (!named) ...[const SizedBox(width: 1), chevron(color)],
        ],
      ),
    );
  }
}
