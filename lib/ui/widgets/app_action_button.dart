import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/button_depth.dart';
import 'settings_card_indicator.dart';
import 'settings_card_inset.dart';
import 'button_theme_sync.dart';

/// The outlined action style shared by Dev Tools and game option toggles.
class const AppActionButton({
  super.key,
  required final String label,
  final IconData? icon,
  required final VoidCallback? onTap,

  /// Null for an ordinary action; false/true enables the fixed toggle indicator.
  final bool? selected,

  /// Selected text, indicator, and highlighted border color.
  final Color? accentColor,

  final bool showStatus = true,
  final bool readOnly = false,

  /// Hide an off toggle's surface only while it is neither hovered nor active.
  final bool transparentWhenIdle = false,
  final double depthStrength = SettingsCardInset.defaultDepthStrength,
}) extends StatelessWidget {
  static const toggleHorizontalPadding = 10.0;

  /// A tag's check or cross, and its gap from the label.
  static const statusSize = 14.0;
  static const statusSpacing = 4.0;

  /// Puts a toggle's light before its [label], for a `foregroundBuilder`:
  /// the light is always there, so the label never moves.
  static Widget withStatus(
    Widget label, {
    required bool selected,
    Color? accentColor,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 7,
    children: [
      AppButtonSelectionIndicator(selected: selected, accentColor: accentColor),
      Flexible(child: label),
    ],
  );

  static ButtonStyle styleFor(
    AppThemeData theme, {
    bool? selected,
    Color? accentColor,
    bool readOnly = false,
    bool transparentWhenIdle = false,
    bool hoverBorder = true,
    double depthStrength = SettingsCardInset.defaultDepthStrength,
  }) {
    final accent = accentColor ?? theme.accent;
    final foreground = selected == true ? accent : theme.textPrimary;
    final background = theme.background.withValues(alpha: 0.65);
    bool hideIdleSurface(Set<WidgetState> states) =>
        transparentWhenIdle &&
        selected == false &&
        !states.contains(WidgetState.hovered) &&
        !states.contains(WidgetState.pressed) &&
        !states.contains(WidgetState.focused);
    return OutlinedButton.styleFrom(
      foregroundColor: foreground,
      backgroundColor: background,
      disabledForegroundColor: readOnly ? foreground : null,
      disabledBackgroundColor: readOnly
          ? background
          : theme.background.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cornerRadius),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: selected == null ? 8 : toggleHorizontalPadding,
        vertical: 7,
      ),
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
    ).copyWith(
      // Ink animates tag surfaces without a physical elevation casting a dark
      // fill behind partially transparent frames.
      backgroundColor: transparentWhenIdle
          ? const WidgetStatePropertyAll(Colors.transparent)
          : null,
      side: WidgetStateProperty.resolveWith((states) {
        if (hideIdleSurface(states) ||
            (!readOnly && states.contains(WidgetState.disabled))) {
          return BorderSide.none;
        }
        final highlighted =
            (hoverBorder &&
                (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.pressed))) ||
            states.contains(WidgetState.focused);
        return BorderSide(
          color: highlighted ? accent : theme.border,
          width: highlighted ? 1.5 : 1,
        );
      }),
      elevation: selected == true || transparentWhenIdle
          ? const WidgetStatePropertyAll(0)
          : null,
      // Keep the theme's shadow color when toggling. Swapping it restarts
      // Material's shadow animation, which flashes a dark fill behind the
      // translucent surface for a frame.
      backgroundBuilder: selected == null
          ? null
          : (context, states, child) {
              final lighting = ButtonDepthLayer(
                outlined: true,
                pressed: states.contains(WidgetState.pressed),
                disabled:
                    selected ||
                    states.contains(WidgetState.disabled) ||
                    hideIdleSurface(states),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(theme.cornerRadius),
                ),
                textDirection: Directionality.of(context),
                // Keep both layers mounted so the status morph survives toggles.
                child: SettingsCardInset(
                  active:
                      selected &&
                      (readOnly || !states.contains(WidgetState.disabled)),
                  borderRadius: theme.cornerRadius,
                  surfaceColor: theme.background,
                  depthStrength: depthStrength,
                  cacheRaster: true,
                  child: child!,
                ),
              );
              if (!transparentWhenIdle) return lighting;
              return TweenAnimationBuilder<double>(
                tween: Tween(
                  end: hideIdleSurface(states)
                      ? 0.0
                      : states.contains(WidgetState.disabled) && !readOnly
                      ? 0.45
                      : 0.65,
                ),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 110),
                curve: Curves.easeOutCubic,
                child: lighting,
                // Only opacity animates. New theme RGB applies immediately,
                // including when it changes halfway through a hover fade.
                builder: (context, opacity, child) => Ink(
                  decoration: BoxDecoration(
                    color: theme.background.withValues(alpha: opacity),
                    borderRadius: BorderRadius.circular(theme.cornerRadius),
                  ),
                  child: child,
                ),
              );
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final materialTheme = Theme.of(context);
    final style = styleFor(
      theme,
      selected: selected,
      accentColor: accentColor,
      readOnly: readOnly,
      transparentWhenIdle: transparentWhenIdle,
      // Toggles, tags that delete on click included, keep a calm outline on
      // hover.
      hoverBorder: selected == null,
      depthStrength: depthStrength,
    );
    final button = ButtonThemeSync(
      theme: theme,
      builder: (context, snapTheme) => OutlinedButton(
        onPressed: readOnly ? null : onTap,
        style:
            (selected == null
                    ? style
                    : style.copyWith(
                        overlayColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.pressed)
                              ? materialTheme.splashColor
                              : states.contains(WidgetState.hovered)
                              ? materialTheme.hoverColor
                              : states.contains(WidgetState.focused)
                              ? materialTheme.focusColor
                              : null,
                        ),
                      ))
                .copyWith(
                  animationDuration: snapTheme ? Duration.zero : null,
                  foregroundBuilder: selected == null || !showStatus
                      ? null
                      : (context, states, label) => withStatus(
                          label!,
                          // Unlit while disabled, like a settings card's bar.
                          selected:
                              selected! &&
                              (readOnly ||
                                  !states.contains(WidgetState.disabled)),
                          accentColor: accentColor,
                        ),
                ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
    // Keep ink, border, and depth animation paints local to this control.
    // A Wrap otherwise repaints every sibling (including blurred shadows)
    // whenever just one button animates. Read-only labels need no extra layer.
    if (!readOnly) return RepaintBoundary(child: button);
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          child: IgnorePointer(child: button),
        ),
      ),
    );
  }
}

