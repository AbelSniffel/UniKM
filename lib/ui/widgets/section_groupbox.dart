/// Section GroupBox widget
/// Matches the original Python SectionGroupBox with left/top title positions
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';

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

/// Section groupbox with configurable title position
class SectionGroupBox extends ConsumerStatefulWidget {
  const SectionGroupBox({
    super.key,
    required this.title,
    required this.theme,
    required this.child,
    this.titleLocation,
    this.padding = const EdgeInsets.all(12),
    this.titleIcon,
    this.trailing,
    this.borderColor,
    this.shrinkToChild = false,
    this.searchQuery = '',
    this.isSearchMatch = false,
    this.groupPosition = SectionGroupPosition.only,
    this.alternateBackground = false,
  });

  /// Whether the box should shrink to the size of its inner content instead of
  /// expanding to fill available width. Use on specific instances (expensive
  /// if used globally) when you want intrinsic sizing behavior.
  final bool shrinkToChild;

  final String title;
  final AppThemeData theme;
  final Widget child;

  /// Optional override. When null, uses `SettingsKeys.sectionTitleLocation`.
  final SectionTitleLocation? titleLocation;
  final EdgeInsets padding;
  final IconData? titleIcon;
  final Widget? trailing;
  final Color? borderColor;
  final String searchQuery;
  final bool isSearchMatch;

  /// Position of this box within a connected group strip.
  final SectionGroupPosition groupPosition;

  /// When true, uses [AppThemeData.background] instead of [AppThemeData.surface]
  /// as the body background — creates the alternating-row visual effect.
  final bool alternateBackground;

  @override
  ConsumerState<SectionGroupBox> createState() => _SectionGroupBoxState();
}

