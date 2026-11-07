import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';

/// Holds a game card's place until it reveals: the card's shape in its
/// loading tones, with a soft shine sweeping across it.
class GameCardPlaceholder extends StatefulWidget {
  const GameCardPlaceholder({
    super.key,
    required this.theme,
    required this.viewMode,
    this.slim = false,
  });

  final AppThemeData theme;
  final GameListViewMode viewMode;

  /// The slim list's row, in place of the full list card.
  final bool slim;

  @override
  State<GameCardPlaceholder> createState() => _GameCardPlaceholderState();
}

class _GameCardPlaceholderState extends State<GameCardPlaceholder>
    with SingleTickerProviderStateMixin {
  static const _period = Duration(milliseconds: 1600);

  // Each starts from the frame clock, so every placeholder shines together.
  late final _sweep = AnimationController(
    vsync: this,
    duration: _period,
    value:
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds %
        _period.inMicroseconds /
        _period.inMicroseconds,
  )..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(painter: _PlaceholderPainter(widget, _sweep)),
  );
}

class _PlaceholderPainter extends CustomPainter {
  _PlaceholderPainter(this.card, this.sweep) : super(repaint: sweep);

  final GameCardPlaceholder card;
  final Animation<double> sweep;

  /// Half the shine's width.
  static const double _shine = 90;

  @override
  void paint(Canvas canvas, Size size) {
    final theme = card.theme;
    final grid = card.viewMode == GameListViewMode.grid;
    final rect = Offset.zero & size;
    canvas
      ..clipRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.circular(card.slim ? 0 : theme.cornerRadius),
        ),
      )
      ..drawColor(theme.cardBackground, BlendMode.srcOver)
      // The cover's area, and a line where the title goes.
      ..drawRect(
        Rect.fromLTWH(
          0,
          0,
          grid ? size.width : (card.slim ? 0 : kListCardImageWidth),
          size.height,
        ),
        Paint()..color = theme.cardCoverPlaceholder,
      );
    if (!grid) {
      final left = card.slim ? 10.0 : kListCardImageWidth + 10;
      final top = card.slim ? size.height / 2 - 6 : 12.0;
      canvas.drawRRect(
        RRect.fromLTRBR(
          left,
          top,
          left + math.max(0, math.min(220, (size.width - left) * 0.45)),
          top + 12,
          const Radius.circular(6),
        ),
        Paint()..color = theme.textPrimary.withValues(alpha: 0.08),
      );
    }
    // The shine crosses the card, then rests before its next pass.
    final pass = sweep.value / 0.65;
    if (pass >= 1) return;
    final x =
        -_shine + (size.width + 2 * _shine) * Curves.easeInOut.transform(pass);
    final shine = Colors.white.withValues(alpha: theme.isDark ? 0.07 : 0.5);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(x - _shine, 0),
          Offset(x + _shine, _shine / 2),
          [shine.withValues(alpha: 0), shine, shine.withValues(alpha: 0)],
          const [0, 0.5, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_PlaceholderPainter old) =>
      old.card.theme != card.theme ||
      old.card.viewMode != card.viewMode ||
      old.card.slim != card.slim;
}
