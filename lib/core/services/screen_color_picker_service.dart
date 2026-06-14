library;

import 'package:flutter/material.dart';

import 'screen_color_picker_service_stub.dart'
    if (dart.library.ffi) 'screen_color_picker_service_ffi.dart' as impl;

class ScreenColorPickResult {
  const ScreenColorPickResult({this.color, this.wasCancelled = false});

  final Color? color;
  final bool wasCancelled;
}

/// Passed to [ScreenColorPickerService.pickColor] to allow the caller to
/// cancel an in-progress pick (e.g. when the parent widget is disposed).
class PickerCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class ScreenColorPickerService {
  static Future<ScreenColorPickResult> pickColor({
    Duration timeout = const Duration(seconds: 30),
    void Function(Color color)? onCursorColor,
    PickerCancelToken? cancelToken,
  }) {
    return impl.pickColor(
      timeout: timeout,
      onCursorColor: onCursorColor,
      cancelToken: cancelToken,
    );
  }
}
