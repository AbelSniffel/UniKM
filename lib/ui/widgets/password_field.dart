/// A reusable password text-field with built-in visibility toggle.
///
/// Replaces 8–10 duplicate password `TextFormField` blocks across:
/// - encryption_dialogs.dart (5 fields)
/// - database_unlock_dialog.dart (1 field)
/// - backup_dialogs.dart (optional future usage)
library;

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import 'field_end_buttons.dart';

/// A [TextFormField] with an obscure-text visibility toggle suffix icon.
///
/// Manages its own `_obscure` state internally so callers don't need a
/// separate `bool _obscurePassword` + `setState` boilerplate.
///
/// ```dart
/// PasswordField(
///   controller: _passwordController,
///   labelText: 'Password',
///   validator: (v) => v == null || v.isEmpty ? 'Required' : null,
/// )
/// ```
class const PasswordField({
  super.key,
  required final TextEditingController controller,
  final String labelText = 'Password',
  final FormFieldValidator<String>? validator,
  final bool autofocus = false,
  final ValueChanged<String>? onFieldSubmitted,
  final ValueChanged<String>? onChanged,
  final TextInputAction? textInputAction,

  /// Shown in the empty field once it has focus and the label has floated.
  final String? hintText,

  /// An error from outside the field, such as a rejected password, shown
  /// while [validator] finds none.
  final String? errorText,
}) extends StatefulWidget {
  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    obscureText: _obscure,
    autofocus: widget.autofocus,
    textInputAction: widget.textInputAction,
    onFieldSubmitted: widget.onFieldSubmitted,
    onChanged: widget.onChanged,
    decoration: InputDecoration(
      labelText: widget.labelText,
      hintText: widget.hintText,
      hintStyle: TextStyle(color: context.appTheme.textHint),
      errorText: widget.errorText,
      border: context.appTheme.resolveInputBorder(labelInside: true),
      suffixIconConstraints: const BoxConstraints(),
      suffixIcon: FieldEndButtons(
        children: [
          IconButton(
            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ],
      ),
    ),
    validator: widget.validator,
  );
}

// ---------------------------------------------------------------------------
// Common validators
// ---------------------------------------------------------------------------

/// Returns a simple "required" validator.
///
/// ```dart
/// PasswordField(
///   controller: ctrl,
///   validator: requiredPassword(),
/// )
/// ```
FormFieldValidator<String> requiredPassword({
  String message = 'Password is required',
}) => (value) {
  if (value == null || value.isEmpty) return message;
  return null;
};

/// Returns a validator that checks both presence and minimum length.
FormFieldValidator<String> requiredPasswordWithLength({
  int minLength = 4,
  String emptyMessage = 'Password is required',
  String? tooShortMessage,
}) => (value) {
  if (value == null || value.isEmpty) return emptyMessage;
  if (value.length < minLength) {
    return tooShortMessage ?? 'Password must be at least $minLength characters';
  }
  return null;
};

/// Returns a confirm-password validator that checks the value matches [match].
FormFieldValidator<String> confirmPassword(
  TextEditingController match, {
  String message = 'Passwords do not match',
}) => (value) {
  if (value != match.text) return message;
  return null;
};
