// Encryption-related dialogs for database security

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/biometric_unlock.dart';
import '../../core/services/encryption_manager.dart';
import '../../core/theme/app_theme.dart';
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
    this.message,
    this.confirmLabel = 'Enable',
  });

  final AppThemeData theme;
  final EncryptionManager? encryptionManager;

  /// Title shown in the dialog header.
  final String title;

  /// Instructional message below the header.
  final String? message;

  /// Label for the confirm button.
  final String confirmLabel;

  static Future<String?> _show(
    BuildContext context,
    EnableEncryptionDialog dialog,
  ) => showAppDialog<String?>(
    context: context,
    builder: (context) => DialogInteractionScope(
      onDismiss: () => Navigator.of(context).pop(),
      child: dialog,
    ),
  );

  /// Shows the dialog for enabling encryption on an existing database.
  static Future<String?> show(
    BuildContext context,
    AppThemeData theme,
    EncryptionManager encryptionManager,
  ) => _show(
    context,
    EnableEncryptionDialog(theme: theme, encryptionManager: encryptionManager),
  );

  /// Shows the dialog for creating a password on a newly created encrypted
  /// database. Returns the password or `null` when the user declines.
  static Future<String?> showForNewDatabase(
    BuildContext context,
    AppThemeData theme,
  ) => _show(
    context,
    EnableEncryptionDialog(
      theme: theme,
      title: 'Create Password',
      message: 'Set a password for your new encrypted database.',
      confirmLabel: 'Create',
    ),
  );

  @override
  ConsumerState<EnableEncryptionDialog> createState() =>
      _EnableEncryptionDialogState();
}

class _EnableEncryptionDialogState
    extends ConsumerState<EnableEncryptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _encryptionInfoTooltipKey = GlobalKey<TooltipState>();

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // Return the password to the caller so it can perform the enable and
  // reopen the DB without prompting the user again.
  void _confirm() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_passwordController.text);
  }

  @override
  Widget build(BuildContext context) => DialogInteractionScope(
    onPrimaryAction: _confirm,
    onDismiss: () => Navigator.of(context).pop(),
    child: ThemedAlertDialog(
      theme: widget.theme,
      title: DialogHeader(
        icon: Icons.lock,
        title: widget.title,
        theme: widget.theme,
        iconColor: widget.theme.baseAccent,
      ),
      titleActions: [
        Tooltip(
          key: _encryptionInfoTooltipKey,
          message: 'Uses AES-256-GCM with PBKDF2 key derivation',
          child: IconButton(
            icon: Icon(Icons.info_outline, color: widget.theme.accent),
            onPressed: () =>
                _encryptionInfoTooltipKey.currentState?.ensureTooltipVisible(),
          ),
        ),
      ],
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.message != null) ...[
                Text(
                  widget.message!,
                  style: TextStyle(color: widget.theme.textSecondary),
                ),
                const SizedBox(height: kDialogSpacing),
              ],
              PasswordField(
                controller: _passwordController,
                validator: requiredPasswordWithLength(),
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _confirmController,
                labelText: 'Confirm Password',
                validator: confirmPassword(_passwordController),
              ),
              const SizedBox(height: kDialogSpacing),
              DialogBanner.warning(
                theme: widget.theme,
                message:
                    'WARNING: If you forget your password, your data cannot be recovered!',
              ),
            ],
          ),
        ),
      ),
      actions: [
        DialogActionBar(
          theme: widget.theme,
          onCancel: () => Navigator.of(context).pop(),
          onConfirm: _confirm,
          confirmIcon: Icons.lock,
          confirmLabel: widget.confirmLabel,
        ),
      ],
    ),
  );
}

/// Shared shell for a password-confirmed change: validates [fields], runs
/// [action] while blocking dismissal, then reports [successMessage] and
/// returns true, or shows [errorText] and stays open.
class _PasswordActionDialog extends StatefulWidget {
  const _PasswordActionDialog({
    required this.theme,
    required this.icon,
    required this.title,
    required this.fields,
    required this.action,
    required this.successMessage,
    required this.errorText,
    required this.confirmIcon,
    required this.confirmLabel,
    required this.loadingLabel,
    this.warning,
  });

