import 'package:flutter/material.dart';

const themeIconGroups = <(String, List<(IconData, String)>)>[
  (
    'Nature',
    [
      (Icons.eco, 'Leaf'),
      (Icons.local_florist, 'Flower'),
      (Icons.park, 'Tree'),
      (Icons.forest, 'Forest'),
      (Icons.water, 'Water'),
      (Icons.tsunami, 'Tsunami'),
    ],
  ),
  (
    'Light & Weather',
    [
      (Icons.wb_twilight, 'Twilight'),
      (Icons.light_mode, 'Sun'),
      (Icons.dark_mode, 'Moon'),
      (Icons.cloud, 'Cloud'),
      (Icons.air, 'Air'),
      (Icons.storm, 'Storm'),
      (Icons.bolt, 'Bolt'),
      (Icons.local_fire_department, 'Fire'),
      (Icons.ac_unit, 'Snow'),
    ],
  ),
  (
    'Space & Cosmos',
    [
      (Icons.star, 'Star'),
      (Icons.auto_awesome, 'Stars'),
      (Icons.flare, 'Flare'),
      (Icons.public, 'Globe'),
      (Icons.rocket_launch, 'Rocket'),
    ],
  ),
  (
    'Basic Shapes',
    [
      (Icons.pentagon, 'Pentagon'),
      (Icons.hexagon, 'Hexagon'),
      (Icons.square, 'Square'),
      (Icons.circle, 'Circle'),
    ],
  ),
  (
    'Misc',
    [
      (Icons.palette, 'Palette'),
      (Icons.brush, 'Brush'),
      (Icons.diamond, 'Diamond'),
      (Icons.favorite, 'Heart'),
    ],
  ),
];

final _themeIconsByCodePoint = <int, IconData>{
  for (final group in themeIconGroups)
    for (final entry in group.$2) entry.$1.codePoint: entry.$1,
};

/// Preserve arbitrary Material code points from legacy theme files. Release
/// builds must use --no-tree-shake-icons until that legacy format is retired.
IconData themeIconFromCodePoint(int codePoint) {
  final builtin = _themeIconsByCodePoint[codePoint];
  if (builtin != null) return builtin;
  // ignore: non_const_argument_for_const_parameter
  return IconData(codePoint, fontFamily: 'MaterialIcons');
}
