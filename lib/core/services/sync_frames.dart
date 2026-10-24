/// Encrypted, length-prefixed frames for one device sync session.
///
/// After the plaintext hello lines, every message is one frame:
/// `u32 length | u8 type | u8 flags | AES-256-GCM ciphertext | 16-byte tag`.
/// The type and flags are authenticated as associated data, and the nonce is
/// the sender's direction plus a frame counter, so a reordered, replayed or
/// dropped frame fails to decrypt. Cover images travel as raw bytes instead
/// of base64 inside JSON inside a base64 envelope.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// A cover image carried by a sync payload, keyed by its content digest.
class SyncCover {
  const SyncCover({
    required this.digest,
    required this.fileName,
    required this.bytes,
  });

  final String digest;
  final String fileName;
  final Uint8List bytes;
}

class SyncFrameException implements Exception {
  const SyncFrameException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Buffers one socket so the hello line and the frames after it share a
/// single subscription. Waits restart whenever bytes arrive, so a large
/// transfer on a slow link is never cut off by a fixed timeout.
class SyncByteReader {
  SyncByteReader(Stream<Uint8List> source) {
    _subscription = source.listen(
      (chunk) {
        _chunks.add(chunk);
        _buffered += chunk.length;
        _wake();
      },
      onError: (Object error) {
        _error = error;
        _wake();
      },
      onDone: () {
        _done = true;
        _wake();
      },
      cancelOnError: true,
    );
  }

  late final StreamSubscription<Uint8List> _subscription;
  final _chunks = ListQueue<Uint8List>();
  int _offset = 0;
  int _buffered = 0;
  bool _done = false;
  Object? _error;
  Completer<void>? _waiter;

  void _wake() {
    final waiter = _waiter;
    _waiter = null;
    waiter?.complete();
  }

  /// Waits for more input; throws [TimeoutException] after [idle] of silence.
  Future<void> _wait(Duration idle) {
    if (_error case final error?) throw error;
    return (_waiter ??= Completer<void>()).future.timeout(idle);
  }

  /// The next newline-terminated line, or null if the connection closed.
  Future<String?> readLine({
    Duration timeout = const Duration(seconds: 10),
    int maxBytes = 64 * 1024,
  }) async {
    while (true) {
      final index = _indexOfNewline();
      if (index >= 0) {
        final bytes = _take(index + 1);
        return utf8.decode(Uint8List.sublistView(bytes, 0, index)).trim();
      }
      if (_buffered > maxBytes) {
        throw const SyncFrameException('Handshake line is too long.');
      }
      if (_done) return null;
      await _wait(timeout);
    }
  }

  /// Exactly [length] bytes, or null if the connection closed before any of
  /// them arrived. [onProgress] reports how many have arrived so far.
  Future<Uint8List?> read(
    int length, {
    required Duration idle,
    void Function(int received)? onProgress,
  }) async {
    while (_buffered < length) {
      if (_done) {
        if (_buffered == 0) return null;
        throw const SyncFrameException('Connection closed mid-message.');
      }
      await _wait(idle);
      onProgress?.call(math.min(_buffered, length));
    }
    return _take(length);
  }

  int _indexOfNewline() {
    var position = 0;
    var start = _offset;
    for (final chunk in _chunks) {
      for (var i = start; i < chunk.length; i++) {
        if (chunk[i] == 10) return position + i - start;
      }
      position += chunk.length - start;
      start = 0;
    }
    return -1;
  }

  Uint8List _take(int length) {
    final out = Uint8List(length);
    var written = 0;
    while (written < length) {
      final chunk = _chunks.first;
      final count = math.min(chunk.length - _offset, length - written);
      out.setRange(written, written + count, chunk, _offset);
      written += count;
      _offset += count;
      if (_offset == chunk.length) {
        _chunks.removeFirst();
        _offset = 0;
      }
    }
    _buffered -= length;
    return out;
  }

  Future<void> cancel() => _subscription.cancel();
}

/// One encrypted session over a socket, after both hello lines.
class SyncChannel {
  SyncChannel(this._socket, this._reader, this._key, {required bool client})
    : _direction = client ? 0 : 1;

  final Socket _socket;
  final SyncByteReader _reader;
  final SecretKey _key;
  final int _direction;
  int _sentFrames = 0;
  int _receivedFrames = 0;
  Future<void> _tail = Future<void>.value();
  List<int>? _keyBytes;

