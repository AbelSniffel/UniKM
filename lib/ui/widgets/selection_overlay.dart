/// Selection overlay widget for drag-select
/// Matches the original Python SelectionOverlay
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Centralized styling for the marquee rectangle.
///
/// These values are intentionally grouped in one place so the selection box
/// can be retuned quickly without touching the drag-selection logic.
class SelectionOverlayStyle {
  const SelectionOverlayStyle({
    this.fillColor,
    this.fillOpacity = 0.10,
    this.borderColor,
    this.borderOpacity = 1.0,
    this.borderWidth = 3.0,
    this.borderRadius =
        8, // use the theme corner radius for consistent rounding with cards and buttons
  });

  final Color? fillColor;
  final double fillOpacity;
  final Color? borderColor;
  final double borderOpacity;
  final double borderWidth;
  final double borderRadius;

  Color resolveFillColor(AppThemeData theme) {
    return (fillColor ?? theme.accent).withValues(
      alpha: fillOpacity.clamp(0.0, 1.0),
    );
  }

  Color resolveBorderColor(AppThemeData theme) {
    return (borderColor ?? theme.accent).withValues(
      alpha: borderOpacity.clamp(0.0, 1.0),
    );
  }
}

const kDefaultSelectionOverlayStyle = SelectionOverlayStyle();

/// Selection rectangle overlay for drag-select
class SelectionOverlay extends StatelessWidget {
  const SelectionOverlay({
    super.key,
    required this.startPosition,
    required this.currentPosition,
    required this.theme,
    required this.selectedCount,
    this.style = kDefaultSelectionOverlayStyle,
  });

  final Offset startPosition;
  final Offset currentPosition;
  final AppThemeData theme;
  final int selectedCount;
  final SelectionOverlayStyle style;

  @override
  Widget build(BuildContext context) {
    final rect = Rect.fromPoints(startPosition, currentPosition);
    final attachRight = currentPosition.dx >= startPosition.dx;
    final attachBottom = currentPosition.dy >= startPosition.dy;
    final selectionBorderColor = style.resolveBorderColor(theme);

    return Stack(
      children: [
        // Selection rectangle
        Positioned(
          left: rect.left,
          top: rect.top,
          width: rect.width.abs(),
          height: rect.height.abs(),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: style.resolveFillColor(theme),
                  border: Border.all(
                    color: selectionBorderColor,
                    width: style.borderWidth,
                  ),
                  borderRadius: BorderRadius.circular(style.borderRadius),
                ),
              ),
              if (selectedCount > 0)
                Positioned(
                  left: attachRight ? null : 0,
                  right: attachRight ? 0 : null,
                  top: attachBottom ? null : 0,
                  bottom: attachBottom ? 0 : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: selectionBorderColor,
                      borderRadius: BorderRadius.circular(
                        style.borderRadius * 0.75,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Text(
                      '$selectedCount',
                      style: TextStyle(
                        color: theme.primaryButtonText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
