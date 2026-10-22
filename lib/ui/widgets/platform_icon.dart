library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/constants/platform_patterns.dart';

FaIconData platformIconFor(GamePlatform platform) {
  return switch (platform) {
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
}

double platformIconSizeFor(GamePlatform platform, {double? minHeight}) {
  final double base = minHeight != null
      ? math.max(23.0, math.min(minHeight * 0.6, 28.0))
      : 18.0;

  double multiplier;
  if (platform == GamePlatform.steam) {
    multiplier = 1.14;
  } else if (platform == GamePlatform.nintendo ||
      platform == GamePlatform.itchio) {
    multiplier = 0.91;
  } else {
    multiplier = 1.0;
  }

  return base * multiplier;
}

class PlatformIcon extends StatelessWidget {
  const PlatformIcon({
    super.key,
    required this.platform,
    required this.color,
    this.size,
  });

  final GamePlatform platform;
  final Color color;
  final double? size;

  @override
  Widget build(BuildContext context) {
    return FaIcon(
      platformIconFor(platform),
      size: size ?? platformIconSizeFor(platform),
      color: color,
    );
  }
}