  final AppThemeData theme;
  final IconData icon;
  final String title;
  final List<Widget> Function(VoidCallback submit) fields;
  final Future<void> Function() action;
  final String successMessage;
  final String Function(Object error) errorText;
  final IconData confirmIcon;
  final String confirmLabel;
  final String loadingLabel;

  /// Pinned above the buttons, outside the scrolling content.
  final String? warning;

  @override
  State<_PasswordActionDialog> createState() => _PasswordActionDialogState();
}

class _PasswordActionDialogState extends State<_PasswordActionDialog> {
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.action();
      if (!mounted) return;
      NotificationManager.instance.success(widget.successMessage);
      // Re-enable popping after the operation; the busy route blocks dismissals.
      setState(() => _busy = false);
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = widget.errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return PopScope(
      canPop: !_busy,
      child: DialogInteractionScope(
        enableEscapeDismiss: !_busy,
        enableEnterToPrimary: !_busy,
        onPrimaryAction: _submit,
        onDismiss: () => Navigator.of(context).pop(false),
        child: ThemedAlertDialog(
          theme: theme,
          maxWidth: 520,
          maxHeight: 600,
          showCloseButton: !_busy,
          title: DialogHeader(
            icon: widget.icon,
            title: widget.title,
            theme: theme,
          ),
          contentChildren: [
            ExcludeFocus(
              excluding: _busy,
              child: AbsorbPointer(
                absorbing: _busy,
                child: Form(
                  key: _form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: kDialogSpacing,
                    children: [
                      ...widget.fields(_submit),
                      if (_error != null)
                        Text(_error!, style: TextStyle(color: theme.secondary)),
                    ],
                  ),
                ),
              ),
            ),
          ],
          actions: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: kDialogSpacing,
              children: [
                if (widget.warning case final warning?)
                  DialogBanner.warning(theme: theme, message: warning),
                DialogActionBar(
                  theme: theme,
                  onCancel: () => Navigator.of(context).pop(false),
                  onConfirm: _submit,
                  confirmIcon: widget.confirmIcon,
                  confirmLabel: widget.confirmLabel,
                  loadingLabel: widget.loadingLabel,
                  isLoading: _busy,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Text controllers disposed with the dialog.
mixin _OwnsControllers<T extends StatefulWidget> on State<T> {
  final controllers = <TextEditingController>[];

  TextEditingController controller() {
    final controller = TextEditingController();
    controllers.add(controller);
    return controller;
  }

  @override
  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }
}

TextStyle _hintStyle(AppThemeData theme) =>
    TextStyle(color: theme.textSecondary, fontSize: 13);

/// Asks for the database password before pairing biometric unlock, which
/// then shows the system prompt. Returns whether the pairing was saved.
class BiometricPairDialog extends StatefulWidget {
  const BiometricPairDialog({
    super.key,
    required this.theme,
    required this.onPair,
  });

  final AppThemeData theme;
  final Future<void> Function(String password) onPair;

  static Future<bool> show(
    BuildContext context,
    AppThemeData theme,
    Future<void> Function(String password) onPair,
  ) async =>
      await showAppDialog<bool>(
        context: context,
        builder: (_) => BiometricPairDialog(theme: theme, onPair: onPair),
      ) ??
      false;

  @override
  State<BiometricPairDialog> createState() => _BiometricPairDialogState();
}

class _BiometricPairDialogState extends State<BiometricPairDialog>
    with _OwnsControllers {
  late final _password = controller();

  @override
  Widget build(BuildContext context) {
    final label = BiometricUnlock.label;
    return _PasswordActionDialog(
      theme: widget.theme,
      icon: Icons.fingerprint,
      title: '$label Unlock',
      action: () => widget.onPair(_password.text),
      successMessage: '$label unlock turned on for this database',
      errorText: (error) => error is InvalidPasswordException
          ? 'Incorrect password'
          : '$label was not confirmed, so nothing changed. Try again.',
      confirmIcon: Icons.fingerprint,
      confirmLabel: 'Turn On',
      loadingLabel: 'Confirming...',
      fields: (submit) => [
        Text(
          'Unlock this database with $label instead of its password. Enter '
          'the password once, then confirm with $label. Other databases are '
          'paired separately.',
          style: _hintStyle(widget.theme),
        ),
        PasswordField(
          controller: _password,
          labelText: 'Database Password',
          validator: requiredPassword(),
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => submit(),
        ),
      ],
    );
  }
}

/// Confirms the password, then removes encryption from the database.
/// Returns whether encryption was removed.
class DisableEncryptionDialog extends StatefulWidget {
  const DisableEncryptionDialog({
    super.key,
    required this.theme,
    required this.onDisable,
  });

  final AppThemeData theme;
  final Future<void> Function(String password) onDisable;

  static Future<bool> show(
    BuildContext context,
    AppThemeData theme,
    Future<void> Function(String password) onDisable,
  ) async =>
      await showAppDialog<bool>(
        context: context,
        builder: (_) =>
            DisableEncryptionDialog(theme: theme, onDisable: onDisable),
      ) ??
      false;

  @override
  State<DisableEncryptionDialog> createState() =>
      _DisableEncryptionDialogState();
}

class _DisableEncryptionDialogState extends State<DisableEncryptionDialog>
    with _OwnsControllers {
  late final _password = controller();

  @override
  Widget build(BuildContext context) => _PasswordActionDialog(
    theme: widget.theme,
    icon: Icons.lock_open,
    title: 'Disable Encryption',
    action: () => widget.onDisable(_password.text),
    successMessage: 'Database encryption disabled',
    errorText: (error) => error is InvalidPasswordException
        ? 'Incorrect password'
        : 'Failed to disable encryption: $error',
    confirmIcon: Icons.lock_open,
    confirmLabel: 'Disable',
    loadingLabel: 'Disabling...',
    warning:
        'Your database will be stored in plain text without password '
        'protection.',
    fields: (submit) => [
      Text(
        'Confirm your password to remove encryption.',
        style: _hintStyle(widget.theme),
      ),
      PasswordField(
        controller: _password,
        labelText: 'Enter Password',
        validator: requiredPassword(),
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => submit(),
      ),
    ],
  );
}

/// Changes the password of an encrypted database. Returns whether it changed.
class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({
    super.key,
    required this.theme,
    required this.onChangePassword,
  });

  final AppThemeData theme;
  final Future<void> Function(String currentPassword, String newPassword)
  onChangePassword;

  static Future<bool> show(
    BuildContext context,
    AppThemeData theme,
    Future<void> Function(String currentPassword, String newPassword)
    onChangePassword,
  ) async =>
      await showAppDialog<bool>(
        context: context,
        builder: (_) => ChangePasswordDialog(
          theme: theme,
          onChangePassword: onChangePassword,
        ),
      ) ??
      false;

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog>
    with _OwnsControllers {
  late final _current = controller();
  late final _new = controller();
  late final _confirm = controller();

  @override
  Widget build(BuildContext context) => _PasswordActionDialog(
    theme: widget.theme,
    icon: Icons.key,
    title: 'Change Database Password',
    action: () => widget.onChangePassword(_current.text, _new.text),
    successMessage: 'Password changed successfully',
    errorText: (error) => error is InvalidPasswordException
        ? 'Current password is incorrect'
        : 'Failed to change password: $error',
    confirmIcon: Icons.key,
    confirmLabel: 'Change Password',
    loadingLabel: 'Changing...',
    fields: (submit) => [
      PasswordField(
        controller: _current,
        labelText: 'Current Password',
        textInputAction: TextInputAction.next,
        validator: requiredPassword(message: 'Current password is required'),
      ),
      Divider(height: 37 - 2 * kDialogSpacing, color: widget.theme.border),
      PasswordField(
        controller: _new,
        labelText: 'New Password',
        textInputAction: TextInputAction.next,
        validator: (value) =>
            requiredPasswordWithLength(
              emptyMessage: 'New password is required',
            )(value) ??
            (value == _current.text ? 'New password must be different' : null),
      ),
      PasswordField(
        controller: _confirm,
        labelText: 'Confirm New Password',
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => submit(),
        validator: confirmPassword(_new),
      ),
    ],
  );
}
