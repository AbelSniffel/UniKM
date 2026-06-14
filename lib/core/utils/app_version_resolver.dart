library;

import 'package:package_info_plus/package_info_plus.dart';

import '../constants/app_constants.dart';

class AppVersionResolver {
  AppVersionResolver._();

  static Future<String>? _cachedVersion;

  static Future<String> currentVersion() {
    return _cachedVersion ??= _loadCurrentVersion();
  }

  static Future<String> _loadCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) {
        return info.version;
      }
    } catch (_) {
      // Ignore and fallback
    }
    return kAppVersion;
  }
}
