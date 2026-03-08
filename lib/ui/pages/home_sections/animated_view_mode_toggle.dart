/// Animated toggle button for switching between grid and list view
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../widgets/hover_builder.dart';

class AnimatedViewModeToggle extends StatefulWidget {
  const AnimatedViewModeToggle({
    super.key,
    required this.theme,
    required this.isGridView,
    required this.onToggle,
  });

  final AppThemeData theme;
  final bool isGridView;
  final VoidCallback onToggle;

  @override
  State<AnimatedViewModeToggle> createState() => _AnimatedViewModeToggleState();
}

class _AnimatedViewModeToggleState extends State<AnimatedViewModeToggle> {
  void _handleTap() {
    widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    return HoverPressBuilder(
      onTap: _handleTap,
      builder: (context, isHovered, isPressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // Special case: view-mode toggle should not show a "selected"
          // background — treat it like a neutral toggle and only show hover.
          color: isHovered ? widget.theme.navItemHover : widget.theme.navItemHover.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: ScaleTransition(scale: anim, child: child)),
          child: Icon(
            widget.isGridView ? Icons.apps : Icons.view_list,
            key: ValueKey<bool>(widget.isGridView),
            color: widget.theme.accent,
            size: 20,
          ),
        ),
      ),
    );
  }
}
