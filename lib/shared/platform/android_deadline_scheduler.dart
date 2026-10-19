import 'dart:io';
import 'package:flutter/services.dart';

class AndroidDeadlineScheduler {
  static const _channel = MethodChannel('unikm/deadline_reminders');

  static Future<void> replace(List<Map<String, Object>> reminders) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('replace', reminders);
  }
}
