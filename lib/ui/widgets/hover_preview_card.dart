library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import 'hover_builder.dart';

/// A unified preview card widget used in settings (e.g., ThemeCard, GradientEffectPreview)
class HoverPreviewCard extends StatefulWidget {
  const HoverPreviewCard({
    super.key,
    required this.name,
    required this.theme,
    required this.isSelected,
    required this.backgroundBuilder,
    this.cornerRadiusOverride,
    this.isCustom = false,
    this.onTap,
    this.onDoubleTap,
    this.onEdit,
    this.onDelete,
    this.onSecondaryTapDown,
    this.icon,
    this.overlayWidget,
  });

  final String name;
  final AppThemeData theme;
  final bool isSelected;
  final Widget Function(BuildContext context, double innerRadius)
  backgroundBuilder;
  final double? cornerRadiusOverride;

  // Custom theme specific features
  final bool isCustom;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final void Function(TapDownDetails)? onSecondaryTapDown;

  // Background icon features
  final IconData? icon;

  /// Optional interactive widget placed at the bottom-right corner of the card.
  /// Receives pointer events before the card's [onTap], so it remains fully
  /// interactive without triggering the card selection.
  final Widget? overlayWidget;

  @override
  State<HoverPreviewCard> createState() => _HoverPreviewCardState();
}

class _HoverPreviewCardState extends State<HoverPreviewCard> {
  bool _suppressAnimation = false;
  bool _lastTickerEnabled = true;

  // Pointer tracking for immediate tap-on-release without gesture-arena delay
  int? _activePrimaryPointer;
  Offset? _primaryPointerDownPosition;
  bool _primaryPointerMoved = false;
  final Set<int> _consumedPrimaryPointers = <int>{};

  static const double _dragSlop = 8.0;

  double get _effectiveCornerRadius =>
      widget.cornerRadiusOverride ?? widget.theme.cornerRadius;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (tickerEnabled && !_lastTickerEnabled) {
      // Page just became visible again — snap to the current visual state
      // instantly (avoids animating the selection border in), then re-enable
      // animations the following frame so hover transitions work correctly.
      _suppressAnimation = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _suppressAnimation = false);
      });
    }
    _lastTickerEnabled = tickerEnabled;
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if ((event.buttons & kPrimaryMouseButton) == 0) return;
    if (_consumedPrimaryPointers.remove(event.pointer)) return;
    _activePrimaryPointer = event.pointer;
    _primaryPointerDownPosition = event.position;
    _primaryPointerMoved = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePrimaryPointer) return;
    final down = _primaryPointerDownPosition;
    if (down != null && (event.position - down).distance > _dragSlop) {
      _primaryPointerMoved = true;
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_consumedPrimaryPointers.remove(event.pointer)) return;
    if (event.pointer != _activePrimaryPointer) return;
    final moved = _primaryPointerMoved;
    _activePrimaryPointer = null;
    _primaryPointerDownPosition = null;
    _primaryPointerMoved = false;
    if (!moved) widget.onTap?.call();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _consumedPrimaryPointers.remove(event.pointer);
    if (event.pointer != _activePrimaryPointer) return;
    _activePrimaryPointer = null;
    _primaryPointerDownPosition = null;
    _primaryPointerMoved = false;
  }

  void _registerActionButtonPointer(int pointer) {
    _consumedPrimaryPointers.add(pointer);
  }

  @override
  Widget build(BuildContext context) {
    // When a double-tap handler is present, bypass InkWell's TapGestureRecognizer
    // (which waits ~300 ms to distinguish single from double) by routing single
    // taps through raw pointer-up events, exactly like GameCard does.
    final useRawTap = widget.onTap != null && widget.onDoubleTap != null;

    return HoverBuilder(
      builder: (context, isHovered) {
        final animationDuration = _suppressAnimation
            ? Duration.zero
            : kHoverCardAnimation;
        final borderWidth = (widget.isSelected || isHovered) ? 2.5 : 1.0;
        final borderColor = widget.isSelected
            ? widget.theme.accent
            : isHovered
            ? widget.theme.accent.withValues(alpha: 0.6)
            : widget.theme.border.withValues(alpha: 0.1);

        final innerRadius = _effectiveCornerRadius > borderWidth
          ? _effectiveCornerRadius - borderWidth
            : 0.0;

        return Listener(
          onPointerDown: useRawTap ? _handlePointerDown : null,
          onPointerMove: useRawTap ? _handlePointerMove : null,
          onPointerUp: useRawTap ? _handlePointerUp : null,
          onPointerCancel: useRawTap ? _handlePointerCancel : null,
          child: GestureDetector(
            onDoubleTap: widget.onDoubleTap,
            child: InkWell(
              onTap: useRawTap ? () {} : widget.onTap,
              onSecondaryTapDown: widget.onSecondaryTapDown,
              borderRadius: BorderRadius.circular(_effectiveCornerRadius),
              child: AnimatedContainer(
              duration: animationDuration,
              curve: Curves.linear,
              width: 125,
              height: 68,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_effectiveCornerRadius),
                border: Border.all(color: borderColor, width: borderWidth),
                boxShadow: widget.isSelected || isHovered
                    ? [BoxShadow(color: widget.theme.accent, blurRadius: 3)]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(innerRadius),
                child: Stack(
                  children: [
                    widget.backgroundBuilder(context, innerRadius),

                    if (widget.icon != null)
                      // Subtle large background icon for depth
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Icon(
                          widget.icon,
                          size: 45,
                          color: widget.theme.surface.withValues(alpha: 0.25),
                        ),
                      ),

                    // Floating Name Pill
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 110),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(
                            _effectiveCornerRadius,
                          ),
                        ),
                        child: Text(
                          widget.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),

                    if (widget.isCustom)
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.onEdit != null)
                              _buildSmallButton(Icons.edit, widget.onEdit!),
                            if (widget.onDelete != null && isHovered) ...[
                              const SizedBox(width: 2),
                              _buildSmallButton(
                                Icons.delete,
                                widget.onDelete!,
                                color: Colors.redAccent,
                              ),
                            ],
                          ],
                        ),
                      ),

                    // Interactive overlay — rendered last so its gesture
                    // recognizers win over the parent InkWell.
                    if (widget.overlayWidget != null)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: widget.overlayWidget!,
                      ),
                  ],
                ),
              ),
            ),
          ),
          ),
        );
      },
    );
  }

  Widget _buildSmallButton(
    IconData iconData,
    VoidCallback onBtnTap, {
    Color color = Colors.white,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Listener(
        onPointerDown: (event) {
          if ((event.buttons & kPrimaryMouseButton) == 0) return;
          _registerActionButtonPointer(event.pointer);
          onBtnTap();
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(_effectiveCornerRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(iconData, size: 14, color: color),
          ),
        ),
      ),
    );
  }
}
