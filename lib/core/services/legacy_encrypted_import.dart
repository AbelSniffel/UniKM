library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';

import 'encryption_manager.dart';

enum EncryptedImportKind {
  uniKmDatabase,
  steamKm1Json,
  steamKm2Database,
  unknown,
}

class PreparedEncryptedDatabaseImport {
  const PreparedEncryptedDatabaseImport({
    required this.databasePath,
    required this.cleanupPaths,
  });

  final String databasePath;
  final List<String> cleanupPaths;

  Future<void> dispose() async {
    for (final path in cleanupPaths.reversed) {
      try {
        final type = FileSystemEntity.typeSync(path, followLinks: false);
        if (type == FileSystemEntityType.directory) {
          await Directory(path).delete(recursive: true);
        } else if (type != FileSystemEntityType.notFound) {
          await File(path).delete();
        }
      } catch (_) {}
    }
  }
}

const _steamKm2Magic = 'SKM2';
const _steamKm1SaltLength = 16;
const _steamKm1IvLength = 16;
const _steamKm1Iterations = 480000;
const _aesBlockSize = 16;
const _uniKmMinimumLength =
    1 + EncryptionConfig.saltLength + EncryptionConfig.nonceLength + 16;
final _base64Pattern = RegExp(r'^[A-Za-z0-9+/=\r\n]+$');

Future<EncryptedImportKind> detectEncryptedImportKind(File file) async {
  // Binary formats need only their header and minimum length. The stream closes
  // its file handle on completion or error, including for truncated files.
  final header = BytesBuilder(copy: false);
  await for (final chunk in file.openRead(0, _uniKmMinimumLength)) {
    header.add(chunk);
  }
  final kind = _detectBinaryEncryptedImportKind(header.takeBytes());
  if (kind != EncryptedImportKind.unknown) return kind;
  return detectEncryptedImportKindFromBytes(await file.readAsBytes());
}

EncryptedImportKind detectEncryptedImportKindFromBytes(Uint8List bytes) {
  final kind = _detectBinaryEncryptedImportKind(bytes);
  if (kind != EncryptedImportKind.unknown) return kind;
  return _looksLikeSteamKm1EncryptedExport(bytes)
      ? EncryptedImportKind.steamKm1Json
      : EncryptedImportKind.unknown;
}

EncryptedImportKind _detectBinaryEncryptedImportKind(Uint8List bytes) {
  if (_looksLikeSteamKm2EncryptedDatabase(bytes)) {
    return EncryptedImportKind.steamKm2Database;
  }
  if (_looksLikeUniKmEncryptedDatabase(bytes)) {
    return EncryptedImportKind.uniKmDatabase;
  }
  return EncryptedImportKind.unknown;
}

Future<String> decryptSteamKm1JsonExport(File file, String password) async {
  final encoded = (await file.readAsString()).trim();
  if (encoded.isEmpty) {
    throw const FormatException('SteamKM1 encrypted export is empty');
  }

  Uint8List raw;
  try {
    raw = Uint8List.fromList(base64.decode(encoded));
  } catch (_) {
    throw const FormatException('SteamKM1 encrypted export is not valid base64');
  }

  if (raw.length <= _steamKm1SaltLength + _steamKm1IvLength) {
    throw const FormatException('SteamKM1 encrypted export is too short');
  }

  final salt = raw.sublist(0, _steamKm1SaltLength);
  final iv = raw.sublist(_steamKm1SaltLength, _steamKm1SaltLength + _steamKm1IvLength);
  final ciphertext = raw.sublist(_steamKm1SaltLength + _steamKm1IvLength);
  if (ciphertext.isEmpty || ciphertext.length % _aesBlockSize != 0) {
    throw const FormatException('SteamKM1 encrypted export is malformed');
  }

  final keyBytes = await _deriveKeyBytes(
    password: password,
    salt: salt,
    iterations: _steamKm1Iterations,
  );

  final cipher = CBCBlockCipher(AESEngine())
    ..init(false, ParametersWithIV<KeyParameter>(KeyParameter(keyBytes), iv));

  final output = Uint8List(ciphertext.length);
  for (var offset = 0; offset < ciphertext.length; offset += cipher.blockSize) {
    cipher.processBlock(ciphertext, offset, output, offset);
  }

  final unpadded = _removePkcs7Padding(output);
  try {
    return utf8.decode(unpadded);
  } catch (_) {
    throw InvalidPasswordException('Incorrect password or corrupted SteamKM1 backup');
  }
}

