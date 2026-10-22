/// Section GroupBox widget
/// Matches the original Python SectionGroupBox with left/top title positions
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/surface_depth.dart';
import '../../providers/app_providers.dart';
import '../../core/constants/app_constants.dart';
import 'search_highlight.dart';

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

/// Settings layout uses separated groupboxes; visual styling is shared.
class SpacedSettingsGroups extends InheritedWidget {
  const SpacedSettingsGroups({super.key, required super.child});

  static bool isEnabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SpacedSettingsGroups>() !=
      null;

  @override
  bool updateShouldNotify(SpacedSettingsGroups oldWidget) => false;
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
    this.description,
    this.titleIcon,
    this.trailing,
    this.stackTrailingWhenCompact = false,
    this.headerCrossAxisAlignment = CrossAxisAlignment.start,
    this.headerBottomPadding = 12,
    this.contentFit = FlexFit.tight,
    this.searchQuery = '',
    this.isSearchMatch = false,
    this.groupPosition = SectionGroupPosition.only,
    this.alternateBackground = false,
    this.showTitle = true,
  });

  /// Whether vertically bounded content fills its space or shrinks to its child.
  final FlexFit contentFit;

  final String title;
  final AppThemeData theme;
  final Widget child;
  final String? description;

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
  final bool isSearchMatch;

  /// Position of this box within a connected group strip.
  final SectionGroupPosition groupPosition;

  /// When true, uses [AppThemeData.background] instead of [AppThemeData.surface]
  /// as the body background — creates the alternating-row visual effect.
  final bool alternateBackground;

  /// When false, the title header (or left title panel) is not rendered — only
  /// the bordered/background container is shown. Useful when you want the
  /// groupbox strip visuals (borders, alternating colours) without labels.
  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaced = SpacedSettingsGroups.isEnabledOf(context);
    final SectionTitleLocation effectiveTitleLocation =
        titleLocation ?? ref.watch(sectionTitleLocationProvider);

    return SearchHighlight(
      query: searchQuery,
      isMatch: isSearchMatch,
      builder: (context, highlightValue) {
        final built = _buildFrame(
          context,
          highlightValue,
          effectiveTitleLocation,
          spaced: spaced,
        );

        return built;
      },
    );
  }

  Widget _buildHeaderText() {
    final description = this.description?.trim();
    final hasDescription = description != null && description.isNotEmpty;

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: title,
            style: TextStyle(
              color: theme.accent,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          if (hasDescription)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  Icons.arrow_right,
                  size: 18,
                  color: theme.secondary,
                ),
              ),
            ),
          if (hasDescription)
            TextSpan(
              text: description,
              style: TextStyle(
                color: theme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 1.35,
              ),
            ),
        ],
      ),
      softWrap: true,
      overflow: TextOverflow.visible,
    );
  }

  Widget _buildFrame(
    BuildContext context,
    double highlightValue,
    SectionTitleLocation location, {
    bool spaced = false,
  }) {
    final baseBorderColor = theme.border;
    final effectiveBorderColor =
        Color.lerp(
          baseBorderColor,
          theme.accent,
          highlightValue.clamp(0.0, 1.0),
        ) ??
        baseBorderColor;
    final highlightBg = theme.accent.withValues(alpha: 0.10 * highlightValue);
    final pos = spaced ? SectionGroupPosition.only : groupPosition;

    // Subtle alternating background: blend 40% toward the base background so
    // the difference is visible but not jarring.
    final baseColor = alternateBackground && !spaced
        ? Color.lerp(theme.surface, theme.background, 0.6)!
        : theme.surface;
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

    // Whether corner radius is applied to top / bottom.  We keep the original
    // rounding rules so attached boxes still have flat top corners unless the
    // position is truly "first"/"only".
    final roundTopCorners = showTop;
    final roundBottomCorners = showBottom;

    final cr = theme.cornerRadius;
    final outerRadius = BorderRadius.only(
      topLeft: roundTopCorners ? Radius.circular(cr) : Radius.zero,
      topRight: roundTopCorners ? Radius.circular(cr) : Radius.zero,
      bottomLeft: roundBottomCorners ? Radius.circular(cr) : Radius.zero,
      bottomRight: roundBottomCorners ? Radius.circular(cr) : Radius.zero,
    );

    final content = location == SectionTitleLocation.left
        ? _buildLeftTitle(outerRadius)
        : _buildTopTitle(outerRadius);

    // Paint the background on Material so child controls' ink stays visible.
    final hasCorners = roundTopCorners || roundBottomCorners;
    final surface = Material(
      color: bgColor,
      textStyle: DefaultTextStyle.of(context).style,
      animationDuration: Duration.zero,
      child: Ink(
        decoration: BoxDecoration(
          gradient: SurfaceDepth.gradient(bgColor, highlight: 0.085),
        ),
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
        strokeWidth: 1.0,
        cornerRadius: cr,
        showTop: showTop,
        showBottom: showBottom,
        roundTopCorners: roundTopCorners,
        roundBottomCorners: roundBottomCorners,
      ),
      child: bgLayer,
    );

    // Keep controls and anchored popups mounted when the search glow fades.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: outerRadius,
        boxShadow: [
          SurfaceDepth.shadow(isDark: theme.isDark),
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

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
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

    return content;
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              stackTrailingWhenCompact &&
              trailing != null &&
              constraints.maxWidth <= kSettingsCompactLayoutBreakpoint;
          final title = Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: headerCrossAxisAlignment,
            children: [
              if (titleIcon != null) ...[
                Icon(titleIcon, size: 20, color: theme.accent),
                const SizedBox(width: kElementHSpacing),
              ],
              Expanded(child: _buildHeaderText()),
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: headerCrossAxisAlignment,
                children: [
                  Expanded(child: title),
                  if (!stacked && trailing != null) ...[
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                ],
              ),
              if (stacked) ...[
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerRight, child: trailing!),
              ],
            ],
          );
        },
      ),
    );

    // Bounded sections give their content the space remaining below the title.
    // The selected fit either fills that space or shrinks around short content.
    // Unbounded sections size naturally inside their surrounding scroll view.
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final fitToHeight = constraints.hasBoundedHeight;
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
        return Column(
          mainAxisSize: contentFit == FlexFit.loose
              ? MainAxisSize.min
              : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showTitle) titleHeader,
            fitToHeight
                ? Flexible(fit: contentFit, child: contentWidget)
                : contentWidget,
          ],
        );
      },
    );

    return content;
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
    required this.strokeWidth,
    required this.cornerRadius,
    required this.showTop,
    required this.showBottom,
    required this.roundTopCorners,
    required this.roundBottomCorners,
  });

  final Color color;
  final double strokeWidth;
  final double cornerRadius;
  final bool showTop;
  final bool showBottom;
  final bool roundTopCorners;
  final bool roundBottomCorners;

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
    final e = strokeWidth / 2; // inset so stroke stays within bounds

    // Fast path: full rounded-rect outline.
    if (showTop && showBottom && roundTopCorners && roundBottomCorners) {
      canvas.drawRRect(
        RRect.fromLTRBR(e, e, w - e, h - e, Radius.circular(r)),
        paint,
      );
      return;
    }

    final path = Path();

    if (showTop) {
      // Trace: left side (bottom→top) → TL arc → top → TR arc → right side (top→bottom)
      // then optionally continue with bottom if showBottom.
      final leftStartY = (showBottom && roundBottomCorners) ? h - e - r : h - e;
      final leftEndY = roundTopCorners ? e + r : e;

      path.moveTo(e, leftStartY);
      path.lineTo(e, leftEndY);
      if (roundTopCorners) {
        path.arcToPoint(
          Offset(e + r, e),
          radius: Radius.circular(r),
          clockwise: true,
        );
      }
      path.lineTo(w - e - (roundTopCorners ? r : 0), e);
      if (roundTopCorners) {
        path.arcToPoint(
          Offset(w - e, e + r),
          radius: Radius.circular(r),
          clockwise: true,
        );
      }
      path.lineTo(
        w - e,
        (showBottom && roundBottomCorners) ? h - e - r : h - e,
      );

      if (showBottom) {
        if (roundBottomCorners) {
          path.arcToPoint(
            Offset(w - e - r, h - e),
            radius: Radius.circular(r),
            clockwise: true,
          );
        }
        path.lineTo(e + (roundBottomCorners ? r : 0), h - e);
        if (roundBottomCorners) {
          path.arcToPoint(
            Offset(e, h - e - r),
            radius: Radius.circular(r),
            clockwise: true,
          );
        }
        path.close();
      }
    } else if (showBottom) {
      // No top: left side (top→bottom) → BL arc → bottom → BR arc → right side (bottom→top).
      // The corner arcs must sweep *counter‑clockwise* so they bulge outward instead
      // of inverting toward the interior. (The y‑axis points down, so the natural
      // direction for a convex bottom corner is opposite the top corner case.)
      final leftEndY = roundBottomCorners ? h - e - r : h - e;

      path.moveTo(e, e);
      path.lineTo(e, leftEndY);
      if (roundBottomCorners) {
        path.arcToPoint(
          Offset(e + r, h - e),
          radius: Radius.circular(r),
          clockwise: false,
        );
      }
      path.lineTo(w - e - (roundBottomCorners ? r : 0), h - e);
      if (roundBottomCorners) {
        path.arcToPoint(
          Offset(w - e, h - e - r),
          radius: Radius.circular(r),
          clockwise: false,
        );
      }
      path.lineTo(w - e, e);
    } else {
      // No top, no bottom: just two vertical lines.
      path.moveTo(e, e);
      path.lineTo(e, h - e);
      path.moveTo(w - e, e);
      path.lineTo(w - e, h - e);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SelectiveBorderPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.cornerRadius != cornerRadius ||
      old.showTop != showTop ||
      old.showBottom != showBottom ||
      old.roundTopCorners != roundTopCorners ||
      old.roundBottomCorners != roundBottomCorners;
}
