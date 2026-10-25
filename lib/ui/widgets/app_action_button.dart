import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/button_depth.dart';
import 'settings_card_inset.dart';
import 'button_theme_sync.dart';

/// The outlined action style shared by Dev Tools and game option toggles.
class AppActionButton extends StatelessWidget {
  const AppActionButton({
    super.key,
    required this.label,
    this.icon,
    required this.theme,
    required this.onTap,
    this.selected,
    this.expandLabel = false,
    this.accentColor,
    this.deleteOnHover = false,
    this.showStatus = true,
    this.readOnly = false,
    this.transparentWhenIdle = false,
    this.depthStrength = SettingsCardInset.defaultDepthStrength,
  });
  final String label;
  final IconData? icon;
  final AppThemeData theme;
  final VoidCallback? onTap;

  /// Null for an ordinary action; false/true enables the fixed toggle indicator.
  final bool? selected;
  final bool expandLabel;

  /// Selected text, indicator, and highlighted border color.
  final Color? accentColor;

  /// Morph the fixed suffix into a delete mark while hovering an action tag.
  final bool deleteOnHover;
  final bool showStatus;
  final bool readOnly;

  /// Hide an off toggle's surface only while it is neither hovered nor active.
  final bool transparentWhenIdle;
  final double depthStrength;

  static const toggleHorizontalPadding = 10.0;
  static const statusSize = 14.0;
  static const statusSpacing = 4.0;

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
    final materialTheme = Theme.of(context);
    final style = styleFor(
      theme,
      selected: selected,
      accentColor: accentColor,
      readOnly: readOnly,
      transparentWhenIdle: transparentWhenIdle,
      // Toggles keep a calm outline on hover; only tags that delete on click
      // highlight it as a warning.
      hoverBorder: selected == null || deleteOnHover,
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
                  foregroundBuilder: !deleteOnHover
                      ? null
                      : (context, states, child) => _ButtonHoverState(
                          hovered: states.contains(WidgetState.hovered),
                          child: child!,
                        ),
                ),
        child: Row(
          mainAxisSize: expandLabel ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16),
              const SizedBox(width: 6),
            ],
            if (expandLabel)
              Expanded(child: Text(label))
            else
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (showStatus && selected != null) ...[
              const SizedBox(width: statusSpacing),
              Builder(
                builder: (context) {
                  final hovered =
                      context
                          .dependOnInheritedWidgetOfExactType<
                            _ButtonHoverState
                          >()
                          ?.hovered ??
                      false;
                  return AppButtonSelectionIndicator(
                    selected: selected!,
                    deleteHovered: deleteOnHover && hovered,
                    theme: theme,
                    accentColor: accentColor,
                  );
                },
              ),
            ],
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

class _ButtonHoverState extends InheritedWidget {
  const _ButtonHoverState({required this.hovered, required super.child});
  final bool hovered;

  @override
  bool updateShouldNotify(_ButtonHoverState oldWidget) =>
      oldWidget.hovered != hovered;
}

/// A fixed-size status slot, shared by ordinary and compound toggle buttons.
class AppButtonSelectionIndicator extends StatelessWidget {
  const AppButtonSelectionIndicator({
    super.key,
    required this.selected,
    required this.theme,
    this.accentColor,
    this.deleteHovered = false,
  });

  final Color? accentColor;
  final bool selected;
  final bool deleteHovered;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: AppActionButton.statusSize,
    child: ExcludeSemantics(
      child: TweenAnimationBuilder<Offset>(
        tween: Tween(end: Offset(selected ? 1 : 0, deleteHovered ? 1 : 0)),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        curve: Curves.easeInOutCubic,
        builder: (context, progress, child) => RepaintBoundary(
          child: CustomPaint(
            painter: _ToggleIndicatorPainter(
              progress: progress.dx,
              deleteProgress: progress.dy,
              color: Color.lerp(
                theme.textHint,
                accentColor ?? theme.accent,
                math.max(progress.dx, progress.dy),
              )!,
            ),
          ),
        ),
      ),
    ),
  );
}

class _ToggleIndicatorPainter extends CustomPainter {
  const _ToggleIndicatorPainter({
    required this.color,
    required this.progress,
    required this.deleteProgress,
  });
  final Color color;
  final double progress;
  final double deleteProgress;

  @override
  void paint(Canvas canvas, Size size) {
    Offset scale(Offset point) =>
        Offset(point.dx * size.width, point.dy * size.height);
    Offset morph(Offset line, Offset check, Offset cross) => scale(
      Offset.lerp(Offset.lerp(line, check, progress)!, cross, deleteProgress)!,
    );
    final start = morph(
      const Offset(0.22, 0.50),
      const Offset(0.18, 0.50),
      const Offset(0.20, 0.20),
    );
    final middle = morph(
      const Offset(0.50, 0.50),
      const Offset(0.41, 0.73),
      const Offset(0.50, 0.50),
    );
    final end = morph(
      const Offset(0.78, 0.50),
      const Offset(0.84, 0.27),
      const Offset(0.80, 0.80),
    );
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
      Offset grow(Offset to) =>
          scale(Offset.lerp(const Offset(0.5, 0.5), to, deleteProgress)!);
      canvas.drawLine(
        grow(const Offset(0.2, 0.8)),
        grow(const Offset(0.8, 0.2)),
        stroke..color = color.withValues(alpha: color.a * deleteProgress),
      );
    }
  }

  @override
  bool shouldRepaint(_ToggleIndicatorPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.progress != progress ||
      oldDelegate.deleteProgress != deleteProgress;
}