class _SectionGroupBoxState extends ConsumerState<SectionGroupBox>
    with SingleTickerProviderStateMixin {
  static const Duration _searchFadeDelay = Duration(seconds: 1);
  static const Duration _searchFadeDuration = Duration(milliseconds: 650);

  late final AnimationController _highlightController;
  Timer? _fadeTimer;

  bool get _shouldHighlight =>
      widget.searchQuery.trim().isNotEmpty && widget.isSearchMatch;

  @override
  void initState() {
    super.initState();
    _highlightController = AnimationController(
      vsync: this,
      duration: _searchFadeDuration,
      value: 0,
    );
    _syncHighlightWithSearch();
  }

  @override
  void didUpdateWidget(covariant SectionGroupBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery ||
        oldWidget.isSearchMatch != widget.isSearchMatch) {
      _syncHighlightWithSearch();
    }
  }

  void _syncHighlightWithSearch() {
    _fadeTimer?.cancel();

    if (!_shouldHighlight) {
      _highlightController.animateTo(0);
      return;
    }

    _highlightController.value = 1;
    _fadeTimer = Timer(_searchFadeDelay, () {
      if (!mounted) return;
      _highlightController.animateTo(0);
    });
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    _highlightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTitleLocation =
        widget.titleLocation ?? ref.watch(sectionTitleLocationProvider);

    return AnimatedBuilder(
      animation: _highlightController,
      builder: (context, _) {
        final highlightValue = Curves.easeOutCubic.transform(
          _highlightController.value,
        );
        final built = effectiveTitleLocation == SectionTitleLocation.left
            ? _buildLeftTitle(highlightValue)
            : _buildTopTitle(highlightValue);

        if (widget.shrinkToChild) {
          // Use Align + IntrinsicWidth to allow the box to size itself to its content
          // instead of stretching to the available width. IntrinsicWidth is more
          // expensive but appropriate for selective use where exact sizing is
          // desired.
          return Align(
            alignment: Alignment.centerLeft,
            child: IntrinsicWidth(child: built),
          );
        }

        return built;
      },
    );
  }

  Widget _buildLeftTitle(double highlightValue) {
    final baseBorderColor = widget.borderColor ?? widget.theme.border;
    final effectiveBorderColor =
        Color.lerp(
          baseBorderColor,
          widget.theme.accent,
          highlightValue.clamp(0.0, 1.0),
        ) ??
        baseBorderColor;
    final highlightBg = widget.theme.accent.withValues(
      alpha: 0.10 * highlightValue,
    );
    final pos = widget.groupPosition;

    // Subtle alternating background: blend 40% toward the base background so
    // the difference is visible but not jarring.
    final baseColor = widget.alternateBackground
        ? Color.lerp(widget.theme.surface, widget.theme.background, 0.6)!
        : widget.theme.surface;
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
    final roundTopCorners =
        showTop &&
        (pos == SectionGroupPosition.only || pos == SectionGroupPosition.first);
    final roundBottomCorners = showBottom;

    final cr = widget.theme.cornerRadius;
    final outerRadius = BorderRadius.only(
      topLeft: roundTopCorners ? Radius.circular(cr) : Radius.zero,
      topRight: roundTopCorners ? Radius.circular(cr) : Radius.zero,
      bottomLeft: roundBottomCorners ? Radius.circular(cr) : Radius.zero,
      bottomRight: roundBottomCorners ? Radius.circular(cr) : Radius.zero,
    );

    // Inner left-panel decorative corners.
    final panelRadius = BorderRadius.only(
      topLeft: roundTopCorners ? Radius.circular(cr) : Radius.zero,
      bottomRight: roundBottomCorners ? Radius.circular(cr) : Radius.zero,
    );

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: widget.shrinkToChild ? MainAxisSize.min : MainAxisSize.max,
      children: [
        // Title panel
        Container(
          width: 150,
          padding: widget.padding,
          decoration: BoxDecoration(
            // no background color so title blends with box body
            borderRadius: panelRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (widget.titleIcon != null) ...[
                    Icon(
                      widget.titleIcon,
                      size: 18,
                      color: widget.theme.accent,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        color: widget.theme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.trailing != null) ...[
                const SizedBox(height: 12),
                widget.trailing!,
              ],
            ],
          ),
        ),
        // Content area
        widget.shrinkToChild
            ? Padding(padding: widget.padding, child: widget.child)
            : Expanded(
                child: Padding(padding: widget.padding, child: widget.child),
              ),
      ],
    );

    // Background clipped to rounded corners.
    final hasCorners = roundTopCorners || roundBottomCorners;
    final bgLayer = hasCorners
        ? ClipRRect(
            borderRadius: outerRadius,
            child: ColoredBox(color: bgColor, child: content),
          )
        : ColoredBox(color: bgColor, child: content);

    // Overlay the selective border via CustomPainter so it is never clipped.
    Widget body = CustomPaint(
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

    if (highlightValue > 0) {
      body = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: outerRadius,
          boxShadow: [
            BoxShadow(
              color: widget.theme.accent.withValues(
                alpha: 0.18 * highlightValue,
              ),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: body,
      );
    }

    return body;
  }

  Widget _buildTopTitle(double highlightValue) {
    final baseBorderColor = widget.borderColor ?? widget.theme.border;
    final effectiveBorderColor =
        Color.lerp(
          baseBorderColor,
          widget.theme.accent,
          highlightValue.clamp(0.0, 1.0),
        ) ??
        baseBorderColor;
    final highlightBg = widget.theme.accent.withValues(
      alpha: 0.10 * highlightValue,
    );
    final pos = widget.groupPosition;

    final baseColor = widget.alternateBackground
        ? Color.lerp(widget.theme.surface, widget.theme.background, 0.6)!
        : widget.theme.surface;
    final bgColor = Color.alphaBlend(highlightBg, baseColor);

    // Similar to the left-title case: attached variants omit their top edge
    // because the section header renders that top border.
    final showTop =
        pos == SectionGroupPosition.only || pos == SectionGroupPosition.first;
    final showBottom =
        pos == SectionGroupPosition.only ||
        pos == SectionGroupPosition.last ||
        pos == SectionGroupPosition.onlyAttached;

    final roundTopCorners =
        showTop &&
        (pos == SectionGroupPosition.only || pos == SectionGroupPosition.first);
    final roundBottomCorners = showBottom;

    final cr = widget.theme.cornerRadius;
    final outerRadius = BorderRadius.only(
      topLeft: roundTopCorners ? Radius.circular(cr) : Radius.zero,
      topRight: roundTopCorners ? Radius.circular(cr) : Radius.zero,
      bottomLeft: roundBottomCorners ? Radius.circular(cr) : Radius.zero,
      bottomRight: roundBottomCorners ? Radius.circular(cr) : Radius.zero,
    );

    // Title header rounds only its own top corners (clipped by outer layer).
    final titleHeaderRadius = roundTopCorners
        ? BorderRadius.vertical(top: Radius.circular(cr))
        : BorderRadius.zero;

    final content = Column(
      crossAxisAlignment: widget.shrinkToChild
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            // remove themed background so header is transparent
            borderRadius: titleHeaderRadius,
          ),
          child: Row(
            children: [
              if (widget.titleIcon != null) ...[
                Icon(widget.titleIcon, size: 18, color: widget.theme.accent),
                const SizedBox(width: 8),
              ],
              Text(
                widget.title,
                style: TextStyle(
                  color: widget.theme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (widget.trailing != null) ...[
                const Spacer(),
                widget.trailing!,
              ],
            ],
          ),
        ),
        Padding(
          padding: widget.padding,
          child: widget.shrinkToChild
              ? Align(alignment: Alignment.centerLeft, child: widget.child)
              : widget.child,
        ),
      ],
    );

    final hasCorners = roundTopCorners || roundBottomCorners;
    final bgLayer = hasCorners
        ? ClipRRect(
            borderRadius: outerRadius,
            child: ColoredBox(color: bgColor, child: content),
          )
        : ColoredBox(color: bgColor, child: content);

    Widget body = CustomPaint(
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

    if (highlightValue > 0) {
      body = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: outerRadius,
          boxShadow: [
            BoxShadow(
              color: widget.theme.accent.withValues(
                alpha: 0.18 * highlightValue,
              ),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: body,
      );
    }

    return body;
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

/// Inner groupbox for nested sections
class InnerGroupBox extends StatelessWidget {
  const InnerGroupBox({
    super.key,
    required this.theme,
    required this.child,
    this.title,
    this.padding = const EdgeInsets.all(12),
  });

  final AppThemeData theme;
  final Widget child;
  final String? title;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // inner boxes also used surfaceVariant; make transparent by default
        borderRadius: BorderRadius.circular(theme.cornerRadius / 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: EdgeInsets.only(
                left: padding.left,
                right: padding.right,
                top: padding.top,
              ),
              child: Text(
                title!,
                style: TextStyle(
                  color: theme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          Padding(
            padding: title != null
                ? EdgeInsets.only(
                    left: padding.left,
                    right: padding.right,
                    bottom: padding.bottom,
                    top: 8,
                  )
                : padding,
            child: child,
          ),
        ],
      ),
    );
  }
}
