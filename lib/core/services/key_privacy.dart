/// Keeps copied keys and the app's screen away from other apps.
library;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class KeyPrivacy {
  /// How long copied keys stay on the clipboard.
  static const clipboardLifetime = Duration(minutes: 1);

  static const _channel = MethodChannel('unikm/privacy');
  static ({String text, DateTime clearAt})? _copied;

  /// Copies [text], which holds keys, for [clipboardLifetime]: once it is
  /// over, [clearExpiredCopy] clears it unless something else was copied
  /// since. Android marks the copy sensitive so clipboard previews hide it;
  /// iOS expires it by itself and keeps it off the user's other devices.
  static Future<void> copy(String text) async {
    final expiresItself = await _invoke<bool>('copySensitive', {
      'text': text,
      'seconds': clipboardLifetime.inSeconds,
    });
    if (expiresItself == null) {
      await Clipboard.setData(ClipboardData(text: text));
    } else if (expiresItself) {
      return;
    }
    _copied = (text: text, clearAt: clock.now().add(clipboardLifetime));
  }

  /// Clears an expired copy while the clipboard still holds it.
  /// AppPrivacyGuard calls this regularly and when the app resumes, since
  /// Android hides the clipboard from apps in the background.
  static Future<void> clearExpiredCopy() async {
    final copied = _copied;
    if (copied == null || clock.now().isBefore(copied.clearAt)) return;
    final current = await Clipboard.getData(Clipboard.kTextPlain);
    if (current == null) return;
    _copied = null;
    if (current.text == copied.text) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }

  /// Keeps the app out of screenshots and the recent-apps preview (Android;
  /// iOS covers the app instead, see AppPrivacyGuard).
  static Future<void> protectScreen(bool enabled) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _invoke<void>('setSecure', enabled);
    }
  }

  /// Calls the mobile app's privacy channel; null on other platforms or when
  /// the call fails.
  static Future<T?> _invoke<T>(String method, Object? arguments) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return null;
    }
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
