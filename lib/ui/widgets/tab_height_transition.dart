/// Animates a panel's height only when its tab changes.
library;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/constants/app_constants.dart';

/// Animates [child]'s box from its old height when [tab] changes. Any other
/// height change, such as cards reflowing in a resizing window, applies at
/// once, which an [AnimatedSize] cannot tell apart.
class TabHeightTransition extends StatefulWidget {
  const TabHeightTransition({
    super.key,
    required this.tab,
    required this.child,
  });

  final Object tab;
  final Widget child;

  @override
  State<TabHeightTransition> createState() => _TabHeightTransitionState();
}

class _TabHeightTransitionState extends State<TabHeightTransition>
    with SingleTickerProviderStateMixin {
  late final _controller =
      AnimationController(vsync: this, duration: kTabTransition)
        ..addStatusListener(
          (s) => s.isCompleted ? setState(() => _from = null) : null,
        );

  /// The height animated from, or null while the box follows its child.
  double? _from;

  @override
  void didUpdateWidget(TabHeightTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    final box = context.findRenderObject() as RenderBox?;
    if (widget.tab != oldWidget.tab &&
        !MediaQuery.disableAnimationsOf(context) &&
        box != null &&
        box.hasSize) {
      _from = box.size.height;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    // Clip only mid-switch, so glows and shadows show at rest.
    builder: (context, child) => ClipRect(
      clipBehavior: _from == null ? Clip.none : Clip.hardEdge,
      child: _HeightFrom(
        from: _from,
        t: kTabTransitionCurve.transform(_controller.value),
        child: child,
      ),
    ),
    child: widget.child,
  );
}

class _HeightFrom extends SingleChildRenderObjectWidget {
  const _HeightFrom({required this.from, required this.t, super.child});

  final double? from;
  final double t;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHeightFrom()
    ..from = from
    ..t = t;

  @override
  void updateRenderObject(BuildContext context, _RenderHeightFrom box) => box
    ..from = from
    ..t = t
    ..markNeedsLayout();
}

/// Takes a height [t] of the way from [from] to its child's.
class _RenderHeightFrom extends RenderProxyBox {
  double? from;
  double t = 1;

  @override
  void performLayout() {
    final child = this.child!..layout(constraints, parentUsesSize: true);
    final to = child.size.height;
    final start = from ?? to;
    size = constraints.constrain(
      Size(child.size.width, start + (to - start) * t),
    );
    // Tell a column layout above the height still to come, so it places
    // sections by where the box ends up rather than every step on the way.
    final pending = to - size.height;
    _placement?.pendingHeights.remove(this);
    _placement = null;
    if (pending == 0) return;
    for (RenderObject node = this; node.parent != null; node = node.parent!) {
      if (node.parent case final PendingHeightPlacement placement) {
        placement.pendingHeights[this] = (child: node, height: pending);
        _placement = placement;
        return;
      }
    }
  }

  PendingHeightPlacement? _placement;

  @override
  void detach() {
    _placement?.pendingHeights.remove(this);
    _placement = null;
    super.detach();
  }
}

/// A layout that places children by height, such as a grid filling its
/// shortest column, and should use the height a [TabHeightTransition] inside
/// a child is heading to.
mixin PendingHeightPlacement on RenderBox {
  /// Running transitions, each with the child it sits in and the height
  /// still to come.
  final pendingHeights =
      <RenderObject, ({RenderObject child, double height})>{};

  /// The height still to come in [child], once its transitions end.
  double pendingHeightOf(RenderObject child) => pendingHeights.values
      .where((entry) => entry.child == child)
      .fold(0, (sum, entry) => sum + entry.height);
}
