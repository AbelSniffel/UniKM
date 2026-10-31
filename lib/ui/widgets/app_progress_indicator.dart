import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_providers.dart';

class AppCircularProgressIndicator extends ConsumerWidget {
  const AppCircularProgressIndicator({
    super.key,
    this.color,
    this.strokeWidth,
    this.size,
  });

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
        color: color ?? theme.accent,
        backgroundColor: theme.accent.withValues(alpha: 0.2),
        strokeWidth: strokeWidth ?? theme.progressIndicatorStrokeWidth,
      ),
    );
    return size == null
        ? indicator
        : SizedBox(width: size, height: size, child: indicator);
  }
}
