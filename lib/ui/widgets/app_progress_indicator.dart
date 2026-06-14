import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_providers.dart';

class AppCircularProgressIndicator extends ConsumerWidget {
  const AppCircularProgressIndicator({
    super.key,
    this.color,
    this.backgroundColor,
    this.strokeWidth,
  });

  final Color? color;
  final Color? backgroundColor;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    return CircularProgressIndicator(
      color: color ?? theme.accent,
      backgroundColor: backgroundColor ?? theme.accent.withValues(alpha: 0.2),
      strokeWidth: strokeWidth ?? theme.progressIndicatorStrokeWidth,
    );
  }
}
