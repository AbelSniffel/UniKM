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
/// subtitle and an optional [trailing] widget. With [selected] it is one
/// choice of several: the chosen tile is tinted more strongly, outlined and
/// checked. A tile with [onTap] is raised and bordered like the settings
/// cards, outlined in its colour on hover and pressed in while held or
/// chosen; one without stays flat.
class TintedOptionTile extends StatefulWidget {
  const TintedOptionTile({
    super.key,
    required this.theme,
    required this.icon,
    required this.title,
    this.subtitle,
    this.selected,
    this.onTap,
    this.color,
    this.trailing,
  });

  final AppThemeData theme;
  final IconData icon;
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
    final fill = color.withValues(alpha: chosen ? 0.16 : 0.08);
    final tile = Material(
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: chosen || (tappable && _hovered)
              ? color
              : tappable
              ? theme.border
              : Colors.transparent,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onHover: tappable ? (value) => setState(() => _hovered = value) : null,
        onHighlightChanged: tappable
            ? (value) => setState(() => _pressed = value)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            spacing: 12,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: radius,
                ),
                child: Icon(widget.icon, color: color, size: 20),
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
                        style: TextStyle(
                          color: theme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.selected != null)
                Icon(
                  chosen ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: chosen ? color : theme.textHint,
                  size: 20,
                )
              else
                ?widget.trailing,
            ],
          ),
        ),
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
              child: tile,
            )
          : tile,
    );
  }
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
