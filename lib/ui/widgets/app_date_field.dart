library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';

class AppDateField extends StatefulWidget {
  const AppDateField({
    super.key,
    required this.theme,
    required this.onTap,
    this.date,
    this.placeholder = 'Select date',
    this.enabled = true,
    this.maxWidth = 160,
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
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final hasDate = widget.date != null;
    final textColor = widget.enabled ? widget.theme.textPrimary : widget.theme.textHint;
    final iconColor = widget.enabled ? widget.theme.textHint : widget.theme.textHint;

    final borderColor = widget.enabled && _isPressed
        ? widget.theme.inputFocusedBorder
        : widget.theme.border;

    final bgColor = widget.enabled && _isHovered
        ? Color.alphaBlend(
            widget.theme.inputFocusedBorder.withValues(alpha: 0.07),
            widget.theme.inputBackground,
          )
        : widget.theme.inputBackground;

    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.7,
      child: MouseRegion(
        onEnter: widget.enabled ? (_) => setState(() => _isHovered = true) : null,
        onExit: widget.enabled ? (_) => setState(() {
          _isHovered = false;
          _isPressed = false;
        }) : null,
        child: GestureDetector(
          onTapDown: widget.enabled ? (_) => setState(() => _isPressed = true) : null,
          onTapUp: widget.enabled ? (_) => setState(() => _isPressed = false) : null,
          onTapCancel: widget.enabled ? () => setState(() => _isPressed = false) : null,
          onTap: widget.enabled ? widget.onTap : null,
          child: Container(
            constraints: BoxConstraints(maxWidth: widget.maxWidth),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today, color: iconColor, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    hasDate ? DateFormat('dd/MM/yyyy').format(widget.date!) : widget.placeholder,
                    style: TextStyle(color: textColor, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}