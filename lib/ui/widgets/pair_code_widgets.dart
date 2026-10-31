library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// PairCodeDisplay
// ---------------------------------------------------------------------------

/// Read-only display of a 6-digit pairing code.
///
/// Numbers are arranged as two groups of three separated by a dash, each
/// digit sitting above a themed underline.
class PairCodeDisplay extends StatelessWidget {
  const PairCodeDisplay({super.key, required this.code, required this.theme});

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
          theme: theme,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared internals
// ---------------------------------------------------------------------------

/// A row of six code cells split into two groups by an em-dash separator.
class _PairCodeRow extends StatelessWidget {
  const _PairCodeRow({required this.chars, required this.theme});

  /// Exactly 6 entries; null means the slot is empty.
  final List<String?> chars;

  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    Widget cell(int i) => _PairCodeCell(char: chars[i], theme: theme);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 6; i++) ...[
          if (i == 3) ...[
            const SizedBox(width: 10),
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                '-',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 10),
          ] else if (i > 0)
            const SizedBox(width: 5),
          cell(i),
        ],
      ],
    );
  }
}

/// One digit cell: digit text above an underline bar.
/// No background — only the underline carries the theme colour.
class _PairCodeCell extends StatelessWidget {
  const _PairCodeCell({required this.char, required this.theme});

  final String? char;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
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
          Positioned(
            left: 2,
            right: 2,
            bottom: 4,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: theme.border,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
