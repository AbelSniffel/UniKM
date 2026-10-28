/// Requests the display mode matching the Frame Rate setting.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

/// Android runs at 60 Hz unless the app asks for another display mode, so
/// "auto" requests the highest refresh rate and a fixed rate picks the closest
/// supported mode at the current resolution. Other platforms follow their
/// display already, so this does nothing there.
Future<void> applyFrameRatePreference(String preference) async {
  if (!Platform.isAndroid) return;
  try {
    final target = int.tryParse(preference);
    if (target == null) {
      await FlutterDisplayMode.setHighRefreshRate();
      return;
    }
    final active = await FlutterDisplayMode.active;
    final modes = (await FlutterDisplayMode.supported).where(
      (mode) => mode.width == active.width && mode.height == active.height,
    );
    if (modes.isEmpty) return;
    final best = modes.reduce(
      (a, b) => (a.refreshRate - target).abs() <= (b.refreshRate - target).abs()
          ? a
          : b,
    );
    await FlutterDisplayMode.setPreferredMode(best);
  } catch (error) {
    debugPrint('Could not set the display refresh rate: $error');
  }
}
