// Encryption-related dialogs for database security

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/encryption_manager.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/notification_system.dart';
import '../widgets/password_field.dart';

/// Dialog to enable encryption with password setup
class EnableEncryptionDialog extends ConsumerStatefulWidget {
  const EnableEncryptionDialog({
    super.key,
    required this.theme,
    required this.encryptionManager,
  });

  final AppThemeData theme;
  final EncryptionManager encryptionManager;

  static Future<String?> show(
    BuildContext context,
    AppThemeData theme,
    EncryptionManager encryptionManager,
  ) async {
    // Returns the entered password when the user confirms, or `null` when
    // cancelled. The caller is responsible for performing the actual
    // `encryptionManager.enable(password)` and reopening the database.
    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => EnableEncryptionDialog(
        theme: theme,
        encryptionManager: encryptionManager,
      ),
    );
    return result;
  }

  @override
  ConsumerState<EnableEncryptionDialog> createState() =>
      _EnableEncryptionDialogState();
}

class _EnableEncryptionDialogState
    extends ConsumerState<EnableEncryptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (!_formKey.currentState!.validate()) return;

    // Return the password to the caller so it can perform the enable and
    // reopen the DB without prompting the user again.
    final pwd = _passwordController.text;
    if (!mounted) return;
    Navigator.of(context).pop(pwd);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: widget.theme.surface,
      title: DialogHeader(
        icon: Icons.lock,
        title: 'Enable Encryption',
        theme: widget.theme,
        iconColor: widget.theme.baseAccent,
        spacing: 8,
      ),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DialogBanner.caution(
                theme: widget.theme,
                message: 'WARNING: If you forget your password, your data cannot be recovered!',
                textColor: Colors.orange.shade700,
              ),
              const SizedBox(height: 16),
              Text(
                'Create a strong password to encrypt your database:',
                style: TextStyle(color: widget.theme.textPrimary),
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _passwordController,
                labelText: 'Password',
                validator: requiredPasswordWithLength(),
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _confirmController,
                labelText: 'Confirm Password',
                validator: confirmPassword(_passwordController),
              ),
              const SizedBox(height: 16),
              DialogBanner.info(
                theme: widget.theme,
                message: 'Uses AES-256-GCM with PBKDF2 key derivation',
              ),
            ],
          ),
        ),
      ),
      actions: [
        DialogActionBar(
          theme: widget.theme,
          onCancel: () => Navigator.of(context).pop(null),
          onConfirm: _isLoading ? null : _confirm,
          confirmIcon: Icons.lock,
          confirmLabel: 'Enable Encryption',
          isLoading: _isLoading,
        ),
      ],
    );
  }
}

/// Dialog to change encryption password
class ChangePasswordDialog extends ConsumerStatefulWidget {
  const ChangePasswordDialog({
    super.key,
    required this.theme,
    required this.encryptionManager,
  });

  final AppThemeData theme;
  final EncryptionManager encryptionManager;

  static Future<bool> show(
    BuildContext context,
    AppThemeData theme,
    EncryptionManager encryptionManager,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ChangePasswordDialog(
        theme: theme,
        encryptionManager: encryptionManager,
      ),
    );
    return result ?? false;
  }

  @override
  ConsumerState<ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await widget.encryptionManager.changePassword(
        _currentController.text,
        _newController.text,
      );
      
      if (mounted) {
        NotificationManager.instance.success('Password changed successfully');
        Navigator.of(context).pop(true);
      }
    } on InvalidPasswordException {
      NotificationManager.instance.error('Current password is incorrect');
      setState(() => _isLoading = false);
    } catch (e) {
      NotificationManager.instance.error('Failed to change password: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: widget.theme.surface,
      title: DialogHeader(
        icon: Icons.key,
        title: 'Change Password',
        theme: widget.theme,
        iconColor: widget.theme.baseAccent,
        spacing: 8,
      ),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PasswordField(
                controller: _currentController,
                labelText: 'Current Password',
                validator: requiredPassword(message: 'Current password is required'),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              PasswordField(
                controller: _newController,
                labelText: 'New Password',
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'New password is required';
                  }
                  if (value.length < 4) {
                    return 'Password must be at least 4 characters';
                  }
                  if (value == _currentController.text) {
                    return 'New password must be different';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _confirmController,
                labelText: 'Confirm New Password',
                validator: confirmPassword(_newController),
              ),
            ],
          ),
        ),
      ),
      actions: [
        DialogActionBar(
          theme: widget.theme,
          onCancel: () => Navigator.of(context).pop(false),
          onConfirm: _changePassword,
          confirmIcon: Icons.key,
          confirmLabel: 'Change Password',
          loadingLabel: 'Changing...',
          isLoading: _isLoading,
        ),
      ],
    );
  }
}

