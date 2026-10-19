/// Encryption manager for database security
/// Provides AES-GCM encryption for the SQLite database file
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../shared/state/session_value.dart';
import 'logging.dart';

/// Encryption configuration
class EncryptionConfig {
  static const int pbkdf2Iterations = 220000;
  static const int saltLength = 16;
  static const int nonceLength = 12;
  static const int keyLength = 32; // 256 bits for AES-256
  static const int metaVersion = 1;
}

/// Exception thrown when password is incorrect
class InvalidPasswordException implements Exception {
  final String message;
  InvalidPasswordException([this.message = 'Invalid password']);

  @override
  String toString() => 'InvalidPasswordException: $message';
}

/// Encryption state
enum EncryptionState { unencrypted, encrypted, unknown }

/// Encryption manager for the database
class EncryptionManager {
  /// SharedPreferences key used to persist a plaintext DB path that needs
  /// to be deleted on the next app launch (belt-and-suspenders for Windows
  /// file-lock situations where the retry loop in the same session times out).
  static const String pendingPlaintextDeletionKey =
      'pending_plaintext_deletion';

  final String dbPath;
  final AesGcm _cipher = AesGcm.with256bits();
  String? _keyPassword;
  List<int>? _keySalt;
  Future<SecretKey>? _key;

  EncryptionManager(this.dbPath);

  /// Path to encrypted database file
  String get encryptedPath => '$dbPath.enc';

  /// Check if database is encrypted
  EncryptionState get state {
    final encFile = File(encryptedPath);
    final plainFile = File(dbPath);

    if (encFile.existsSync()) {
      return EncryptionState.encrypted;
    } else if (plainFile.existsSync()) {
      return EncryptionState.unencrypted;
    }
    return EncryptionState.unknown;
  }

  /// Check if database is encrypted
  bool get isEncrypted => state == EncryptionState.encrypted;

  /// Enable encryption with the given password
  Future<void> enable(
    String password, {
    bool deletePlaintextFile = true,
  }) async {
    if (isEncrypted) {
      throw StateError('Database is already encrypted');
    }

    final plainFile = File(dbPath);
    if (!plainFile.existsSync()) {
      throw FileSystemException('Database file not found', dbPath);
    }

    // Read plain database
    final plaintext = await plainFile.readAsBytes();

    await _encryptWithNewSalt(plaintext, password);

    if (deletePlaintextFile) {
      await deletePlaintextDatabaseFile(throwOnFailure: false);
    }
  }

  Future<bool> deletePlaintextDatabaseFile({
    bool throwOnFailure = true,
    int maxAttempts = 8,
    Duration initialDelay = const Duration(milliseconds: 50),
  }) async {
    // Best-effort removal of SQLite WAL companion files first.
    // These can hold OS-level locks that prevent deletion of the main .db file
    // on Windows, especially right after the connection is closed.
    for (final suffix in ['-wal', '-shm']) {
      await _deleteWithRetry(
        File('$dbPath$suffix'),
        label: 'plain DB companion ($suffix)',
        throwOnFailure: false,
        maxAttempts: 3,
        initialDelay: const Duration(milliseconds: 30),
      );
    }

    return _deleteWithRetry(
      File(dbPath),
      label: 'plain database',
      throwOnFailure: throwOnFailure,
      maxAttempts: maxAttempts,
      initialDelay: initialDelay,
    );
  }

  /// Disable encryption with the given password
  Future<void> disable(String password) async {
    if (!isEncrypted) {
      throw StateError('Database is not encrypted');
    }

    // Decrypt
    final plaintext = await decrypt(password);

    // Write plain file
    await File(dbPath).writeAsBytes(plaintext);

    // Delete encrypted file (best-effort with backoff on Windows file locks)
    await _deleteWithRetry(
      File(encryptedPath),
      label: 'encrypted database',
      throwOnFailure: false,
    );
  }

  /// Decrypt database and return plaintext bytes
  Future<Uint8List> decrypt(String password) async {
    if (!isEncrypted) {
      throw StateError('Database is not encrypted');
    }

    final encFile = File(encryptedPath);
    final data = await encFile.readAsBytes();

    // Parse encrypted file format
    if (data.length <
        1 + EncryptionConfig.saltLength + EncryptionConfig.nonceLength + 16) {
      throw FormatException('Invalid encrypted file format');
    }

    var offset = 0;

    // Version
    final version = data[offset];
    offset += 1;
    if (version != EncryptionConfig.metaVersion) {
      throw FormatException('Unsupported encryption version: $version');
    }

    // Salt
    final salt = Uint8List.fromList(
      data.sublist(offset, offset + EncryptionConfig.saltLength),
    );
    offset += EncryptionConfig.saltLength;

    // Nonce
    final nonce = data.sublist(offset, offset + EncryptionConfig.nonceLength);
    offset += EncryptionConfig.nonceLength;

    // Ciphertext (everything except last 16 bytes which is MAC)
    final macStart = data.length - 16;
    final ciphertext = data.sublist(offset, macStart);
    final mac = Mac(data.sublist(macStart));

    // Derive key
    final key = await _deriveKey(password, salt);

    // Decrypt
    try {
      final secretBox = SecretBox(ciphertext, nonce: nonce, mac: mac);
      final plaintext = await _cipher.decrypt(secretBox, secretKey: key);
      return Uint8List.fromList(plaintext);
    } catch (e) {
      throw InvalidPasswordException('Incorrect password or corrupted data');
    }
  }

