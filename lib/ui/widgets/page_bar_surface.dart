import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/surface_depth.dart';

/// Full-width page controls with the same raised surface as groupboxes.
class PageBarSurface extends StatelessWidget {
  const PageBarSurface({
    super.key,
    required this.theme,
    required this.child,
    this.isFooter = false,
  });

  final AppThemeData theme;
  final Widget child;
  final bool isFooter;

  @override
  Widget build(BuildContext context) {
    final edge = BorderSide(color: theme.border);
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [SurfaceDepth.shadow(isDark: theme.isDark)],
      ),
      child: Material(
        color: theme.surface,
        textStyle: DefaultTextStyle.of(context).style,
        animationDuration: Duration.zero,
        child: Ink(
          decoration: BoxDecoration(
            gradient: SurfaceDepth.gradient(theme.surface, highlight: 0.085),
            border: isFooter ? Border(top: edge) : Border(bottom: edge),
          ),
          child: child,
        ),
      ),
    );
  }
}
