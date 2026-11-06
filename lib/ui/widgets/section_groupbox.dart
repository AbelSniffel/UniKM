/// Section GroupBox widget
/// Matches the original Python SectionGroupBox with left/top title positions
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/surface_depth.dart';
import 'search_highlight.dart';
import 'tinted_card.dart';

/// Controls how a group box is positioned within a connected group strip.
/// - [only]: standalone box, full border, all corners rounded (default)
/// - [first]: top of a strip, top border + left/right, top corners rounded
/// - [middle]: interior row, left/right border only, no corner rounding
/// - [last]: bottom of a strip, bottom + left/right, bottom corners rounded
/// - [firstAttached]: like [first] but top corners are flat — for when a
///   header widget sits directly above the strip.
/// - [onlyAttached]: like [only] but top corners are flat — solo group with
///   a header directly above it.
enum SectionGroupPosition {
  only,
  first,
  middle,
  last,
  firstAttached,
  onlyAttached,
}

/// Settings panels show their groups as plain headings over their content,
/// without a frame, like the Tinted Tile dialogs.
class SpacedSettingsGroups extends InheritedWidget {
  const SpacedSettingsGroups({super.key, required super.child});

  static bool isEnabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SpacedSettingsGroups>() !=
      null;

  @override
  bool updateShouldNotify(SpacedSettingsGroups oldWidget) => false;
}

/// Keeps the [SectionGroupBox]es below it raised whatever the page pattern,
/// for a dialog that no page pattern shows through.
class RaisedGroupBoxes extends InheritedWidget {
  const RaisedGroupBoxes({super.key, required super.child});

  static bool isEnabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RaisedGroupBoxes>() != null;

  @override
  bool updateShouldNotify(RaisedGroupBoxes oldWidget) => false;
}

/// Section groupbox with configurable title position
class SectionGroupBox extends ConsumerWidget {
  const SectionGroupBox({
    super.key,
    required this.title,
    required this.theme,
    required this.child,
    this.titleLocation,
    this.padding = const EdgeInsets.all(12),
    this.titleIcon,
    this.trailing,
    this.stackTrailingWhenCompact = false,
    this.headerCrossAxisAlignment = CrossAxisAlignment.start,
    this.headerBottomPadding = 12,
    this.searchQuery = '',
    this.groupPosition = SectionGroupPosition.only,
    this.alternateBackground = false,
    this.showTitle = true,
    this.plainTitle = false,
  });

  final String title;
  final AppThemeData theme;
  final Widget child;

  /// Optional override. When null, uses `SettingsKeys.sectionTitleLocation`.
  final SectionTitleLocation? titleLocation;
  final EdgeInsets padding;
  final IconData? titleIcon;
  final Widget? trailing;

  /// Header action groups use the same breakpoint as full-width settings cards.
  final bool stackTrailingWhenCompact;
  final CrossAxisAlignment headerCrossAxisAlignment;

  /// Gap below a top title, before the body content.
  final double headerBottomPadding;
  final String searchQuery;

  /// Position of this box within a connected group strip.
  final SectionGroupPosition groupPosition;

  /// When true, the body takes the tinted cards' slightly stronger tint
  /// ([TintedCard.fillAlpha]) — creates the alternating-row visual effect.
  final bool alternateBackground;

  /// When false, the title header (or left title panel) is not rendered — only
  /// the bordered/background container is shown. Useful when you want the
  /// groupbox strip visuals (borders, alternating colours) without labels.
  final bool showTitle;

  /// Titles a framed box in the text colour, as flat headings are, instead
  /// of the accent.
  final bool plainTitle;

  /// The surface's opacity while the pattern shows on pages ([tinted]).
  static const double patternAlpha = 0.8;

  /// The raised surface under the [gradient], see-through while the pattern
  /// shows on pages ([tinted]). [alternate] takes the darker surface.
  static Color background(
    AppThemeData theme, {
    required bool tinted,
    bool alternate = false,
  }) =>
      (alternate
              ? Color.lerp(theme.surface, theme.background, 0.6)!
              : theme.surface)
          .withValues(alpha: tinted ? patternAlpha : 1);

  /// The raised surface's shading over [color].
  static Gradient gradient(Color color, {double highlight = 0.085}) =>
      SurfaceDepth.gradient(color, highlight: highlight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaced = SpacedSettingsGroups.isEnabledOf(context);
    final SectionTitleLocation effectiveTitleLocation =
        titleLocation ?? ref.watch(sectionTitleLocationProvider);

    if (spaced) return _buildFlat(effectiveTitleLocation);
    final tinted =
        !RaisedGroupBoxes.isEnabledOf(context) &&
        ref.watch(pagePatternProvider);
    return SearchHighlight(
      query: searchQuery,
      builder: (context, highlightValue) =>
          _buildFrame(context, highlightValue, effectiveTitleLocation, tinted),
    );
  }

