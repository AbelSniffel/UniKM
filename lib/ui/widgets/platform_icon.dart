library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/constants/platform_patterns.dart';

FaIconData platformIconFor(GamePlatform platform) => switch (platform) {
  GamePlatform.steam => FontAwesomeIcons.steamSymbol,
  GamePlatform.epicGames => FontAwesomeIcons.store,
  GamePlatform.gog => FontAwesomeIcons.solidFloppyDisk,
  GamePlatform.origin => FontAwesomeIcons.circleDot,
  GamePlatform.ubisoft => FontAwesomeIcons.coins,
  GamePlatform.xbox => FontAwesomeIcons.xbox,
  GamePlatform.playStation => FontAwesomeIcons.playstation,
  GamePlatform.nintendo => FontAwesomeIcons.gamepad,
  GamePlatform.humble => FontAwesomeIcons.store,
  GamePlatform.itchio => FontAwesomeIcons.gamepad,
  GamePlatform.webLink => FontAwesomeIcons.link,
  GamePlatform.other => FontAwesomeIcons.question,
};

double platformIconSizeFor(GamePlatform platform, {double? minHeight}) {
  final double base = minHeight != null
      ? math.max(23.0, math.min(minHeight * 0.6, 28.0))
      : 18.0;

  return base *
      switch (platform) {
        GamePlatform.steam => 1.14,
        GamePlatform.nintendo || GamePlatform.itchio => 0.91,
        _ => 1.0,
      };
}

class const PlatformIcon({
  super.key,
  required final GamePlatform platform,

  /// The surrounding icon theme's colour by default.
  final Color? color,
  final double? size,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => FaIcon(
    platformIconFor(platform),
    size: size ?? platformIconSizeFor(platform),
    color: color,
  );
}
