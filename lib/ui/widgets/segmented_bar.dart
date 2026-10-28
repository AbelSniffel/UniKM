/// Bars split by share and the tinted chips that label them, shared by the
/// library stats and update dialogs.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import 'slider_style_tooltip.dart';

/// One part of a [SegmentedBar].
typedef BarSegment = ({String label, int count, Color color});

/// A bar as tall as a slider track, split into [segments] by count. Each
/// part shows its count and share in a slider value bubble.
class SegmentedBar extends StatelessWidget {
  const SegmentedBar({
    super.key,
    required this.theme,
    required this.segments,
    this.formatCount = _plain,
    this.gap = 2,
  });

  final AppThemeData theme;
  final List<BarSegment> segments;

  /// Writes a count in the bubbles, such as a file size.
  final String Function(int count) formatCount;

  /// The separator between parts, in the dialog's background colour.
  final double gap;

  static String _plain(int count) => '$count';

  /// Splits [width] by [counts], keeping every share wide enough to hover.
  static List<double> _segmentWidths(List<int> counts, double width) {
    const minWidth = 8.0;
    final total = counts.fold(0, (sum, n) => sum + n);
    bool small(int n) => n / total * width < minWidth;
    final smallCount = counts.where(small).length;
    final restTotal = counts
        .where((n) => !small(n))
        .fold(0, (sum, n) => sum + n);
    final rest = width - smallCount * minWidth;
    return [for (final n in counts) small(n) ? minWidth : n / restTotal * rest];
  }

  @override
  Widget build(BuildContext context) {
    final total = segments.fold(0, (sum, s) => sum + s.count);
    final shown = segments.where((s) => s.count > 0).toList();
    String share(int count) {
      final percent = count * 100 / total;
      return percent < 0.5 ? '<1%' : '${percent.round()}%';
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(
        math.min(theme.cornerRadius, kSliderTrackHeight / 2),
      ),
      child: SizedBox(
        height: kSliderTrackHeight,
        child: shown.isEmpty
            ? ColoredBox(color: theme.accent.withValues(alpha: 0.12))
            : LayoutBuilder(
                builder: (context, constraints) {
                  final widths = _segmentWidths([
                    for (final segment in shown) segment.count,
                  ], constraints.maxWidth - gap * (shown.length - 1));
                  // Separators show the dialog's background.
                  return ColoredBox(
                    color: theme.background,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: gap,
                      children: [
                        for (final (i, segment) in shown.indexed)
                          SizedBox(
                            width: widths[i],
                            child: SliderStyleTooltip(
                              // Faded colours are made solid over the
                              // dialog, as they look in the bar.
                              color: Color.alphaBlend(
                                segment.color,
                                theme.background,
                              ),
                              message:
                                  '${segment.label}: '
                                  '${formatCount(segment.count)} '
                                  '(${share(segment.count)})',
                              child: ColoredBox(color: segment.color),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// A small chip tinted with [color]: a swatch, [label] and an optional bold
/// [value]. Faded chips stand back.
class TintedChip extends StatelessWidget {
  const TintedChip({
    super.key,
    required this.theme,
    required this.color,
    required this.label,
    this.value,
    this.faded = false,
  });

  final AppThemeData theme;
  final Color color;
  final String label;
  final String? value;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final radius = theme.cornerRadius;
    return Opacity(
      opacity: faded ? 0.5 : 1,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(6, 4, 8, 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: color.a * 0.14),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: color.withValues(alpha: color.a * 0.35)),
        ),
        // Rich text, so a long label wraps instead of overflowing.
        child: Text.rich(
          TextSpan(
            style: TextStyle(color: theme.textSecondary, fontSize: 12),
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsetsDirectional.only(end: 6),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(radius / 2),
                  ),
                ),
              ),
              TextSpan(text: label),
              if (value != null)
                TextSpan(
                  text: '  $value',
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
