import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Edit this value (1 or greater) to cap columns in All and search views.
const int kSettingsSectionMaxColumns = 2;

const double kSettingsSectionMinimumWidth = 440;
const double kSettingsSectionSpacing = 24;

int settingsSectionColumnCount(double availableWidth) => availableWidth.isFinite
    ? math.max(
        1,
        math.min(
          kSettingsSectionMaxColumns,
          ((availableWidth + kSettingsSectionSpacing) /
                  (kSettingsSectionMinimumWidth + kSettingsSectionSpacing))
              .floor(),
        ),
      )
    : 1;

/// Packs whole settings sections into equal-width columns without reparenting
/// their controls when the window is resized.
class SettingsSectionGrid extends MultiChildRenderObjectWidget {
  const SettingsSectionGrid({
    super.key,
    required this.columns,
    required this.spacing,
    required super.children,
  }) : assert(columns > 0),
       assert(spacing >= 0);

  final int columns;
  final double spacing;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSettingsSectionGrid(columns, spacing, Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderSettingsSectionGrid).update(
        columns,
        spacing,
        Directionality.of(context),
      );
}

class _SettingsSectionParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSettingsSectionGrid extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _RenderSettingsSectionGrid(this._columns, this._spacing, this._textDirection);

  int _columns;
  double _spacing;
  TextDirection _textDirection;

  void update(int columns, double spacing, TextDirection textDirection) {
    if (_columns == columns &&
        _spacing == spacing &&
        _textDirection == textDirection) {
      return;
    }
    _columns = columns;
    _spacing = spacing;
    _textDirection = textDirection;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _SettingsSectionParentData();
    }
  }

  @override
  void performLayout() {
    if (childCount == 0) {
      size = constraints.constrain(Size.zero);
      return;
    }

    final columns = math.min(_columns, childCount);
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : kSettingsSectionMinimumWidth * columns + _spacing * (columns - 1);
    final columnWidth = math.max(
      0.0,
      (width - _spacing * (columns - 1)) / columns,
    );
    final heights = List<double>.filled(columns, 0);
    var child = firstChild;
    while (child != null) {
      // Place the next section in the shortest column, preferring reading order
      // when columns have equal heights.
      var column = 0;
      for (var i = 1; i < columns; i++) {
        if (heights[i] < heights[column]) column = i;
      }
      child.layout(
        BoxConstraints.tightFor(width: columnWidth),
        parentUsesSize: true,
      );
      final data = child.parentData! as ContainerBoxParentData<RenderBox>;
      final visualColumn = _textDirection == TextDirection.ltr
          ? column
          : columns - column - 1;
      data.offset = Offset(
        visualColumn * (columnWidth + _spacing),
        heights[column],
      );
      heights[column] += child.size.height + _spacing;
      child = data.nextSibling;
    }
    size = constraints.constrain(
      Size(width, heights.reduce(math.max) - _spacing),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final viewport = RenderAbstractViewport.maybeOf(this);
    if (viewport == null) {
      defaultPaint(context, offset);
      return;
    }
    // The grid is a single sliver child. Cull whole sections ourselves so
    // theme changes do not rasterize every offscreen section and its shadows.
    // Retain a small margin for shadows extending beyond section bounds.
    final visible = MatrixUtils.transformRect(
      viewport.getTransformTo(this),
      viewport.paintBounds,
    ).inflate(12);
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as ContainerBoxParentData<RenderBox>;
      if (visible.overlaps(data.offset & child.size)) {
        context.paintChild(child, offset + data.offset);
      }
      child = data.nextSibling;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
