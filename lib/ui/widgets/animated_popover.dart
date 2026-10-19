import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

/// An anchored panel with independently timed opening and closing transitions.
class AnimatedPopover extends StatefulWidget {
  const AnimatedPopover({
    super.key,
    required this.theme,
    required this.child,
    required this.builder,
  });

  final AppThemeData theme;
  final Widget child;
  final Widget Function(BuildContext context, VoidCallback toggle) builder;

  @override
  State<AnimatedPopover> createState() => _AnimatedPopoverState();
}

class _AnimatedPopoverState extends State<AnimatedPopover>
    with SingleTickerProviderStateMixin {
  final _menu = MenuController();
  final _buttonFocus = FocusNode();
  late final _animation =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
        reverseDuration: const Duration(milliseconds: 300),
      )..addStatusListener((_) {
        if (mounted) setState(() {});
      });
  late final _height = CurvedAnimation(
    parent: _animation,
    curve: const Cubic(.3, 0, 0, 1),
    reverseCurve: Curves.easeInOutCubic,
  );
  late final _opacity = CurvedAnimation(
    parent: _animation,
    curve: const Interval(0, .5),
    reverseCurve: const Interval(0, .67),
  );

  @override
  void dispose() {
    _height.dispose();
    _opacity.dispose();
    _animation.dispose();
    _buttonFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    _animation.duration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 500);
    _animation.reverseDuration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 300);
    final closing = !_animation.status.isForwardOrCompleted;

    return RawMenuAnchor(
      controller: _menu,
      childFocusNode: _buttonFocus,
      consumeOutsideTaps: true,
      onOpenRequested: (_, showOverlay) {
        showOverlay();
        _animation.forward();
      },
      onCloseRequested: (hideOverlay) {
        if (!_animation.status.isForwardOrCompleted) return;
        _animation.reverse().whenComplete(() {
          if (mounted && _animation.isDismissed) hideOverlay();
        });
      },
      overlayBuilder: (context, info) => AnimatedBuilder(
        animation: _height,
        builder: (context, child) => CustomSingleChildLayout(
          delegate: _PopoverPosition(
            anchor: info.anchorRect,
            heightFactor: _height.value,
            padding: MediaQuery.paddingOf(context) + const EdgeInsets.all(8),
            direction: Directionality.of(context),
          ),
          child: child,
        ),
        child: TapRegion(
          groupId: info.tapRegionGroupId,
          consumeOutsideTaps: true,
          onTapOutside: (_) => _menu.close(),
          child: ExcludeSemantics(
            excluding: closing,
            child: IgnorePointer(
              ignoring: closing,
              child: ExcludeFocus(
                excluding: closing,
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.escape):
                        _menu.close,
                  },
                  child: Focus(
                    autofocus: true,
                    child: FadeTransition(
                      opacity: _opacity,
                      child: Material(
                        color: widget.theme.surface,
                        surfaceTintColor: Colors.transparent,
                        elevation: 3,
                        borderRadius: BorderRadius.circular(
                          widget.theme.cornerRadius,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SizeTransition(
                          sizeFactor: _height,
                          alignment: Alignment.topLeft,
                          fixedCrossAxisSizeFactor: 1,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: widget.child,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      builder: (context, _, _) => Focus(
        focusNode: _buttonFocus,
        child: widget.builder(context, () {
          if (_animation.status.isForwardOrCompleted) {
            _menu.close();
          } else {
            _menu.open();
          }
        }),
      ),
    );
  }
}

class _PopoverPosition extends SingleChildLayoutDelegate {
  const _PopoverPosition({
    required this.anchor,
    required this.heightFactor,
    required this.padding,
    required this.direction,
  });

  final Rect anchor;
  final double heightFactor;
  final EdgeInsets padding;
  final TextDirection direction;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen().deflate(padding);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = direction == TextDirection.ltr
        ? anchor.left
        : anchor.right - childSize.width;
    // Use the full panel height to choose a side throughout the transition.
    final fullHeight = heightFactor > 0 ? childSize.height / heightFactor : 0;
    final top = anchor.bottom + fullHeight <= size.height - padding.bottom
        ? anchor.bottom
        : anchor.top - childSize.height;
    return Offset(
      left.clamp(padding.left, size.width - padding.right - childSize.width),
      top.clamp(padding.top, size.height - padding.bottom - childSize.height),
    );
  }

  @override
  bool shouldRelayout(_PopoverPosition oldDelegate) =>
      anchor != oldDelegate.anchor ||
      heightFactor != oldDelegate.heightFactor ||
      padding != oldDelegate.padding ||
      direction != oldDelegate.direction;
}
