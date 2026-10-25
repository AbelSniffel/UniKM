import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/app_constants.dart';
import '../../core/services/legacy_db_converter.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/dialog_helpers.dart';

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
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'The imported games were adapted to the current schema. Your source file was not changed.',
              style: TextStyle(color: theme.textPrimary),
            ),
            const SizedBox(height: kElementVSpacing),
            Text(
              'File: ${p.basename(dbPath)}',
              style: TextStyle(color: theme.textSecondary, fontSize: 12),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Changes applied:',
                style: TextStyle(
                  color: theme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: kElementVSpacing),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SizedBox(
                  width: double.infinity,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final action in actions)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '• $action',
                              style: TextStyle(color: theme.textPrimary),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
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