/// A toggle's light, like a status LED: a muted dot while off, glowing in the
/// accent when [selected].
class const AppButtonSelectionIndicator({
  super.key,
  required final bool selected,
  final Color? accentColor,
}) extends StatelessWidget {
  static const size = 10.0;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final accent = accentColor ?? theme.accent;
    // Tweens only how lit it is, so a theme change recolours it at once.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: selected ? 1 : 0),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      builder: (context, lit, _) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.lerp(SettingsCardMiniDot.idleColor(theme), accent, lit),
          boxShadow: [
            if (lit > 0)
              BoxShadow(
                color: accent.withValues(alpha: 0.8 * lit),
                blurRadius: 4,
              ),
          ],
        ),
      ),
    );
  }
}

/// A toggle's mark: off, a small dot; on ([progress] 1), a check; and over
/// a tag that deletes, a cross ([deleteProgress] 1).
class const ToggleIndicatorPainter({
  required final Color color,
  required final double progress,
  final double deleteProgress = 0,
}) extends CustomPainter {
  /// The off dot's radius, as a share of the mark's width.
  static const _dotRadius = 0.14;

  @override
  void paint(Canvas canvas, Size size) {
    Offset scale(Offset point) =>
        Offset(point.dx * size.width, point.dy * size.height);
    // The check and cross grow out of the dot at the centre.
    const centre = Offset(0.5, 0.5);
    Offset morph(Offset check, Offset cross) => scale(
      Offset.lerp(
        Offset.lerp(centre, check, progress)!,
        cross,
        deleteProgress,
      )!,
    );
    final start = morph(const Offset(0.18, 0.50), const Offset(0.20, 0.20));
    final middle = morph(const Offset(0.41, 0.73), centre);
    final end = morph(const Offset(0.84, 0.27), const Offset(0.80, 0.80));
    // The dot shrinks away as the check or cross grows.
    final dotShare = (1 - progress) * (1 - deleteProgress);
    if (dotShare > 0) {
      canvas.drawCircle(
        scale(centre),
        _dotRadius * size.width * dotShare,
        Paint()..color = color,
      );
      if (dotShare == 1) return;
    }
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 + 0.4 * math.max(progress, deleteProgress)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(middle.dx, middle.dy)
        ..lineTo(end.dx, end.dy),
      stroke,
    );
    if (deleteProgress > 0) {
      // The cross's second stroke grows out from the centre.
      Offset grow(Offset to) => scale(Offset.lerp(centre, to, deleteProgress)!);
      canvas.drawLine(
        grow(const Offset(0.2, 0.8)),
        grow(const Offset(0.8, 0.2)),
        stroke..color = color.withValues(alpha: color.a * deleteProgress),
      );
    }
  }

  @override
  bool shouldRepaint(ToggleIndicatorPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.progress != progress ||
      oldDelegate.deleteProgress != deleteProgress;
}
