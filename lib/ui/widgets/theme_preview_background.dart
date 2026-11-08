import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import 'background_pattern.dart';

/// The same gradient and background pattern at any preview-card size. Every
/// theme shows the background pattern setting.
class ThemePreviewBackground extends ConsumerWidget {
  const ThemePreviewBackground({super.key, required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Stack(
    fit: StackFit.expand,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [theme.background, theme.accent, theme.secondary],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
      CustomPaint(
        painter: BackgroundPatternPainter(
          theme: theme,
          style: ref.watch(backgroundPatternProvider),
          preview: true,
        ),
      ),
    ],
  );
}
