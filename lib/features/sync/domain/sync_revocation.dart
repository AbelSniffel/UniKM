import 'dart:collection';
import 'dart:convert';

/// Keeps the identity needed to authenticate an offline peer after unpairing.
///
/// A revocation is local trust state, never library data. Keep it across app
/// restarts and do not expire it: the removed device may be offline for months.
class SyncRevocationRecord {
  const SyncRevocationRecord({
    required this.peerId,
    required this.fingerprint,
    this.pairingId = '',
    required this.revokedAtMillis,
  });

  final String peerId;
  final String fingerprint;
  final String pairingId;
  final int revokedAtMillis;

  Map<String, Object> toJson() => {
    'peerId': peerId,
    'fingerprint': fingerprint,
    'pairingId': pairingId,
    'revokedAtMillis': revokedAtMillis,
  };

  static SyncRevocationRecord? fromJson(Object? value) {
    if (value is! Map) return null;
    final peerId = value['peerId'];
    final fingerprint = value['fingerprint'];
    final pairingId = value['pairingId'] ?? '';
    final revokedAtMillis = value['revokedAtMillis'];
    if (peerId is! String ||
        fingerprint is! String ||
        pairingId is! String ||
        revokedAtMillis is! int ||
        peerId.trim().isEmpty ||
        fingerprint.trim().isEmpty ||
        revokedAtMillis < 0) {
      return null;
    }
    return SyncRevocationRecord(
      peerId: peerId.trim(),
      fingerprint: fingerprint.trim(),
      pairingId: pairingId.trim(),
      revokedAtMillis: revokedAtMillis,
    );
  }
}

/// Immutable, JSON-backed revocation state for one local device.
///
/// Persist [record] before deleting trust metadata or attempting delivery. Only
/// [removePeer] after a new pairing succeeds, with a new signed pairing ID; a
/// discovery packet or changed address must never restore trust.
class SyncRevocationLedger {
  SyncRevocationLedger([Iterable<SyncRevocationRecord> records = const []])
    : records = List.unmodifiable(_latestRecords(records));

  final List<SyncRevocationRecord> records;

  static Iterable<SyncRevocationRecord> _latestRecords(
    Iterable<SyncRevocationRecord> records,
  ) {
    final latest = <String, SyncRevocationRecord>{};
    for (final record in records) {
      final existing = latest[record.peerId];
      if (existing == null ||
          record.revokedAtMillis >= existing.revokedAtMillis) {
        latest[record.peerId] = record;
      }
    }
    final peerIds = latest.keys.toList()..sort();
    return peerIds.map((peerId) => latest[peerId]!);
  }

  factory SyncRevocationLedger.decode(String? encoded) {
    if (encoded == null || encoded.trim().isEmpty) {
      return SyncRevocationLedger();
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return SyncRevocationLedger();
      return SyncRevocationLedger(
        decoded.map(SyncRevocationRecord.fromJson).whereType(),
      );
    } on FormatException {
      return SyncRevocationLedger();
    }
  }

  String encode() => jsonEncode(records.map((r) => r.toJson()).toList());

  /// Matches only the revoked identity and generation when supplied.
  ///
  /// Authenticate the packet against the returned fingerprint before replying.
  /// A matching device ID alone does not establish the sender's identity.
  SyncRevocationRecord? find(
    String peerId, {
    String? fingerprint,
    String? pairingId,
  }) {
    for (final record in records) {
      if (record.peerId == peerId &&
          (fingerprint == null || record.fingerprint == fingerprint) &&
          (pairingId == null || record.pairingId == pairingId)) {
        return record;
      }
    }
    return null;
  }

  /// Replaces this peer's tombstone; the caller has verified the removal.
  SyncRevocationLedger record(SyncRevocationRecord record) {
    if (SyncRevocationRecord.fromJson(record.toJson()) == null) {
      throw ArgumentError.value(record, 'record', 'Invalid revocation');
    }
    return SyncRevocationLedger([
      ...records.where((r) => r.peerId != record.peerId),
      record,
    ]);
  }

  SyncRevocationLedger removePeer(String peerId) =>
      SyncRevocationLedger(records.where((record) => record.peerId != peerId));
}

/// Bounded duplicate suppression for authenticated control packets.
///
/// Call [accept] only after verifying the MAC. Include the message ID, issue
/// time, and pairing generation in the MAC. Pairing IDs prevent a captured
/// unpair command from affecting a later pairing with the same static keys.
/// An evicted entry may be accepted again while its timestamp is still valid;
/// sensitive operations must also validate the current pairing generation and
/// be idempotent. This guard does not replace trust verification.
class SyncControlReplayGuard {
  SyncControlReplayGuard({
    this.capacity = 4096,
    this.retention = const Duration(minutes: 10),
    this.maxClockSkew = const Duration(minutes: 5),
  }) {
    if (capacity <= 0 ||
        maxClockSkew.isNegative ||
        retention.inMilliseconds < 2 * maxClockSkew.inMilliseconds) {
      throw ArgumentError(
        'Replay retention must cover twice the allowed clock skew, '
        'and capacity must be positive.',
      );
    }
  }

  final int capacity;
  final Duration retention;
  final Duration maxClockSkew;
  final LinkedHashMap<String, int> _accepted = LinkedHashMap();
  int _lastNowMillis = 0;

  int get length => _accepted.length;

  bool accept({
    required String peerId,
    required String messageId,
    required int issuedAtMillis,
    required int nowMillis,
    String pairingId = '',
  }) {
    if (peerId.isEmpty ||
        messageId.isEmpty ||
        peerId.length > 256 ||
        messageId.length > 256 ||
        pairingId.length > 256 ||
        issuedAtMillis < 0 ||
        nowMillis < 0 ||
        (issuedAtMillis - nowMillis).abs() > maxClockSkew.inMilliseconds) {
      return false;
    }

    // Expire against monotonic observed time if the device clock moves back.
    final observedNow = nowMillis > _lastNowMillis ? nowMillis : _lastNowMillis;
    _lastNowMillis = observedNow;
    final expiryCutoff = observedNow - retention.inMilliseconds;
    while (_accepted.isNotEmpty && _accepted.values.first < expiryCutoff) {
      _accepted.remove(_accepted.keys.first);
    }

    final identity = jsonEncode([peerId, pairingId, messageId]);
    if (_accepted.containsKey(identity)) return false;
    while (_accepted.length >= capacity) {
      _accepted.remove(_accepted.keys.first);
    }
    _accepted[identity] = observedNow;
    return true;
  }
}