  /// The heading and content alone; a search marks its words in the title.
  Widget _buildFlat(SectionTitleLocation location) =>
      location == SectionTitleLocation.left
      ? Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            if (showTitle)
              SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [_buildTitleRow(flat: true), ?trailing],
                ),
              ),
            Expanded(child: child),
          ],
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [if (showTitle) _buildHeader(flat: true), child],
        );

  /// Flat headings centre their title on the trailing actions.
  CrossAxisAlignment _alignment(bool flat) =>
      flat ? CrossAxisAlignment.center : headerCrossAxisAlignment;

  /// The icon and title; flat headings title in the text colour.
  Widget _buildTitleRow({bool flat = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: _alignment(flat),
    children: [
      if (titleIcon != null) ...[
        Icon(titleIcon, size: 20, color: theme.accent),
        const SizedBox(width: kElementHSpacing),
      ],
      Expanded(child: _buildHeaderText(flat: flat)),
    ],
  );

  Widget _buildHeaderText({bool flat = false}) {
    final titleStyle = TextStyle(
      color: flat || plainTitle ? theme.textPrimary : theme.accent,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.35,
    );
    return Text.rich(
      // A flat heading marks the searched words in its title.
      searchHighlightSpan(
        title,
        flat ? searchQuery : '',
        titleStyle,
        searchMarkStyle(theme.accent),
      ),
      overflow: TextOverflow.visible,
    );
  }

  Widget _buildFrame(
    BuildContext context,
    double highlightValue,
    SectionTitleLocation location,
    bool tinted,
  ) {
    final baseBorderColor = theme.border;
    final effectiveBorderColor =
        Color.lerp(
          baseBorderColor,
          theme.accent,
          highlightValue.clamp(0.0, 1.0),
        ) ??
        baseBorderColor;
    final highlightBg = theme.accent.withValues(alpha: 0.10 * highlightValue);
    final pos = groupPosition;

    final baseColor = background(
      theme,
      tinted: tinted,
      alternate: alternateBackground,
    );
    final bgColor = Color.alphaBlend(highlightBg, baseColor);

    // Which sides carry a visible border.
    // Attached variants omit their top edge so the preceding section header
    // provides the top border seamlessly.
    final showTop =
        pos == SectionGroupPosition.only || pos == SectionGroupPosition.first;
    final showBottom =
        pos == SectionGroupPosition.only ||
        pos == SectionGroupPosition.last ||
        pos == SectionGroupPosition.onlyAttached;

    // Visible top / bottom edges are rounded; attached boxes keep flat top
    // corners unless the position is truly "first"/"only".
    final cr = theme.cornerRadius;
    final outerRadius = BorderRadius.vertical(
      top: showTop ? Radius.circular(cr) : Radius.zero,
      bottom: showBottom ? Radius.circular(cr) : Radius.zero,
    );

    final content = location == SectionTitleLocation.left
        ? _buildLeftTitle(outerRadius)
        : _buildTopTitle(outerRadius);

    // Paint the background on Material so child controls' ink stays visible.
    final hasCorners = showTop || showBottom;
    // While see-through, only the gradient paints, so the fill is not doubled.
    final surface = Material(
      color: tinted ? Colors.transparent : bgColor,
      textStyle: DefaultTextStyle.of(context).style,
      animationDuration: Duration.zero,
      child: Ink(
        decoration: BoxDecoration(gradient: gradient(bgColor)),
        child: content,
      ),
    );
    // Keep controls mounted when search filtering changes connected corners.
    final bgLayer = ClipRRect(
      borderRadius: outerRadius,
      clipBehavior: hasCorners ? Clip.antiAlias : Clip.none,
      child: surface,
    );

    // Overlay the selective border via CustomPainter so it is never clipped.
    final body = CustomPaint(
      foregroundPainter: _SelectiveBorderPainter(
        color: effectiveBorderColor,
        cornerRadius: cr,
        showTop: showTop,
        showBottom: showBottom,
      ),
      child: bgLayer,
    );

    // Keep controls and anchored popups mounted when the search glow fades.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: outerRadius,
        boxShadow: [
          if (!tinted) SurfaceDepth.shadow(isDark: theme.isDark),
          if (highlightValue > 0)
            BoxShadow(
              color: theme.accent.withValues(alpha: 0.18 * highlightValue),
              blurRadius: 12,
              spreadRadius: 1,
            ),
        ],
      ),
      child: body,
    );
  }

  Widget _buildLeftTitle(BorderRadius outerRadius) {
    // Inner left-panel decorative corners.
    final panelRadius = BorderRadius.only(
      topLeft: outerRadius.topLeft,
      bottomRight: outerRadius.bottomRight,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title panel
        if (showTitle)
          Container(
            width: 150,
            padding: padding,
            decoration: BoxDecoration(
              // no background color so title blends with box body
              borderRadius: panelRadius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: theme.accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(
                            theme.cornerRadius,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (titleIcon != null) ...[
                              Icon(titleIcon, size: 18, color: theme.accent),
                              const SizedBox(width: kElementHSpacing),
                            ],
                            Expanded(child: _buildHeaderText()),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (trailing != null) ...[
                  const SizedBox(height: 12),
                  trailing!,
                ],
              ],
            ),
          ),
        // Content area
        Expanded(
          child: Padding(padding: padding, child: child),
        ),
      ],
    );
  }

  // Both header layouts are built outside the layout callback, so a width
  // change only picks one instead of rebuilding the title and trailing.
  Widget _buildHeader({bool flat = false}) {
    final title = Expanded(child: _buildTitleRow(flat: flat));
    Column header(List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: children,
    );
    final inline = header([
      Row(
        crossAxisAlignment: _alignment(flat),
        spacing: 12,
        children: [title, ?trailing],
      ),
    ]);
    if (!stackTrailingWhenCompact || trailing == null) return inline;
    final stacked = header([
      Row(crossAxisAlignment: _alignment(flat), children: [title]),
      Align(alignment: Alignment.centerRight, child: trailing!),
    ]);
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth <= kSettingsCompactLayoutBreakpoint
          ? stacked
          : inline,
    );
  }

  Widget _buildTopTitle(BorderRadius outerRadius) {
    // Title header rounds only its own top corners (clipped by outer layer).
    final titleHeaderRadius = BorderRadius.only(
      topLeft: outerRadius.topLeft,
      topRight: outerRadius.topRight,
    );

    final titleHeader = Container(
      padding: EdgeInsets.fromLTRB(
        padding.left,
        padding.top,
        padding.right,
        headerBottomPadding,
      ),
      decoration: BoxDecoration(borderRadius: titleHeaderRadius),
      child: _buildHeader(),
    );

    // Bounded sections give their content the space remaining below the title.
    // The selected fit either fills that space or shrinks around short content.
    // Unbounded sections size naturally inside their surrounding scroll view.
    final contentWidget = Padding(
      padding: showTitle
          ? EdgeInsets.only(
              left: padding.left,
              right: padding.right,
              bottom: padding.bottom,
            )
          : padding,
      child: child,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final fitToHeight = constraints.hasBoundedHeight;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showTitle) titleHeader,
            fitToHeight ? Expanded(child: contentWidget) : contentWidget,
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Border painter
// ---------------------------------------------------------------------------

/// Paints a selective rounded border for [SectionGroupBox].
///
/// Drawing the border in a [CustomPainter] (as a foreground overlay) rather
/// than inside a [ClipRRect] prevents the anti-alias clipping artifact that
/// makes corners appear faded.
class _SelectiveBorderPainter extends CustomPainter {
  const _SelectiveBorderPainter({
    required this.color,
    required this.cornerRadius,
    required this.showTop,
    required this.showBottom,
  });

  static const strokeWidth = 1.0;

  final Color color;
  final double cornerRadius;

  /// A visible top or bottom edge always has rounded corners.
  final bool showTop;
  final bool showBottom;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;
    final maxR = (w < h ? w : h) / 2;
    final r = cornerRadius < maxR ? cornerRadius : maxR;
    final radius = Radius.circular(r);
    const e = strokeWidth / 2; // inset so stroke stays within bounds

    // Fast path: full rounded-rect outline.
    if (showTop && showBottom) {
      canvas.drawRRect(RRect.fromLTRBR(e, e, w - e, h - e, radius), paint);
      return;
    }

    final path = Path();
    if (showTop) {
      // Left side (bottom→top) → TL arc → top → TR arc → right side.
      path
        ..moveTo(e, h - e)
        ..lineTo(e, e + r)
        ..arcToPoint(Offset(e + r, e), radius: radius)
        ..lineTo(w - e - r, e)
        ..arcToPoint(Offset(w - e, e + r), radius: radius)
        ..lineTo(w - e, h - e);
    } else if (showBottom) {
      // Left side (top→bottom) → BL arc → bottom → BR arc → right side.
      // The corner arcs must sweep *counter‑clockwise* so they bulge outward instead
      // of inverting toward the interior. (The y‑axis points down, so the natural
      // direction for a convex bottom corner is opposite the top corner case.)
      path
        ..moveTo(e, e)
        ..lineTo(e, h - e - r)
        ..arcToPoint(Offset(e + r, h - e), radius: radius, clockwise: false)
        ..lineTo(w - e - r, h - e)
        ..arcToPoint(Offset(w - e, h - e - r), radius: radius, clockwise: false)
        ..lineTo(w - e, e);
    } else {
      // No top, no bottom: just two vertical lines.
      path
        ..moveTo(e, e)
        ..lineTo(e, h - e)
        ..moveTo(w - e, e)
        ..lineTo(w - e, h - e);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SelectiveBorderPainter old) =>
      old.color != color ||
      old.cornerRadius != cornerRadius ||
      old.showTop != showTop ||
      old.showBottom != showBottom;
}
