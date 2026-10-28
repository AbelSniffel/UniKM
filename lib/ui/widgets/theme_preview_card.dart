import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'preview_card.dart';
import 'theme_preview_background.dart';

/// One theme preview used at menu size or at the regular Settings card size.
class ThemePreviewCard extends StatelessWidget {
  const ThemePreviewCard({
    super.key,
    required this.data,
    required this.theme,
    required this.selected,
    required this.onTap,
    this.onDoubleTap,
    this.preview,
    this.height = PreviewCard.defaultHeight,
    this.tapKey,
  });

  final AppThemeData data;
  final AppThemeData theme;
  final AppThemeData? preview;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final double? height;
  final Key? tapKey;

  @override
  Widget build(BuildContext context) {
    final background = preview ?? data;
    return PreviewCard(
      name: data.name,
      theme: theme,
      isSelected: selected,
      height: height,
      tapKey: tapKey,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      icon: data.icon,
      backgroundIconColor: background.surface.withValues(alpha: 0.25),
      backgroundBuilder: (_, _) => ThemePreviewBackground(theme: background),
    );
  }
}
