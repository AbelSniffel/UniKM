library;

import 'package:flutter/material.dart';

import 'screen_color_picker_service_stub.dart'
    if (dart.library.ffi) 'screen_color_picker_service_ffi.dart' as impl;

class ScreenColorPickResult {
  const ScreenColorPickResult({this.color, this.wasCancelled = false});

  final Color? color;
  final bool wasCancelled;
}

class ScreenColorPickerService {
  static Future<ScreenColorPickResult> pickColor({
    Duration timeout = const Duration(seconds: 15),
  }) {
    return impl.pickColor(timeout: timeout);
  }
}