  static final _aes = AesGcm.with256bits();
  static final _gzip = GZipCodec(level: 3);
  static const int _json = 1;
  static const int _cover = 2;
  static const int _keepAlive = 3;
  static const int _gzipped = 1;
  static const int _tagBytes = 16;

  /// Frames larger than this are rejected before their body is buffered.
  static const int maxFrameBytes = 256 * 1024 * 1024;

  /// JSON at least this large is gzip-compressed; images are never.
  static const int _compressBytes = 16 * 1024;

  /// Frames at least this large are sealed and opened on a worker isolate,
  /// so a large payload never stalls the UI thread.
  static const int _isolateBytes = 256 * 1024;

  /// Large frames are written in chunks so sending progress can be reported.
  static const int _chunkBytes = 256 * 1024;

  Future<void> sendJson(
    Map<String, dynamic> message, {
    void Function(int sent, int total)? onProgress,
  }) => _send(_json, utf8.encode(jsonEncode(message)), onProgress);

  /// An empty frame that keeps the peer waiting while this side works.
  Future<void> keepAlive() => _send(_keepAlive, const <int>[], null);

  /// Sends a payload's JSON, then each of its `covers` as a raw frame.
  Future<void> sendPayload(
    Map<String, dynamic> payload, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final covers = (payload.remove('covers') as List<SyncCover>?) ?? const [];
    final coverBytes = covers.fold<int>(0, (sum, c) => sum + c.bytes.length);
    final json = utf8.encode(
      jsonEncode({
        ...payload,
        'coverCount': covers.length,
        'coverBytes': coverBytes,
      }),
    );
    final total = json.length + coverBytes;
    await _send(_json, json, (sent, _) => onProgress?.call(sent, total));
    var sent = json.length;
    for (final cover in covers) {
      final digest = utf8.encode(cover.digest);
      final name = utf8.encode(cover.fileName);
      final nameStart = 4 + digest.length;
      final bytesStart = nameStart + name.length;
      final frame = Uint8List(bytesStart + cover.bytes.length)
        ..setAll(4, digest)
        ..setAll(nameStart, name)
        ..setAll(bytesStart, cover.bytes);
      ByteData.sublistView(frame)
        ..setUint16(0, digest.length)
        ..setUint16(2, name.length);
      await _send(_cover, frame, null);
      sent += cover.bytes.length;
      onProgress?.call(sent, total);
    }
  }

  /// Reads a payload sent by [sendPayload]; its covers are keyed by digest.
  Future<Map<String, dynamic>?> readPayload({
    Duration idle = const Duration(seconds: 30),
    void Function()? onKeepAlive,
    void Function(int received, int total)? onProgress,
  }) async {
    final payload = await readJson(
      idle: idle,
      onKeepAlive: onKeepAlive,
      onProgress: onProgress,
    );
    if (payload == null) return null;
    final count = (payload['coverCount'] as num?)?.toInt() ?? 0;
    final coverBytes = (payload['coverBytes'] as num?)?.toInt() ?? 0;
    final covers = <String, SyncCover>{};
    var received = 0;
    for (var i = 0; i < count; i++) {
      final frame = await _readFrame(idle: idle, onKeepAlive: onKeepAlive);
      if (frame == null || frame.type != _cover) {
        throw const SyncFrameException('Cover image transfer was cut short.');
      }
      final bytes = frame.data as Uint8List;
      final header = ByteData.sublistView(bytes, 0, 4);
      final digestEnd = 4 + header.getUint16(0);
      final nameEnd = digestEnd + header.getUint16(2);
      final cover = SyncCover(
        digest: utf8.decode(Uint8List.sublistView(bytes, 4, digestEnd)),
        fileName: utf8.decode(Uint8List.sublistView(bytes, digestEnd, nameEnd)),
        bytes: Uint8List.sublistView(bytes, nameEnd),
      );
      covers[cover.digest] = cover;
      received += cover.bytes.length;
      onProgress?.call(received, coverBytes);
    }
    payload['covers'] = covers;
    return payload;
  }

  /// The next JSON message, skipping keep-alives; null if the peer closed.
  Future<Map<String, dynamic>?> readJson({
    Duration idle = const Duration(seconds: 30),
    void Function()? onKeepAlive,
    void Function(int received, int total)? onProgress,
  }) async {
    final frame = await _readFrame(
      idle: idle,
      onKeepAlive: onKeepAlive,
      onProgress: onProgress,
    );
    if (frame == null) return null;
    if (frame.type != _json || frame.data is! Map<String, dynamic>) {
      throw const SyncFrameException('Unexpected sync message.');
    }
    return frame.data as Map<String, dynamic>;
  }

