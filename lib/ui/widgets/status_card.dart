import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A card tinted by its status [color], shared by the update dialog and
/// notifications: an icon tile (a spinner while [busy]), a bold [title] over
/// an optional [subtitle], an optional large [figure] at the end such as a
/// percentage or count, and [children] such as a progress bar or actions
/// across the card under them.
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.theme,
    required this.color,
    required this.icon,
    required this.title,
    this.subtitle,
    this.figure,
    this.busy = false,
    this.busyValue,
    this.children = const [],
    this.backdrop,
    this.shadows,
    this.bottomEdge,
  });

  final AppThemeData theme;
  final Color color;
  final IconData icon;
  final String title;
  final Widget? subtitle;
  final String? figure;
  final bool busy;

  /// Fills the spinner to this share instead of spinning.
  final double? busyValue;
  final List<Widget> children;

  /// An opaque colour under the tint, for a card floating over other content.
  final Color? backdrop;
  final List<BoxShadow>? shadows;

  /// Drawn flush along the card's bottom edge, outside its padding.
  final Widget? bottomEdge;

  /// Secondary detail text, such as the subtitle's own line.
  static TextStyle detailStyle(AppThemeData theme) =>
      TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w400);

  @override
  Widget build(BuildContext context) {
    final tint = color.withValues(alpha: 0.12);
    final radius = BorderRadius.circular(theme.cornerRadius);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Row(
          spacing: 12,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: radius,
              ),
              child: Center(
                child: busy
                    ? SizedBox.square(
                        dimension: 24,
                        // Its own layer, so the spinner repaints only itself.
                        child: RepaintBoundary(
                          child: CircularProgressIndicator(
                            value: busyValue,
                            color: color,
                            backgroundColor: theme.accent.withValues(
                              alpha: 0.2,
                            ),
                            strokeWidth: theme.progressIndicatorStrokeWidth,
                          ),
                        ),
                      )
                    : Icon(icon, color: color, size: 28),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Semantics(
                    liveRegion: true,
                    header: true,
                    child: Text(
                      title,
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ?subtitle,
                ],
              ),
            ),
            // As large as the stats tiles' numbers.
            if (figure != null)
              Text(
                figure!,
                style: TextStyle(
                  color: color,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
        ...children,
      ],
    );
    return Container(
      decoration: BoxDecoration(
        color: backdrop == null ? tint : Color.alphaBlend(tint, backdrop!),
        borderRadius: radius,
        boxShadow: shadows,
      ),
      clipBehavior: bottomEdge == null ? Clip.none : Clip.antiAlias,
      child: bottomEdge == null
          ? Padding(padding: const EdgeInsets.all(12), child: content)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(padding: const EdgeInsets.all(12), child: content),
                bottomEdge!,
              ],
            ),
    );
  }
}
