library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../core/theme/app_theme.dart';

class AppFpsCounter extends StatefulWidget {
  const AppFpsCounter({super.key, required this.theme});

  final AppThemeData theme;

  @override
  State<AppFpsCounter> createState() => _AppFpsCounterState();
}

class _AppFpsCounterState extends State<AppFpsCounter>
    with SingleTickerProviderStateMixin {
  static const int _fpsUpdateIntervalMs = 250;

  late final Ticker _ticker;
  Duration? _windowStart;
  int _ticksInWindow = 0;
  int _fps = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    _windowStart ??= elapsed;
    _ticksInWindow++;

    final elapsedMs = (elapsed - _windowStart!).inMilliseconds;
    if (elapsedMs < _fpsUpdateIntervalMs) return;

    final nextFps = ((_ticksInWindow * 1000) / elapsedMs).round();
    _ticksInWindow = 0;
    _windowStart = elapsed;

    if (!mounted || nextFps == _fps) return;
    setState(() => _fps = nextFps);
  }

  @override
  Widget build(BuildContext context) => Text(
    '${_fps > 0 ? _fps : '--'} FPS',
    style: TextStyle(
      color: widget.theme.textSecondary,
      fontSize: 11,
      fontWeight: FontWeight.w500,
    ),
  );
}
