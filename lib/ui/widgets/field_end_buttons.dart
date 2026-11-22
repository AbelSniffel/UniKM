import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import 'platform_menu_button.dart' show FieldSegment;

/// Icon buttons at the end of a text field's box, each filling the box's
/// [height] with square corners and the last ending at the box's rounded
/// edge, [endExtraWidth] wider unless it is a [FieldSegment]. Give the field
/// `suffixIconConstraints: const BoxConstraints()` so nothing pads them.
class const FieldEndButtons({
  super.key,
  required final List<Widget> children,

  /// The box's height; a labelled field's ([labelledHeight]) by default.
  final double? height,
}) extends StatelessWidget {
  /// The width of each button.
  static const buttonWidth = 38.0;

  /// The extra width of a button at the box's end.
  static const endExtraWidth = 4.0;

  /// The height of a labelled field's box at standard density.
  static const _labelledHeight = 60.0;

  /// The height of a labelled field's box, such as the game key's, under
  /// [context]'s theme, whose density makes it shorter on desktop.
  static double labelledHeight(BuildContext context) =>
      _labelledHeight + Theme.of(context).visualDensity.baseSizeAdjustment.dy;

  @override
  Widget build(BuildContext context) {
    final boxHeight = height ?? labelledHeight(context);
    final inherited = IconButtonTheme.of(context).style;
    Widget sized(double width, Widget child) => IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: Size(width, boxHeight),
          shape: const RoundedRectangleBorder(),
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ).merge(inherited),
      ),
      child: child,
    );
    // A button at the box's end is wider, so its icon clears the rounded
    // corner; a split segment there is wide enough already.
    final last = children.lastOrNull;
    final widenLast = last != null && last is! FieldSegment;
    return ClipRRect(
      borderRadius: BorderRadius.horizontal(
        right: Radius.circular(context.appTheme.cornerRadius),
      ),
      child: sized(
        buttonWidth,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...widenLast ? children.take(children.length - 1) : children,
            if (widenLast) sized(buttonWidth + endExtraWidth, last),
          ],
        ),
      ),
    );
  }
}
