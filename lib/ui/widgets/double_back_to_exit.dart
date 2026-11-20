library;

import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'notification_system.dart';

/// On Android, a back gesture that would close the app only warns the first
/// time; a second one within [window] closes it. Back still closes dialogs
/// and pages above as usual. Other platforms are left alone.
class const DoubleBackToExit({
  super.key,
  required final Widget child,
  final Duration window = const Duration(seconds: 2),
}) extends StatefulWidget {
  static const message = 'Go back again to close UniKM';

  @override
  State<DoubleBackToExit> createState() => _DoubleBackToExitState();
}

class _DoubleBackToExitState extends State<DoubleBackToExit> {
  /// Running while a second back closes the app.
  Timer? _armed;
  NotificationHandle? _hint;

  @override
  void dispose() {
    _armed?.cancel();
    super.dispose();
  }

  void _onBack(bool didPop, Object? _) {
    if (didPop) return;
    if (_armed?.isActive ?? false) {
      _armed!.cancel();
      _hint?.dismiss();
      SystemNavigator.pop();
      return;
    }
    _armed = Timer(widget.window, () => _hint?.dismiss());
    _hint = NotificationManager.instance.showHandle(
      message: DoubleBackToExit.message,
      autoDismissAfter: widget.window,
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: defaultTargetPlatform != TargetPlatform.android,
    onPopInvokedWithResult: _onBack,
    child: widget.child,
  );
}
