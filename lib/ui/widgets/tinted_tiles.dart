/// Headings and tiles of the Tinted Tile dialogs (library stats, updates,
/// copy options, the game editor and the rest).
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'settings_card_inset.dart';

/// A section title with an optional count or note on the right, and an
/// optional [action] after it.
class TintedHeading extends StatelessWidget {
  const TintedHeading({
    super.key,
    required this.theme,
    required this.title,
    this.trailing,
    this.action,
  });

  final AppThemeData theme;
  final String title;
  final String? trailing;
  final Widget? action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
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

/// A tinted tile with an icon in its own square, a title, an optional
/// subtitle and an optional [trailing] widget. A [leading] widget, such as a
/// live preview of the choice, replaces the icon in a wider square.
/// With [selected] it is one choice of several: the chosen tile is tinted more
/// strongly, pressed in and checked, easing in and out with the press depth.
/// A tile with [onTap] is raised and bordered like the settings cards,
/// outlined in its colour on hover and pressed in while held or chosen; one
/// without stays flat.
class TintedOptionTile extends StatefulWidget {
  const TintedOptionTile({
    super.key,
    required this.theme,
    required this.title,
    this.icon,
    this.leading,
    this.subtitle,
    this.selected,
    this.onTap,
    this.color,
    this.trailing,
  }) : assert(icon != null || leading != null);

  final AppThemeData theme;
  final IconData? icon;

  /// Shown instead of [icon], for display only: it takes no taps or focus.
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// Null for an action rather than a choice.
  final bool? selected;
  final VoidCallback? onTap;

  /// The tint; the accent by default.
  final Color? color;

  @override
  State<TintedOptionTile> createState() => _TintedOptionTileState();
}

class _TintedOptionTileState extends State<TintedOptionTile> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final color = widget.color ?? theme.accent;
    final chosen = widget.selected ?? false;
    final tappable = widget.onTap != null;
    final radius = BorderRadius.circular(theme.cornerRadius);
    final leading = widget.leading;
    final content = Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        spacing: 12,
        children: [
          Container(
            width: leading == null ? 36 : 64,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: radius,
            ),
            child: leading == null
                ? Icon(widget.icon, color: color, size: 20)
                : IgnorePointer(
                    child: ExcludeSemantics(
                      child: ExcludeFocus(
                        child: FittedBox(fit: BoxFit.scaleDown, child: leading),
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  widget.title,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.subtitle != null)
                  Text(
                    widget.subtitle!,
                    style: TextStyle(color: theme.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (widget.selected != null)
            AnimatedSwitcher(
              duration: _selectionDuration(context),
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
                size: 20,
              ),
            )
          else
            ?widget.trailing,
        ],
      ),
    );
    // The tint follows the selection at the pace of the inset's depth, so a
    // tile losing its choice eases out instead of snapping.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: chosen ? 1 : 0),
      duration: _selectionDuration(context),
      curve: Curves.easeOutCubic,
      child: content,
      builder: (context, t, content) {
        final fill = color.withValues(alpha: 0.08 + 0.08 * t);
        final tile = Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: !tappable
                ? BorderSide.none
                : _hovered
                ? BorderSide(color: color, width: 1.5)
                : BorderSide(color: theme.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onHover: tappable
                ? (value) => setState(() => _hovered = value)
                : null,
            onHighlightChanged: tappable
                ? (value) => setState(() => _pressed = value)
                : null,
            child: content,
          ),
        );
        return Semantics(
          checked: widget.selected,
          inMutuallyExclusiveGroup: widget.selected != null,
          child: tappable
              ? SettingsCardInset(
                  active: chosen || _pressed,
                  raisedWhenInactive: true,
                  borderRadius: theme.cornerRadius,
                  surfaceColor: Color.alphaBlend(fill, theme.surface),
                  cacheRaster: true,
                  child: tile,
                )
              : tile,
        );
      },
    );
  }

  /// Matches [SettingsCardInset]'s depth change.
  static Duration _selectionDuration(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 140);
}

/// A card tinted with [color] (the accent by default): a large icon in its
/// own square, or [leading] in its place, a bold title and a subtitle, with
/// an optional [trailing] widget.
class TintedStatusCard extends StatelessWidget {
  const TintedStatusCard({
    super.key,
    required this.theme,
    required this.title,
    this.icon,
    this.leading,
    this.subtitle,
    this.trailing,
    this.color,
  });

  final AppThemeData theme;
  final String title;
  final IconData? icon;
  final Widget? leading;
  final String? subtitle;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? theme.accent;
    final radius = BorderRadius.circular(theme.cornerRadius);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: radius,
      ),
      child: Row(
        spacing: 14,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: radius,
            ),
            child: Center(child: leading ?? Icon(icon, color: color, size: 26)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(color: theme.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
