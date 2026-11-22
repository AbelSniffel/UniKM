/// Section GroupBox widget
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
enum SectionGroupPosition() {
  only,
  first,
  middle,
  last,
  firstAttached,
  onlyAttached,
}

/// Settings panels show their groups as plain headings over their content,
/// without a frame, like the Tinted Tile dialogs.
class const SpacedSettingsGroups({super.key, required super.child})
    extends InheritedWidget {
  static bool isEnabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SpacedSettingsGroups>() !=
      null;

  @override
  bool updateShouldNotify(SpacedSettingsGroups oldWidget) => false;
}

/// Keeps the [SectionGroupBox]es below it raised whatever the page pattern,
/// for a dialog that no page pattern shows through.
class const RaisedGroupBoxes({super.key, required super.child})
    extends InheritedWidget {
  static bool isEnabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RaisedGroupBoxes>() != null;

  @override
  bool updateShouldNotify(RaisedGroupBoxes oldWidget) => false;
}

/// A titled group of settings or controls, its title above its content.
class const SectionGroupBox({
  super.key,
  required final String title,
  required final Widget child,
  final EdgeInsets padding = const EdgeInsets.all(12),
  final IconData? titleIcon,
  final Widget? trailing,

  /// Header action groups use the same breakpoint as full-width settings cards.
  final bool stackTrailingWhenCompact = false,
  final CrossAxisAlignment headerCrossAxisAlignment = CrossAxisAlignment.start,

  /// Gap below a top title, before the body content.
  final double headerBottomPadding = 12,
  final String searchQuery = '',

  /// Position of this box within a connected group strip.
  final SectionGroupPosition groupPosition = SectionGroupPosition.only,

  /// When true, the body takes the tinted cards' slightly stronger tint
  /// ([TintedCard.fillAlpha]) — creates the alternating-row visual effect.
  final bool alternateBackground = false,

  /// When false, the title header (or left title panel) is not rendered — only
  /// the bordered/background container is shown. Useful when you want the
  /// groupbox strip visuals (borders, alternating colours) without labels.
  final bool showTitle = true,

  /// Titles a framed box in the text colour, as flat headings are, instead
  /// of the accent.
  final bool plainTitle = false,

  /// Square, without its own border or shadow, so it fills its parent edge
  /// to edge, as in the library's filter sidebar, and see-through
  /// ([flushAlpha]) over the parent's surface.
  final bool flush = false,
}) extends ConsumerWidget {
  /// The surface's opacity while the pattern shows on pages ([tinted]).
  static const double patternAlpha = 0.8;

  /// A [flush] box's surface opacity over the panel it fills.
  static const double flushAlpha = 0.75;

  /// The raised surface, see-through while the pattern shows on pages
  /// ([tinted]). [alternate] takes the darker surface.
  static Color background(
    AppThemeData theme, {
    required bool tinted,
    bool alternate = false,
  }) =>
      (alternate
              ? Color.lerp(theme.surface, theme.background, 0.6)!
              : theme.surface)
          .withValues(alpha: tinted ? patternAlpha : 1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (SpacedSettingsGroups.isEnabledOf(context)) {
      return _buildFlat(context.appTheme);
    }
    final tinted =
        !RaisedGroupBoxes.isEnabledOf(context) &&
        ref.watch(pagePatternProvider);
    return SearchHighlight(
      query: searchQuery,
      builder: (context, highlightValue) =>
          _buildFrame(context, highlightValue, tinted),
    );
  }

  /// The heading and content alone; a search marks its words in the title.
  Widget _buildFlat(AppThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    spacing: 8,
    children: [if (showTitle) _buildHeader(theme, flat: true), child],
  );

  /// Flat headings centre their title on the trailing actions.
  CrossAxisAlignment _alignment(bool flat) =>
      flat ? CrossAxisAlignment.center : headerCrossAxisAlignment;

  /// The icon and title; flat headings title in the text colour.
  Widget _buildTitleRow(AppThemeData theme, {bool flat = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: _alignment(flat),
    children: [
      if (titleIcon != null) ...[
        Icon(titleIcon, size: 20, color: theme.accent),
        const SizedBox(width: kElementHSpacing),
      ],
      Expanded(child: _buildHeaderText(theme, flat: flat)),
    ],
  );

  Widget _buildHeaderText(AppThemeData theme, {bool flat = false}) {
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

  Widget _buildFrame(BuildContext context, double highlightValue, bool tinted) {
    final theme = context.appTheme;
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

    // A flush box veils the panel it fills, so it stays close to the
    // panel's surface, a little lighter.
    final baseColor = flush
        ? theme.surface.withValues(alpha: flushAlpha)
        : background(theme, tinted: tinted, alternate: alternateBackground);
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
    // Curves with its cards, 12 px in.
    final cr = theme.panelRadius;
    final outerRadius = BorderRadius.vertical(
      top: showTop ? Radius.circular(cr) : Radius.zero,
      bottom: showBottom ? Radius.circular(cr) : Radius.zero,
    );

    // Paint the background on Material so child controls' ink stays visible.
    final hasCorners = showTop || showBottom;
    final surface = Material(
      color: bgColor,
      textStyle: DefaultTextStyle.of(context).style,
      animationDuration: Duration.zero,
      child: _buildTopTitle(theme, outerRadius),
    );
    if (flush) return surface;
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

  // Both header layouts are built outside the layout callback, so a width
  // change only picks one instead of rebuilding the title and trailing.
  Widget _buildHeader(AppThemeData theme, {bool flat = false}) {
    final title = Expanded(child: _buildTitleRow(theme, flat: flat));
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

  Widget _buildTopTitle(AppThemeData theme, BorderRadius outerRadius) {
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
      child: _buildHeader(theme),
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
class const _SelectiveBorderPainter({
  required final Color color,
  required final double cornerRadius,

  /// A visible top or bottom edge always has rounded corners.
  required final bool showTop,
  required final bool showBottom,
}) extends CustomPainter {
  static const strokeWidth = 1.0;

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
