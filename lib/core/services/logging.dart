import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Lightweight application logger used throughout the app.
///
/// - Avoids using `print()` (which the linter flags for production code).
/// - Uses `dart:developer.log` so logs can be captured by tooling.
/// - `.d()` (debug) is a no-op in release builds.
class AppLog {
  static const String _defaultName = 'UniKM';

  /// Debug-level messages (only emitted in debug builds).
  static void d(String message, {String? name}) {
    if (kDebugMode) {
      developer.log(message, name: name ?? _defaultName, level: 700);
    }
  }

  /// Informational messages (emitted in all builds).
  static void i(String message, {String? name}) {
    developer.log(message, name: name ?? _defaultName, level: 800);
  }

  /// Warning-level messages (emitted in all builds).
  static void w(String message, {Object? error, StackTrace? stackTrace, String? name}) {
    developer.log(
      message,
      name: name ?? _defaultName,
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Error-level messages (emitted in all builds).
  static void e(String message, {Object? error, StackTrace? stackTrace, String? name}) {
    developer.log(
      message,
      name: name ?? _defaultName,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
