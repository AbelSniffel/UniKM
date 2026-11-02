/// The tinted card shared by the dialogs and notifications: an icon in its
/// own tinted square beside a title and a subtitle, on a card tinted with the
/// same colour. Its tints are set here, for every card at once.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The card's scale: [compact] for list rows and choices, [large] for the
/// status card heading a dialog or a notification.
enum TintedCardSize { compact, large }

/// A card tinted with [color] (the accent by default): [icon] in its own
/// tinted square (a spinner while [busy]), or [leading] in its place (or
/// neither, for text alone), a
/// [title] over a [subtitle] or richer [details], an optional large [figure]
/// with its [figureCaption], and [trailing] actions. [children] run across
/// the card under them, such as progress or buttons.
///
/// The [highlighted] card is tinted more strongly and outlined in its colour.
/// A card with [onTap] has an ink splash.
class TintedCard extends StatelessWidget {
  const TintedCard({
    super.key,
    required this.theme,
    required this.title,
    this.icon,
    this.leading,
    this.busy = false,
    this.busyValue,
    this.subtitle,
    this.details,
    this.figure,
    this.figureCaption,
    this.trailing,
    this.children = const [],
    this.color,
    this.size = TintedCardSize.compact,
    this.highlighted = false,
    this.fill,
    this.side,
    this.onTap,
    this.onHover,
    this.onHighlightChanged,
    this.backdrop,
    this.shadows,
    this.bottomEdge,
    this.liveRegion = false,
  });

  /// The card's tint.
  static const double fillAlpha = 0.15;

  /// A highlighted card's tint, and a chosen choice tile's.
  static const double highlightedFillAlpha = 0.35;

  /// A choice tile's tint while it is not chosen.
  static const double choiceFillAlpha = 0.10;

  /// The icon square's tint, over the card's.
  static const double tileAlpha = 0.25;

  final AppThemeData theme;
  final String title;
  final IconData? icon;

  /// Replaces the icon square, such as a cover or a [tile] around a preview.
  final Widget? leading;
  final bool busy;

  /// Fills the spinner to this share instead of spinning.
  final double? busyValue;
  final String? subtitle;

  /// Replaces [subtitle], for rich or styled text.
  final Widget? details;

  /// A number as large as the stats tiles' numbers, in the card's colour.
  final String? figure;
  final String? figureCaption;
  final Widget? trailing;
  final List<Widget> children;
  final Color? color;
  final TintedCardSize size;
  final bool highlighted;

  /// Overrides the tint, such as a choice tile easing between its tints.
  final Color? fill;

  /// Overrides the outline.
  final BorderSide? side;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHover;
  final ValueChanged<bool>? onHighlightChanged;

  /// An opaque colour under the tint, for a card floating over other content.
  final Color? backdrop;
  final List<BoxShadow>? shadows;

  /// Drawn flush along the card's bottom edge, outside its padding.
  final Widget? bottomEdge;

  /// Announces the title when it changes.
  final bool liveRegion;

  /// Secondary detail text, such as a subtitle's own line; larger on a
  /// [TintedCardSize.large] card.
  static TextStyle detailStyle(AppThemeData theme, {bool large = false}) =>
      TextStyle(
        color: theme.textSecondary,
        fontSize: large ? 14 : 12,
        fontWeight: FontWeight.w400,
      );

  /// The icon square, for a [leading] widget that keeps its look.
  static Widget tile({
    required AppThemeData theme,
    required Color color,
    required Widget child,
    double size = 36,
    double? width,
  }) => Container(
    width: width ?? size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: tileAlpha),
      borderRadius: BorderRadius.circular(theme.cornerRadius),
    ),
    child: Center(child: child),
  );

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? theme.accent;
    final large = size == TintedCardSize.large;
    final tint =
        fill ??
        color.withValues(alpha: highlighted ? highlightedFillAlpha : fillAlpha);
    final row = Row(
      spacing: large ? 14 : 12,
      children: [
        if (leading != null)
          leading!
        else if (icon != null || busy)
          tile(
            theme: theme,
            color: color,
            size: large ? 46 : 36,
            child: busy
                ? SizedBox.square(
                    dimension: large ? 24 : 18,
                    // Its own layer, so the spinner repaints only itself.
                    child: RepaintBoundary(
                      child: CircularProgressIndicator(
                        value: busyValue,
                        color: color,
                        backgroundColor: theme.accent.withValues(alpha: 0.2),
                        strokeWidth: theme.progressIndicatorStrokeWidth,
                      ),
                    ),
                  )
                : Icon(icon, color: color, size: large ? 26 : 20),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Semantics(
                liveRegion: liveRegion,
                header: large,
                child: Text(
                  title,
                  maxLines: large ? null : 2,
                  overflow: large ? null : TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: large ? 18 : null,
                    fontWeight: large ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              details ??
                  (subtitle == null
                      ? null
                      : Text(
                          subtitle!,
                          style: detailStyle(theme, large: large),
                        )),
            ].nonNulls.toList(),
          ),
        ),
        if (figure != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                figure!,
                style: TextStyle(
                  color: color,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (figureCaption != null)
                Text(figureCaption!, style: detailStyle(theme)),
            ],
          ),
        ?trailing,
      ],
    );
    Widget content = Padding(
      padding: EdgeInsets.all(large ? 12 : 8),
      child: children.isEmpty
          ? row
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [row, ...children],
            ),
    );
    if (bottomEdge != null) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [content, bottomEdge!],
      );
    }
    if (onTap != null || onHover != null || onHighlightChanged != null) {
      content = InkWell(
        onTap: onTap,
        onHover: onHover,
        onHighlightChanged: onHighlightChanged,
        child: content,
      );
    }
    final radius = BorderRadius.circular(theme.cornerRadius);
    final card = Material(
      color: backdrop == null ? tint : Color.alphaBlend(tint, backdrop!),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        // side:
        //     side ?? (highlighted ? BorderSide(color: color) : BorderSide.none),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
    return shadows == null
        ? card
        : DecoratedBox(
            decoration: BoxDecoration(borderRadius: radius, boxShadow: shadows),
            child: card,
          );
  }
}
