import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A small corner dot that grows when on; inset so it clears the card corner.
class SettingsCardMiniDot extends StatelessWidget {
  const SettingsCardMiniDot({
    super.key,
    required this.theme,
    required this.value,
    required this.enabled,
    this.outlineColor,
    this.glow = true,
  });

  /// The corner it takes, padding included, which a card's content clears.
  static const double extent = _gap + _dot + _inset;

  /// From the card's top and right edges.
  static const double _inset = 10;

  /// Between the dot and the content beside or below it.
  static const double _gap = 4;
  static const double _dot = 18;

  final AppThemeData theme;
  final bool value;
  final bool enabled;

  /// A 2px ring drawn around the dot while it is on.
  final Color? outlineColor;

  /// An accent glow around the dot while it is on.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final lit = value && enabled;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gap, _inset, _inset, _gap),
      child: SizedBox.square(
        dimension: _dot,
        child: Center(
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            width: lit ? _dot : 16,
            height: lit ? _dot : 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Transparent while off, so the ring fades in with the dot.
              border: outlineColor == null
                  ? null
                  : Border.all(
                      color: lit
                          ? theme.secondary.withValues(alpha: 0.6)
                          : outlineColor!.withValues(alpha: 0),
                      width: 2,
                    ),
              color: lit
                  ? theme.accent
                  : Color.lerp(theme.background, theme.textSecondary, 0.25),
              boxShadow: lit && glow
                  ? [
                      BoxShadow(
                        color: theme.accent.withValues(alpha: 0.8),
                        blurRadius: 5,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
