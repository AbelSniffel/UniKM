import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../widgets/nav_button_group.dart';
import '../../widgets/settings_card_inset.dart';
import '../../widgets/settings_card_indicator.dart';
import '../../widgets/settings_card_layout.dart';
import '../../widgets/popup_menu_helpers.dart';
import '../../widgets/search_highlight.dart';
import '../../widgets/tinted_card.dart';

/// Responsive settings cards with shared widths across each row.
class const SettingsControlWrap({
  super.key,
  required final List<Widget> children,
  final double minimumCardWidth = kInteractionCardMinWidth,
}) extends StatelessWidget {
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

class const SettingsChoice<T>(
  final T value,
  final String label, {

  /// What a [SettingsButtonGroupCard] button shows; the label becomes its
  /// tooltip.
  final Widget? icon,
});

/// A toggle setting as a whole-card button, its state shown by a corner dot
/// that grows when on.
class const SettingsToggleCard({
  super.key,
  required final String label,
  required final bool value,
  required final ValueChanged<bool>? onChanged,
  final String? description,

  /// Shown in a tinted square before the label: the accent while on.
  final IconData? icon,
}) extends StatelessWidget {
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

class const SettingsChoiceCard<T>({
  super.key,
  required final String label,
  required final T value,
  required final List<SettingsChoice<T>> choices,
  required final ValueChanged<T>? onChanged,
  final String? description,

  /// Shown in a tinted square before the label.
  final IconData? icon,

  /// The menu scrolls past this height, for long lists of choices.
  final double menuMaxHeight = kDropdownMenuMaxHeight,
}) extends StatefulWidget {
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
    final theme = context.appTheme;
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
class const SettingsButtonGroupCard<T>({
  super.key,
  required final String label,
  required final T value,

  /// One button each, showing its icon.
  required final List<SettingsChoice<T>> choices,
  required final ValueChanged<T>? onChanged,
  final String? description,

  /// Shown in a tinted square before the label.
  final IconData? icon,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final buttons = [for (final choice in choices) _button(choice)];
    return Semantics(
      container: true,
      enabled: onChanged != null,
      child: _SettingsControlCard(
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
            child: NavButtonGroup(isHorizontal: true, children: buttons),
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

class const _SettingsControlCard({
  required final String label,
  required final String? description,
  required final bool active,
  required final bool enabled,
  required final Widget trailing,
  final IconData? icon,

  /// Without it, the card takes no taps or hover itself and leaves them to
  /// its controls.
  final VoidCallback? onTap,

  /// A toggle card, with the corner dot in place of a trailing control.
  final bool toggle = false,

  /// Shrinks a trailing control that scales down into the room beside the
  /// label's one line, down to a third of the row.
  final bool fitTrailingBesideLabel = false,
}) extends StatefulWidget {
  @override
  State<_SettingsControlCard> createState() => _SettingsControlCardState();
}

class _SettingsControlCardState extends State<_SettingsControlCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final radius = BorderRadius.circular(theme.cornerRadius);
    final isToggle = widget.toggle;
    // Keyboard focus lights the outline of a card that takes taps; hovering
    // and pressing leave it.
    final highlighted = widget.onTap != null && _focused;
    // A settings search lights the card whose label it matches.
    final query = SettingsSearchScope.queryOf(context);
    final matched =
        query.isNotEmpty && settingsSearchMatches(query, widget.label);
    final borderColor = highlighted || matched ? theme.accent : theme.border;
    final icon = widget.icon;
    final description = widget.description?.trim().isNotEmpty == true
        ? widget.description!
        : null;
    // The option tiles' icon square.
    const iconExtent = 36.0;
    const iconGap = 12.0;
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
    // The label over its description, beside the icon, like an option
    // tile's title and subtitle.
    final label = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          Text.rich(
            searchHighlightSpan(
              widget.label,
              matched ? query : '',
              labelStyle,
              searchMarkStyle(theme.accent),
            ),
          ),
          if (description != null)
            Text(description, style: TintedCard.detailStyle(theme)),
        ],
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
              // Its corner curves with the card's, a padding out.
              borderRadius: BorderRadius.circular(
                theme.insetRadius(_cardPadding),
              ),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          );
    final background = theme.background.withValues(
      alpha: widget.enabled ? SettingsCardInset.cardFillAlpha : 0.45,
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
        // A ripple without the accent tint while held.
        highlightColor: Colors.transparent,
        onFocusChange: (value) => setState(() => _focused = value),
        onTap: widget.onTap,
        child: Padding(
          // The option tiles' padding: text alone starts further in, and a
          // toggle's label and description stop short of its bar.
          padding: EdgeInsets.all(_cardPadding).copyWith(
            left: icon == null ? 14 : null,
            right: isToggle ? SettingsCardMiniDot.barExtent : null,
          ),
          child: Opacity(
            opacity: widget.enabled ? 1 : 0.42,
            // Only the row is built in the layout callback.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final row = constraints.maxWidth;
                // A third of the row at least beside a long label.
                final trailingWidth = besideLabel == null
                    ? row * 0.65
                    : (row - besideLabel).clamp(row / 3, row * 0.65);
                // A control's height on every card.
                return ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: kElementHeight),
                  child: Row(
                    children: [
                      ?iconSquare,
                      label,
                      if (!isToggle) ...[
                        const SizedBox(width: 12),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: trailingWidth),
                          child: widget.trailing,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    return RepaintBoundary(
      child: SettingsCardInset(
        active: widget.active && widget.enabled,
        raisedWhenInactive: isToggle && widget.enabled,
        surfaceColor: theme.background,
        borderRadius: theme.cornerRadius,
        overlay: isToggle
            ? Align(
                alignment: Alignment.centerRight,
                child: SettingsCardMiniDot(
                  value: widget.active,
                  enabled: widget.enabled,
                  bar: true,
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
