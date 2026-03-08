/// Dialog prompting user to unlock an encrypted database.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../widgets/dialog_helpers.dart';

class DatabaseUnlockDialog extends StatefulWidget {
  const DatabaseUnlockDialog({
    super.key,
    required this.theme,
    this.title = 'Unlock Database',
    this.message = 'This database is encrypted. Enter the password to continue.',
  });

  final AppThemeData theme;
  final String title;
  final String message;

  static Future<String?> show(BuildContext context, AppThemeData theme) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DatabaseUnlockDialog(theme: theme),
    );
  }

  @override
  State<DatabaseUnlockDialog> createState() => _DatabaseUnlockDialogState();
}

class _DatabaseUnlockDialogState extends State<DatabaseUnlockDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_passwordController.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: widget.theme.surface,
      title: DialogHeader(
        icon: Icons.lock,
        title: widget.title,
        theme: widget.theme,
        spacing: 10,
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.message, style: TextStyle(color: widget.theme.textSecondary)),
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscure,
              autofocus: true,
              style: TextStyle(color: widget.theme.textPrimary),
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                labelStyle: TextStyle(color: widget.theme.textSecondary),
                filled: true,
                fillColor: widget.theme.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
                  borderSide: BorderSide(color: widget.theme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
                  borderSide: BorderSide(color: widget.theme.border),
                ),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show' : 'Hide',
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
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
          cancelLabel: 'Exit',
          onConfirm: _submit,
          confirmIcon: Icons.lock_open,
          confirmLabel: 'Unlock',
        ),
      ],
    );
  }
}
