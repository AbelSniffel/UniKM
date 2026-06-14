library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// PairCodeDisplay
// ---------------------------------------------------------------------------

/// Read-only display of a 6-digit pairing code.
///
/// Numbers are arranged as two groups of three separated by an em-dash, each
/// digit sitting above a themed underline, matching the layout of
/// [PairCodeInput].
class PairCodeDisplay extends StatelessWidget {
  const PairCodeDisplay({
    super.key,
    required this.code,
    required this.theme,
  });

  /// The 6-digit code string to display. May be shorter during animation.
  final String code;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    final padded = code.padRight(6);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.border),
      ),
      child: Center(
        child: _PairCodeRow(
          chars: List.generate(6, (i) => padded[i] == ' ' ? null : padded[i]),
          activeIndex: null,
          theme: theme,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PairCodeInput
// ---------------------------------------------------------------------------

/// A 6-digit pairing-code entry widget styled to match [PairCodeDisplay].
///
/// - Six cells arranged as two groups of three separated by an em-dash.
/// - The active cursor position glows with the theme accent colour.
/// - A hidden [TextField] handles focus and system keyboard/IME input so
///   paste, accessibility, and key events all work normally.
class PairCodeInput extends StatefulWidget {
  const PairCodeInput({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.theme,
    this.error,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final AppThemeData theme;
  final String? error;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PairCodeInput> createState() => _PairCodeInputState();
}

class _PairCodeInputState extends State<PairCodeInput> {
  static const int _length = 6;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    widget.focusNode.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    widget.focusNode.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final text = widget.controller.text;
    final focused = widget.focusNode.hasFocus;
    final cursorPos = text.length.clamp(0, _length);

    return GestureDetector(
      onTap: widget.focusNode.requestFocus,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hidden TextField — owns focus and all keyboard/IME input.
          SizedBox(
            height: 0,
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(_length),
                ],
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
              ),
            ),
          ),
          // Visual cell row.
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: focused
                    ? theme.accent.withValues(alpha: 0.5)
                    : theme.border,
              ),
            ),
            child: Center(
              child: _PairCodeRow(
                chars: List.generate(
                  _length,
                  (i) => i < text.length ? text[i] : null,
                ),
                activeIndex: focused ? cursorPos : null,
                theme: theme,
              ),
            ),
          ),
          if (widget.error != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared internals
// ---------------------------------------------------------------------------

/// A row of six code cells split into two groups by an em-dash separator.
class _PairCodeRow extends StatelessWidget {
  const _PairCodeRow({
    required this.chars,
    required this.activeIndex,
    required this.theme,
  });

  /// Exactly 6 entries; null means the slot is empty.
  final List<String?> chars;

  /// Index of the active (glowing) cell, or null for display-only mode.
  final int? activeIndex;

  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    Widget cell(int i) => _PairCodeCell(
          char: chars[i],
          isActive: activeIndex == i,
          theme: theme,
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        cell(0),
        const SizedBox(width: 5),
        cell(1),
        const SizedBox(width: 5),
        cell(2),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '-',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        cell(3),
        const SizedBox(width: 5),
        cell(4),
        const SizedBox(width: 5),
        cell(5),
      ],
    );
  }
}

/// One digit cell: digit text above a coloured/glowing underline bar.
/// No background — only the underline carries the theme colour.
class _PairCodeCell extends StatelessWidget {
  const _PairCodeCell({
    required this.char,
    required this.isActive,
    required this.theme,
  });

  final String? char;
  final bool isActive;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    final accent = theme.accent;
    final underlineColor = isActive ? accent : theme.border;

    return SizedBox(
      width: 32,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Digit with fade+scale transition when value changes.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 120),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.75, end: 1.0).animate(anim),
                child: child,
              ),
            ),
            child: Text(
              char ?? '',
              key: ValueKey(char),
              style: TextStyle(
                color: theme.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Underline bar — glows accent when this slot is the cursor.
          Positioned(
            left: 2,
            right: 2,
            bottom: 4,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              height: 2,
              decoration: BoxDecoration(
                color: underlineColor,
                borderRadius: BorderRadius.circular(1),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.75),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
