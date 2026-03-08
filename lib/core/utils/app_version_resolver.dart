library;

import '../constants/app_constants.dart';

class AppVersionResolver {
  AppVersionResolver._();

  static Future<String>? _cachedVersion;

  static Future<String> currentVersion() {
    return _cachedVersion ??= _loadCurrentVersion();
  }

  static Future<String> _loadCurrentVersion() async {
    return kAppVersion;
  }
}
