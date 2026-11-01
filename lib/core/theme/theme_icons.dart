import 'package:flutter/material.dart';

const themeIconGroups = <(String, List<(IconData, String)>)>[
  (
    'Nature',
    [
      (Icons.eco, 'Leaf'),
      (Icons.local_florist, 'Flower'),
      (Icons.park, 'Tree'),
      (Icons.forest, 'Forest'),
      (Icons.grass, 'Grass'),
      (Icons.spa, 'Lotus'),
      (Icons.landscape, 'Mountains'),
      (Icons.terrain, 'Terrain'),
      (Icons.volcano, 'Volcano'),
      (Icons.water, 'Water'),
      (Icons.waves, 'Waves'),
      (Icons.tsunami, 'Tsunami'),
      (Icons.emoji_nature, 'Bee'),
      (Icons.pets, 'Paw'),
      (Icons.cruelty_free, 'Bunny'),
    ],
  ),
  (
    'Light & Weather',
    [
      (Icons.wb_twilight, 'Twilight'),
      (Icons.light_mode, 'Sun'),
      (Icons.dark_mode, 'Moon'),
      (Icons.nights_stay, 'Night'),
      (Icons.cloud, 'Cloud'),
      (Icons.air, 'Air'),
      (Icons.storm, 'Storm'),
      (Icons.bolt, 'Bolt'),
      (Icons.local_fire_department, 'Fire'),
      (Icons.whatshot, 'Flame'),
      (Icons.ac_unit, 'Snow'),
      (Icons.lightbulb, 'Bulb'),
      (Icons.wb_iridescent, 'Neon Tube'),
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
      (Icons.blur_on, 'Nebula'),
      (Icons.shield_moon, 'Moon Shield'),
    ],
  ),
  (
    'Food & Drink',
    [
      (Icons.icecream, 'Ice Cream'),
      (Icons.cake, 'Cake'),
      (Icons.cookie, 'Cookie'),
      (Icons.bakery_dining, 'Croissant'),
      (Icons.ramen_dining, 'Ramen'),
      (Icons.coffee, 'Coffee'),
      (Icons.local_bar, 'Cocktail'),
      (Icons.wine_bar, 'Wine'),
    ],
  ),
  (
    'Games & Tech',
    [
      (Icons.sports_esports, 'Controller'),
      (Icons.gamepad, 'D-Pad'),
      (Icons.smart_toy, 'Robot'),
      (Icons.memory, 'Chip'),
      (Icons.terminal, 'Terminal'),
      (Icons.code, 'Code'),
      (Icons.science, 'Science'),
      (Icons.headphones, 'Headphones'),
      (Icons.music_note, 'Music'),
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
      (Icons.castle, 'Castle'),
      (Icons.anchor, 'Anchor'),
      (Icons.sailing, 'Sailing'),
      (Icons.key, 'Key'),
      (Icons.shield, 'Shield'),
      (Icons.celebration, 'Party'),
      (Icons.workspace_premium, 'Badge'),
      (Icons.toys, 'Pinwheel'),
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
