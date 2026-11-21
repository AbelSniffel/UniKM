import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../providers/ui_state_providers.dart' show kAutoDetectPlatformValue;
import '../../core/constants/app_constants.dart';
import '../../core/constants/platform_patterns.dart';
import '../../core/theme/app_theme.dart';
import 'platform_icon.dart';
import 'popup_menu_helpers.dart';

/// Compact platform selector shared by game-key fields and batch entry.
class const PlatformMenuButton({
  super.key,
  required final String value,
  required final String tooltip,
  required final ValueChanged<String>? onSelected,
  final GamePlatform? detectedPlatform,
  final bool includeAutoDetect = true,

  /// Drawn as an [IconMenuButton.segment] of a split box.
  final bool segment = false,

  /// See [IconMenuButton.segmentAtTop].
  final bool segmentAtTop = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final platform = value == kAutoDetectPlatformValue
        ? detectedPlatform
        : GamePlatform.fromDisplayName(value);
    return IconMenuButton<String>(
      value: value,
      tooltip: tooltip,
      segment: segment,
      segmentAtTop: segmentAtTop,
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
            PlatformIcon(
              platform: choice,
              color: context.appTheme.textPrimary,
              size: 18,
            ),
          ),
      ],
    );
  }
}

/// A navigation-style button showing the current choice's icon and a chevron,
/// which opens a menu of [choices] (value, label, icon).
class const IconMenuButton<T>({
  super.key,
  required final T value,
  required final String tooltip,
  required final ValueChanged<T>? onSelected,

  /// The current choice's icon in the given color and size.
  required final Widget Function(Color color, double size) icon,
  required final List<(T, String, Widget)> choices,

  /// Fills the width offered, naming the current choice beside its icon
  /// whenever the whole name fits.
  final bool expanded = false,

  /// One part of a split box, such as a [MenuButtonGroup] or the game key
  /// field, in place of the navigation style: the icon, the name when it
  /// fits, and the chevron, centred when the name is left out. Tinted with
  /// the accent while the menu is open.
  final bool segment = false,

  /// Keeps a tall segment's icon and chevron at its top, as tall as a
  /// button, instead of centred.
  final bool segmentAtTop = false,
}) extends StatefulWidget {
  @override
  State<IconMenuButton<T>> createState() => _IconMenuButtonState<T>();
}

class _IconMenuButtonState<T> extends State<IconMenuButton<T>> with MenuToggle {
  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final enabled = widget.onSelected != null;
    return AppMenuAnchor(
      controller: menu,
      childFocusNode: menuFocusNode,
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
          focusNode: menuFocusNode,
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
    // Padding, icon, gaps and chevron around the name.
    final chrome = widget.segment
        ? 10 + 20 + 6 + 6 + 20 + 10
        : 10 + kIconSize + 6 + 20 + 6;
    var named = false;
    if (constraints != null && label != null) {
      final painter = TextPainter(
        // The button's label style, over the inherited one.
        text: TextSpan(
          text: label,
          style: DefaultTextStyle.of(context).style
              .merge(const TextStyle(fontSize: 14)),
        ),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      named = painter.width + chrome <= constraints.maxWidth;
      painter.dispose();
    }
    if (widget.segment) {
      // The name, when shown, takes the spare width, so the icon sits at the
      // start and the chevron at the end; without it the two are centred.
      final row = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: named ? 6 : 2,
        children: [
          widget.icon(enabled ? theme.accent : theme.textSecondary, 20),
          if (named)
            Expanded(
              child: Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: theme.textPrimary),
              ),
            ),
          Icon(Icons.keyboard_arrow_down, color: theme.textSecondary, size: 20),
        ],
      );
      return Tooltip(
        message: widget.tooltip,
        child: Material(
          color: controller.isOpen
              ? theme.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          child: InkWell(
            onTap: enabled ? toggleMenu : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: widget.segmentAtTop
                  ? Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(height: 42, child: row),
                    )
                  : row,
            ),
          ),
        ),
      );
    }
    return AppNavigationButton(
      isSelected: controller.isOpen,
      isEnabled: enabled,
      isHorizontal: true,
      onTap: toggleMenu,
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

/// Menu buttons made [IconMenuButton.segment]s, side by side in one box
/// framed like a search field, with a thin line between each. [expanded]
/// shares the width it is given out between them.
class const MenuButtonGroup({
  super.key,
  required final List<Widget> children,
  final bool expanded = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final radius = BorderRadius.circular(theme.cornerRadius);
    return Container(
      decoration: BoxDecoration(
        color: theme.inputBackground,
        borderRadius: radius,
        border: Border.all(color: theme.border),
      ),
      // The segments' ink stays inside the frame.
      child: ClipRRect(
        borderRadius: radius,
        child: Row(
          mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, child) in children.indexed) ...[
              if (index > 0)
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  indent: 8,
                  endIndent: 8,
                  color: theme.border,
                ),
              if (expanded) Expanded(child: child) else child,
            ],
          ],
        ),
      ),
    );
  }
}

/// An [IconMenuButton.segment] inside a text field's box, split from the
/// text by a line as [MenuButtonGroup]'s segments are: at the end of the box,
/// or at its start.
class const FieldSegment({
  super.key,
  required final Widget child,
  final bool atStart = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final divider = SizedBox(
      height: 44,
      child: VerticalDivider(width: 1, thickness: 1, color: theme.border),
    );
    final segment = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        child: SizedBox(height: 42, child: child),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: atStart ? [segment, divider] : [divider, segment],
    );
  }
}