  Future<void> close() async {
    await _reader.cancel();
    _socket.destroy();
  }

  Future<void> _send(
    int type,
    List<int> plain,
    void Function(int sent, int total)? onProgress,
  ) {
    // Counters are taken in write order, which is also the peer's read order.
    final done = _tail.then((_) async {
      final frame = await _seal(type, plain, _sentFrames++);
      for (var offset = 0; offset < frame.length; offset += _chunkBytes) {
        final end = math.min(offset + _chunkBytes, frame.length);
        _socket.add(Uint8List.sublistView(frame, offset, end));
        await _socket.flush();
        onProgress?.call(end, frame.length);
      }
    });
    _tail = done.catchError((Object _) {});
    return done;
  }

  Future<Uint8List> _seal(int type, List<int> plain, int counter) async {
    final key = _keyBytes ??= await _key.extractBytes();
    final direction = _direction;
    if (plain.length < _isolateBytes) {
      return _sealNow(type, plain, counter, direction, key);
    }
    return Isolate.run(() => _sealNow(type, plain, counter, direction, key));
  }

  Future<({int type, Object data})?> _readFrame({
    required Duration idle,
    void Function()? onKeepAlive,
    void Function(int received, int total)? onProgress,
  }) async {
    while (true) {
      final header = await _reader.read(6, idle: idle);
      if (header == null) return null;
      final length = ByteData.sublistView(header).getUint32(0);
      if (length < 2 + _tagBytes || length > maxFrameBytes) {
        throw const SyncFrameException('Invalid sync message size.');
      }
      final body = await _reader.read(
        length - 2,
        idle: idle,
        onProgress: onProgress == null
            ? null
            : (received) => onProgress(received, length - 2),
      );
      if (body == null) {
        throw const SyncFrameException('Connection closed mid-message.');
      }
      final type = header[4];
      final flags = header[5];
      final counter = _receivedFrames++;
      final key = _keyBytes ??= await _key.extractBytes();
      final direction = 1 - _direction;
      final data = body.length < _isolateBytes
          ? await _openNow(type, flags, body, counter, direction, key)
          : await Isolate.run(
              () => _openNow(type, flags, body, counter, direction, key),
            );
      if (type == _keepAlive) {
        onKeepAlive?.call();
        continue;
      }
      return (type: type, data: data);
    }
  }

  static List<int> _nonce(int direction, int counter) {
    final nonce = Uint8List(12);
    nonce[3] = direction;
    ByteData.sublistView(nonce).setUint64(4, counter);
    return nonce;
  }

  static Future<Uint8List> _sealNow(
    int type,
    List<int> plain,
    int counter,
    int direction,
    List<int> key,
  ) async {
    final compress = type == _json && plain.length >= _compressBytes;
    final flags = compress ? _gzipped : 0;
    final box = await _aes.encrypt(
      compress ? _gzip.encode(plain) : plain,
      secretKey: SecretKeyData(key),
      nonce: _nonce(direction, counter),
      aad: [type, flags],
    );
    final length = 2 + box.cipherText.length + _tagBytes;
    final frame = Uint8List(4 + length);
    ByteData.sublistView(frame).setUint32(0, length);
    frame[4] = type;
    frame[5] = flags;
    frame.setAll(6, box.cipherText);
    frame.setAll(6 + box.cipherText.length, box.mac.bytes);
    return frame;
  }

  /// Decrypts a frame body; JSON is decoded here so large messages are parsed
  /// on the worker isolate too.
  static Future<Object> _openNow(
    int type,
    int flags,
    Uint8List body,
    int counter,
    int direction,
    List<int> key,
  ) async {
    final List<int> clear;
    try {
      clear = await _aes.decrypt(
        SecretBox(
          Uint8List.sublistView(body, 0, body.length - _tagBytes),
          nonce: _nonce(direction, counter),
          mac: Mac(Uint8List.sublistView(body, body.length - _tagBytes)),
        ),
        secretKey: SecretKeyData(key),
        aad: [type, flags],
      );
    } on SecretBoxAuthenticationError {
      throw const SyncFrameException('Sync message failed authentication.');
    }
    final bytes = flags & _gzipped != 0 ? _gzip.decode(clear) : clear;
    if (type != _json) return Uint8List.fromList(bytes);
    return jsonDecode(utf8.decode(bytes)) as Object;
  }
}
