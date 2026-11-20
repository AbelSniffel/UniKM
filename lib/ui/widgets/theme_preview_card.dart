import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import 'preview_card.dart';
import 'theme_preview_background.dart';

/// One theme preview used at menu size or at the regular Settings card size.
class const ThemePreviewCard({
  super.key,
  required final AppThemeData data,
  required final bool selected,
  required final VoidCallback onTap,
  final VoidCallback? onDoubleTap,
  final double? height = PreviewCard.defaultHeight,
  final Key? tapKey,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => PreviewCard(
    name: data.name,
    isSelected: selected,
    height: height,
    tapKey: tapKey,
    onTap: onTap,
    onDoubleTap: onDoubleTap,
    icon: data.icon,
    backgroundIconColor: data.surface.withValues(alpha: 0.25),
    backgroundBuilder: (_, _) => ThemePreviewBackground(theme: data),
  );
}
