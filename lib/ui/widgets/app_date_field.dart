library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';

class AppDateField extends StatefulWidget {
  const AppDateField({
    super.key,
    required this.theme,
    required this.onTap,
    this.date,
    this.placeholder = 'Select date',
    this.enabled = true,
    this.maxWidth = kDeadlineSelectorWidth,
  });

  final AppThemeData theme;
  final DateTime? date;
  final VoidCallback? onTap;
  final String placeholder;
  final bool enabled;
  final double maxWidth;

  @override
  State<AppDateField> createState() => _AppDateFieldState();
}

class _AppDateFieldState extends State<AppDateField> {
  late final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _syncText();
  }

  @override
  void didUpdateWidget(covariant AppDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.date != widget.date ||
        oldWidget.placeholder != widget.placeholder) {
      _syncText();
    }
  }

  void _syncText() {
    _controller.text = widget.date == null
        ? ''
        : DateFormat('dd/MM/yyyy').format(widget.date!);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.7,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: TextField(
          controller: _controller,
          enabled: widget.enabled,
          readOnly: true,
          showCursor: false,
          enableInteractiveSelection: false,
          mouseCursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onTap: widget.enabled ? widget.onTap : null,
          style: TextStyle(
            color: widget.enabled
                ? widget.theme.textPrimary
                : widget.theme.textHint,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.placeholder,
            hintStyle: TextStyle(color: widget.theme.textHint),
            prefixIcon: Icon(
              Icons.calendar_today,
              color: widget.theme.textHint,
              size: 18,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 42,
              minHeight: 36,
            ),
            filled: true,
            fillColor: widget.theme.inputBackground,
            border: widget.theme.resolveInputBorder(),
            contentPadding: EdgeInsets.symmetric(
              horizontal: widget.theme.inputPaddingHorizontal,
              vertical: widget.theme.inputPaddingVertical,
            ),
          ),
        ),
      ),
    );
  }
}