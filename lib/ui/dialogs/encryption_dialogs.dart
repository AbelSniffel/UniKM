// Encryption-related dialogs for database security

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/encryption_manager.dart';
import '../../core/theme/app_theme.dart';
import 'database_unlock_dialog.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/notification_system.dart';
import '../widgets/password_field.dart';

/// Dialog to enable encryption with password setup.
///
/// The [title], [message], and [confirmLabel] parameters allow reuse for
/// related flows such as creating a password for a new encrypted database.
class EnableEncryptionDialog extends ConsumerStatefulWidget {
  const EnableEncryptionDialog({
    super.key,
    required this.theme,
    this.encryptionManager,
    this.title = 'Enable Encryption',
    this.message = 'Set a password to encrypt your database.',
    this.confirmLabel = 'Enable',
  });

  final AppThemeData theme;
  final EncryptionManager? encryptionManager;

  /// Title shown in the dialog header.
  final String title;

  /// Instructional message below the header.
  final String message;

  /// Label for the confirm button.
  final String confirmLabel;

  /// Shows the dialog for enabling encryption on an existing database.
  static Future<String?> show(
    BuildContext context,
    AppThemeData theme,
    EncryptionManager encryptionManager,
  ) async {
    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: true,
      builder: (context) => DialogInteractionScope(
        onDismiss: () => Navigator.of(context).pop(null),
        child: EnableEncryptionDialog(
          theme: theme,
          encryptionManager: encryptionManager,
        ),
      ),
    );
    return result;
  }

  /// Shows the dialog for creating a password on a newly created encrypted
  /// database. Returns the password or `null` when the user declines.
  static Future<String?> showForNewDatabase(
    BuildContext context,
    AppThemeData theme,
  ) async {
    return showDialog<String?>(
      context: context,
      barrierDismissible: true,
      builder: (context) => DialogInteractionScope(
        onDismiss: () => Navigator.of(context).pop(null),
        child: EnableEncryptionDialog(
          theme: theme,
          title: 'Create Password',
          message: 'Set a password for your new encrypted database.',
          confirmLabel: 'Create',
        ),
      ),
    );
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
    return DialogInteractionScope(
      onPrimaryAction: _isLoading ? null : _confirm,
      onDismiss: () => Navigator.of(context).pop(null),
      child: ThemedAlertDialog(
        theme: widget.theme,
        title: DialogHeader(
          icon: Icons.lock,
          title: widget.title,
          theme: widget.theme,
          iconColor: widget.theme.baseAccent,
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
                  message:
                      'WARNING: If you forget your password, your data cannot be recovered!',
                  textColor: Colors.orange.shade700,
                ),
                const SizedBox(height: kDialogSpacing),
                Text(widget.message, style: TextStyle(color: widget.theme.textSecondary)),
                const SizedBox(height: kDialogSpacing),
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
                const SizedBox(height: kDialogSpacing),
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
            confirmLabel: widget.confirmLabel,
            isLoading: _isLoading,
          ),
        ],
      ),
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
      barrierDismissible: true,
      builder: (context) => DialogInteractionScope(
        onDismiss: () => Navigator.of(context).pop(false),
        child: ChangePasswordDialog(
          theme: theme,
          encryptionManager: encryptionManager,
        ),
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
    return DialogInteractionScope(
      onPrimaryAction: _isLoading ? null : _changePassword,
      onDismiss: () => Navigator.of(context).pop(false),
      child: ThemedAlertDialog(
        theme: widget.theme,
        title: DialogHeader(
          icon: Icons.key,
          title: 'Change Password',
          theme: widget.theme,
          iconColor: widget.theme.baseAccent,
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
                  validator: requiredPassword(
                    message: 'Current password is required',
                  ),
                ),
                const SizedBox(height: kDialogSpacing),
                const Divider(),
                const SizedBox(height: kDialogSpacing),
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
      ),
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
      barrierDismissible: true,
      builder: (context) => DialogInteractionScope(
        onDismiss: () => Navigator.of(context).pop(null),
        child: DisableEncryptionDialog(
          theme: theme,
          encryptionManager: encryptionManager,
        ),
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
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (!_formKey.currentState!.validate()) return;
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
    return DialogInteractionScope(
      onPrimaryAction: _isLoading ? null : _confirm,
      onDismiss: () => Navigator.of(context).pop(null),
      child: ThemedAlertDialog(
        theme: widget.theme,
        title: DialogHeader(
          icon: Icons.lock_open,
          title: 'Disable Encryption',
          theme: widget.theme,
          iconColor: Colors.red,
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
                  message:
                      'WARNING: This will remove encryption from your database. '
                      'Your data will be stored in plain text.',
                  textColor: Colors.red.shade700,
                ),
                const SizedBox(height: kDialogSpacing),
                PasswordField(
                  controller: _passwordController,
                  labelText: 'Enter Password',
                  validator: requiredPassword(),
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
            confirmLabel: 'Disable',
            loadingLabel: 'Disabling...',
            isLoading: _isLoading,
            destructive: true,
          ),
        ],
      ),
    );
  }
}

/// Dialog to prompt for password when opening an encrypted database
class UnlockDatabaseDialog {
  const UnlockDatabaseDialog._();

  static Future<String?> show(BuildContext context, AppThemeData theme) {
    return DatabaseUnlockDialog.show(
      context,
      theme,
      title: 'Unlock Database',
      message: 'Your database is encrypted. Please enter your password to unlock it.',
      barrierDismissible: true,
    );
  }
}
