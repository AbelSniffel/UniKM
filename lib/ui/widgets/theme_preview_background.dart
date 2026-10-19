import 'package:flutter/material.dart';

import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import 'navigation_panel_overlay.dart';

/// The same gradient and navigation overlay at any preview-card size.
class ThemePreviewBackground extends StatelessWidget {
  const ThemePreviewBackground({super.key, required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Stack(
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
        if (theme.navPanelOverlayStyle != NavPanelOverlayStyle.none)
          IgnorePointer(
            child: NavigationPanelOverlayPaint(
              theme: theme,
              preview: true,
              child: const SizedBox.expand(),
            ),
          ),
      ],
    );
  }
}
