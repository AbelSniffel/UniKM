import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';

/// A settings header's action: a plain icon button sitting straight on the
/// header row, as tall as the title so every header keeps one height.
class const SettingsHeaderAction({
  super.key,
  required final IconData icon,
  required final String tooltip,
  required final VoidCallback? onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon),
    tooltip: tooltip,
    onPressed: onTap,
    style: IconButton.styleFrom(
      // The accent, like the title's icon.
      foregroundColor: context.appTheme.accent,
      minimumSize: const Size.square(36),
      iconSize: 22,
      padding: EdgeInsets.zero,
      // Not shrunk by the app's compact density, so it fills the title row.
      visualDensity: VisualDensity.standard,
    ),
  );
}

/// A header's actions in a row, 2 px apart.
class const SettingsHeaderActionRow({
  super.key,
  required final List<Widget> children,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: children);
}