/// Dialog to disable encryption (requires password confirmation)
class DisableEncryptionDialog extends ConsumerStatefulWidget {
  const DisableEncryptionDialog({
    super.key,
    required this.theme,
    required this.encryptionManager,
  });

  final AppThemeData theme;
  final EncryptionManager encryptionManager;

  static Future<String?> show(
    BuildContext context,
    AppThemeData theme,
    EncryptionManager encryptionManager,
  ) async {
    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => DisableEncryptionDialog(
        theme: theme,
        encryptionManager: encryptionManager,
      ),
    );
    return result;
  }

  @override
  ConsumerState<DisableEncryptionDialog> createState() =>
      _DisableEncryptionDialogState();
}

class _DisableEncryptionDialogState
    extends ConsumerState<DisableEncryptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  bool _isLoading = false; // now mutable so we can show progress
  bool _confirmed = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (!_formKey.currentState!.validate() || !_confirmed) return;
    final pwd = _passwordController.text;

    // validate password before closing
    setState(() => _isLoading = true);
    try {
      // attempt a quick decrypt to verify the password
      await widget.encryptionManager.decrypt(pwd);
      if (!mounted) return;
      Navigator.of(context).pop(pwd);
    } on InvalidPasswordException catch (_) {
      NotificationManager.instance.error('Incorrect password');
    } catch (e) {
      NotificationManager.instance.error('Failed to verify password: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: widget.theme.surface,
      title: DialogHeader(
        icon: Icons.lock_open,
        title: 'Disable Encryption',
        theme: widget.theme,
        iconColor: Colors.red,
        spacing: 8,
      ),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DialogBanner.danger(
                theme: widget.theme,
                message: 'WARNING: This will remove encryption from your database. '
                    'Your data will be stored in plain text.',
                textColor: Colors.red.shade700,
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _passwordController,
                labelText: 'Enter Password',
                validator: requiredPassword(),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _confirmed,
                onChanged: (value) => setState(() => _confirmed = value ?? false),
                title: Text(
                  'I understand that my data will no longer be encrypted',
                  style: TextStyle(
                    color: widget.theme.textPrimary,
                    fontSize: 13,
                  ),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
      actions: [
        DialogActionBar(
          theme: widget.theme,
          onCancel: () => Navigator.of(context).pop(null),
          onConfirm: _confirm,
          confirmIcon: Icons.lock_open,
          confirmLabel: 'Disable Encryption',
          loadingLabel: 'Disabling...',
          isLoading: _isLoading,
          // only allow interaction when user has confirmed and we're not loading
          isEnabled: _confirmed && !_isLoading,
          destructive: true,
        ),
      ],
    );
  }
}

/// Dialog to prompt for password when opening an encrypted database
class UnlockDatabaseDialog extends StatefulWidget {
  const UnlockDatabaseDialog({
    super.key,
    required this.theme,
  });

  final AppThemeData theme;

  static Future<String?> show(BuildContext context, AppThemeData theme) async {
    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => UnlockDatabaseDialog(theme: theme),
    );
  }

  @override
  State<UnlockDatabaseDialog> createState() => _UnlockDatabaseDialogState();
}

class _UnlockDatabaseDialogState extends State<UnlockDatabaseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _unlock() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_passwordController.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: widget.theme.surface,
      title: DialogHeader(
        icon: Icons.lock,
        title: 'Unlock Database',
        theme: widget.theme,
        iconColor: widget.theme.baseAccent,
        spacing: 8,
      ),
      content: SizedBox(
        width: 350,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your database is encrypted. Please enter your password to unlock it.',
                style: TextStyle(color: widget.theme.textPrimary),
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _passwordController,
                autofocus: true,
                validator: requiredPassword(),
                onFieldSubmitted: (_) => _unlock(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        DialogActionBar(
          theme: widget.theme,
          onCancel: () => Navigator.of(context).pop(null),
          onConfirm: _unlock,
          confirmIcon: Icons.lock_open,
          confirmLabel: 'Unlock',
        ),
      ],
    );
  }
}
