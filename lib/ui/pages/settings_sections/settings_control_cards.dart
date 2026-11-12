import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../widgets/nav_button_group.dart';
import '../../widgets/settings_card_inset.dart';
import '../../widgets/settings_card_indicator.dart';
import '../../widgets/settings_card_layout.dart';
import '../../widgets/popup_menu_helpers.dart';
import '../../widgets/search_highlight.dart';

/// Responsive settings cards with shared widths across each row.
class SettingsControlWrap extends StatelessWidget {
  const SettingsControlWrap({
    super.key,
    required this.children,
    this.minimumCardWidth = kInteractionCardMinWidth,
  });

  final List<Widget> children;
  final double minimumCardWidth;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final width = constraints.maxWidth;
        if (!width.isFinite) {
          return Wrap(spacing: gap, runSpacing: gap, children: children);
        }
        final cardWidth = settingsCardWidth(
          availableWidth: width,
          cardCount: children.length,
          minimumCardWidth: minimumCardWidth,
        );
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(width: cardWidth, child: child),
          ],
        );
      },
    );
  }
}

class SettingsChoice<T> {
  const SettingsChoice(this.value, this.label, {this.icon});

  final T value;
  final String label;

  /// What a [SettingsButtonGroupCard] button shows; the label becomes its
  /// tooltip.
  final Widget? icon;
}

/// A toggle setting as a whole-card button, its state shown by a corner dot
/// that grows when on.
class SettingsToggleCard extends StatelessWidget {
  const SettingsToggleCard({
    super.key,
    required this.theme,
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
    this.icon,
  });

  final AppThemeData theme;
  final String label;
  final String? description;

  /// Shown in a tinted square before the label: the accent while on.
  final IconData? icon;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: value,
      enabled: onChanged != null,
      label: label,
      value: onChanged == null
          ? 'Disabled'
          : value
          ? 'On'
          : 'Off',
      child: _SettingsControlCard(
        theme: theme,
        label: label,
        description: description,
        icon: icon,
        active: value,
        toggle: true,
        enabled: onChanged != null,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: const SizedBox.shrink(),
      ),
    );
  }
}

/// A whole-card action for status and management settings.
class SettingsActionCard extends StatelessWidget {
  const SettingsActionCard({
    super.key,
    required this.theme,
    required this.label,
    required this.actionLabel,
    required this.onTap,
    this.description,
    this.actionIcon,
  });

  final AppThemeData theme;
  final String label;
  final String? description;
  final String actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Flexible in rows sized to their content, so the action takes only the
    // width it needs and leaves the rest to the label.
    final text = Flexible(
      child: Text(
        actionLabel,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: theme.accent, fontWeight: FontWeight.w600),
      ),
    );
    // Both layouts are built here, so a width change only picks one.
    final withIcons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (actionIcon != null) ...[
          Icon(actionIcon, color: theme.accent, size: 18),
          const SizedBox(width: 6),
        ],
        text,
        const SizedBox(width: 4),
        // Themed like the action's text.
        Icon(Icons.arrow_forward_rounded, color: theme.accent, size: 18),
      ],
    );
    final textOnly = Row(mainAxisSize: MainAxisSize.min, children: [text]);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: '$label, $actionLabel',
      child: _SettingsControlCard(
        theme: theme,
        label: label,
        description: description,
        active: false,
        enabled: onTap != null,
        onTap: onTap,
        // Raised like an off toggle card while it takes taps.
        raised: onTap != null,
        trailing: LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth >= 120 ? withIcons : textOnly,
        ),
      ),
    );
  }
}

class SettingsChoiceCard<T> extends StatefulWidget {
  const SettingsChoiceCard({
    super.key,
    required this.theme,
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.description,
    this.icon,
    this.menuMaxHeight = kDropdownMenuMaxHeight,
  });

  final AppThemeData theme;
  final String label;
  final String? description;

  /// Shown in a tinted square before the label.
  final IconData? icon;

  final T value;
  final List<SettingsChoice<T>> choices;
  final ValueChanged<T>? onChanged;

  /// The menu scrolls past this height, for long lists of choices.
  final double menuMaxHeight;

  @override
  State<SettingsChoiceCard<T>> createState() => _SettingsChoiceCardState<T>();
}

class _SettingsChoiceCardState<T> extends State<SettingsChoiceCard<T>> {
  final _menu = MenuController();

  /// The card's width, taken as the menu opens so a resize never rebuilds it.
  double? _menuWidth;

