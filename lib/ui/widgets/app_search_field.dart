/// A themed search text field matching the app's visual language.
///
/// Replaces 3 duplicate search TextField blocks in:
/// - home_page.dart
/// - flow_tag_selector.dart
/// - settings_page.dart
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A themed search [TextField] with prefix search icon, optional clear button,
/// and rounded border using [AppThemeData] colours.
///
/// ```dart
/// AppSearchField(
///   theme: theme,
///   hintText: 'Search by title or key...',
///   controller: searchController,
///   onChanged: (value) => ref.read(provider.notifier).setSearchQuery(value),
/// )
/// ```
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.theme,
    required this.onChanged,
    this.controller,
    this.focusNode,
    this.hintText = 'Search...',
    this.showClearButton = true,
    this.onCleared,
    this.contentPadding,
  });

  final AppThemeData theme;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hintText;

  /// Whether to show a clear ✕ button when the field is not empty.
  /// Requires [controller] to be provided to detect non-empty state.
  final bool showClearButton;

  /// Called after the field is cleared. If null, only the controller
  /// is cleared and [onChanged] is called with `''`.
  final VoidCallback? onCleared;

  /// Override the content padding. Defaults to theme-appropriate value.
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final showClear =
        showClearButton && controller != null && controller!.text.isNotEmpty;

    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      style: TextStyle(color: theme.textPrimary),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: theme.textHint),
        prefixIcon: Icon(Icons.search, color: theme.textHint),
        suffixIcon: showClear
            ? IconButton(
                icon: Icon(Icons.clear, color: theme.textHint),
                onPressed: () {
                  controller!.clear();
                  onChanged('');
                  onCleared?.call();
                },
              )
            : null,
        filled: true,
        fillColor: theme.inputBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(theme.cornerRadius),
          borderSide: BorderSide(color: theme.border),
        ),
        contentPadding: contentPadding,
      ),
    );
  }
}
