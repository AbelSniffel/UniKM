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
      padding: const EdgeInsets.all(8),
      child: SizedBox.square(
        dimension: 18,
        child: Center(
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            width: lit ? 18 : 16,
            height: lit ? 18 : 16,
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
