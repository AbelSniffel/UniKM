import 'package:material_ui/material_ui.dart';

import '../../core/constants/app_constants.dart';

/// Unfolds [child] sideways from its leading edge as it fades in, and folds
/// the last one shown away again when [child] becomes null, so the widgets
/// beside it slide apart or together.
class const HorizontalFold({super.key, required final Widget? child})
    extends StatefulWidget {
  @override
  State<HorizontalFold> createState() => _HorizontalFoldState();
}

class _HorizontalFoldState extends State<HorizontalFold> {
  Widget? _shown;

  @override
  Widget build(BuildContext context) {
    final instant = MediaQuery.disableAnimationsOf(context);
    // Without animations it goes at once: finishing in the middle of this
    // build, its end could not rebuild it.
    _shown = widget.child ?? (instant ? null : _shown);
    final shown = _shown;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.child == null ? 0 : 1),
      duration: instant ? Duration.zero : kMediumAnimation,
      curve: Curves.easeInOutCubic,
      onEnd: () {
        if (!instant && widget.child == null) setState(() => _shown = null);
      },
      builder: (context, width, _) => shown == null || width == 0
          ? const SizedBox.shrink()
          : IgnorePointer(
              ignoring: widget.child == null,
              child: ClipRect(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: width,
                  child: Opacity(opacity: width, child: shown),
                ),
              ),
            ),
    );
  }
}
