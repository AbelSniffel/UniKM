import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';

/// A small corner dot that lights up when on; inset so it clears the card
/// corner. As a [bar], it runs down the card's right edge instead. Either
/// keeps its size, only its colour and glow change.
class const SettingsCardMiniDot({
  super.key,
  required final bool value,
  required final bool enabled,

  /// A 2px ring drawn around the dot while it is on.
  final Color? outlineColor,

  /// An accent glow around the dot while it is on.
  final bool glow = true,

  /// A bar the card's height, rounded to curve with the card's corners, for
  /// the settings toggle cards.
  final bool bar = false,
}) extends StatelessWidget {
  /// The width a [bar] takes, padding included, which a card's content clears.
  static const double barExtent = _gap + _bar + _inset;

  /// From the card's edges.
  static const double _inset = 10;

  /// Between the dot and the content beside or below it.
  static const double _gap = 4;
  static const double _dot = 18;
  static const double _bar = 12;

  /// An unlit indicator's colour, which the slim toggles' bars share.
  static Color idleColor(AppThemeData theme) =>
      Color.lerp(theme.background, theme.textSecondary, 0.25)!;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final lit = value && enabled;
    return Padding(
      padding: EdgeInsets.fromLTRB(_gap, _inset, _inset, bar ? _inset : _gap),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        // A bar fills the card's height.
        width: bar ? _bar : _dot,
        height: bar ? null : _dot,
        decoration: BoxDecoration(
          shape: bar ? BoxShape.rectangle : BoxShape.circle,
          // A bar's corners curve with the card's, its inset out.
          borderRadius: bar
              ? BorderRadius.circular(theme.insetRadius(_inset))
              : null,
          // Transparent while off, so the ring fades in with the dot.
          border: outlineColor == null
              ? null
              : Border.all(
                  color: lit
                      ? theme.secondary.withValues(alpha: 0.6)
                      : outlineColor!.withValues(alpha: 0),
                  width: 2,
                ),
          color: lit ? theme.accent : idleColor(theme),
          boxShadow: lit && glow
              ? [
                  BoxShadow(
                    color: theme.accent.withValues(alpha: 0.9),
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}
