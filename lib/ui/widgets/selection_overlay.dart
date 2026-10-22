/// Selection overlay widget for drag-select
/// Matches the original Python SelectionOverlay
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Selection rectangle overlay for drag-select
class SelectionOverlay extends StatelessWidget {
  const SelectionOverlay({
    super.key,
    required this.startPosition,
    required this.currentPosition,
    required this.theme,
    required this.selectedCount,
  });

  final Offset startPosition;
  final Offset currentPosition;
  final AppThemeData theme;
  final int selectedCount;

  @override
  Widget build(BuildContext context) {
    final rect = Rect.fromPoints(startPosition, currentPosition);
    final attachRight = currentPosition.dx >= startPosition.dx;
    final attachBottom = currentPosition.dy >= startPosition.dy;
    final selectionBorderColor = theme.accent.withValues(alpha: 1);

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
                  color: theme.accent.withValues(alpha: 0.10),
                  border: Border.all(
                    color: selectionBorderColor,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(8),
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
                      borderRadius: BorderRadius.circular(6),
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
