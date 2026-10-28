import 'package:flutter/rendering.dart';

class _ChildParentData extends ContainerBoxParentData<RenderBox> {}

/// A [RenderBox] that lays out its own children, then paints and hit tests
/// them in order. Subclasses implement [performLayout].
abstract class MultiChildRenderBox extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  /// The layout data of [child]: its offset and its siblings.
  ContainerBoxParentData<RenderBox> childData(RenderBox child) =>
      child.parentData! as ContainerBoxParentData<RenderBox>;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _ChildParentData();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
