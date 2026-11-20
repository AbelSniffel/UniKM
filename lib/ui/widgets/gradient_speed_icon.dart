import 'package:material_ui/material_ui.dart';

import '../../core/settings/settings_model.dart';

/// Rounded Material icons for the animation speed presets, or a pause icon
/// while the previews are [paused].
class const GradientSpeedIcon({
  super.key,
  required final GradientAnimationSpeed speed,
  required final Color color,
  final bool paused = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 28,
    height: 28,
    child: Icon(
      paused
          ? Icons.pause_rounded
          : switch (speed) {
              GradientAnimationSpeed.slow => Icons.slow_motion_video_rounded,
              GradientAnimationSpeed.standard => Icons.play_arrow_rounded,
              GradientAnimationSpeed.fast => Icons.fast_forward_rounded,
              GradientAnimationSpeed.veryFast => Icons.double_arrow_rounded,
            },
      color: color,
      size: 26,
    ),
  );
}
