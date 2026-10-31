library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Cryptographic utilities for the UniKM device sync encrypted channel.
///
/// Protocol summary (per TCP sync session):
///   1. Client → Server: JSON handshake with ephemeral X25519 public key +
///      device ID + static public key.
///   2. Server → Client: JSON handshake with server's ephemeral + static keys.
///   3. Both sides derive a shared AES-256-GCM session key via two ECDH steps:
///      • ephemeral × ephemeral  → forward secrecy (sessions are independent)
///      • static × static        → peer authentication (prevents MITM)
///      Combined via HKDF-SHA256 with both ephemeral public keys as salt.
///   4. All subsequent data on the channel is AES-256-GCM encrypted.
///
/// Peer identity verification strategy:
/// static public-key fingerprints are pinned during pairing and must be
/// verified by the caller during handshake before deriving/accepting a session.
class SyncCrypto {
  SyncCrypto._();

  static final _x25519 = X25519();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static const _hkdfInfo = 'unikm_sync_v2';

  // ── Key pair management ──────────────────────────────────────────────────

  /// Generates a fresh X25519 key pair.
  static Future<SimpleKeyPair> generateKeyPair() => _x25519.newKeyPair();

  /// Encodes the 32-byte X25519 public key as standard base64.
  static Future<String> exportPublicKey(SimpleKeyPair pair) async {
    final pub = await pair.extractPublicKey();
    return base64.encode(pub.bytes);
  }

  /// Encodes the 32-byte X25519 private key as standard base64.
  static Future<String> exportPrivateKey(SimpleKeyPair pair) async {
    final data = await pair.extract();
    return base64.encode(data.bytes);
  }

  /// Reconstructs an X25519 [SimpleKeyPair] from base64-encoded key bytes.
  static Future<SimpleKeyPair> importKeyPair(
    String privateKeyBase64,
    String publicKeyBase64,
  ) async {
    final privBytes = base64.decode(privateKeyBase64);
    final pubBytes = base64.decode(publicKeyBase64);
    return SimpleKeyPairData(
      privBytes,
      publicKey: SimplePublicKey(pubBytes, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }

  /// Creates an X25519 [SimplePublicKey] from a base64-encoded string.
  static SimplePublicKey publicKeyFromBase64(String b64) =>
      SimplePublicKey(base64.decode(b64), type: KeyPairType.x25519);

  // ── Session key derivation ───────────────────────────────────────────────

  /// Derives a 256-bit AES-GCM session key from ECDH shared secrets.
  ///
  /// The ephemeral ECDH provides forward secrecy — compromising a long-term
  /// key does not expose past sessions.  When [localStatic] and
  /// [remoteStaticPub] are also provided, a second ECDH mixes in a
  /// static-identity binding that prevents man-in-the-middle attacks.
  ///
  /// The HKDF salt is the canonical concatenation
  /// `clientEphemeralPubBytes || serverEphemeralPubBytes` so that both sides,
  /// using opposite roles, derive the exact same key.
  static Future<SecretKey> deriveSessionKey({
    required SimpleKeyPair localEphemeral,
    required SimplePublicKey remoteEphemeralPub,
    SimpleKeyPair? localStatic,
    SimplePublicKey? remoteStaticPub,
    required List<int> clientEphemeralPubBytes,
    required List<int> serverEphemeralPubBytes,
  }) async {
    // Ephemeral ECDH — forward secrecy.
    final ecdh1 = await _x25519.sharedSecretKey(
      keyPair: localEphemeral,
      remotePublicKey: remoteEphemeralPub,
    );
    final bytes1 = await ecdh1.extractBytes();

    final List<int> ikm;
    if (localStatic != null && remoteStaticPub != null) {
      // Static ECDH — authenticates both endpoints.
      final ecdh2 = await _x25519.sharedSecretKey(
        keyPair: localStatic,
        remotePublicKey: remoteStaticPub,
      );
      final bytes2 = await ecdh2.extractBytes();
      ikm = [...bytes1, ...bytes2];
    } else {
      ikm = bytes1;
    }

    // HKDF with canonical salt: client eph pub || server eph pub.
    final salt = Uint8List.fromList([
      ...clientEphemeralPubBytes,
      ...serverEphemeralPubBytes,
    ]);

    return _hkdf.deriveKey(
      secretKey: SecretKey(Uint8List.fromList(ikm)),
      nonce: salt,
      info: utf8.encode(_hkdfInfo),
    );
  }
}
