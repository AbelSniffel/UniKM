import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import 'dialog_helpers.dart';
import 'notification_system.dart';

/// Use the same confirmation and active-theme fallback from every theme action.
Future<void> deleteCustomThemeWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  String id,
  String name,
) async {
  if (ref.read(builtInThemeIdsProvider).contains(id)) return;
  // The initiating menu/header may unmount while the dialog is displayed.
  final notifier = ref.read(themeProvider.notifier);
  final theme = ref.read(effectiveThemeProvider);
  final confirmed = await showConfirmDialog(
    context: context,
    theme: theme,
    title: 'Delete Theme',
    titleIcon: Icons.delete,
    message: 'Are you sure you want to delete "$name"?',
    confirmLabel: 'Delete',
    destructive: true,
  );
  if (!confirmed) return;
  await notifier.deleteCustomTheme(id);
  NotificationManager.instance.success('Theme "$name" deleted');
}
