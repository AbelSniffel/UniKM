import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

/// Shared radio row for dialog choices. RawRadio retains RadioGroup's keyboard
/// traversal and checked semantics while the whole row owns Material feedback.
class AppRadioListTile<T> extends StatefulWidget {
  const AppRadioListTile({
    super.key,
    required this.theme,
    required this.value,
    required this.title,
    required this.subtitle,
    this.enabled = true,
  });

  final AppThemeData theme;
  final T value;
  final String title;
  final String subtitle;
  final bool enabled;

  @override
  State<AppRadioListTile<T>> createState() => _AppRadioListTileState<T>();
}

class _AppRadioListTileState<T> extends State<AppRadioListTile<T>> {
  final _focusNode = FocusNode();
  bool _keyboardFocus = true;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_refreshFocus);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  void _refreshFocus() => setState(() {});

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent && !_keyboardFocus) {
      setState(() => _keyboardFocus = true);
    }
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _focusNode.removeListener(_refreshFocus);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registry = RadioGroup.maybeOf<T>(context);
    final enabled = widget.enabled && registry != null;
    final theme = widget.theme;
    final radius = BorderRadius.circular(theme.cornerRadius);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Listener(
        onPointerDown: (_) {
          if (_keyboardFocus) setState(() => _keyboardFocus = false);
        },
        child: MergeSemantics(
          child: RawRadio<T>(
            value: widget.value,
            groupRegistry: registry,
            enabled: enabled,
            toggleable: false,
            focusNode: _focusNode,
            autofocus: false,
            mouseCursor: WidgetStatePropertyAll(
              enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            ),
            builder: (context, state) => AnimatedBuilder(
              animation: state.position,
              builder: (context, _) => Material(
                animationDuration: Duration.zero,
                color: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: radius,
                  side: BorderSide(
                    color: theme.accent.withValues(
                      alpha: enabled && _keyboardFocus && _focusNode.hasFocus
                          ? 0.65
                          : 0,
                    ),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  // RawRadio is the single keyboard/accessibility focus target.
                  canRequestFocus: false,
                  excludeFromSemantics: true,
                  borderRadius: radius,
                  hoverColor: theme.accent.withValues(alpha: 0.10),
                  highlightColor: theme.accent.withValues(alpha: 0.16),
                  splashColor: theme.accent.withValues(alpha: 0.20),
                  onTap: enabled
                      ? () {
                          _focusNode.requestFocus();
                          if (registry.groupValue != widget.value) {
                            registry.onChanged(widget.value);
                          }
                        }
                      : null,
                  child: ListTile(
                    enabled: enabled,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    minVerticalPadding: 6,
                    minTileHeight: 68,
                    minLeadingWidth: 32,
                    horizontalTitleGap: 12,
                    shape: RoundedRectangleBorder(borderRadius: radius),
                    leading: SizedBox.square(
                      dimension: 32,
                      child: Center(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            size: const Size.square(24),
                            painter: _TriangleRadioPainter(
                              selection: reducedMotion
                                  ? (state.value == true ? 1 : 0)
                                  : state.position.value,
                              accent: theme.accent,
                              inactive: theme.textSecondary,
                              enabled: enabled,
                              cornerRadius: theme.cornerRadius,
                            ),
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      widget.title,
                      style: TextStyle(color: theme.textPrimary),
                    ),
                    subtitle: Text(
                      widget.subtitle,
                      style: TextStyle(color: theme.textSecondary),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TriangleRadioPainter extends CustomPainter {
  const _TriangleRadioPainter({
    required this.selection,
    required this.accent,
    required this.inactive,
    required this.enabled,
    required this.cornerRadius,
  });

  final double selection;
  final Color accent;
  final Color inactive;
  final bool enabled;
  final double cornerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = (Offset.zero & size).deflate(2);
    final points = [bounds.topLeft, bounds.centerRight, bounds.bottomLeft];
    final rounding = math.min(cornerRadius * 0.5, 6.0);
    final path = _triangle(points, rounding);
    final color = Color.lerp(inactive, accent, selection)!;
    final paint = Paint()
      ..color = enabled ? color : color.withValues(alpha: color.a * 0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, paint);
    if (selection > 0) {
      canvas.drawPath(
        path,
        paint
          ..color = paint.color.withValues(alpha: paint.color.a * selection)
          ..style = PaintingStyle.fill,
      );
    }
  }

  Path _triangle(List<Offset> points, double rounding) {
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final corner = points[i];
      final before = points[(i + 2) % 3] - corner;
      final after = points[(i + 1) % 3] - corner;
      // Keep adjacent corners from overlapping at large theme radii.
      final distance = math.min(
        rounding,
        math.min(before.distance, after.distance) / 2,
      );
      final start = corner + before / before.distance * distance;
      final end = corner + after / after.distance * distance;
      i == 0
          ? path.moveTo(start.dx, start.dy)
          : path.lineTo(start.dx, start.dy);
      path.quadraticBezierTo(corner.dx, corner.dy, end.dx, end.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_TriangleRadioPainter oldDelegate) =>
      selection != oldDelegate.selection ||
      accent != oldDelegate.accent ||
      inactive != oldDelegate.inactive ||
      enabled != oldDelegate.enabled ||
      cornerRadius != oldDelegate.cornerRadius;
}
