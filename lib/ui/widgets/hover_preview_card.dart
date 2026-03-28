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

  void _triggerImmediateTap() {
    widget.onTap?.call();
  }

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

  @override
  Widget build(BuildContext context) {
    final useImmediateTap = widget.onTap != null && widget.onDoubleTap != null;

    return HoverBuilder(
      builder: (context, isHovered) {
        final animationDuration = _suppressAnimation
            ? Duration.zero
            : kVeryFastAnimation;
        final borderWidth = (widget.isSelected || isHovered) ? 2.5 : 0.0;
        final borderColor = widget.isSelected
            ? widget.theme.accent
            : isHovered
            ? widget.theme.accent.withValues(alpha: 0.6)
            : widget.theme.border.withValues(alpha: 0.1);

        final innerRadius = widget.theme.cornerRadius > borderWidth
            ? widget.theme.cornerRadius - borderWidth
            : 0.0;

        return Listener(
          // When both onTap and onDoubleTap are provided, use the raw pointer-down
          // event for immediate selection so there is no gesture-arena delay caused
          // by the DoubleTapGestureRecognizer competing with the TapGestureRecognizer.
          onPointerDown: useImmediateTap
              ? (event) {
                  if (event.buttons & kPrimaryMouseButton != 0) {
                    _triggerImmediateTap();
                  }
                }
              : null,
          child: InkWell(
            onTap: useImmediateTap ? () {} : widget.onTap,
            onDoubleTap: widget.onDoubleTap,
            onSecondaryTapDown: widget.onSecondaryTapDown,
            borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
            child: AnimatedContainer(
            duration: animationDuration,
            width: 120,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
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
                      constraints: const BoxConstraints(maxWidth: 100),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
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

                  // Hover controls for custom themes
                  if (widget.isCustom && isHovered)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.onEdit != null)
                            _buildSmallButton(Icons.edit, widget.onEdit!),
                          if (widget.onDelete != null) ...[
                            const SizedBox(width: 4),
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
      );
      },
    );
  }

  Widget _buildSmallButton(
    IconData iconData,
    VoidCallback onBtnTap, {
    Color color = Colors.white,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onBtnTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(iconData, size: 14, color: color),
        ),
      ),
    );
  }
}
