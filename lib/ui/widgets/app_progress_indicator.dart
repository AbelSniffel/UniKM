import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_providers.dart';

class AppCircularProgressIndicator extends ConsumerWidget {
  const AppCircularProgressIndicator({
    super.key,
    this.color,
    this.strokeWidth,
    this.size,
  }) : _asIcon = false,
       _page = false;

  /// Stands in for an [Icon] of [size], or of the surrounding icon size: as
  /// wide as an icon's glyph, inside the same padding, with the theme's
  /// stroke.
  const AppCircularProgressIndicator.icon({super.key, this.size})
    : color = null,
      strokeWidth = null,
      _asIcon = true,
      _page = false;

  /// Alone on a loading page: a pixel heavier than the theme's stroke.
  const AppCircularProgressIndicator.page({super.key})
    : color = null,
      strokeWidth = null,
      size = null,
      _asIcon = false,
      _page = true;

  final bool _asIcon;
  final bool _page;
  final Color? color;
  final double? strokeWidth;

  /// Square size; without it the indicator takes its default size.
  final double? size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    // Its own layer, so the spinner's animation repaints only itself.
    final indicator = RepaintBoundary(
      child: CircularProgressIndicator(
        color: theme.accent,
        backgroundColor: theme.accent.withValues(alpha: 0.4),
        strokeWidth:
            strokeWidth ?? theme.progressIndicatorStrokeWidth + (_page ? 1 : 0),
      ),
    );
    if (_asIcon) {
      final iconSize = size ?? IconTheme.of(context).size ?? 24;
      // Material icons leave 2 of every 24 px clear around their glyphs.
      return SizedBox.square(
        dimension: iconSize,
        child: Padding(
          padding: EdgeInsets.all(iconSize / 12),
          child: indicator,
        ),
      );
    }
    return size == null
        ? indicator
        : SizedBox(width: size, height: size, child: indicator);
  }
}
