/// A themed search text field matching the app's visual language.
library;

import 'package:material_ui/material_ui.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import 'field_end_buttons.dart';
import 'horizontal_fold.dart';

/// A themed search [TextField] with prefix search icon, optional clear button,
/// and rounded border using [AppThemeData] colours.
class const AppSearchField({
  super.key,
  required final ValueChanged<String> onChanged,
  final TextEditingController? controller,
  final FocusNode? focusNode,
  final String hintText = 'Search...',

  /// Called after the field is cleared. If null, only the controller
  /// is cleared and [onChanged] is called with `''`.
  final VoidCallback? onCleared,

  /// Called when the user submits the field from the keyboard.
  final ValueChanged<String>? onSubmitted,

  /// Optional leading icon override. Defaults to the standard search icon.
  final IconData? prefixIcon,

  /// Icon buttons at the field's end, after the clear button; wrap one that
  /// comes and goes in a [HorizontalFold].
  final List<Widget> actions = const [],
}) extends StatefulWidget {
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
    final theme = context.appTheme;
    final controller = _effectiveController;
    return TextField(
      controller: controller,
      focusNode: widget.focusNode,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      style: TextStyle(color: theme.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        // One height on every platform, with or without the clear button.
        constraints: const BoxConstraints.tightFor(height: kElementHeight),
        hintText: widget.hintText,
        hintStyle: TextStyle(color: theme.textHint),
        prefixIcon: Icon(
          widget.prefixIcon ?? Icons.search,
          color: theme.textHint,
        ),
        prefixIconConstraints: _iconBox,
        // The end buttons size themselves, so one folding away takes no room.
        suffixIconConstraints: const BoxConstraints(minHeight: 36),
        // The clear button folds in and out with the text; actions fold
        // themselves.
        suffixIcon: FieldEndButtons(
          height: kElementHeight,
          children: [
            HorizontalFold(
              child: !_showClear
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.clear, color: theme.textHint),
                      onPressed: () {
                        controller.clear();
                        widget.onChanged('');
                        widget.onCleared?.call();
                      },
                    ),
            ),
            ...widget.actions,
          ],
        ),
        filled: true,
        border: theme.resolveInputBorder(),
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      ),
    );
  }
}
