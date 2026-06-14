library;

import 'package:flutter/material.dart';

import 'screen_color_picker_service.dart';

Future<ScreenColorPickResult> pickColor({
  Duration timeout = const Duration(seconds: 30),
  void Function(Color color)? onCursorColor,
  PickerCancelToken? cancelToken,
}) async {
  return const ScreenColorPickResult();
}
