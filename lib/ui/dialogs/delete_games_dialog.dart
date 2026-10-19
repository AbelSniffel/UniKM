import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../widgets/dialog_helpers.dart';

/// One confirmation for deletion from the library, cards, and game editor.
Future<bool> showDeleteGamesDialog(
  BuildContext context,
  AppThemeData theme,
  int count, {
  String? gameTitle,
}) {
  assert(count > 0);
  return showConfirmDialog(
    context: context,
    theme: theme,
    title: 'Delete ${count == 1 ? 'Game' : '$count Games'}?',
    titleIcon: Icons.delete_forever,
    message: count == 1 && gameTitle != null
        ? 'Delete "$gameTitle"? This action cannot be undone.'
        : 'This action cannot be undone.',
    confirmLabel: 'Delete',
    destructive: true,
  );
}