  void _toggleMenu() {
    if (_menu.isOpen) return _menu.close();
    setState(() => _menuWidth = (context.size ?? Size.zero).width);
    // Opens once the width has rebuilt into the menu.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_menu.isOpen) _menu.open();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final selected = widget.choices
        .where((choice) => choice.value == widget.value)
        .firstOrNull;
    final selectedLabel = selected?.label ?? widget.value.toString();
    final selectedChoice = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            selectedLabel,
            style: TextStyle(color: theme.accent, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 3),
          Icon(Icons.arrow_drop_down, color: theme.textSecondary),
        ],
      ),
    );
    return AppMenuAnchor(
      theme: theme,
      controller: _menu,
      // The menu matches the card's width.
      width: _menuWidth,
      maxHeight: widget.menuMaxHeight,
      menuChildren: [
        for (final choice in widget.choices)
          appMenuItem(
            theme,
            selected: choice.value == widget.value,
            onPressed: () => widget.onChanged?.call(choice.value),
            child: Text(choice.label),
          ),
      ],
      builder: (context, controller, _) => Semantics(
        button: true,
        enabled: widget.onChanged != null,
        label: widget.label,
        value: selectedLabel,
        child: _SettingsControlCard(
          theme: theme,
          label: widget.label,
          description: widget.description,
          icon: widget.icon,
          active: selected != null,
          enabled: widget.onChanged != null,
          onTap: widget.onChanged == null ? null : _toggleMenu,
          trailing: selectedChoice,
        ),
      ),
    );
  }
}

/// A card with its choices as a row of buttons, in the navigation panel's
/// button group like settings headers' actions, the selected one highlighted.
/// Only the buttons take taps, so the card itself never lights up.
class SettingsButtonGroupCard<T> extends StatelessWidget {
  const SettingsButtonGroupCard({
    super.key,
    required this.theme,
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.description,
    this.icon,
  });

  final AppThemeData theme;
  final String label;
  final String? description;

  /// Shown in a tinted square before the label.
  final IconData? icon;

  final T value;

  /// One button each, showing its icon.
  final List<SettingsChoice<T>> choices;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final buttons = [for (final choice in choices) _button(choice)];
    return Semantics(
      container: true,
      enabled: onChanged != null,
      child: _SettingsControlCard(
        theme: theme,
        label: label,
        description: description,
        icon: icon,
        active: choices.any((choice) => choice.value == value),
        enabled: onChanged != null,
        fitTrailingBesideLabel: true,
        // Button animations can repaint without redrawing the card.
        trailing: FittedBox(
          fit: BoxFit.scaleDown,
          child: RepaintBoundary(
            // Settings header actions' button group.
            child: NavButtonGroup(
              theme: theme,
              isHorizontal: true,
              children: buttons,
            ),
          ),
        ),
      ),
    );
  }

  Widget _button(SettingsChoice<T> choice) {
    final selected = choice.value == value;
    final choose = onChanged == null
        ? null
        : () {
            if (!selected) onChanged!(choice.value);
          };
    return Semantics(
      container: true,
      button: true,
      enabled: onChanged != null,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: choice.label,
      excludeSemantics: true,
      onTap: choose,
      // The navigation panel's selectable button, as settings headers use it.
      child: SizedBox(
        height: 28,
        child: AppNavigationButton(
          theme: theme,
          isSelected: selected,
          isEnabled: choose != null,
          isHorizontal: true,
          onTap: choose,
          tooltipMessage: choice.label,
          iconBuilder: (context, color, size) => IconTheme.merge(
            data: IconThemeData(color: color, size: size),
            child: choice.icon ?? const SizedBox.shrink(),
          ),
          iconSize: 18,
          padding: const EdgeInsets.all(5),
          minWidth: 28,
        ),
      ),
    );
  }
}

class _SettingsControlCard extends StatefulWidget {
  const _SettingsControlCard({
    required this.theme,
    required this.label,
    required this.description,
    required this.active,
    required this.enabled,
    required this.trailing,
    this.icon,
    this.onTap,
    this.toggle = false,
    this.raised = false,
    this.fitTrailingBesideLabel = false,
  });

  final AppThemeData theme;
  final String label;
  final String? description;
  final bool active;
  final bool enabled;
  final Widget trailing;
  final IconData? icon;

  /// A toggle card, with the corner dot in place of a trailing control.
  final bool toggle;

  /// Raises the card like an off toggle card; toggle cards always are, the
  /// other cards rest flat without it.
  final bool raised;

  /// Without it, the card takes no taps or hover itself and leaves them to
  /// its controls.
  final VoidCallback? onTap;

  /// Shrinks a trailing control that scales down into the room beside the
  /// label's one line, down to a third of the row.
  final bool fitTrailingBesideLabel;

  @override
  State<_SettingsControlCard> createState() => _SettingsControlCardState();
}

