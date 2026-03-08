/// Encryption manager for database security
/// Provides AES-GCM encryption for the SQLite database file
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

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
enum EncryptionState {
  unencrypted,
  encrypted,
  unknown,
}

/// Encryption manager for the database
class EncryptionManager {
  final String dbPath;
  final AesGcm _cipher = AesGcm.with256bits();
  
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
  Future<void> enable(String password) async {
    if (isEncrypted) {
      throw StateError('Database is already encrypted');
    }
    
    final plainFile = File(dbPath);
    if (!plainFile.existsSync()) {
      throw FileSystemException('Database file not found', dbPath);
    }
    
    // Read plain database
    final plaintext = await plainFile.readAsBytes();
    
    // Generate salt and derive key
    final salt = SecretKeyData.random(length: EncryptionConfig.saltLength).bytes;
    final key = await _deriveKey(password, Uint8List.fromList(salt));
    
    // Encrypt
    final nonce = _cipher.newNonce();
    final secretBox = await _cipher.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
    );
    
    // Build encrypted file format:
    // [version:1][salt:16][nonce:12][ciphertext+mac]
    final output = BytesBuilder();
    output.addByte(EncryptionConfig.metaVersion);
    output.add(salt);
    output.add(nonce);
    output.add(secretBox.cipherText);
    output.add(secretBox.mac.bytes);
    
    // Write encrypted file
    await File(encryptedPath).writeAsBytes(output.toBytes());
    
    // Delete plain file (best-effort with backoff on Windows file locks)
    await _deleteWithRetry(
      plainFile,
      label: 'plain database',
      throwOnFailure: false,
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
    if (data.length < 1 + EncryptionConfig.saltLength + EncryptionConfig.nonceLength + 16) {
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
    final salt = Uint8List.fromList(data.sublist(offset, offset + EncryptionConfig.saltLength));
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
    final plaintext = await File(tempPath).readAsBytes();
    
    // Read existing salt from encrypted file
    final encFile = File(encryptedPath);
    final existingData = await encFile.readAsBytes();
    final salt = Uint8List.fromList(existingData.sublist(1, 1 + EncryptionConfig.saltLength));
    
    // Derive key
    final key = await _deriveKey(password, salt);
    
    // Encrypt
    final nonce = _cipher.newNonce();
    final secretBox = await _cipher.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
    );
    
    // Build encrypted file
    final output = BytesBuilder();
    output.addByte(EncryptionConfig.metaVersion);
    output.add(salt);
    output.add(nonce);
    output.add(secretBox.cipherText);
    output.add(secretBox.mac.bytes);
    
    // Write encrypted file
    await encFile.writeAsBytes(output.toBytes());
    
    // Note: Temp file cleanup is NOT done here anymore.
    // The temp file should remain accessible while the database session is active.
    // Cleanup happens in closeAndPersist() after the database is closed.
  }
  
  /// Change the encryption password
  Future<void> changePassword(String oldPassword, String newPassword) async {
    if (!isEncrypted) {
      throw StateError('Database is not encrypted');
    }
    
    // Decrypt with old password
    final plaintext = await decrypt(oldPassword);
    
    // Generate new salt and derive new key
    final salt = SecretKeyData.random(length: EncryptionConfig.saltLength).bytes;
    final key = await _deriveKey(newPassword, Uint8List.fromList(salt));
    
    // Encrypt with new key
    final nonce = _cipher.newNonce();
    final secretBox = await _cipher.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
    );
    
    // Build encrypted file
    final output = BytesBuilder();
    output.addByte(EncryptionConfig.metaVersion);
    output.add(salt);
    output.add(nonce);
    output.add(secretBox.cipherText);
    output.add(secretBox.mac.bytes);
    
    // Write encrypted file
    await File(encryptedPath).writeAsBytes(output.toBytes());
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
  Future<SecretKey> _deriveKey(String password, Uint8List salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: EncryptionConfig.pbkdf2Iterations,
      bits: EncryptionConfig.keyLength * 8,
    );
    
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  bool _isFileInUse(FileSystemException e) {
    // Windows file lock error code is 32.
    return e.osError?.errorCode == 32;
  }

  Future<void> _deleteWithRetry(
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
        return;
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
          return;
        }
      }

      await Future.delayed(delay);
      delay *= 2;
    }
  }
}

/// Provider for encryption manager
final encryptionManagerProvider = Provider.family<EncryptionManager, String>((ref, dbPath) {
  return EncryptionManager(dbPath);
});

/// Provider for encryption state
final encryptionStateProvider =
    NotifierProvider<EncryptionStateNotifier, EncryptionState>(
      EncryptionStateNotifier.new,
    );

class EncryptionStateNotifier extends Notifier<EncryptionState> {
  @override
  EncryptionState build() {
    return EncryptionState.unknown;
  }

  void setEncryptionState(EncryptionState value) {
    state = value;
  }
}

/// Provider for whether encryption is enabled
final isEncryptedProvider = Provider<bool>((ref) {
  return ref.watch(encryptionStateProvider) == EncryptionState.encrypted;
});
