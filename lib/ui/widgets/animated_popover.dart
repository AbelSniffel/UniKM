import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

/// An anchored panel with independently timed opening and closing transitions.
class const AnimatedPopover({
  super.key,
  required final Widget child,
  required final Widget Function(BuildContext context, VoidCallback toggle)
  builder,

  /// Called as the panel starts opening (true) or closing (false).
  final ValueChanged<bool>? onOpenChanged,
}) extends StatefulWidget {
  @override
  State<AnimatedPopover> createState() => _AnimatedPopoverState();
}

class _AnimatedPopoverState extends State<AnimatedPopover>
    with SingleTickerProviderStateMixin {
  final _menu = MenuController();
  final _buttonFocus = FocusNode();
  // Its durations are set in build, as reduced motion allows.
  late final _animation = AnimationController(vsync: this)
    ..addStatusListener((_) {
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
    _animation
      ..duration = context.motion(const Duration(milliseconds: 500))
      ..reverseDuration = context.motion(const Duration(milliseconds: 300));
    final closing = !_animation.status.isForwardOrCompleted;

    return RawMenuAnchor(
      controller: _menu,
      childFocusNode: _buttonFocus,
      consumeOutsideTaps: true,
      onOpenRequested: (_, showOverlay) {
        showOverlay();
        _animation.forward();
        widget.onOpenChanged?.call(true);
      },
      onCloseRequested: (hideOverlay) {
        if (!_animation.status.isForwardOrCompleted) return;
        widget.onOpenChanged?.call(false);
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
                        color: context.appTheme.surface,
                        surfaceTintColor: Colors.transparent,
                        elevation: 3,
                        borderRadius: BorderRadius.circular(
                          context.appTheme.cornerRadius,
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

class const _PopoverPosition({
  required final Rect anchor,
  required final double heightFactor,
  required final EdgeInsets padding,
  required final TextDirection direction,
}) extends SingleChildLayoutDelegate {
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

/// A header icon button that opens a popover with a titled slider, such as
/// the gradient bar's animation speed.
class const SliderPopoverButton({
  super.key,

  /// Heads the popover and is the button's tooltip.
  required final String title,

  /// The current value, in the accent right after the title.
  required final String value,
  required final Widget icon,
  required final Widget slider,

  /// An extra button at the end of the title row.
  final Widget? action,

  /// Called as the popover starts opening (true) or closing (false).
  final ValueChanged<bool>? onOpenChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return AnimatedPopover(
      onOpenChanged: onOpenChanged,
      child: SizedBox(
        width: 300,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 36,
                // The value sits right after the title, reading as one label.
                child: Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: Row(
                        spacing: 6,
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            value,
                            style: TextStyle(
                              color: theme.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ?action,
                  ],
                ),
              ),
              // Without side padding, so the track lines up with the title row.
              SliderTheme(
                data: SliderTheme.of(context)
                    .copyWith(padding: const EdgeInsets.symmetric(vertical: 8)),
                child: slider,
              ),
            ],
          ),
        ),
      ),
      builder: (context, toggle) =>
          IconButton(tooltip: title, onPressed: toggle, icon: icon),
    );
  }
}
