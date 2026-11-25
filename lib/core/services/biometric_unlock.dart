/// Optional fingerprint unlock for encrypted databases on phones.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/database_providers.dart';

final biometricUnlockProvider = Provider<BiometricUnlock>(
  (ref) => BiometricUnlock(ref.watch(sharedPreferencesProvider)),
);

/// The open database's biometric pairing, for its encryption settings.
typedef BiometricPairing = ({
  bool paired,
  Future<void> Function(String password) pair,
  Future<void> Function() unpair,
});

/// Unlocks an encrypted database with the phone's biometrics instead of its
/// password. Each database file is paired on its own: its password is kept
/// in the Android Keystore or iOS Keychain under a key that only a fresh
/// biometric check can use, so pairing and every unlock show the system
/// prompt, and a change to the enrolled biometrics invalidates the pairing.
///
/// Which files are paired is also kept in plain preferences, so checking
/// whether to offer the prompt never shows it.
///
/// Android keeps the stored passwords and their key out of app backups
/// (`android/app/src/main/res/xml`): restored onto another key, they could
/// never be read again.
class BiometricUnlock(
  final SharedPreferences _prefs, {
  final FlutterSecureStorage _storage = const FlutterSecureStorage(),
  LocalAuthentication? auth,
  bool? supported,
}) {
  this
    : _auth = auth ?? LocalAuthentication(),
      _supported = supported ?? platformSupported;

  final LocalAuthentication _auth;
  final bool _supported;

  /// Whether this platform can offer biometric unlock at all.
  bool get supported => _supported;

  /// Preferences key listing the paired databases by their storage key.
  static const pairedDatabasesKey = 'biometric_unlock_databases';

  /// Biometric unlock is offered on phones only.
  static bool get platformSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// What the prompt and settings call the biometric method.
  static String get label =>
      !kIsWeb && Platform.isIOS ? 'Face ID / Touch ID' : 'Fingerprint';

  static const _namespace = 'unikm_biometric_unlock';

  /// The plugin keeps the options of its first call in each run, so every
  /// call passes these same ones: an empty title from one call would break
  /// every later prompt.
  static const _android = AndroidOptions.biometric(
    enforceBiometrics: true,
    requireBiometricsPerOperation: true,
    biometricType: AndroidBiometricType.strongBiometricOnly,
    // A stored key that no longer opens (restored onto a new phone key, or
    // invalidated by a newly enrolled fingerprint) is reset and the scan
    // asked again once, where migrating it asked twice and then failed on
    // every later try. Only a key failure resets the store; a cancelled
    // prompt never does, so it never wipes the other pairings.
    resetOnError: true,
    migrateOnAlgorithmChange: false,
    storageNamespace: _namespace,
    biometricPromptTitle: 'Fingerprint unlock',
    biometricPromptSubtitle: 'Confirm your fingerprint for this database',
    biometricPromptNegativeButton: 'Use password',
  );

  /// How long after the app returns from the system prompt its answer may
  /// take before the prompt counts as dismissed.
  static const promptAnswerGrace = Duration(seconds: 2);

  /// The longest a prompt is waited for when the app never sees it open, as
  /// on a phone that does not report the prompt covering the app.
  static const promptTimeout = Duration(minutes: 1);

  static const _apple = IOSOptions(
    accountName: _namespace,
    accessibility: KeychainAccessibility.passcode,
    accessControlFlags: [AccessControlFlag.biometryCurrentSet],
  );

  /// Whether this phone has strong biometrics enrolled that can guard a
  /// stored password (Android 9 or newer for the keystore prompt).
  Future<bool> isAvailable() async {
    if (!_supported) return false;
    try {
      if (Platform.isAndroid &&
          (await DeviceInfoPlugin().androidInfo).version.sdkInt < 28) {
        return false;
      }
      if (!await _auth.isDeviceSupported()) return false;
      final types = await _auth.getAvailableBiometrics();
      return Platform.isIOS
          ? types.isNotEmpty
          : types.contains(BiometricType.strong);
    } catch (_) {
      return false;
    }
  }

  /// Whether [databasePath] is paired on this phone.
  Future<bool> isPaired(String databasePath) async =>
      _supported &&
      (_prefs.getStringList(pairedDatabasesKey) ?? const []).contains(
        await _keyFor(databasePath),
      );

  /// Stores [password] for [databasePath] behind a biometric check, which the
  /// system prompt asks for now. Throws when the check fails or is cancelled.
  Future<void> pair(String databasePath, String password) async {
    final key = await _keyFor(databasePath);
    await _whilePrompting(
      _storage.write(
        key: key,
        value: password,
        aOptions: _android,
        iOptions: _apple,
      ),
    );
    final paired = {...?_prefs.getStringList(pairedDatabasesKey), key};
    await _prefs.setStringList(pairedDatabasesKey, paired.toList());
  }

  /// The stored password for [databasePath] after a biometric check, or null
  /// when the check is cancelled or fails. A pairing that can no longer be
  /// read (for example after the enrolled fingerprints changed, which
  /// invalidates the key) is removed; a cancelled prompt keeps it.
  Future<String?> readPassword(String databasePath) async {
    final key = await _keyFor(databasePath);
    try {
      final password = await _whilePrompting(
        _storage.read(key: key, aOptions: _android, iOptions: _apple),
      );
      if (password == null) await forget(databasePath);
      return password;
    } on BiometricPromptDismissed {
      return null;
    } on PlatformException catch (error) {
      if (!_isPromptError(error)) await forget(databasePath);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Waits for [call], which shows the system prompt, and throws
  /// [BiometricPromptDismissed] once the prompt has closed without an
  /// answer. On Android the plugin never answers the prompt's negative
  /// button ("Use password"), which would leave [call] waiting for good.
  ///
  /// The prompt takes the app out of [AppLifecycleState.resumed]; back in
  /// it, a real answer arrives within [promptAnswerGrace]. A second prompt
  /// (a reset key asks again) leaves the app again and keeps waiting.
  static Future<T> _whilePrompting<T>(Future<T> call) async {
    final dismissed = Completer<T>();
    void dismiss() {
      if (!dismissed.isCompleted) {
        dismissed.completeError(const BiometricPromptDismissed());
      }
    }

    var prompted = false;
    Timer? grace;
    final timeout = Timer(promptTimeout, dismiss);
    final lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        grace?.cancel();
        if (state != AppLifecycleState.resumed) {
          // A prompt left open is the user's to answer or dismiss.
          prompted = true;
          timeout.cancel();
        } else if (prompted) {
          grace = Timer(promptAnswerGrace, dismiss);
        }
      },
    );
    try {
      // A late answer or error from an abandoned call is dropped.
      return await Future.any([call, dismissed.future]);
    } finally {
      lifecycle.dispose();
      grace?.cancel();
      timeout.cancel();
    }
  }

  /// Whether [error] came from the prompt itself (cancelled, dismissed or
  /// locked out) rather than from an unusable key.
  static bool _isPromptError(PlatformException error) {
    final text = '${error.code} ${error.message}'.toLowerCase();
    return text.contains('biometric authentication error') || // Android
        text.contains('-128') || // iOS errSecUserCanceled
        text.contains('cancel');
  }

  /// Removes the pairing for [databasePath]; it then needs its password.
  Future<void> forget(String databasePath) async {
    final key = await _keyFor(databasePath);
    final paired = _prefs.getStringList(pairedDatabasesKey) ?? const [];
    if (paired.contains(key)) {
      await _prefs.setStringList(
        pairedDatabasesKey,
        paired.where((entry) => entry != key).toList(),
      );
    }
    if (!_supported) return;
    try {
      await _storage.delete(key: key, aOptions: _android, iOptions: _apple);
    } catch (_) {
      // The keystore entry may already be gone with an invalidated key.
    }
  }

  /// One key per database file, from its normalised path without `.enc`.
  static Future<String> _keyFor(String databasePath) async {
    var path = p.normalize(databasePath);
    if (path.endsWith('.enc')) path = path.substring(0, path.length - 4);
    final digest = await Sha256().hash(utf8.encode(path));
    return 'db_${digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }
}

/// The system biometric prompt closed without an answer, as with its
/// "Use password" button.
class const BiometricPromptDismissed() implements Exception {
  @override
  String toString() => 'The fingerprint prompt was dismissed';
}
