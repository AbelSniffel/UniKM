/// A themed search text field matching the app's visual language.
///
/// Replaces 3 duplicate search TextField blocks in:
/// - home_page.dart
/// - tag_list.dart
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
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.theme,
    required this.onChanged,
    this.controller,
    this.focusNode,
    this.hintText = 'Search...',
    this.onCleared,
    this.contentPadding,
    this.backgroundColor,
    this.onSubmitted,
    this.prefixIcon,
  });

  final AppThemeData theme;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hintText;

  /// Called after the field is cleared. If null, only the controller
  /// is cleared and [onChanged] is called with `''`.
  final VoidCallback? onCleared;

  /// Override the content padding. Defaults to theme-appropriate value.
  final EdgeInsetsGeometry? contentPadding;

  /// Overrides the default background color used for the filled input.
  /// If null, falls back to [theme.inputBackground].
  final Color? backgroundColor;

  /// Called when the user submits the field from the keyboard.
  final ValueChanged<String>? onSubmitted;

  /// Optional leading icon override. Defaults to the standard search icon.
  final IconData? prefixIcon;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  static const _iconBox = BoxConstraints(minWidth: 38, minHeight: 36);
  late final TextEditingController _internalController;
  late bool _showClear;

  TextEditingController get _effectiveController =>
      widget.controller ?? _internalController;

  @override
  void initState() {
    super.initState();
    _internalController = TextEditingController();
    _showClear = _effectiveController.text.isNotEmpty;
    _effectiveController.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant AppSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _internalController).removeListener(
        _handleTextChanged,
      );
      _showClear = _effectiveController.text.isNotEmpty;
      _effectiveController.addListener(_handleTextChanged);
    }
  }

  @override
  void dispose() {
    _effectiveController.removeListener(_handleTextChanged);
    _internalController.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    final showClear = _effectiveController.text.isNotEmpty;
    // EditableText already listens for text, selection and composing changes.
    // Only the clear-button visibility needs to rebuild this decoration.
    if (mounted && showClear != _showClear) {
      setState(() => _showClear = showClear);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _effectiveController;
    return TextField(
      controller: controller,
      focusNode: widget.focusNode,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      style: TextStyle(color: widget.theme.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hintText,
        hintStyle: TextStyle(color: widget.theme.textHint),
        prefixIcon: Icon(
          widget.prefixIcon ?? Icons.search,
          color: widget.theme.textHint,
        ),
        prefixIconConstraints: _iconBox,
        suffixIconConstraints: _iconBox,
        suffixIcon: _showClear
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Clear search',
                    padding: EdgeInsets.zero,
                    constraints: _iconBox,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.clear, color: widget.theme.textHint),
                    onPressed: () {
                      controller.clear();
                      widget.onChanged('');
                      widget.onCleared?.call();
                    },
                  ),
                ],
              )
            : null,
        filled: true,
        fillColor: widget.backgroundColor,
        border: widget.theme.resolveInputBorder(),
        contentPadding:
            widget.contentPadding ??
            const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      ),
    );
  }
}
