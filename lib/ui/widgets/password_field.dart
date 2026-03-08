/// A reusable password text-field with built-in visibility toggle.
///
/// Replaces 8–10 duplicate password `TextFormField` blocks across:
/// - encryption_dialogs.dart (5 fields)
/// - database_unlock_dialog.dart (1 field)
/// - backup_dialogs.dart (optional future usage)
library;

import 'package:flutter/material.dart';

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
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.labelText = 'Password',
    this.validator,
    this.autofocus = false,
    this.onFieldSubmitted,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String labelText;
  final FormFieldValidator<String>? validator;
  final bool autofocus;
  final ValueChanged<String>? onFieldSubmitted;
  final TextInputAction? textInputAction;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      autofocus: widget.autofocus,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onFieldSubmitted,
      decoration: InputDecoration(
        labelText: widget.labelText,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(
            _obscure ? Icons.visibility_off : Icons.visibility,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      validator: widget.validator,
    );
  }
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
}) {
  return (value) {
    if (value == null || value.isEmpty) return message;
    return null;
  };
}

/// Returns a validator that checks both presence and minimum length.
FormFieldValidator<String> requiredPasswordWithLength({
  int minLength = 4,
  String emptyMessage = 'Password is required',
  String? tooShortMessage,
}) {
  return (value) {
    if (value == null || value.isEmpty) return emptyMessage;
    if (value.length < minLength) {
      return tooShortMessage ??
          'Password must be at least $minLength characters';
    }
    return null;
  };
}

/// Returns a confirm-password validator that checks the value matches [match].
FormFieldValidator<String> confirmPassword(
  TextEditingController match, {
  String message = 'Passwords do not match',
}) {
  return (value) {
    if (value != match.text) return message;
    return null;
  };
}
