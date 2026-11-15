/// An [AnimatedSize] that animates only its child's height.
library;

import 'package:material_ui/material_ui.dart';

/// Animates changes in [child]'s height while its width follows the room it
/// is given at once. An [AnimatedSize] given a loose width animates that too,
/// so a widening window leaves the box behind, clipping its content. With
/// animations turned off the child shows as it is.
class AnimatedHeight extends StatelessWidget {
  const AnimatedHeight({
    super.key,
    required this.duration,
    required this.curve,
    this.alignment = Alignment.topCenter,
    required this.child,
  });

  final Duration duration;
  final Curve curve;
  final AlignmentGeometry alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      // Not a zero duration: that can notify its render object mid-layout.
      MediaQuery.disableAnimationsOf(context)
      ? child
      : SizedBox(
          width: double.infinity,
          child: AnimatedSize(
            duration: duration,
            curve: curve,
            alignment: alignment,
            child: child,
          ),
        );
}
