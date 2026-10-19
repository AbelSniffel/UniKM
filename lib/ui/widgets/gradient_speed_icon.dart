import 'package:flutter/material.dart';

import '../../core/settings/settings_model.dart';

/// Rounded Material icons for the three animation speed presets.
class GradientSpeedIcon extends StatelessWidget {
  const GradientSpeedIcon({
    super.key,
    required this.speed,
    required this.color,
  });

  final GradientAnimationSpeed speed;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 28,
    height: 28,
    child: Icon(
      switch (speed) {
        GradientAnimationSpeed.slow => Icons.slow_motion_video_rounded,
        GradientAnimationSpeed.standard => Icons.play_arrow_rounded,
        GradientAnimationSpeed.fast => Icons.fast_forward_rounded,
      },
      color: color,
      size: 26,
    ),
  );
}
