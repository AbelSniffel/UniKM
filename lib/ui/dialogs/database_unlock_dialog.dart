/// Dialog prompting user to unlock an encrypted database.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/password_field.dart';

class StartupDatabaseUnlockResult {
  const StartupDatabaseUnlockResult._({
    this.password,
    this.selectedDatabasePath,
    this.cancelled = false,
  });

  const StartupDatabaseUnlockResult.unlock(String value)
    : this._(password: value);

  const StartupDatabaseUnlockResult.changeDatabase(String value)
    : this._(selectedDatabasePath: value);

  const StartupDatabaseUnlockResult.cancelled()
    : this._(cancelled: true);

  final String? password;
  final String? selectedDatabasePath;
  final bool cancelled;
}

class _StartupDatabaseSelection {
  const _StartupDatabaseSelection(this.path);

  final String path;
}

class DatabaseUnlockDialog extends StatefulWidget {
  const DatabaseUnlockDialog({
    super.key,
    required this.theme,
    this.title = 'Unlock Database',
    this.message =
        'This database is encrypted. Enter the password to continue.',
    this.currentDatabasePath,
    this.allowChangeDatabase = false,
  });

  final AppThemeData theme;
  final String title;
  final String message;
  final String? currentDatabasePath;
  final bool allowChangeDatabase;

  static Future<String?> show(
    BuildContext context,
    AppThemeData theme, {
    String title = 'Unlock Database',
    String message = 'This database is encrypted. Enter the password to continue.',
    bool barrierDismissible = false,
  }) {
    return showDialog<String?>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => DatabaseUnlockDialog(
        theme: theme,
        title: title,
        message: message,
      ),
    );
  }

  static Future<StartupDatabaseUnlockResult> showForStartup(
    BuildContext context,
    AppThemeData theme, {
    required String currentDatabasePath,
  }) async {
    final result = await showDialog<Object?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DatabaseUnlockDialog(
        theme: theme,
        currentDatabasePath: currentDatabasePath,
        allowChangeDatabase: true,
      ),
    );

    if (result is _StartupDatabaseSelection) {
      return StartupDatabaseUnlockResult.changeDatabase(result.path);
    }

    if (result is String) {
      return StartupDatabaseUnlockResult.unlock(result);
    }

    return const StartupDatabaseUnlockResult.cancelled();
  }

  @override
  State<DatabaseUnlockDialog> createState() => _DatabaseUnlockDialogState();
}

class _DatabaseUnlockDialogState extends State<DatabaseUnlockDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_passwordController.text);
  }

  Future<void> _changeDatabase() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Open UniKM Database',
      type: FileType.custom,
      allowedExtensions: const ['db', 'enc'],
      allowMultiple: false,
    );

    final selectedPath = result?.files.single.path;
    if (!mounted || selectedPath == null || selectedPath.isEmpty) {
      return;
    }

    Navigator.of(context).pop(_StartupDatabaseSelection(selectedPath));
  }

  @override
  Widget build(BuildContext context) {
    return ThemedAlertDialog(
      theme: widget.theme,
      title: DialogHeader(
        icon: Icons.lock,
        title: widget.title,
        theme: widget.theme,
      ),
      titleActions: widget.allowChangeDatabase &&
              widget.currentDatabasePath != null &&
              widget.currentDatabasePath!.isNotEmpty
          ? [
              Tooltip(
                message: 'Change database\n${widget.currentDatabasePath!}',
                child: IconButton(
                  onPressed: _changeDatabase,
                  icon: const Icon(Icons.storage),
                  tooltip: 'Change database',
                ),
              ),
            ]
          : null,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.message, style: TextStyle(color: widget.theme.textSecondary)),
            const SizedBox(height: kDialogSpacing),
            PasswordField(
              controller: _passwordController,
              labelText: 'Password',
              autofocus: true,
              onFieldSubmitted: (_) => _submit(),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Enter your password';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        DialogActionBar(
          theme: widget.theme,
          onCancel: () => Navigator.of(context).pop(null),
          onConfirm: _submit,
          confirmIcon: Icons.lock_open,
          confirmLabel: 'Unlock',
        ),
      ],
    );
  }
}