  /// Decrypt to a temporary file for database access
  /// Returns the path to the temporary decrypted file
  Future<String> decryptToTemp(String password) async {
    final plaintext = await decrypt(password);

    // Create temp directory
    final tempDir = Directory.systemTemp.createTempSync('UniKM_db_');
    final tempPath = p.join(tempDir.path, 'keys.db');

    await File(tempPath).writeAsBytes(plaintext);
    return tempPath;
  }

  /// Re-encrypt from a temporary file
  ///
  /// Note: This does NOT delete the temp file, as the database may still be
  /// using it. The temp file should be deleted separately when closing the session.
  Future<void> reencryptFromTemp(String tempPath, String password) async {
    final file = await File(encryptedPath).open();
    late Uint8List header;
    try {
      header = await file.read(1 + EncryptionConfig.saltLength);
    } finally {
      await file.close();
    }
    if (header.length != 1 + EncryptionConfig.saltLength ||
        header.first != EncryptionConfig.metaVersion) {
      throw const FormatException('Invalid encrypted database header');
    }
    final salt = Uint8List.fromList(header.sublist(1));
    final key = await _deriveKey(password, salt);
    final keyBytes = await key.extractBytes();
    final output = await Isolate.run(
      () => _encryptSnapshot(tempPath, salt, keyBytes),
    );
    await _replaceEncryptedFile(output);
  }

  /// Write in the destination directory, flush, then replace. If replacement
  /// fails the original and the completed temporary encrypted file survive.
  Future<void> _replaceEncryptedFile(Uint8List bytes) async {
    final directory = await Directory(
      File(encryptedPath).parent.path,
    ).createTemp('.unikm-save-');
    final pending = File(p.join(directory.path, 'database.enc'));
    await pending.writeAsBytes(bytes, flush: true);
    await pending.rename(encryptedPath);
    await directory.delete();
  }

  /// Change the encryption password
  Future<void> changePassword(String oldPassword, String newPassword) async {
    if (!isEncrypted) {
      throw StateError('Database is not encrypted');
    }

    // Decrypt with old password
    final plaintext = await decrypt(oldPassword);

    await _encryptWithNewSalt(plaintext, newPassword);
  }

  Future<void> _encryptWithNewSalt(Uint8List plaintext, String password) async {
    final salt = SecretKeyData.random(
      length: EncryptionConfig.saltLength,
    ).bytes;
    final key = await _deriveKey(password, Uint8List.fromList(salt));
    await _replaceEncryptedFile(
      await _encryptDatabaseBytes(plaintext, salt, key),
    );
  }

  /// Verify a password is correct
  Future<bool> verifyPassword(String password) async {
    if (!isEncrypted) return true;

    try {
      await decrypt(password);
      return true;
    } on InvalidPasswordException {
      return false;
    }
  }

  /// Derive encryption key from password using PBKDF2
  Future<SecretKey> _deriveKey(String password, Uint8List salt) {
    if (_keyPassword == password &&
        const ListEquality<int>().equals(_keySalt, salt)) {
      return _key!;
    }
    _keyPassword = password;
    _keySalt = List.unmodifiable(salt);
    return _key = Isolate.run(() async {
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: EncryptionConfig.pbkdf2Iterations,
        bits: EncryptionConfig.keyLength * 8,
      );
      final derived = await pbkdf2.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      );
      return await derived.extractBytes();
    }).then((bytes) => SecretKey(bytes));
  }

  bool _isFileInUse(FileSystemException e) {
    // Windows file-lock error codes:
    //   32 = ERROR_SHARING_VIOLATION  (file held by another process)
    //   33 = ERROR_LOCK_VIOLATION     (region lock on the file)
    final code = e.osError?.errorCode;
    return code == 32 || code == 33;
  }

  Future<bool> _deleteWithRetry(
    File file, {
    required String label,
    bool throwOnFailure = true,
    int maxAttempts = 6,
    Duration initialDelay = const Duration(milliseconds: 50),
  }) async {
    var delay = initialDelay;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        if (await file.exists()) {
          await file.delete();
        }
        return true;
      } on FileSystemException catch (e) {
        final isLocked = _isFileInUse(e);
        final isLastAttempt = attempt == maxAttempts;
        if (!isLocked || isLastAttempt) {
          if (throwOnFailure) {
            rethrow;
          }
          AppLog.w(
            '[Encryption] Failed to delete $label after $attempt attempts: $e',
          );
          return false;
        }
      }

      await Future.delayed(delay);
      delay *= 2;
    }

    return !(await file.exists());
  }
}

/// Provider for encryption manager
final encryptionManagerProvider = Provider.family<EncryptionManager, String>((
  ref,
  dbPath,
) {
  return EncryptionManager(dbPath);
});

/// Provider for encryption state
final encryptionStateProvider = sessionValueProvider(EncryptionState.unknown);

/// Snapshot reading and full-file encryption run outside the UI isolate.
Future<Uint8List> _encryptSnapshot(
  String path,
  List<int> salt,
  List<int> keyBytes,
) async {
  final plaintext = await File(path).readAsBytes();
  return _encryptDatabaseBytes(plaintext, salt, SecretKey(keyBytes));
}

/// Shared version-1 format for initial encryption, password changes, and saves:
/// [version:1][salt:16][nonce:12][ciphertext][mac:16].
Future<Uint8List> _encryptDatabaseBytes(
  List<int> plaintext,
  List<int> salt,
  SecretKey key,
) async {
  final cipher = AesGcm.with256bits();
  final nonce = cipher.newNonce();
  final box = await cipher.encrypt(plaintext, secretKey: key, nonce: nonce);
  return (BytesBuilder()
        ..addByte(EncryptionConfig.metaVersion)
        ..add(salt)
        ..add(nonce)
        ..add(box.cipherText)
        ..add(box.mac.bytes))
      .toBytes();
}
