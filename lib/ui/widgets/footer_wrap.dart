import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/constants/app_constants.dart';

/// Wraps when the actual controls do not fit, retaining both footer edges.
class FooterWrap extends Wrap {
  FooterWrap({super.key, required Widget leading, required Widget trailing})
    : super(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: kElementHSpacing,
        runSpacing: kElementVSpacing,
        children: [
          IntrinsicWidth(child: leading),
          trailing,
        ],
      );

  @override
  RenderWrap createRenderObject(BuildContext context) => _RenderFooterWrap(
    alignment: alignment,
    crossAxisAlignment: crossAxisAlignment,
    spacing: spacing,
    runSpacing: runSpacing,
    textDirection: Directionality.of(context),
  );
}

class _RenderFooterWrap extends RenderWrap {
  _RenderFooterWrap({
    required super.alignment,
    required super.crossAxisAlignment,
    required super.spacing,
    required super.runSpacing,
    required super.textDirection,
  });

  @override
  void performLayout() {
    super.performLayout();
    final trailing = lastChild;
    if (trailing == null) return;
    final parentData = trailing.parentData! as WrapParentData;
    parentData.offset = Offset(
      textDirection == TextDirection.rtl ? 0 : size.width - trailing.size.width,
      parentData.offset.dy,
    );
  }
}