Future<PreparedEncryptedDatabaseImport> decryptSteamKm2DatabaseToTemp(
  File file,
  String password,
) async {
  final data = await file.readAsBytes();
  if (!_looksLikeSteamKm2EncryptedDatabase(data)) {
    throw const FormatException('Not a SteamKM2 encrypted database');
  }

  var offset = 4;
  final version = data[offset++];
  if (version != EncryptionConfig.metaVersion) {
    throw FormatException('Unsupported SteamKM2 encryption version: $version');
  }

  final saltLength = _readUint16(data, offset);
  offset += 2;
  final salt = data.sublist(offset, offset + saltLength);
  offset += saltLength;

  final iterations = _readUint32(data, offset);
  offset += 4;

  final nonceLength = _readUint16(data, offset);
  offset += 2;
  final nonce = data.sublist(offset, offset + nonceLength);
  offset += nonceLength;

  final ciphertextAndMac = data.sublist(offset);
  if (ciphertextAndMac.length < 16) {
    throw const FormatException('SteamKM2 encrypted database is malformed');
  }

  final key = await _deriveSecretKey(
    password: password,
    salt: salt,
    iterations: iterations,
  );

  Directory? tempDir;
  try {
    final macStart = ciphertextAndMac.length - 16;
    final secretBox = crypto.SecretBox(
      ciphertextAndMac.sublist(0, macStart),
      nonce: nonce,
      mac: crypto.Mac(ciphertextAndMac.sublist(macStart)),
    );
    final plaintext = await crypto.AesGcm.with256bits().decrypt(
      secretBox,
      secretKey: key,
    );

    tempDir = await Directory.systemTemp.createTemp('UniKM_import_skm2_');
    final dbPath = p.join(tempDir.path, 'steamkm2_import.db');
    await File(dbPath).writeAsBytes(plaintext);

    return PreparedEncryptedDatabaseImport(
      databasePath: dbPath,
      cleanupPaths: <String>[tempDir.path],
    );
  } catch (_) {
    try {
      await tempDir?.delete(recursive: true);
    } catch (_) {}
    throw InvalidPasswordException('Incorrect password or corrupted SteamKM2 backup');
  }
}

Future<PreparedEncryptedDatabaseImport> decryptUniKmDatabaseToTemp(
  File file,
  String password,
) async {
  final tempDir = await Directory.systemTemp.createTemp('UniKM_import_enc_');
  final basePath = p.join(tempDir.path, 'imported_database');
  final tempEncryptedPath = '$basePath.enc';
  try {
    await file.copy(tempEncryptedPath);
    final manager = EncryptionManager(basePath);
    final tempDbPath = await manager.decryptToTemp(password);
    return PreparedEncryptedDatabaseImport(
      databasePath: tempDbPath,
      cleanupPaths: <String>[File(tempDbPath).parent.path, tempEncryptedPath, tempDir.path],
    );
  } catch (_) {
    try {
      await Directory(tempDir.path).delete(recursive: true);
    } catch (_) {}
    rethrow;
  }
}

bool _looksLikeSteamKm2EncryptedDatabase(Uint8List bytes) {
  if (bytes.length < 4) return false;
  return ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == _steamKm2Magic;
}

bool _looksLikeUniKmEncryptedDatabase(Uint8List bytes) {
  return bytes.length >= _uniKmMinimumLength &&
      bytes.first == EncryptionConfig.metaVersion;
}

bool _looksLikeSteamKm1EncryptedExport(Uint8List bytes) {
  if (bytes.isEmpty) return false;

  final text = utf8.decode(bytes, allowMalformed: true).trim();
  if (text.isEmpty || !_base64Pattern.hasMatch(text)) return false;

  try {
    final raw = base64.decode(text);
    return raw.length > _steamKm1SaltLength + _steamKm1IvLength &&
        raw.length % _aesBlockSize == 0;
  } catch (_) {
    return false;
  }
}

Future<crypto.SecretKey> _deriveSecretKey({
  required String password,
  required List<int> salt,
  required int iterations,
}) {
  final pbkdf2 = crypto.Pbkdf2(
    macAlgorithm: crypto.Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  );
  return pbkdf2.deriveKey(
    secretKey: crypto.SecretKey(utf8.encode(password)),
    nonce: salt,
  );
}

Future<Uint8List> _deriveKeyBytes({
  required String password,
  required List<int> salt,
  required int iterations,
}) async {
  final key = await _deriveSecretKey(
    password: password,
    salt: salt,
    iterations: iterations,
  );
  return Uint8List.fromList(await key.extractBytes());
}

Uint8List _removePkcs7Padding(Uint8List data) {
  if (data.isEmpty) {
    throw const FormatException('SteamKM1 decrypted payload is empty');
  }

  final padLength = data.last;
  if (padLength <= 0 || padLength > _aesBlockSize || padLength > data.length) {
    throw InvalidPasswordException('Incorrect password or corrupted SteamKM1 backup');
  }

  for (var i = data.length - padLength; i < data.length; i++) {
    if (data[i] != padLength) {
      throw InvalidPasswordException('Incorrect password or corrupted SteamKM1 backup');
    }
  }

  return Uint8List.sublistView(data, 0, data.length - padLength);
}

int _readUint16(Uint8List data, int offset) {
  return (data[offset] << 8) | data[offset + 1];
}

int _readUint32(Uint8List data, int offset) {
  return (data[offset] << 24) |
      (data[offset + 1] << 16) |
      (data[offset + 2] << 8) |
      data[offset + 3];
}
