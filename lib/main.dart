/// UniKM Flutter - Game Key Manager
/// Rewrite of UniKM-Sonnet in Flutter for better performance and UI
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app/presentation/app_bootstrap.dart';
import 'core/services/deadline_notification_service.dart';
import 'core/settings/settings_model.dart';
import 'providers/database_providers.dart';

export 'app/unikm_app.dart' show UniKMApp;

Future<void> _configureSystemUiForMobile() async {
  if (!Platform.isAndroid) {
    return;
  }

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  await _configureSystemUiForMobile();

  // Initialize window manager for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
  }

  // Initialize SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(SettingsKeys.notificationsEnabled);

  // Initialize OS-level notification plugin.
  await DeadlineNotificationService.instance.initialize();

  runApp(
    ProviderScope(
      overrides: [
        // Provide the SharedPreferences instance
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const UniKMBootstrap(),
    ),
  );
}
