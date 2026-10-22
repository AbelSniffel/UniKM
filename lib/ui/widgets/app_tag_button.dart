import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import 'app_action_button.dart';

/// Maps tag selection and category colors to the shared option-button style.
class AppTagButton extends StatelessWidget {
  const AppTagButton({
    super.key,
    required this.tag,
    required this.theme,
    this.isSelected = false,
    this.onTap,
    this.deleteOnTap = false,
  });

  final Tag tag;
  final AppThemeData theme;
  final bool isSelected;
  final VoidCallback? onTap;

  final bool deleteOnTap;

  @override
  Widget build(BuildContext context) => AppActionButton(
    key: ValueKey('app_tag_button_${tag.id}'),
    label: tag.name,
    theme: theme,
    selected: onTap == null || isSelected,
    transparentWhenIdle: true,
    accentColor: tag.isSteamTag ? theme.accent : theme.secondary,
    readOnly: onTap == null,
    deleteOnHover: deleteOnTap && !tag.isSteamTag && onTap != null,
    showStatus: onTap != null,
    onTap: onTap,
  );
}
