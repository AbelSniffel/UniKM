// Encryption-related dialogs for database security

import 'package:flutter/material.dart';
import '../widgets/app_tab_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
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

  /// Shows the dialog for enabling encryption on an existing database.
  static Future<String?> show(
    BuildContext context,
    AppThemeData theme,
    EncryptionManager encryptionManager,
  ) async {
    final result = await showAppDialog<String?>(
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
    return showAppDialog<String?>(
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
  final _encryptionInfoTooltipKey = GlobalKey<TooltipState>();
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
  Widget build(BuildContext context) => DialogInteractionScope(
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

/// One window for managing an encrypted database, with tab-specific actions.
class EncryptionManagementDialog extends StatefulWidget {
  const EncryptionManagementDialog({
    super.key,
    required this.theme,
    required this.onDisable,
    required this.onChangePassword,
    this.initialTab = 0,
  });

  final AppThemeData theme;
  final int initialTab;
  final Future<void> Function(String password) onDisable;
  final Future<void> Function(String currentPassword, String newPassword)
  onChangePassword;

  static Future<bool> show(
    BuildContext context,
    AppThemeData theme, {
    required Future<void> Function(String password) onDisable,
    required Future<void> Function(String currentPassword, String newPassword)
    onChangePassword,
  }) async =>
      await showAppDialog<bool>(
        context: context,
        builder: (_) => EncryptionManagementDialog(
          theme: theme,
          onDisable: onDisable,
          onChangePassword: onChangePassword,
        ),
      ) ??
      false;

  @override
  State<EncryptionManagementDialog> createState() =>
      _EncryptionManagementDialogState();
}

class _EncryptionManagementDialogState extends State<EncryptionManagementDialog>
    with SingleTickerProviderStateMixin {
  final _disableForm = GlobalKey<FormState>();
  final _changeForm = GlobalKey<FormState>();
  final _disablePassword = TextEditingController();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  late final TabController _tabs;
  int _selectedTab = 0;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    _tabs = TabController(
      length: 2,
      initialIndex: widget.initialTab,
      vsync: this,
      animationDuration: kTabTransition,
    )..addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_selectedTab == _tabs.index) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedTab = _tabs.index;
      _error = null;
    });
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _disablePassword.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final disabling = _selectedTab == 0;
    final form = disabling ? _disableForm : _changeForm;
    if (!form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (disabling) {
        await widget.onDisable(_disablePassword.text);
      } else {
        await widget.onChangePassword(_currentPassword.text, _newPassword.text);
      }
      if (!mounted) return;
      NotificationManager.instance.success(
        disabling
            ? 'Database encryption disabled'
            : 'Password changed successfully',
      );
      // Re-enable popping after the operation; the busy route blocks dismissals.
      setState(() => _busy = false);
      Navigator.of(context).pop(true);
    } on InvalidPasswordException {
      if (mounted) {
        setState(
          () => _error = disabling
              ? 'Incorrect password'
              : 'Current password is incorrect',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = disabling
              ? 'Failed to disable encryption: $error'
              : 'Failed to change password: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _disableContent() => Form(
    key: _disableForm,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Confirm your password to remove encryption.',
          style: TextStyle(color: widget.theme.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        PasswordField(
          controller: _disablePassword,
          labelText: 'Enter Password',
          validator: requiredPassword(),
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
        ),
      ],
    ),
  );

  Widget _changeContent() => Form(
    key: _changeForm,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PasswordField(
          controller: _currentPassword,
          labelText: 'Current Password',
          textInputAction: TextInputAction.next,
          validator: requiredPassword(message: 'Current password is required'),
        ),
        Divider(height: 37, color: widget.theme.border),
        PasswordField(
          controller: _newPassword,
          labelText: 'New Password',
          textInputAction: TextInputAction.next,
          validator: (value) {
            final requiredError = requiredPasswordWithLength(
              emptyMessage: 'New password is required',
            )(value);
            if (requiredError != null) return requiredError;
            if (value == _currentPassword.text) {
              return 'New password must be different';
            }
            return null;
          },
        ),
        const SizedBox(height: kDialogSpacing),
        PasswordField(
          controller: _confirmPassword,
          labelText: 'Confirm New Password',
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          validator: confirmPassword(_newPassword),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final disabling = _selectedTab == 0;
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
            icon: Icons.lock,
            title: disabling
                ? 'Disable Encryption'
                : 'Change Database Password',
            theme: theme,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IgnorePointer(
                ignoring: _busy,
                child: AppTabBar(
                  theme: theme,
                  controller: _tabs,
                  tabs: const [AppTab('Disable'), AppTab('Change Password')],
                ),
              ),
              const SizedBox(height: kDialogSpacing),
              ExcludeFocus(
                excluding: _busy,
                child: AbsorbPointer(
                  absorbing: _busy,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppTabTransition(
                        index: _selectedTab,
                        child: disabling ? _disableContent() : _changeContent(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: kDialogSpacing),
                        Text(_error!, style: TextStyle(color: theme.secondary)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (disabling) ...[
                  DialogBanner.warning(
                    theme: theme,
                    message:
                        'Your database will be stored in plain text '
                        'without password protection.',
                  ),
                  const SizedBox(height: kDialogSpacing),
                ],
                DialogActionBar(
                  theme: theme,
                  onCancel: () => Navigator.of(context).pop(false),
                  onConfirm: _submit,
                  confirmIcon: disabling ? Icons.lock_open : Icons.key,
                  confirmLabel: disabling ? 'Disable' : 'Change Password',
                  loadingLabel: disabling ? 'Disabling...' : 'Changing...',
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
