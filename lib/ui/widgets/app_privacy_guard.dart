import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/key_privacy.dart';

/// Wraps the app to lock it after [lockAfter] without input, clear expired
/// key copies from the clipboard, and keep the app out of the recent-apps
/// preview while [hideInRecents] is on.
class AppPrivacyGuard extends StatefulWidget {
  const AppPrivacyGuard({
    super.key,
    required this.lockAfter,
    required this.onLock,
    required this.hideInRecents,
    required this.child,
  });

  /// Idle time before [onLock] runs; null never locks.
  final Duration? lockAfter;

  /// Runs on each check once the app has been idle for [lockAfter].
  final VoidCallback onLock;
  final bool hideInRecents;
  final Widget child;

  @override
  State<AppPrivacyGuard> createState() => _AppPrivacyGuardState();
}

class _AppPrivacyGuardState extends State<AppPrivacyGuard>
    with WidgetsBindingObserver {
  // Wall-clock time, so time asleep in the background counts.
  DateTime _lastInput = clock.now();
  late final Timer _ticker;
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) => _check());
    unawaited(KeyPrivacy.protectScreen(widget.hideInRecents));
  }

  @override
  void didUpdateWidget(AppPrivacyGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // An unlock starts a fresh idle period.
    if (widget.lockAfter != oldWidget.lockAfter) _onInput();
    if (widget.hideInRecents != oldWidget.hideInRecents) {
      unawaited(KeyPrivacy.protectScreen(widget.hideInRecents));
    }
  }

  @override
  void dispose() {
    _ticker.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed) _check();
    // iOS takes its app-switcher snapshot as the app leaves the foreground;
    // Android hides it through the window instead.
    final cover =
        !resumed &&
        widget.hideInRecents &&
        defaultTargetPlatform == TargetPlatform.iOS;
    if (cover != _covered) setState(() => _covered = cover);
  }

  void _check() {
    unawaited(KeyPrivacy.clearExpiredCopy());
    final lockAfter = widget.lockAfter;
    if (lockAfter != null && clock.now().difference(_lastInput) >= lockAfter) {
      widget.onLock();
    }
  }

  void _onInput([Object? _]) => _lastInput = clock.now();

  bool _onKey(KeyEvent event) {
    _onInput();
    return false;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _onInput,
    onPointerHover: _onInput,
    onPointerSignal: _onInput,
    onPointerPanZoomStart: _onInput,
    child: Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (_covered)
          Positioned.fill(
            child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
          ),
      ],
    ),
  );
}
