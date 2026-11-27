/// Headings and tiles of the Tinted Tile dialogs (library stats, updates,
/// copy options, the game editor and the rest).
library;

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import 'settings_card_inset.dart';
import 'tinted_card.dart';

/// A section title with an optional count or note on the right, and an
/// optional [action] after it.
class const TintedHeading({
  super.key,
  required final String title,
  final String? trailing,
  final Widget? action,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        spacing: 8,
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: theme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // A long note wraps within most of the row rather than pushing the
          // title out.
          if (trailing != null)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.6),
              child: Text(
                trailing!,
                textAlign: TextAlign.end,
                style: TextStyle(color: theme.textSecondary),
              ),
            ),
          ?action,
        ],
      ),
    );
  }
}

/// A tile with an optional icon in its own tinted square, a title, an
/// optional subtitle and an optional [trailing] widget.
/// With [selected] it is one choice of several, tinted: the chosen tile is
/// tinted more strongly, pressed in and checked, easing in and out with the
/// press depth. Without, it is an action: with [onTap], raised with the
/// settings toggle cards' fill and outline and pressed in while held;
/// without, a flat [TintedCard] with its usual tint.
class const TintedOptionTile({
  super.key,
  required final String title,
  final IconData? icon,
  final String? subtitle,

  /// Replaces [subtitle], for rich or styled text.
  final Widget? details,

  /// Null for an action rather than a choice.
  final bool? selected,

  /// Presses in an action like a chosen tile, even while it takes no taps,
  /// keeping its [trailing], such as the current database.
  final bool highlighted = false,
  final VoidCallback? onTap,

  /// The icon square's colour, and a choice's tint; the accent by default.
  final Color? color,
  final Widget? trailing,
}) extends StatefulWidget {
  @override
  State<TintedOptionTile> createState() => _TintedOptionTileState();
}

class _TintedOptionTileState extends State<TintedOptionTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final color = widget.color ?? theme.accent;
    final choice = widget.selected != null;
    final chosen = widget.selected ?? widget.highlighted;
    final tappable = widget.onTap != null;
    final raised = tappable || widget.highlighted;
    final trailing = widget.selected == null
        ? widget.trailing
        : AnimatedSwitcher(
            duration: context.motion(_selectionTime),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: Icon(
              chosen ? Icons.check_circle : Icons.radio_button_unchecked,
              key: ValueKey(chosen),
              color: chosen ? color : theme.textHint,
              size: 24,
            ),
          );
    // The tint follows the selection at the pace of the inset's depth, so a
    // tile losing its choice eases out instead of snapping.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: chosen ? 1 : 0),
      duration: context.motion(_selectionTime),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        // A raised action rests on the settings cards' fill, untinted; a
        // flat one keeps the card's own tint, like the cards it sits among.
        final fill = choice
            ? color.withValues(
                alpha:
                    TintedCard.choiceFillAlpha +
                    (TintedCard.highlightedFillAlpha -
                            TintedCard.choiceFillAlpha) *
                        t,
              )
            : raised
            ? theme.background.withValues(
                alpha: SettingsCardInset.cardFillAlpha,
              )
            : null;
        final tile = TintedCard(
          color: color,
          icon: widget.icon,
          title: widget.title,
          subtitle: widget.subtitle,
          details: widget.details,
          trailing: trailing,
          fill: fill,
          // Outlined like the settings cards; choices have no outline.
          side: choice || !raised
              ? BorderSide.none
              : BorderSide(color: theme.border),
          onTap: widget.onTap,
          // Held tiles press in and ripple rather than tint.
          pressTint: false,
          onHighlightChanged: tappable
              ? (value) => setState(() => _pressed = value)
              : null,
        );
        return Semantics(
          checked: widget.selected,
          inMutuallyExclusiveGroup: widget.selected != null,
          child: raised
              ? SettingsCardInset(
                  active: chosen || _pressed,
                  raisedWhenInactive: true,
                  borderRadius: BorderRadius.circular(theme.cornerRadius),
                  // An action's depth is lit like the settings cards'.
                  surfaceColor: choice
                      ? Color.alphaBlend(fill!, theme.surface)
                      : theme.background,
                  // Like the toggle cards, a chosen tile's shading sits
                  // under its content.
                  shadeOverlay: true,
                  cacheRaster: true,
                  child: tile,
                )
              : tile,
        );
      },
    );
  }

  /// Matches [SettingsCardInset]'s depth change.
  static const _selectionTime = Duration(milliseconds: 140);
}
