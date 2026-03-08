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
    
    return Stack(
      children: [
        // Selection rectangle
        Positioned(
          left: rect.left,
          top: rect.top,
          width: rect.width.abs(),
          height: rect.height.abs(),
          child: Container(
            decoration: BoxDecoration(
              color: theme.accent.withValues(alpha: 0.1),
              border: Border.all(
                color: theme.accent,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        
        // Selection count badge
        if (selectedCount > 0)
          Positioned(
            left: currentPosition.dx + 10,
            top: currentPosition.dy + 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.accent,
                borderRadius: BorderRadius.circular(theme.cornerRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Text(
                '$selectedCount selected',
                style: TextStyle(
                  color: theme.primaryButtonText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Mixin to add drag-select functionality to a widget
mixin DragSelectMixin<T extends StatefulWidget> on State<T> {
  bool _isDragging = false;
  Offset? _dragStart;
  Offset? _dragCurrent;

  bool get isDragging => _isDragging;
  Offset? get dragStart => _dragStart;
  Offset? get dragCurrent => _dragCurrent;

  void startDrag(Offset position) {
    setState(() {
      _isDragging = true;
      _dragStart = position;
      _dragCurrent = position;
    });
  }

  void updateDrag(Offset position) {
    if (_isDragging) {
      setState(() {
        _dragCurrent = position;
      });
    }
  }

  void endDrag() {
    setState(() {
      _isDragging = false;
      _dragStart = null;
      _dragCurrent = null;
    });
  }

  Rect? get selectionRect {
    if (_dragStart == null || _dragCurrent == null) return null;
    return Rect.fromPoints(_dragStart!, _dragCurrent!);
  }
}