class _SettingsControlCardState extends State<_SettingsControlCard> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final radius = BorderRadius.circular(theme.cornerRadius);
    final isToggle = widget.toggle;
    // Only a card that takes taps lights up; a disabled one takes none.
    final highlighted =
        widget.onTap != null && (_hovered || _pressed || _focused);
    // A settings search lights the card whose label it matches.
    final query = SettingsSearchScope.queryOf(context);
    final matched =
        query.isNotEmpty && settingsSearchMatches(query, widget.label);
    final borderColor = highlighted || matched ? theme.accent : theme.border;
    final icon = widget.icon;
    final description = widget.description?.trim().isNotEmpty == true
        ? widget.description!
        : null;
    // The option tiles' icon square, smaller above a description so the
    // description stays close under the label.
    final compactIcon = description != null;
    final iconExtent = compactIcon ? 28.0 : 36.0;
    final iconGap = compactIcon ? 10.0 : 12.0;
    final descriptionStyle = TextStyle(
      color: theme.textSecondary,
      fontSize: 12,
    );
    // Built outside the layout callback, so a width change does not rebuild it.
    final labelStyle = TextStyle(
      color: theme.textPrimary,
      fontWeight: FontWeight.w600,
    );
    // The label's one line with the icon square and both gaps, for a
    // trailing control that fits beside them.
    final besideLabel = widget.fitTrailingBesideLabel
        ? _lineWidth(context, widget.label, labelStyle) +
              (icon == null ? 0 : iconExtent + iconGap) +
              12
        : null;
    final label = Expanded(
      child: Text.rich(
        searchHighlightSpan(
          widget.label,
          matched ? query : '',
          labelStyle,
          searchMarkStyle(theme.accent),
        ),
      ),
    );
    // A disabled card's icon goes grey even while its setting stays on.
    final iconColor = widget.active && widget.enabled
        ? theme.accent
        : theme.textSecondary;
    final iconSquare = icon == null
        ? null
        : Container(
            width: iconExtent,
            height: iconExtent,
            margin: EdgeInsetsDirectional.only(end: iconGap),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.25),
              borderRadius: radius,
            ),
            child: Icon(icon, size: compactIcon ? 18 : 20, color: iconColor),
          );
    final background = theme.background.withValues(
      alpha: widget.enabled ? 0.55 : 0.45,
    );
    final material = Material(
      animationDuration: const Duration(milliseconds: 140),
      color: matched
          ? Color.alphaBlend(theme.accent.withValues(alpha: 0.12), background)
          : background,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: !widget.enabled
            ? BorderSide.none
            : BorderSide(
                color: borderColor,
                width: highlighted || matched ? 1.5 : 1,
              ),
      ),
      child: InkWell(
        borderRadius: radius,
        mouseCursor: !widget.enabled
            ? SystemMouseCursors.forbidden
            : widget.onTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        onHover: (value) => setState(() => _hovered = value),
        onHighlightChanged: (value) => setState(() => _pressed = value),
        onFocusChange: (value) => setState(() => _focused = value),
        onTap: widget.onTap,
        child: Padding(
          // The option tiles' padding: text alone starts further in.
          padding: EdgeInsets.all(
            _cardPadding,
          ).copyWith(left: icon == null ? 14 : null),
          child: Opacity(
            opacity: widget.enabled ? 1 : 0.42,
            // The icon and control sit on the label's row, and the
            // description spans the whole card below them, so neither takes
            // width from it. Only the label row is built in the layout
            // callback.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final row = constraints.maxWidth;
                    // A third of the row at least beside a long label.
                    final trailingWidth = besideLabel == null
                        ? row * 0.65
                        : (row - besideLabel).clamp(row / 3, row * 0.65);
                    // A toggle's switch height on every card, so a
                    // description keeps the same gap below its row.
                    return ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: kElementHeight,
                      ),
                      child: Row(
                        children: [
                          ?iconSquare,
                          label,
                          // The label stops short of the corner dot.
                          if (isToggle)
                            const SizedBox(
                              width: SettingsCardMiniDot.extent - _cardPadding,
                            )
                          else ...[
                            const SizedBox(width: 12),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: trailingWidth,
                              ),
                              child: widget.trailing,
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
                if (description != null)
                  Text(description, style: descriptionStyle),
              ],
            ),
          ),
        ),
      ),
    );
    return RepaintBoundary(
      child: SettingsCardInset(
        active: widget.active && widget.enabled,
        raisedWhenInactive: (isToggle || widget.raised) && widget.enabled,
        surfaceColor: theme.background,
        borderRadius: theme.cornerRadius,
        overlay: isToggle
            ? Align(
                alignment: Alignment.topRight,
                child: SettingsCardMiniDot(
                  theme: theme,
                  value: widget.active,
                  enabled: widget.enabled,
                ),
              )
            : null,
        shadeOverlay: !(widget.active && widget.enabled),
        cacheRaster: true,
        child: RepaintBoundary(child: material),
      ),
    );
  }
}

/// The option tiles' padding around a card's content.
const double _cardPadding = 10;

/// [text]'s width on one line in [style], as a [Text] here would draw it.
double _lineWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width.ceilToDouble();
  painter.dispose();
  return width;
}
