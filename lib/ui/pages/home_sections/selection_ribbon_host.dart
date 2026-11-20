import 'package:material_ui/material_ui.dart';

import '../../../core/constants/app_constants.dart';
import 'selection_ribbon.dart';

/// Lives in the shell below the navigation slots so the navigation paints over
/// the ribbon while both animate with the same duration and curve.
class const SelectionRibbonHost({
  super.key,
  required final Widget child,
  required final bool visible,
  required final bool atTop,
}) extends StatefulWidget {
  @override
  State<SelectionRibbonHost> createState() => _SelectionRibbonHostState();
}

class _SelectionRibbonHostState extends State<SelectionRibbonHost>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: kNavPanelMotionAnimation,
    value: widget.visible ? 1 : 0,
  );
  late final _animation = CurvedAnimation(
    parent: _controller,
    curve: kNavPanelMotionCurve,
  );

  @override
  void didUpdateWidget(SelectionRibbonHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ribbon = IgnorePointer(
      ignoring: !widget.visible,
      child: ClipRect(
        child: SizeTransition(
          sizeFactor: _animation,
          alignment: widget.atTop
              ? Alignment.topCenter
              : Alignment.bottomCenter,
          child: const SelectionRibbon(),
        ),
      ),
    );
    return Column(
      children: [
        if (widget.atTop) ribbon,
        Expanded(child: widget.child),
        if (!widget.atTop) ribbon,
      ],
    );
  }
}
