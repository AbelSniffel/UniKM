/// Shared tag deletion confirmation and persistence.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../widgets/dialog_helpers.dart';

/// Returns the deleted count, or null when cancelled.
Future<int?> deleteTagWithConfirmation({
  required BuildContext context,
  required AppThemeData theme,
  required int tagId,
  required String tagName,
}) => _deleteTagsWithConfirmation(
  context: context,
  theme: theme,
  title: 'Delete Tag',
  message: 'Delete "$tagName" from this database and all games?',
  confirmLabel: 'Delete',
  delete: (db) => db.deleteTag(tagId),
);

/// Returns the deleted count, or null when cancelled or the list is empty.
Future<int?> deleteAllCustomTagsWithConfirmation({
  required BuildContext context,
  required AppThemeData theme,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final count = container
      .read(tagsProvider)
      .where((tag) => !tag.isSteamTag)
      .length;
  if (count == 0) return null;
  return _deleteTagsWithConfirmation(
    context: context,
    theme: theme,
    title: 'Delete All Custom Tags',
    message:
        'Delete $count custom ${count == 1 ? 'tag' : 'tags'} from this database and all games? Steam tags stay.',
    confirmLabel: 'Delete',
    delete: (db) => db.deleteAllCustomTags(),
  );
}

Future<int?> _deleteTagsWithConfirmation({
  required BuildContext context,
  required AppThemeData theme,
  required String title,
  required String message,
  required String confirmLabel,
  required Future<int> Function(AppDatabase) delete,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final db = container.read(requireDatabaseProvider);
  final confirmed = await showConfirmDialog(
    context: context,
    theme: theme,
    title: title,
    titleIcon: Icons.delete_forever,
    message: message,
    confirmLabel: confirmLabel,
    destructive: true,
  );
  if (!confirmed || !context.mounted) return null;
  if (!identical(container.read(databaseProvider), db)) {
    throw StateError('Database changed while confirming deletion');
  }
  final deleted = await delete(db);
  await container.read(tagsProvider.notifier).refresh();
  await container.read(gamesProvider.notifier).refresh();
  await persistEncryptedDbIfNeeded(container, database: db);
  return deleted;
}
