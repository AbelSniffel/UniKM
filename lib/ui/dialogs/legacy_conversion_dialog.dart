import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/services/legacy_db_converter.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/tinted_tiles.dart';

/// Reports legacy migration details without owning database initialization.
Future<void> showLegacyConversionDialog(
  BuildContext context, {
  required AppThemeData theme,
  required LegacyDbConversionResult conversion,
  required String dbPath,
}) async {
  if (!conversion.converted || !context.mounted) return;
  final actions = conversion.actions;
  await showAppDialog<void>(
    context: context,
    builder: (ctx) => ThemedAlertDialog(
      theme: theme,
      maxWidth: 560,
      title: DialogHeader(
        icon: Icons.upgrade,
        title: 'Legacy Database Converted',
        theme: theme,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          Text(
            'The imported games were adapted to the current schema.',
            style: TextStyle(color: theme.textSecondary),
          ),
          TintedOptionTile(
            theme: theme,
            icon: Icons.description_outlined,
            title: p.basename(dbPath),
            subtitle: 'Source file, left unchanged',
          ),
          if (actions.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                TintedHeading(
                  theme: theme,
                  title: 'Changes Applied',
                  trailing: '${actions.length}',
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 6,
                      children: [
                        for (final action in actions)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 8,
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: theme.accent,
                                size: 18,
                              ),
                              Expanded(
                                child: Text(
                                  action,
                                  style: TextStyle(color: theme.textPrimary),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
}
