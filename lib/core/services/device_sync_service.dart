library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:cryptography/cryptography.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../models/device_sync_models.dart';
import '../settings/settings_model.dart';
import 'backup_service.dart';
import 'database_switching.dart';
import 'steam_service.dart';
import 'sync_crypto.dart';
import 'sync_payload_codec.dart';

class DeviceSyncException implements Exception {
  const DeviceSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DeviceSyncCodeCheckResult {
  const DeviceSyncCodeCheckResult({
    required this.reachable,
    this.peer,
    this.localDbName,
    this.remoteDbName,
    this.dbNameMismatch = false,
    this.localRevision = 0,
    this.remoteRevision = 0,
    this.localKnownRemoteRevision = 0,
    this.remoteKnownLocalRevision = 0,
    this.localKnownRemoteSyncAtMillis = 0,
    this.remoteKnownLocalSyncAtMillis = 0,
    this.localSyncRevisionId = '',
    this.remoteSyncRevisionId = '',
    this.localDbTimestampMillis = 0,
    this.remoteDbTimestampMillis = 0,
    this.remoteReceiverSyncInFlight = false,
  });

  final bool reachable;
  final TrustedSyncPeer? peer;
  final String? localDbName;
  final String? remoteDbName;
  final bool dbNameMismatch;
  final int localRevision;
  final int remoteRevision;
  final int localKnownRemoteRevision;
  final int remoteKnownLocalRevision;
  final int localKnownRemoteSyncAtMillis;
  final int remoteKnownLocalSyncAtMillis;
  final String localSyncRevisionId;
  final String remoteSyncRevisionId;
  final int localDbTimestampMillis;
  final int remoteDbTimestampMillis;
  final bool remoteReceiverSyncInFlight;

  bool get hasConvergedSnapshot {
    if (localSyncRevisionId.isEmpty ||
        localSyncRevisionId != remoteSyncRevisionId) {
      return false;
    }
    if (localDbTimestampMillis > 0 && remoteDbTimestampMillis > 0) {
      return localDbTimestampMillis == remoteDbTimestampMillis;
    }
    return localRevision == remoteRevision;
  }

  bool get localHasChanges =>
      !hasConvergedSnapshot && localRevision > remoteKnownLocalRevision;
  bool get remoteHasChanges =>
      !hasConvergedSnapshot && remoteRevision > localKnownRemoteRevision;
  bool get hasBidirectionalChanges => localHasChanges && remoteHasChanges;
  bool get matches =>
      reachable && !dbNameMismatch && !localHasChanges && !remoteHasChanges;
}

class WindowsFirewallCheckResult {
  const WindowsFirewallCheckResult({
    required this.available,
    this.hasPrivateAllow = false,
    this.hasPublicAllow = false,
  });

  final bool available;
  final bool hasPrivateAllow;
  final bool hasPublicAllow;

  bool get fullyAllowed => hasPrivateAllow && hasPublicAllow;
}

class _PeerPingResult {
  const _PeerPingResult({
    required this.reachable,
    this.remoteTrusted = false,
    this.remoteDbName,
    this.remoteRevision = 0,
    this.remoteKnownLocalRevision = 0,
    this.remoteKnownLocalSyncAtMillis = 0,
    this.remoteSyncRevisionId,
    this.remoteDbTimestampMillis = 0,
    this.remoteReceiverSyncInFlight = false,
  });

  final bool reachable;
  final bool remoteTrusted;
  final String? remoteDbName;
  final int remoteRevision;
  final int remoteKnownLocalRevision;
  final int remoteKnownLocalSyncAtMillis;
  final String? remoteSyncRevisionId;
  final int remoteDbTimestampMillis;
  final bool remoteReceiverSyncInFlight;
}

class _PendingPongState {
  const _PendingPongState({
    required this.expectedPeerId,
    required this.completer,
  });

  final String expectedPeerId;
  final Completer<_PeerPingResult> completer;
}

class _PairDecisionResponse {
  const _PairDecisionResponse({
    required this.accepted,
    this.remoteStaticPubB64,
    this.encryptedCodeProof,
    this.declineReason,
  });

  final bool accepted;
  final String? remoteStaticPubB64;
  final String? encryptedCodeProof;
  final String? declineReason;
}

class _PairAckResponse {
  const _PairAckResponse({required this.accepted, this.remoteStaticPubB64});

  final bool accepted;
  final String? remoteStaticPubB64;
}

class _IncomingPairRequestState {
  const _IncomingPairRequestState({
    required this.requestId,
    required this.peer,
    required this.sourceAddress,
    required this.replyPort,
    required this.createdAt,
    this.receiverAccepted = false,
    this.initiatorStaticPubB64,
    this.receiverStaticPubB64,
    this.initiatorCommitAccepted = false,
  });

  final String requestId;
  final DiscoveredSyncPeer peer;
  final InternetAddress sourceAddress;
  final int replyPort;
  final DateTime createdAt;
  final bool receiverAccepted;
  final String? initiatorStaticPubB64;
  final String? receiverStaticPubB64;
  final bool initiatorCommitAccepted;

  _IncomingPairRequestState copyWith({
    bool? receiverAccepted,
    String? initiatorStaticPubB64,
    String? receiverStaticPubB64,
    bool? initiatorCommitAccepted,
  }) {
    return _IncomingPairRequestState(
      requestId: requestId,
      peer: peer,
      sourceAddress: sourceAddress,
      replyPort: replyPort,
      createdAt: createdAt,
      receiverAccepted: receiverAccepted ?? this.receiverAccepted,
      initiatorStaticPubB64:
          initiatorStaticPubB64 ?? this.initiatorStaticPubB64,
      receiverStaticPubB64: receiverStaticPubB64 ?? this.receiverStaticPubB64,
      initiatorCommitAccepted:
          initiatorCommitAccepted ?? this.initiatorCommitAccepted,
    );
  }
}

class DeviceSyncService {
  DeviceSyncService({required this.ref}) : _codec = SyncPayloadCodec(ref: ref);

  final Ref ref;
  final SyncPayloadCodec _codec;
  final StreamController<SyncEvent> _eventController =
      StreamController<SyncEvent>.broadcast();

  /// Stream of events emitted by this service as sync lifecycle events occur.
  /// Subscribe in [DeviceSyncNotifier] to update UI state atomically.
  Stream<SyncEvent> get syncEvents => _eventController.stream;

  /// Cached device name to avoid repeated async lookups
  String? _cachedDeviceName;

  static const String _firewallAppRuleName = 'UniKM';
  static const String _legacyUdpRuleName = 'UniKM Device Sync (UDP Discovery)';
  static const String _legacyTcpRuleName = 'UniKM Device Sync (TCP Transfer)';

  static const int defaultLanPort = 45871;
  static const int _syncDataTcpPort = 45872;
  static const int _protocolVersion = 1;
  static const Duration _discoveryWindow = Duration(milliseconds: 1200);
  static const Duration _announceInterval = Duration(milliseconds: 2500);
  static const Duration _pairRequestTimeout = Duration(seconds: 30);
  static const Duration _pairCommitTimeout = Duration(seconds: 30);
  static const Duration _pairFinalizeTimeout = Duration(seconds: 30);
  static const Duration _pairRequestLifetime = Duration(seconds: 30);
  static const String _discoverType = 'unikm_sync_discover';
  static const String _discoverResponseType = 'unikm_sync_discover_response';
  static const String _announceType = 'unikm_sync_announce';
  static const String _pairRequestType = 'unikm_sync_pair_request';
  static const String _pairReceiverDecisionType =
      'unikm_sync_pair_receiver_decision';
  static const String _pairCommitType = 'unikm_sync_pair_commit';
  static const String _pairCommitAckType = 'unikm_sync_pair_commit_ack';
  static const String _pairFinalizeType = 'unikm_sync_pair_finalize';
  static const String _pairFinalizeAckType = 'unikm_sync_pair_finalize_ack';
  static const String _pairCancelType = 'unikm_sync_pair_cancel';
  static const String _pairCodeRejectedType = 'unikm_sync_pair_code_rejected';
  static const String _syncPingType = 'unikm_sync_ping';
  static const String _syncPongType = 'unikm_sync_pong';
  static const String _untrustType = 'unikm_sync_untrust';
  static const String _controlAuthAlg = 'x25519-hmac-sha256-v1';
  static const String _pairCodeProofAlg = 'x25519-aesgcm-v1';
  static const Duration _syncPingTimeout = Duration(milliseconds: 1500);
  static const _uuid = Uuid();
  static final X25519 _x25519 = X25519();
  static final Hkdf _pairProofHkdf = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  );

  RawDatagramSocket? _responderSocket;
  StreamSubscription<RawSocketEvent>? _responderSub;
  Timer? _announceTimer;
  final Map<String, _IncomingPairRequestState> _pendingPairRequests = {};
  final Map<String, DiscoveredSyncPeer> _announcedPeers = {};

  /// Timestamp of the last announce received per peer, used to expire stale
  /// cache entries when a device goes offline.
  final Map<String, DateTime> _announcedPeersSeenAt = {};

  /// Completers waiting for a pong reply routed through the responder socket.
  final Map<String, _PendingPongState> _pendingPongs = {};
  ServerSocket? _syncServer;

  /// True while an incoming (receiver-role) sync is being handled.  Used by
  /// [DeviceSyncNotifier] to suppress competing initiator syncs that would
  /// race to overwrite the revision ID adopted from the incoming sender.
  bool _receiverSyncInFlight = false;
  bool get isReceiverSyncInFlight => _receiverSyncInFlight;

  SyncDeviceType _currentDeviceType() {
    if (kIsWeb) {
      return SyncDeviceType.web;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      return SyncDeviceType.mobile;
    }
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return SyncDeviceType.desktop;
    }
    return SyncDeviceType.unknown;
  }

  String _defaultDeviceName(SyncDeviceType type) {
    return switch (type) {
      SyncDeviceType.mobile => 'Mobile Device',
      SyncDeviceType.desktop => 'Desktop Device',
      SyncDeviceType.web => 'UniKM Web',
      SyncDeviceType.unknown => 'UniKM Device',
    };
  }

  bool _isPlaceholderName(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) {
      return true;
    }
    return normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1' ||
        normalized == '0.0.0.0' ||
        normalized == 'unknown' ||
        normalized == 'device';
  }

  String _normalizeDeviceName(String? value, {SyncDeviceType? fallbackType}) {
    if (!_isPlaceholderName(value)) {
      return value!.trim();
    }
    return _defaultDeviceName(fallbackType ?? SyncDeviceType.unknown);
  }

  Map<String, dynamic> _localIdentityMap(String deviceId) {
    return {
      'id': deviceId,
      'name': _currentDeviceName(),
      'deviceType': syncDeviceTypeToWire(_currentDeviceType()),
    };
  }

  Future<Map<String, dynamic>> _getLocalSyncStateForPeer(String peerId) async {
    final db = ref.read(databaseProvider);
    final localRevision = db == null ? 0 : await db.getLocalSyncRevision();
    final localDbTimestamp = db == null
        ? 0
        : await db.getSyncDbTimestampMillis();
    final checkpoint = db == null
        ? null
        : await db.getPeerSyncCheckpoint(peerId);
    return {
      'localRevision': localRevision,
      'localDbTimestamp': localDbTimestamp,
      'peerKnownRevision': (checkpoint?['lastRevision'] as int?) ?? 0,
      'peerKnownSyncAt': (checkpoint?['lastSyncAt'] as int?) ?? 0,
    };
  }

  Future<DeviceSyncSnapshot> loadSnapshot() async {
    final settings = ref.read(settingsProvider);
    final configuredDeviceId =
        (settings[SettingsKeys.syncDeviceId] as String?) ??
        DefaultSettings.syncDeviceId;
    final deviceId = configuredDeviceId.isEmpty
        ? _uuid.v4()
        : configuredDeviceId;

    final trustedPeers = decodeTrustedPeers(
      (settings[SettingsKeys.syncTrustedPeersJson] as String?) ??
          DefaultSettings.syncTrustedPeersJson,
    );

    final lastSyncIso =
        (settings[SettingsKeys.syncLastSyncAtIso] as String?) ??
        DefaultSettings.syncLastSyncAtIso;

    final enabled =
        (settings[SettingsKeys.syncEnabled] as bool?) ??
        DefaultSettings.syncEnabled;

    // Refresh device name on load
    await refreshDeviceName();

    if (enabled) {
      await ensureDiscoveryResponder(deviceId: deviceId);
      _startAnnounceLoop(deviceId);
    } else {
      await stopDiscoveryResponder();
    }

    return DeviceSyncSnapshot(
      enabled: enabled,
      autoOnStartup:
          (settings[SettingsKeys.syncAutoOnStartup] as bool?) ??
          DefaultSettings.syncAutoOnStartup,
      deviceId: deviceId,
      status: DeviceSyncStatus.idle,
      trustedPeers: trustedPeers,
      discoveredPeers: const [],
      pendingPairRequests: getPendingPairRequests(),
      lastSyncAt: lastSyncIso.isEmpty ? null : DateTime.tryParse(lastSyncIso),
      lastTrustedPeerId:
          (settings[SettingsKeys.syncLastTrustedPeerId] as String?)?.trim(),
      statusMessage: null,
    );
  }

  Future<List<DiscoveredSyncPeer>> discoverPeers() async {
    if (kIsWeb) {
      return const [];
    }

    final deviceId = await _ensureDeviceId();
    await ensureDiscoveryResponder(deviceId: deviceId);

    final discoveredById = <String, DiscoveredSyncPeer>{};
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? listenSub;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
        reusePort: false,
      );

      socket.broadcastEnabled = true;

      listenSub = socket.listen((event) {
        if (event != RawSocketEvent.read) {
          return;
        }
        final datagram = socket?.receive();
        if (datagram == null) {
          return;
        }

        final payload = _decodePacket(datagram.data);
        if (payload == null) {
          return;
        }

        final type = payload['type'];
        if (type != _discoverResponseType && type != _announceType) {
          return;
        }

        final from = payload['from'];
        if (from is! Map) {
          return;
        }

        final fromMap = Map<String, dynamic>.from(from);
        final peerId = (fromMap['id'] as String?)?.trim() ?? '';
        if (peerId.isEmpty || peerId == deviceId) {
          return;
        }

        final peerName = (fromMap['name'] as String?)?.trim();
        final peerType = syncDeviceTypeFromWire(
          fromMap['deviceType'] as String? ?? fromMap['device_type'] as String?,
        );
        final host = (payload['host'] as String?)?.trim();
        final port = (payload['port'] as num?)?.toInt() ?? defaultLanPort;

        discoveredById[peerId] = DiscoveredSyncPeer(
          id: peerId,
          name: _normalizeDeviceName(peerName, fallbackType: peerType),
          host: (host == null || host.isEmpty)
              ? datagram.address.address
              : host,
          port: port,
          deviceType: peerType,
        );
      });

      final discoverPacket = utf8.encode(
        jsonEncode({
          'type': _discoverType,
          'protocol': _protocolVersion,
          'from': _localIdentityMap(deviceId),
          'replyPort': socket.port,
        }),
      );

      socket.send(
        discoverPacket,
        InternetAddress('255.255.255.255'),
        defaultLanPort,
      );

      await Future<void>.delayed(_discoveryWindow);
    } finally {
      await listenSub?.cancel();
      socket?.close();
    }

    // Merge in any peers seen via announce packets (e.g. Android devices that
    // broadcast announces to the responder socket rather than replying to
    // discover packets directly). Only include entries that are fresh — older
    // than 6× the announce interval (15 s) means the device has gone silent.
    final now = DateTime.now();
    final announceExpiry = _announceInterval * 6;
    for (final entry in _announcedPeers.entries) {
      final seenAt = _announcedPeersSeenAt[entry.key];
      if (seenAt == null || now.difference(seenAt) > announceExpiry) continue;
      discoveredById.putIfAbsent(entry.key, () => entry.value);
    }
    // Remove stale self-entry if device ID was already known
    discoveredById.remove(deviceId);

    return discoveredById.values.toList(growable: false);
  }

  String _generatePairVerificationCode() {
    final value = math.Random.secure().nextInt(1000000);
    return value.toString().padLeft(6, '0');
  }

  Future<SecretKey> _derivePairCodeProofKey({
    required String requestId,
    required String remoteStaticPubB64,
  }) async {
    final remote = remoteStaticPubB64.trim();
    if (remote.isEmpty) {
      throw const DeviceSyncException(
        'Pair verification key is unavailable. Update UniKM on both devices and retry.',
      );
    }

    final localStaticPair = await _getOrGenerateStaticKeyPair();
    final remoteStaticPub = SyncCrypto.publicKeyFromBase64(remote);
    final shared = await _x25519.sharedSecretKey(
      keyPair: localStaticPair,
      remotePublicKey: remoteStaticPub,
    );
    final sharedBytes = await shared.extractBytes();
    return _pairProofHkdf.deriveKey(
      secretKey: SecretKey(sharedBytes),
      nonce: utf8.encode('pair-code-proof|$requestId'),
      info: utf8.encode('unikm_pair_code_proof_v1'),
    );
  }

  Future<String> _encryptPairCodeProof({
    required String requestId,
    required String remoteStaticPubB64,
    required String verificationCode,
  }) async {
    final key = await _derivePairCodeProofKey(
      requestId: requestId,
      remoteStaticPubB64: remoteStaticPubB64,
    );
    return SyncCrypto.encrypt(verificationCode, key);
  }

  Future<String> _decryptPairCodeProof({
    required String requestId,
    required String remoteStaticPubB64,
    required String encryptedCodeProof,
  }) async {
    final key = await _derivePairCodeProofKey(
      requestId: requestId,
      remoteStaticPubB64: remoteStaticPubB64,
    );
    return SyncCrypto.decrypt(encryptedCodeProof, key);
  }

  List<PendingPairRequest> getPendingPairRequests() {
    _evictExpiredPairRequests();
    return _pendingPairRequests.values
        .where((e) => !e.receiverAccepted)
        .map(
          (e) => PendingPairRequest(
            requestId: e.requestId,
            peer: e.peer,
            requestedAt: e.createdAt,
          ),
        )
        .toList(growable: false)
      ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
  }

  Future<TrustedSyncPeer> requestPairing(
    DiscoveredSyncPeer peer, {
    void Function(String verificationCode)? showVerificationCode,
    Future<void>? onUserCancel,
  }) async {
    final enabled =
        (ref.read(settingsProvider)[SettingsKeys.syncEnabled] as bool?) ??
        DefaultSettings.syncEnabled;
    if (!enabled) {
      throw const DeviceSyncException('Enable device sync before pairing.');
    }

    final localDeviceId = await _ensureDeviceId();
    await ensureDiscoveryResponder(deviceId: localDeviceId);

    final requestId = _uuid.v4();
    final localStaticPair = await _getOrGenerateStaticKeyPair();
    final localStaticPub = await localStaticPair.extractPublicKey();
    final localStaticPubB64 = base64.encode(localStaticPub.bytes);
    final verificationCode = _generatePairVerificationCode();

    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
      reusePort: false,
    );

    final pendingDecisionResponses = Queue<_PairDecisionResponse>();
    Completer<void>? decisionAvailable;

    Future<_PairDecisionResponse> waitForReceiverDecision() async {
      if (pendingDecisionResponses.isNotEmpty) {
        return pendingDecisionResponses.removeFirst();
      }

      final signal = Completer<void>();
      decisionAvailable = signal;

      if (pendingDecisionResponses.isNotEmpty) {
        decisionAvailable = null;
        return pendingDecisionResponses.removeFirst();
      }

      await signal.future;
      decisionAvailable = null;

      if (pendingDecisionResponses.isEmpty) {
        return waitForReceiverDecision();
      }
      return pendingDecisionResponses.removeFirst();
    }

    final commitAckCompleter = Completer<_PairAckResponse>();
    final finalizeAckCompleter = Completer<_PairAckResponse>();

    StreamSubscription<RawSocketEvent>? sub;
    sub = socket.listen((event) {
      if (event != RawSocketEvent.read) {
        return;
      }
      final datagram = socket.receive();
      if (datagram == null) {
        return;
      }

      final payload = _decodePacket(datagram.data);
      if (payload == null) {
        return;
      }

      final incomingRequestId = (payload['requestId'] as String?)?.trim();
      if (incomingRequestId != requestId) {
        return;
      }

      final from = payload['from'];
      if (from is! Map) {
        return;
      }
      final fromMap = Map<String, dynamic>.from(from);
      final fromId = (fromMap['id'] as String?)?.trim() ?? '';
      if (fromId != peer.id) {
        return;
      }
      if (datagram.address.address != peer.host) {
        return;
      }

      final type = payload['type'];
      if (type == _pairReceiverDecisionType) {
        pendingDecisionResponses.add(
          _PairDecisionResponse(
            accepted: payload['accepted'] == true,
            remoteStaticPubB64: (payload['spub'] as String?)?.trim(),
            encryptedCodeProof: (payload['proof'] as String?)?.trim(),
            declineReason: (payload['reason'] as String?)?.trim(),
          ),
        );
        if (decisionAvailable != null && !decisionAvailable!.isCompleted) {
          decisionAvailable!.complete();
        }
        decisionAvailable = null;
        return;
      }
      if (type == _pairCommitAckType && !commitAckCompleter.isCompleted) {
        commitAckCompleter.complete(
          _PairAckResponse(
            accepted: payload['accepted'] == true,
            remoteStaticPubB64: (payload['spub'] as String?)?.trim(),
          ),
        );
        return;
      }
      if (type == _pairFinalizeAckType && !finalizeAckCompleter.isCompleted) {
        finalizeAckCompleter.complete(
          _PairAckResponse(
            accepted: payload['accepted'] == true,
            remoteStaticPubB64: (payload['spub'] as String?)?.trim(),
          ),
        );
      }
    });
    try {
      final pairRequestPacket = utf8.encode(
        jsonEncode({
          'type': _pairRequestType,
          'protocol': _protocolVersion,
          'requestId': requestId,
          'replyPort': socket.port,
          'spub': localStaticPubB64,
          'proofAlg': _pairCodeProofAlg,
          'from': _localIdentityMap(localDeviceId),
        }),
      );
      socket.send(pairRequestPacket, InternetAddress(peer.host), peer.port);

      // Show code to sender now that request has been sent
      showVerificationCode?.call(verificationCode);

      // Keep waiting for receiver decisions until code verification succeeds,
      // the sender cancels, or the request is declined/times out.
      final Future<Object?> cancelFuture =
          onUserCancel ?? Future<void>.delayed(const Duration(days: 365));
      var remoteDecisionSpub = '';

      while (true) {
        final decision =
            (await Future.any<Object?>([
                  waitForReceiverDecision().timeout(
                    _pairRequestTimeout,
                    onTimeout: () => const _PairDecisionResponse(
                      accepted: false,
                      declineReason: 'timeout',
                    ),
                  ),
                  cancelFuture.then(
                    (_) => const _PairDecisionResponse(
                      accepted: false,
                      declineReason: 'user_cancel',
                    ),
                  ),
                ]))
                as _PairDecisionResponse;

        if (!decision.accepted) {
          await _sendPairCancel(
            peer: peer,
            requestId: requestId,
            localDeviceId: localDeviceId,
          );
          final reason = (decision.declineReason ?? '').toLowerCase();
          if (reason.contains('user_cancel') || reason.contains('cancel')) {
            throw const DeviceSyncException('Pairing was canceled.');
          }
          if (reason.contains('timeout')) {
            throw const DeviceSyncException(
              'Pairing request timed out after 30 seconds.',
            );
          }
          throw const DeviceSyncException('Pairing request was declined.');
        }

        final incomingRemoteSpub = (decision.remoteStaticPubB64 ?? '').trim();
        if (incomingRemoteSpub.isEmpty) {
          await _sendPairCancel(
            peer: peer,
            requestId: requestId,
            localDeviceId: localDeviceId,
          );
          throw const DeviceSyncException(
            'Remote device did not provide a pairing verification key. Update UniKM on both devices and retry.',
          );
        }

        if (remoteDecisionSpub.isEmpty) {
          remoteDecisionSpub = incomingRemoteSpub;
        } else if (incomingRemoteSpub != remoteDecisionSpub) {
          await _sendPairCancel(
            peer: peer,
            requestId: requestId,
            localDeviceId: localDeviceId,
          );
          throw const DeviceSyncException(
            'Remote pairing identity changed during code verification. Retry pairing.',
          );
        }

        final encryptedProof = (decision.encryptedCodeProof ?? '').trim();
        if (encryptedProof.isEmpty) {
          await _sendPairCancel(
            peer: peer,
            requestId: requestId,
            localDeviceId: localDeviceId,
          );
          throw const DeviceSyncException(
            'Remote device did not return a pairing verification proof.',
          );
        }

        final enteredCode = await _decryptPairCodeProof(
          requestId: requestId,
          remoteStaticPubB64: remoteDecisionSpub,
          encryptedCodeProof: encryptedProof,
        );
        if (enteredCode.trim() != verificationCode) {
          // Let the receiver submit the code again without tearing down the
          // entire pairing session, and explicitly notify them to clear/retry.
          await _sendPairCodeRejected(
            peer: peer,
            requestId: requestId,
            localDeviceId: localDeviceId,
          );
          continue;
        }

        break;
      }

      final pairCommitPacket = utf8.encode(
        jsonEncode({
          'type': _pairCommitType,
          'protocol': _protocolVersion,
          'requestId': requestId,
          'replyPort': socket.port,
          'spub': localStaticPubB64,
          'ok': true,
          'from': _localIdentityMap(localDeviceId),
        }),
      );
      socket.send(pairCommitPacket, InternetAddress(peer.host), peer.port);

      final commitAck = await commitAckCompleter.future.timeout(
        _pairCommitTimeout,
        onTimeout: () => const _PairAckResponse(accepted: false),
      );
      if (!commitAck.accepted) {
        await _sendPairCancel(
          peer: peer,
          requestId: requestId,
          localDeviceId: localDeviceId,
        );
        throw const DeviceSyncException(
          'Pairing handshake timed out before receiver confirmation.',
        );
      }

      final remoteCommitAckSpub = (commitAck.remoteStaticPubB64 ?? '').trim();
      if (remoteCommitAckSpub.isNotEmpty &&
          remoteCommitAckSpub != remoteDecisionSpub) {
        await _sendPairCancel(
          peer: peer,
          requestId: requestId,
          localDeviceId: localDeviceId,
        );
        throw const DeviceSyncException(
          'Remote pairing identity changed during confirmation. Retry pairing.',
        );
      }

      final pairFinalizePacket = utf8.encode(
        jsonEncode({
          'type': _pairFinalizeType,
          'protocol': _protocolVersion,
          'requestId': requestId,
          'replyPort': socket.port,
          'spub': localStaticPubB64,
          'ok': true,
          'from': _localIdentityMap(localDeviceId),
        }),
      );
      socket.send(pairFinalizePacket, InternetAddress(peer.host), peer.port);

      final finalizeAck = await finalizeAckCompleter.future.timeout(
        _pairFinalizeTimeout,
        onTimeout: () => const _PairAckResponse(accepted: false),
      );
      if (!finalizeAck.accepted) {
        await _sendPairCancel(
          peer: peer,
          requestId: requestId,
          localDeviceId: localDeviceId,
        );
        await _sendUntrustPacket(
          TrustedSyncPeer(
            id: peer.id,
            name: peer.name,
            host: peer.host,
            port: peer.port,
            deviceType: peer.deviceType,
            fingerprint: remoteDecisionSpub,
          ),
          remoteFingerprint: remoteDecisionSpub,
        );
        throw const DeviceSyncException(
          'Pairing handshake timed out waiting for final receiver OK.',
        );
      }

      final remoteFinalizeSpub = (finalizeAck.remoteStaticPubB64 ?? '').trim();
      if (remoteFinalizeSpub.isNotEmpty &&
          remoteFinalizeSpub != remoteDecisionSpub) {
        await _sendPairCancel(
          peer: peer,
          requestId: requestId,
          localDeviceId: localDeviceId,
        );
        throw const DeviceSyncException(
          'Remote pairing identity changed during final confirmation. Retry pairing.',
        );
      }

      return _upsertTrustedPeer(
        DiscoveredSyncPeer(
          id: peer.id,
          name: peer.name,
          host: peer.host,
          port: peer.port,
          deviceType: peer.deviceType,
        ),
        fingerprint: remoteDecisionSpub,
      );
    } finally {
      await sub.cancel();
      socket.close();
    }
  }

  Future<void> respondToPairRequest({
    required String requestId,
    required bool accept,
    String? enteredVerificationCode,
  }) async {
    _evictExpiredPairRequests();
    final request = _pendingPairRequests[requestId];
    if (request == null) {
      throw const DeviceSyncException('Pair request no longer available.');
    }

    String? localStaticPubB64;
    String? encryptedCodeProof;
    if (accept) {
      final providedCode = (enteredVerificationCode ?? '').trim();
      if (providedCode.isEmpty) {
        throw const DeviceSyncException(
          'Enter the 6-digit verification code shown on the sending device.',
        );
      }
      if (!RegExp(r'^\d{6}$').hasMatch(providedCode)) {
        throw const DeviceSyncException(
          'Verification code must be a 6-digit number.',
        );
      }

      final initiatorSpub = (request.initiatorStaticPubB64 ?? '').trim();
      if (initiatorSpub.isEmpty) {
        throw const DeviceSyncException(
          'Remote pairing verification key is unavailable. Update UniKM on both devices and retry.',
        );
      }

      localStaticPubB64 = (request.receiverStaticPubB64 ?? '').trim();
      if (localStaticPubB64.isEmpty) {
        final localStaticPair = await _getOrGenerateStaticKeyPair();
        final localStaticPub = await localStaticPair.extractPublicKey();
        localStaticPubB64 = base64.encode(localStaticPub.bytes);
      }

      encryptedCodeProof = await _encryptPairCodeProof(
        requestId: requestId,
        remoteStaticPubB64: initiatorSpub,
        verificationCode: providedCode,
      );
    }

    final localDeviceId = await _ensureDeviceId();
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
      reusePort: false,
    );

    try {
      final decisionPacket = utf8.encode(
        jsonEncode({
          'type': _pairReceiverDecisionType,
          'protocol': _protocolVersion,
          'requestId': requestId,
          'accepted': accept,
          if (accept && localStaticPubB64 != null) 'spub': localStaticPubB64,
          if (accept && encryptedCodeProof != null) 'proof': encryptedCodeProof,
          if (accept) 'proofAlg': _pairCodeProofAlg,
          if (!accept) 'reason': 'declined',
          'from': _localIdentityMap(localDeviceId),
        }),
      );

      socket.send(decisionPacket, request.sourceAddress, request.replyPort);
    } finally {
      socket.close();
    }

    if (accept) {
      _pendingPairRequests[requestId] = request.copyWith(
        receiverAccepted: true,
        receiverStaticPubB64: localStaticPubB64,
      );
      return;
    }

    _pendingPairRequests.remove(requestId);
  }

  Future<void> removeTrustedPeer(
    String peerId, {
    bool notifyRemote = true,
  }) async {
    final trusted = decodeTrustedPeers(
      ref.read(settingsProvider)[SettingsKeys.syncTrustedPeersJson]
              as String? ??
          DefaultSettings.syncTrustedPeersJson,
    );

    // Look up peer info before removing so we can notify them.
    TrustedSyncPeer? target;
    if (notifyRemote) {
      try {
        target = trusted.firstWhere((p) => p.id == peerId);
      } catch (_) {
        target = null;
      }
    }

    // Notify the removed peer before deleting local trust metadata so auth can
    // still be computed with the pinned fingerprint.
    if (notifyRemote && target != null && !kIsWeb) {
      await _sendUntrustPacket(target, remoteFingerprint: target.fingerprint);
    }

    final next = trusted.where((p) => p.id != peerId).toList(growable: false);
    await _setSetting(
      SettingsKeys.syncTrustedPeersJson,
      encodeTrustedPeers(next),
    );

    final currentLast =
        (ref.read(settingsProvider)[SettingsKeys.syncLastTrustedPeerId]
                as String?)
            ?.trim();
    if (currentLast == peerId) {
      await _setSetting(SettingsKeys.syncLastTrustedPeerId, '');
    }
  }

  Future<void> _sendUntrustPacket(
    TrustedSyncPeer peer, {
    String? remoteFingerprint,
  }) async {
    final localId =
        (ref.read(settingsProvider)[SettingsKeys.syncDeviceId] as String?) ??
        '';
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      final packetPayload = await _attachControlAuthForFingerprint(
        payload: {
          'type': _untrustType,
          'protocol': _protocolVersion,
          'from': _localIdentityMap(localId),
        },
        remoteStaticPubB64: remoteFingerprint,
      );
      final packet = utf8.encode(jsonEncode(packetPayload));
      socket.send(packet, InternetAddress(peer.host), peer.port);
    } finally {
      socket.close();
    }
  }

  Future<void> setEnabled(bool value) async {
    await _setSetting(SettingsKeys.syncEnabled, value);
    if (value) {
      // Refresh device name when enabling sync
      await refreshDeviceName();
      final deviceId = await _ensureDeviceId();
      await ensureDiscoveryResponder(deviceId: deviceId);
      _startAnnounceLoop(deviceId);
    } else {
      await stopDiscoveryResponder();
    }
  }

  String _normalizeWindowsPath(String value) {
    return p.normalize(value).replaceAll('/', r'\').toLowerCase().trim();
  }

  Future<WindowsFirewallCheckResult?> checkWindowsFirewallAccess() async {
    if (kIsWeb || !Platform.isWindows) {
      return null;
    }

    final executablePath = _normalizeWindowsPath(Platform.resolvedExecutable);
    try {
      final result = await Process.run('netsh.exe', [
        'advfirewall',
        'firewall',
        'show',
        'rule',
        'name=all',
        'verbose',
      ], runInShell: true);

      final output = (result.stdout as String).trim();
      if (output.isEmpty) {
        return const WindowsFirewallCheckResult(available: false);
      }

      var hasPrivateAllow = false;
      var hasPublicAllow = false;

      var currentProgram = '';
      var currentProfiles = '';
      var currentAction = '';

      void commitRule() {
        if (currentProgram == executablePath && currentAction == 'allow') {
          if (currentProfiles.contains('private') ||
              currentProfiles.contains('all')) {
            hasPrivateAllow = true;
          }
          if (currentProfiles.contains('public') ||
              currentProfiles.contains('all')) {
            hasPublicAllow = true;
          }
        }

        currentProgram = '';
        currentProfiles = '';
        currentAction = '';
      }

      for (final rawLine in const LineSplitter().convert(output)) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;

        final lower = line.toLowerCase();
        if (lower.startsWith('rule name:')) {
          commitRule();
          continue;
        }

        final delimiter = line.indexOf(':');
        if (delimiter <= 0) {
          continue;
        }

        final value = line.substring(delimiter + 1).trim();
        if (lower.startsWith('program:')) {
          currentProgram = _normalizeWindowsPath(value);
          continue;
        }

        if (lower.startsWith('profiles:') || lower.startsWith('profile:')) {
          currentProfiles = value.toLowerCase();
          continue;
        }

        if (lower.startsWith('action:')) {
          final action = value.toLowerCase();
          currentAction = action.contains('allow') ? 'allow' : action;
        }
      }

      commitRule();

      return WindowsFirewallCheckResult(
        available: true,
        hasPrivateAllow: hasPrivateAllow,
        hasPublicAllow: hasPublicAllow,
      );
    } catch (_) {
      return const WindowsFirewallCheckResult(available: false);
    }
  }

  Future<bool> grantWindowsFirewallAccess() async {
    if (kIsWeb || !Platform.isWindows) {
      return false;
    }

    final appPath = Platform.resolvedExecutable;
    final scriptPath = p.join(
      Directory.systemTemp.path,
      'unikm_firewall_${DateTime.now().millisecondsSinceEpoch}.cmd',
    );
    final scriptFile = File(scriptPath);

    try {
      final lines = <String>[
        '@echo off',
        'netsh advfirewall firewall delete rule name="$_firewallAppRuleName"',
        'netsh advfirewall firewall delete rule name="$_legacyUdpRuleName"',
        'netsh advfirewall firewall delete rule name="$_legacyTcpRuleName"',
        'netsh firewall delete allowedprogram program="$appPath"',
        'netsh advfirewall firewall add rule name="$_firewallAppRuleName" dir=in action=allow enable=yes profile=private,public program="$appPath" remoteip=LocalSubnet',
        'exit /b %ERRORLEVEL%',
      ];
      await scriptFile.writeAsString(lines.join('\r\n'), flush: true);

      final quotedScriptPath = scriptPath.replaceAll("'", "''");
      final elevateCommand =
          "\$p = Start-Process -FilePath '$quotedScriptPath' -Verb RunAs -Wait -PassThru; "
          'exit \$p.ExitCode';

      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        elevateCommand,
      ], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    } finally {
      try {
        if (await scriptFile.exists()) {
          await scriptFile.delete();
        }
      } catch (_) {}
    }
  }

  Future<bool> openWindowsFirewallAllowedApps() async {
    if (kIsWeb || !Platform.isWindows) {
      return false;
    }

    try {
      await Process.start('control.exe', [
        '/name',
        'Microsoft.WindowsFirewall',
        '/page',
        'pageConfigureApps',
      ], runInShell: true);
      return true;
    } catch (_) {
      try {
        await Process.start('control.exe', ['firewall.cpl'], runInShell: true);
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  Future<bool> openWindowsFirewallAdvancedSettings() async {
    if (kIsWeb || !Platform.isWindows) {
      return false;
    }

    try {
      await Process.start('wf.msc', const [], runInShell: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setAutoOnStartup(bool value) async {
    await _setSetting(SettingsKeys.syncAutoOnStartup, value);
  }

  Future<void> markSyncCompleted({
    String? peerId,
    int? authoritativeTimestampMillis,
  }) async {
    final db = ref.read(databaseProvider);
    final timestampMillis =
        authoritativeTimestampMillis ?? DateTime.now().millisecondsSinceEpoch;
    if (db != null) {
      await db.setSyncDbTimestampMillis(timestampMillis);
    }
    await _setSetting(
      SettingsKeys.syncLastSyncAtIso,
      DateTime.fromMillisecondsSinceEpoch(timestampMillis).toIso8601String(),
    );
    await _setSetting(SettingsKeys.syncDbTimestampMillis, timestampMillis);
    if (peerId != null && peerId.isNotEmpty) {
      await _setSetting(SettingsKeys.syncLastTrustedPeerId, peerId);
    }
  }

  bool _isValidDatabaseFileName(String fileName) {
    final trimmed = fileName.trim();
    if (trimmed.isEmpty || trimmed == '.' || trimmed == '..') {
      return false;
    }
    if (trimmed != p.basename(trimmed)) {
      return false;
    }
    if (!kIsWeb && Platform.isWindows) {
      if (RegExp(r'[<>:"/\\|?*]').hasMatch(trimmed)) {
        return false;
      }
    }
    return true;
  }

  TrustedSyncPeer _mergePeerFromDiscovery({
    required TrustedSyncPeer trustedPeer,
    required DiscoveredSyncPeer discoveredPeer,
  }) {
    final mergedType = discoveredPeer.deviceType == SyncDeviceType.unknown
        ? trustedPeer.deviceType
        : discoveredPeer.deviceType;
    return trustedPeer.copyWith(
      name: _normalizeDeviceName(discoveredPeer.name, fallbackType: mergedType),
      host: discoveredPeer.host,
      port: discoveredPeer.port,
      deviceType: mergedType,
      lastSeenAtIso: DateTime.now().toIso8601String(),
    );
  }

  bool _peerEndpointChanged(TrustedSyncPeer a, TrustedSyncPeer b) {
    return a.host != b.host ||
        a.port != b.port ||
        a.name != b.name ||
        a.deviceType != b.deviceType;
  }

  DiscoveredSyncPeer? _freshAnnouncedPeerById(String peerId) {
    final announced = _announcedPeers[peerId];
    final seenAt = _announcedPeersSeenAt[peerId];
    if (announced == null || seenAt == null) {
      return null;
    }
    final announceExpiry = _announceInterval * 6;
    if (DateTime.now().difference(seenAt) > announceExpiry) {
      return null;
    }
    return announced;
  }

  Future<TrustedSyncPeer> _resolveTrustedPeerEndpoint(
    TrustedSyncPeer peer,
  ) async {
    final announcedPeer = _freshAnnouncedPeerById(peer.id);
    if (announcedPeer == null) {
      return peer;
    }

    final refreshed = _mergePeerFromDiscovery(
      trustedPeer: peer,
      discoveredPeer: announcedPeer,
    );
    if (!_peerEndpointChanged(peer, refreshed)) {
      return peer;
    }

    final probe = await _pingPeer(refreshed);
    if (!probe.reachable || !probe.remoteTrusted) {
      return peer;
    }

    return _upsertTrustedPeer(
      DiscoveredSyncPeer(
        id: refreshed.id,
        name: refreshed.name,
        host: refreshed.host,
        port: refreshed.port,
        deviceType: refreshed.deviceType,
      ),
      fingerprint: peer.fingerprint,
    );
  }

  Future<TrustedSyncPeer?> _rediscoverTrustedPeerEndpoint(
    TrustedSyncPeer peer,
  ) async {
    final discoveredPeers = await discoverPeers();
    DiscoveredSyncPeer? matched;
    for (final candidate in discoveredPeers) {
      if (candidate.id == peer.id) {
        matched = candidate;
        break;
      }
    }
    if (matched == null) {
      return null;
    }

    final refreshed = _mergePeerFromDiscovery(
      trustedPeer: peer,
      discoveredPeer: matched,
    );
    if (!_peerEndpointChanged(peer, refreshed)) {
      return peer;
    }

    final probe = await _pingPeer(refreshed);
    if (!probe.reachable || !probe.remoteTrusted) {
      return null;
    }

    return _upsertTrustedPeer(
      DiscoveredSyncPeer(
        id: refreshed.id,
        name: refreshed.name,
        host: refreshed.host,
        port: refreshed.port,
        deviceType: refreshed.deviceType,
      ),
      fingerprint: peer.fingerprint,
    );
  }

  Future<void> _alignLocalDatabaseToRemoteNameForPull({
    required TrustedSyncPeer targetPeer,
    required String? remoteDbName,
  }) async {
    final normalizedRemoteName = (remoteDbName ?? '').trim();
    if (normalizedRemoteName.isEmpty) {
      return;
    }

    final settings = ref.read(settingsProvider);
    final currentBasePath =
        (settings[SettingsKeys.databasePath] as String?)?.trim() ?? '';
    if (currentBasePath.isEmpty) {
      return;
    }

    final currentName = p.basename(currentBasePath);
    if (currentName == normalizedRemoteName) {
      return;
    }

    if (!_isValidDatabaseFileName(normalizedRemoteName)) {
      throw DeviceSyncException(
        'Remote database file "$normalizedRemoteName" is not a valid filename on this device.',
      );
    }

    final switchCallback = ref.read(databaseSwitchCallbackProvider);
    if (switchCallback == null) {
      throw const DeviceSyncException(
        'Unable to switch database file automatically right now. Please retry.',
      );
    }

    final targetBasePath = p.join(
      p.dirname(currentBasePath),
      normalizedRemoteName,
    );

    _eventController.add(
      SyncTransferActivityEvent(
        active: true,
        message:
            '[${targetPeer.name}] Switching local database to "$normalizedRemoteName" to match remote...',
      ),
    );

    final targetFile = File(targetBasePath);
    try {
      if (targetFile.existsSync()) {
        await switchCallback(OpenDatabaseRequest(targetBasePath));
      } else {
        await switchCallback(
          CreateDatabaseRequest(path: targetBasePath, encrypted: false),
        );
      }
    } catch (error) {
      throw DeviceSyncException(
        'Could not switch to remote database file "$normalizedRemoteName": $error',
      );
    }
  }

  Future<void> _ensureExpectedRemoteDatabaseForPush({
    required TrustedSyncPeer targetPeer,
    required String expectedRemoteDbName,
  }) async {
    final normalizedExpected = expectedRemoteDbName.trim();
    if (normalizedExpected.isEmpty) {
      return;
    }

    final recheck = await _pingPeer(targetPeer);
    if (!recheck.reachable) {
      throw DeviceSyncException(
        'Could not re-verify ${targetPeer.name} before sending data.',
      );
    }

    final currentRemoteDbName = (recheck.remoteDbName ?? '').trim();
    if (currentRemoteDbName != normalizedExpected) {
      throw DeviceSyncException(
        '[${targetPeer.name}] Active remote database changed from '
        '"$normalizedExpected" to "$currentRemoteDbName". '
        'Sync cancelled before transfer.',
      );
    }
  }

  Future<void> performManualSync({
    String? peerId,
    bool isPull = false,
    bool fullScan = false,
  }) async {
    final settings = ref.read(settingsProvider);
    final enabled =
        (settings[SettingsKeys.syncEnabled] as bool?) ??
        DefaultSettings.syncEnabled;
    if (!enabled) {
      throw const DeviceSyncException('Device sync is disabled.');
    }

    final trustedPeers = decodeTrustedPeers(
      settings[SettingsKeys.syncTrustedPeersJson] as String? ??
          DefaultSettings.syncTrustedPeersJson,
    );
    if (trustedPeers.isEmpty) {
      throw const DeviceSyncException('No trusted devices available for sync.');
    }

    var targetPeer = _resolveTargetPeer(
      trustedPeers: trustedPeers,
      explicitPeerId: peerId,
      fallbackPeerId: (settings[SettingsKeys.syncLastTrustedPeerId] as String?)
          ?.trim(),
    );
    if (targetPeer == null) {
      throw const DeviceSyncException('Selected sync peer was not found.');
    }

    targetPeer = await _resolveTrustedPeerEndpoint(targetPeer);

    final targetFingerprint = (targetPeer.fingerprint ?? '').trim();
    if (targetFingerprint.isEmpty) {
      throw DeviceSyncException(
        'Paired key fingerprint is missing for ${targetPeer.name}. '
        'Remove and re-pair this device before syncing.',
      );
    }

    var ping = await _pingPeer(targetPeer);
    if (!ping.reachable) {
      _eventController.add(
        SyncTransferActivityEvent(
          active: true,
          message:
              '[${targetPeer.name}] Saved address is unreachable. Refreshing peer address...',
        ),
      );
      final rediscovered = await _rediscoverTrustedPeerEndpoint(targetPeer);
      if (rediscovered != null) {
        targetPeer = rediscovered;
        ping = await _pingPeer(targetPeer);
      }
    }

    if (!ping.reachable) {
      throw DeviceSyncException(
        'Failed to reach ${targetPeer.name} at ${targetPeer.host}:${targetPeer.port}.',
      );
    }
    if (!ping.remoteTrusted) {
      throw const DeviceSyncException(
        'Remote device has not completed pairing confirmation.',
      );
    }

    // Backup-first safety guard — labeled so users can identify it on restore.
    _eventController.add(
      SyncTransferActivityEvent(
        active: true,
        message: '[${targetPeer.name}] Step 1/4: Creating pre-sync backup...',
      ),
    );
    await ref.read(backupServiceProvider).createBackup(label: 'pre-sync');

    // If this is a pull and peer DB name differs, switch/create a local DB
    // with the remote filename before applying incoming changes.
    if (isPull) {
      await _alignLocalDatabaseToRemoteNameForPull(
        targetPeer: targetPeer,
        remoteDbName: ping.remoteDbName,
      );
    }

    // Needed for the encrypted handshake on both pull and push paths.
    final localDeviceId = await _ensureDeviceId();
    final localState = await _getLocalSyncStateForPeer(targetPeer.id);
    final localRevision = localState['localRevision'] as int? ?? 0;
    final localKnownRemoteRevision =
        localState['peerKnownRevision'] as int? ?? 0;
    final localKnownRemoteSyncAtMillis =
        localState['peerKnownSyncAt'] as int? ?? 0;
    final remoteKnownLocalRevision = ping.remoteKnownLocalRevision;
    final remoteKnownLocalSyncAtMillis = ping.remoteKnownLocalSyncAtMillis;
    final expectedReceiverDbName = (ping.remoteDbName ?? '').trim();

    // ── Pull mode: ask the remote to send us their database ──────────────────
    if (isPull) {
      Socket tcpSocketPull;
      try {
        _eventController.add(
          SyncTransferActivityEvent(
            active: true,
            message:
                '[${targetPeer.name}] Step 2/4: Connecting to pull data...',
          ),
        );
        tcpSocketPull = await Socket.connect(
          targetPeer.host,
          _syncDataTcpPort,
        ).timeout(const Duration(seconds: 10));
      } catch (_) {
        throw DeviceSyncException(
          'Could not connect to ${targetPeer.name}. '
          'Make sure the remote device has sync enabled.',
        );
      }

      try {
        _eventController.add(
          SyncTransferActivityEvent(
            active: true,
            message:
                '[${targetPeer.name}] Step 3/4: Requesting remote database...',
          ),
        );

        // ── Encrypted handshake ──────────────────────────────────────────
        final (:sessionKey, :lineIter) = await _performClientHandshake(
          tcpSocketPull,
          targetPeer,
          localDeviceId,
        );

        _eventController.add(
          SyncTransferActivityEvent(
            active: true,
            message:
                '[${targetPeer.name}] Step 4/4: Waiting for remote data...',
          ),
        );

        // Send encrypted pull request.
        final pullRequest = jsonEncode({
          'pullRequest': true,
          'requestFullDataset': fullScan,
          'syncRevisionId': _currentSyncCode(),
          'deviceName': _currentDeviceName(),
          'requestingPeerId': localDeviceId,
          'knownRemoteRevision': localKnownRemoteRevision,
          'knownRemoteSyncAt': localKnownRemoteSyncAtMillis,
        });
        tcpSocketPull.add(
          utf8.encode('${await SyncCrypto.encrypt(pullRequest, sessionKey)}\n'),
        );
        await tcpSocketPull.flush();

        // Read and decrypt the single data line from the server.
        const perLineTimeout = Duration(seconds: 20);
        final overallDeadline = DateTime.now().add(const Duration(minutes: 3));
        String? dataLine;
        try {
          while (await lineIter.moveNext().timeout(
            perLineTimeout,
            onTimeout: () => false,
          )) {
            if (DateTime.now().isAfter(overallDeadline)) {
              throw const DeviceSyncException(
                'Pull timed out — 3-minute limit exceeded.',
              );
            }
            final trimmed = lineIter.current.trim();
            if (trimmed.isEmpty) continue;
            dataLine = trimmed;
            break;
          }
        } finally {
          await lineIter.cancel();
        }

        if (dataLine == null || dataLine.isEmpty) {
          throw const DeviceSyncException(
            'Remote device did not send any data.',
          );
        }

        final decryptedData = await SyncCrypto.decrypt(dataLine, sessionKey);
        final remotePayload =
            jsonDecode(decryptedData) as Map<String, dynamic>?;
        if (remotePayload == null) {
          throw const DeviceSyncException('Remote data could not be parsed.');
        }

        final incomingSteamCache = remotePayload['steamCache'];
        if (incomingSteamCache is Map) {
          await mergeSteamCacheSnapshotFromSync(
            Map<String, dynamic>.from(incomingSteamCache),
          );
        }

        final gamesRaw = remotePayload['games'];
        final games = gamesRaw is List
            ? gamesRaw
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList(growable: false)
            : const <Map<String, dynamic>>[];
        final tombstonesRaw = remotePayload['tombstones'];
        final tombstones = tombstonesRaw is List
            ? tombstonesRaw
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList(growable: false)
            : const <Map<String, dynamic>>[];
        final remoteFullDataset = remotePayload['fullDataset'] == true;

        _eventController.add(
          SyncTransferActivityEvent(
            active: true,
            message: remoteFullDataset
                ? '[${targetPeer.name}] Applying ${games.length} records and ${tombstones.length} deletions...'
                : '[${targetPeer.name}] Applying ${games.length} changed records and ${tombstones.length} deletions...',
          ),
        );

        final result = await _codec.applyDeltaPayload(
          games,
          tombstones: tombstones,
          lastSyncAt: localKnownRemoteSyncAtMillis <= 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  localKnownRemoteSyncAtMillis,
                ),
        );

        // Adopt the remote's revision ID.
        final remoteRevisionId =
            (remotePayload['syncRevisionId'] as String?)?.trim() ?? '';
        if (remoteRevisionId.isNotEmpty) {
          await _setSetting(SettingsKeys.syncDbRevisionId, remoteRevisionId);
        }
        final remoteDbTimestampMillis =
            (remotePayload['dbTimestampMillis'] as num?)?.toInt() ?? 0;
        if (remoteDbTimestampMillis > 0) {
          final dbMeta = ref.read(databaseProvider);
          if (dbMeta != null) {
            await dbMeta.setSyncDbTimestampMillis(remoteDbTimestampMillis);
          }
          await _setSetting(
            SettingsKeys.syncDbTimestampMillis,
            remoteDbTimestampMillis,
          );
        }
        final dbAfterPull = ref.read(databaseProvider);
        if (dbAfterPull != null) {
          await dbAfterPull.savePeerSyncCheckpoint(
            peerId: targetPeer.id,
            lastRevision:
                (remotePayload['localRevision'] as num?)?.toInt() ??
                ping.remoteRevision,
            lastSyncAt: DateTime.fromMillisecondsSinceEpoch(
              remoteDbTimestampMillis > 0
                  ? remoteDbTimestampMillis
                  : DateTime.now().millisecondsSinceEpoch,
            ),
            remoteRevisionId: remoteRevisionId,
          );
        }
        await markSyncCompleted(
          peerId: targetPeer.id,
          authoritativeTimestampMillis: remoteDbTimestampMillis > 0
              ? remoteDbTimestampMillis
              : null,
        );

        _eventController.add(SyncDataAppliedEvent(result));
        _eventController.add(const SyncTransferActivityEvent(active: false));
      } on TimeoutException {
        throw const DeviceSyncException(
          'Remote device stopped responding during pull.',
        );
      } finally {
        tcpSocketPull.destroy();
      }
      return;
    }

    // ── Push mode: serialize our database and send it to the peer ─────────
    final db = ref.read(databaseProvider);
    if (db == null) {
      throw const DeviceSyncException('Database is not available.');
    }

    final currentRevisionId = _currentSyncCode();

    _eventController.add(
      SyncTransferActivityEvent(
        active: true,
        message:
            '[${targetPeer.name}] Step 2/4: Serialising local data snapshot...',
      ),
    );
    final builtPayload = await _codec.buildDeltaPayload(
      syncRevisionId: currentRevisionId,
      deviceName: _currentDeviceName(),
      baseRevision: remoteKnownLocalRevision,
      baseSyncAtMillis: remoteKnownLocalSyncAtMillis,
      localRevision: localRevision,
      includeAllGames: fullScan,
    );
    if (expectedReceiverDbName.isNotEmpty) {
      builtPayload['expectedReceiverDbName'] = expectedReceiverDbName;
    }
    builtPayload['requestingPeerId'] = localDeviceId;
    await _ensureExpectedRemoteDatabaseForPush(
      targetPeer: targetPeer,
      expectedRemoteDbName: expectedReceiverDbName,
    );
    var lastRound = await _pushDeltaRound(
      targetPeer: targetPeer,
      localDeviceId: localDeviceId,
      builtPayload: builtPayload,
      expectedRevisionId: currentRevisionId,
      fallbackRemoteRevision: ping.remoteRevision,
    );

    var finalSyncedRevisionId = currentRevisionId;
    final firstRoundBaseSyncAt =
        (builtPayload['dbTimestampMillis'] as num?)?.toInt() ?? 0;

    final localRevisionAfterFirstRound = await db.getLocalSyncRevision();
    if (localRevisionAfterFirstRound > localRevision) {
      final followUpRevisionId = _currentSyncCode();
      final followUpPayload = await _codec.buildDeltaPayload(
        syncRevisionId: followUpRevisionId,
        deviceName: _currentDeviceName(),
        baseRevision: localRevision,
        baseSyncAtMillis: firstRoundBaseSyncAt,
        localRevision: localRevisionAfterFirstRound,
      );
      if (expectedReceiverDbName.isNotEmpty) {
        followUpPayload['expectedReceiverDbName'] = expectedReceiverDbName;
      }
      followUpPayload['requestingPeerId'] = localDeviceId;

      _eventController.add(
        SyncTransferActivityEvent(
          active: true,
          message:
              '[${targetPeer.name}] Mid-sync local edits detected. Sending follow-up delta...',
        ),
      );

      await _ensureExpectedRemoteDatabaseForPush(
        targetPeer: targetPeer,
        expectedRemoteDbName: expectedReceiverDbName,
      );

      lastRound = await _pushDeltaRound(
        targetPeer: targetPeer,
        localDeviceId: localDeviceId,
        builtPayload: followUpPayload,
        expectedRevisionId: followUpRevisionId,
        fallbackRemoteRevision: lastRound.remoteLocalRevision,
      );

      finalSyncedRevisionId = followUpRevisionId;
    }

    _eventController.add(const SyncTransferActivityEvent(active: false));

    // Re-anchor our revision ID to the one we sent.  The receiver has adopted
    // this same ID, so both devices now share an identical code and the next
    // checkSyncCode poll returns `matches = true`.  Without this, a concurrent
    // incoming sync (receiver role on the same device) could have overwritten
    // syncDbRevisionId with the remote peer's old code, creating a permanent
    // mismatch that would trigger an infinite sync loop.
    await _setSetting(SettingsKeys.syncDbRevisionId, finalSyncedRevisionId);
    await markSyncCompleted(
      peerId: targetPeer.id,
      authoritativeTimestampMillis: lastRound.confirmedTimestampMillis > 0
          ? lastRound.confirmedTimestampMillis
          : null,
    );
  }

  Future<({int confirmedTimestampMillis, int remoteLocalRevision})>
  _pushDeltaRound({
    required TrustedSyncPeer targetPeer,
    required String localDeviceId,
    required Map<String, dynamic> builtPayload,
    required String expectedRevisionId,
    required int fallbackRemoteRevision,
  }) async {
    // The local revision that was current when this payload was assembled.
    // It is the value the receiver is going to (eventually) report back as
    // its `peerKnownRevision` for us, so it is also the safe upper bound for
    // pruning any tombstones we know we just delivered to this peer.
    final localRevisionSent = await ref
        .read(databaseProvider)
        ?.getLocalSyncRevision() ??
        fallbackRemoteRevision;
    final payload = jsonEncode(builtPayload);
    final gameCount = (builtPayload['games'] as List?)?.length ?? 0;
    final deletedCount = (builtPayload['tombstones'] as List?)?.length ?? 0;
    final fullDataset = builtPayload['fullDataset'] == true;

    Socket tcpSocket;
    try {
      _eventController.add(
        SyncTransferActivityEvent(
          active: true,
          message: '[${targetPeer.name}] Connecting for data transfer...',
        ),
      );
      tcpSocket = await Socket.connect(
        targetPeer.host,
        _syncDataTcpPort,
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      throw DeviceSyncException(
        'Could not connect to ${targetPeer.name} for data transfer. '
        'Make sure the remote device has sync enabled.',
      );
    }

    _eventController.add(
      SyncTransferActivityEvent(
        active: true,
        message: fullDataset
            ? '[${targetPeer.name}] Sending $gameCount records and $deletedCount deletions...'
            : '[${targetPeer.name}] Sending $gameCount changed records and $deletedCount deletions...',
      ),
    );

    var confirmedTimestampMillis = 0;
    var remoteLocalRevision = fallbackRemoteRevision;

    try {
      final (:sessionKey, :lineIter) = await _performClientHandshake(
        tcpSocket,
        targetPeer,
        localDeviceId,
      );

      tcpSocket.add(
        utf8.encode('${await SyncCrypto.encrypt(payload, sessionKey)}\n'),
      );
      await tcpSocket.flush();

      _eventController.add(
        SyncTransferActivityEvent(
          active: true,
          message: '[${targetPeer.name}] Waiting for confirmation...',
        ),
      );

      const perLineTimeout = Duration(seconds: 15);
      final overallDeadline = DateTime.now().add(const Duration(minutes: 3));
      String? confirmationLine;
      try {
        while (await lineIter.moveNext().timeout(
          perLineTimeout,
          onTimeout: () => false,
        )) {
          if (DateTime.now().isAfter(overallDeadline)) {
            throw const DeviceSyncException(
              'Sync timed out — overall 3-minute limit exceeded.',
            );
          }
          final trimmed = lineIter.current.trim();
          if (trimmed.isEmpty) continue;
          final decrypted = await SyncCrypto.decrypt(trimmed, sessionKey);
          try {
            final probe = jsonDecode(decrypted);
            if (probe is Map<String, dynamic> && probe['keepAlive'] == true) {
              _eventController.add(
                SyncTransferActivityEvent(
                  active: true,
                  message: '[${targetPeer.name}] Remote is still processing...',
                ),
              );
              continue;
            }
          } catch (_) {}
          confirmationLine = decrypted;
          break;
        }
      } on TimeoutException {
        throw const DeviceSyncException(
          'Remote device stopped responding during sync.',
        );
      } finally {
        await lineIter.cancel();
      }

      if (confirmationLine == null || confirmationLine.isEmpty) {
        throw const DeviceSyncException(
          'Remote device did not return sync confirmation.',
        );
      }

      try {
        final responsePayload = jsonDecode(confirmationLine);
        if (responsePayload is Map<String, dynamic>) {
          final receiverApplied = responsePayload['syncApplied'] == true;
          if (!receiverApplied) {
            final errorCode =
                (responsePayload['errorCode'] as String?)?.trim() ?? '';
            final expectedDbName =
                (responsePayload['expectedReceiverDbName'] as String?)
                    ?.trim() ??
                '';
            final receiverDbName =
                (responsePayload['receiverDbName'] as String?)?.trim() ?? '';
            if (errorCode == 'receiver_db_changed') {
              throw DeviceSyncException(
                '[${targetPeer.name}] Sync cancelled because the receiver switched active database '
                'from "$expectedDbName" to "$receiverDbName" before apply. '
                'Please recheck and start sync again.',
              );
            }

            final remoteError =
                (responsePayload['error'] as String?)?.trim() ?? '';
            if (remoteError.isNotEmpty) {
              throw DeviceSyncException('[${targetPeer.name}] $remoteError');
            }

            throw const DeviceSyncException(
              'Remote device did not confirm synced state.',
            );
          }

          final confirmedRevisionId =
              (responsePayload['syncRevisionId'] as String?)?.trim() ?? '';
          if (confirmedRevisionId.isNotEmpty &&
              confirmedRevisionId != expectedRevisionId) {
            throw DeviceSyncException(
              '[${targetPeer.name}] Sync ID mismatch after apply '
              '(sent: $expectedRevisionId, got: $confirmedRevisionId). '
              'Sync may be incomplete.',
            );
          }

          final responseSteamCache = responsePayload['steamCache'];
          if (responseSteamCache is Map) {
            await mergeSteamCacheSnapshotFromSync(
              Map<String, dynamic>.from(responseSteamCache),
            );
          }

          confirmedTimestampMillis =
              (responsePayload['dbTimestampMillis'] as num?)?.toInt() ?? 0;
          remoteLocalRevision =
              (responsePayload['localRevision'] as num?)?.toInt() ??
              fallbackRemoteRevision;

          final dbAfterPush = ref.read(databaseProvider);
          if (dbAfterPush != null) {
            // Persist the peer's checkpoint using *our* local revision (the
            // one we just transmitted), not the remote's `localRevision`.
            // The checkpoint represents the last value WE sent that the peer
            // has acknowledged receiving, so on the next sync we use it to
            // compute `baseRevision` for delta payloads.  Saving the remote's
            // revision here would mean future tombstones whose `local_revision`
            // is below that value would be silently filtered out even though
            // the peer never actually received them — and would also
            // accumulate forever in our own tombstone table.
            await dbAfterPush.savePeerSyncCheckpoint(
              peerId: targetPeer.id,
              lastRevision: localRevisionSent,
              lastSyncAt: DateTime.fromMillisecondsSinceEpoch(
                confirmedTimestampMillis > 0
                    ? confirmedTimestampMillis
                    : DateTime.now().millisecondsSinceEpoch,
              ),
              remoteRevisionId: confirmedRevisionId,
            );

            // Prune tombstones we have just successfully delivered to this
            // peer.  Every tombstone with `local_revision <= localRevisionSent`
            // is either inside the payload we just confirmed or was sent in
            // a previous round, so the peer has had a chance to apply it.
            // Leaving these rows around forever was the root cause of stale
            // tombstones leaking into subsequent payloads and accidentally
            // re-deleting already-converged games on the receiver.
            await dbAfterPush.clearGameTombstonesUpToRevision(localRevisionSent);
          }
        }
      } catch (e) {
        if (e is DeviceSyncException) {
          rethrow;
        }
        throw const DeviceSyncException(
          'Failed to confirm remote sync completion.',
        );
      }
    } finally {
      tcpSocket.destroy();
    }

    return (
      confirmedTimestampMillis: confirmedTimestampMillis,
      remoteLocalRevision: remoteLocalRevision,
    );
  }

  Future<void> _setSetting<T>(String key, T value) {
    return ref.read(settingsProvider.notifier).setSetting(key, value);
  }

  Future<String> _ensureDeviceId() async {
    final settings = ref.read(settingsProvider);
    var deviceId =
        (settings[SettingsKeys.syncDeviceId] as String?) ??
        DefaultSettings.syncDeviceId;

    if (deviceId.isEmpty) {
      deviceId = _uuid.v4();
      await _setSetting(SettingsKeys.syncDeviceId, deviceId);
    }

    return deviceId;
  }

  Future<void> ensureDiscoveryResponder({required String deviceId}) async {
    if (kIsWeb || _responderSocket != null) {
      return;
    }

    // Bind to all network interfaces (0.0.0.0) to enable LAN discovery.
    // This will trigger Windows Firewall prompt on first run for portable versions.
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      defaultLanPort,
      reuseAddress: true,
      reusePort: false,
    );
    _responderSocket = socket;

    _responderSub = socket.listen(
      (event) {
        if (event != RawSocketEvent.read) {
          return;
        }

        final datagram = socket.receive();
        if (datagram == null) {
          return;
        }

        final payload = _decodePacket(datagram.data);
        if (payload == null) {
          return;
        }

        if (payload['type'] != _discoverType) {
          unawaited(
            _handleResponderControlPacket(
              socket: socket,
              datagram: datagram,
              payload: payload,
              deviceId: deviceId,
            ),
          );
          return;
        }

        final from = payload['from'];
        if (from is! Map) {
          return;
        }

        final fromMap = Map<String, dynamic>.from(from);
        final fromId = (fromMap['id'] as String?)?.trim() ?? '';
        if (fromId.isNotEmpty && fromId == deviceId) {
          return;
        }

        final replyPort =
            (payload['replyPort'] as num?)?.toInt() ?? datagram.port;

        final replyPacket = utf8.encode(
          jsonEncode({
            'type': _discoverResponseType,
            'protocol': _protocolVersion,
            'from': _localIdentityMap(deviceId),
            'port': defaultLanPort,
          }),
        );

        socket.send(replyPacket, datagram.address, replyPort);
      },
      onError: (Object error, StackTrace stackTrace) async {
        await stopDiscoveryResponder();
      },
      onDone: () async {
        await stopDiscoveryResponder();
      },
    );

    // Start the TCP sync data server alongside the UDP responder.
    await _startSyncServer();
  }

  Future<void> _startSyncServer() async {
    if (kIsWeb || _syncServer != null) return;
    try {
      // Bind to all network interfaces (0.0.0.0) to accept connections from LAN.
      // This will trigger Windows Firewall prompt on first run, allowing users
      // to grant network access for the portable version of the app.
      _syncServer = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        _syncDataTcpPort,
        shared: true,
      );
      _syncServer!.listen(
        _handleIncomingSyncConnection,
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {
      _syncServer = null;
    }
  }

  Future<void> _handleIncomingSyncConnection(Socket socket) async {
    // Set the flag synchronously before any await so that _pollSyncCode (which
    // runs on the timer) sees it immediately and does not launch a competing
    // initiator sync that would race to overwrite the revision ID we are about
    // to adopt from the incoming sender.
    _receiverSyncInFlight = true;
    // Single StreamIterator for all reads on this socket.
    final lineIter = StreamIterator<String>(
      utf8.decoder.bind(socket).transform(const LineSplitter()),
    );
    try {
      _eventController.add(
        const SyncTransferActivityEvent(
          active: true,
          message: 'Incoming sync: waiting for data...',
        ),
      );

      // ── Read first line and detect protocol version ───────────────────────
      bool gotFirst;
      try {
        gotFirst = await lineIter.moveNext().timeout(
          const Duration(seconds: 10),
        );
      } on TimeoutException {
        return;
      }
      if (!gotFirst || lineIter.current.trim().isEmpty) return;
      final firstLine = lineIter.current.trim();

      Map<String, dynamic>? firstParsed;
      try {
        firstParsed = jsonDecode(firstLine) as Map<String, dynamic>?;
      } catch (_) {
        return;
      }
      if (firstParsed == null) return;

      // ── Encrypted protocol only (v2) ─────────────────────────────────────
      if (firstParsed['v'] != 2) {
        debugPrint('Sync: rejected non-v2 connection on encrypted channel.');
        return;
      }

      // Complete key exchange, then read and decrypt the payload line.
      final handshakeResult = await _performServerHandshake(
        socket,
        firstParsed,
      );
      if (handshakeResult == null) return;
      final sessionKey = handshakeResult.sessionKey;

      bool gotPayload;
      try {
        gotPayload = await lineIter.moveNext().timeout(
          const Duration(seconds: 20),
        );
      } on TimeoutException {
        return;
      }
      if (!gotPayload || lineIter.current.trim().isEmpty) return;
      final encryptedLine = lineIter.current.trim();

      String requestLine;
      try {
        requestLine = await SyncCrypto.decrypt(encryptedLine, sessionKey);
      } catch (e) {
        debugPrint('Sync: decryption failed for incoming payload: $e');
        return;
      }

      Map<String, dynamic>? payload;
      try {
        payload = jsonDecode(requestLine) as Map<String, dynamic>?;
      } catch (_) {
        return;
      }
      if (payload == null) return;

      final syncRevisionId =
          (payload['syncRevisionId'] as String?)?.trim() ?? '';
      final senderPeerId =
          (payload['requestingPeerId'] as String?)?.trim() ?? '';
      final senderName = (payload['deviceName'] as String?)?.trim() ?? '';
      final displayName = senderName.isNotEmpty ? senderName : 'remote device';

      // Helper: sends [json] to the client as an encrypted line.
      Future<void> sendLine(Map<String, dynamic> json) async {
        final content = await SyncCrypto.encrypt(jsonEncode(json), sessionKey);
        socket.add(utf8.encode('$content\n'));
      }

      // ── Pull request: remote is asking US to push our database to them ──
      if (payload['pullRequest'] == true) {
        final requesterPeerId =
            (payload['requestingPeerId'] as String?)?.trim() ?? '';
        final requestFullDataset = payload['requestFullDataset'] == true;
        _eventController.add(
          SyncTransferActivityEvent(
            active: true,
            message: requestFullDataset
                ? '[$displayName] Pull request received. Sending full data snapshot...'
                : '[$displayName] Pull request received. Sending delta snapshot...',
          ),
        );
        final currentRevisionId = _currentSyncCode();
        final peerState = await _getLocalSyncStateForPeer(requesterPeerId);
        final responsePayload = await _codec.buildDeltaPayload(
          syncRevisionId: currentRevisionId,
          deviceName: _currentDeviceName(),
          baseRevision: (payload['knownRemoteRevision'] as num?)?.toInt() ?? 0,
          baseSyncAtMillis:
              (payload['knownRemoteSyncAt'] as num?)?.toInt() ?? 0,
          localRevision: peerState['localRevision'] as int? ?? 0,
          includeAllGames: requestFullDataset,
        );
        await sendLine(responsePayload);
        await socket.flush();
        final db = ref.read(databaseProvider);
        if (db != null && requesterPeerId.isNotEmpty) {
          final responseDbTimestampMillis =
              (responsePayload['dbTimestampMillis'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch;
          final localRevisionSent =
              (peerState['localRevision'] as int?) ?? 0;
          await db.savePeerSyncCheckpoint(
            peerId: requesterPeerId,
            lastRevision: localRevisionSent,
            lastSyncAt: DateTime.fromMillisecondsSinceEpoch(
              responseDbTimestampMillis,
            ),
            remoteRevisionId: currentRevisionId,
          );
          // Mirror the push path: once we have flushed the response we know
          // every tombstone up to our current local revision is now in the
          // requester's hands, so prune them here too.
          await db.clearGameTombstonesUpToRevision(localRevisionSent);
        }
        _eventController.add(const SyncTransferActivityEvent(active: false));
        return;
      }

      // ── Normal push: remote is sending their database to us ──
      final expectedReceiverDbName =
          (payload['expectedReceiverDbName'] as String?)?.trim() ?? '';
      if (expectedReceiverDbName.isNotEmpty) {
        final activeReceiverDbName = _currentDatabaseName();
        if (activeReceiverDbName != expectedReceiverDbName) {
          await sendLine({
            'syncApplied': false,
            'errorCode': 'receiver_db_changed',
            'error':
                'Receiver active database changed before apply. Sync cancelled.',
            'expectedReceiverDbName': expectedReceiverDbName,
            'receiverDbName': activeReceiverDbName,
            'syncRevisionId': syncRevisionId,
          });
          await socket.flush();
          _eventController.add(
            SyncTransferActivityEvent(
              active: true,
              message:
                  '[$displayName] Sync blocked: active database changed from "$expectedReceiverDbName" to "$activeReceiverDbName".',
            ),
          );
          _eventController.add(const SyncTransferActivityEvent(active: false));
          return;
        }
      }

      final incomingSteamCache = payload['steamCache'];
      if (incomingSteamCache is Map) {
        await mergeSteamCacheSnapshotFromSync(
          Map<String, dynamic>.from(incomingSteamCache),
        );
      }
      final gamesRaw = payload['games'];
      final games = gamesRaw is List
          ? gamesRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList(growable: false)
          : const <Map<String, dynamic>>[];
      final tombstonesRaw = payload['tombstones'];
      final tombstones = tombstonesRaw is List
          ? tombstonesRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList(growable: false)
          : const <Map<String, dynamic>>[];
      final incomingFullDataset = payload['fullDataset'] == true;

      _eventController.add(
        SyncTransferActivityEvent(
          active: true,
          message: incomingFullDataset
              ? '[$displayName] Received ${games.length} records and ${tombstones.length} deletions. Applying...'
              : '[$displayName] Received ${games.length} changed records and ${tombstones.length} deletions. Applying...',
        ),
      );

      // Send keep-alive pings every 4 seconds so the initiator doesn't time
      // out while applying cover images and DB writes.
      Timer? keepAliveTimer;
      keepAliveTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
        try {
          final content = await SyncCrypto.encrypt(
            '{"keepAlive":true}',
            sessionKey,
          );
          socket.add(utf8.encode('$content\n'));
        } catch (_) {}
      });

      final SyncImportResult result;
      try {
        final receiverPeerState = await _getLocalSyncStateForPeer(senderPeerId);
        final peerKnownSyncAtMillis =
            receiverPeerState['peerKnownSyncAt'] as int? ?? 0;
        result = await _codec.applyDeltaPayload(
          games,
          tombstones: tombstones,
          lastSyncAt: peerKnownSyncAtMillis <= 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(peerKnownSyncAtMillis),
        );
      } finally {
        keepAliveTimer.cancel();
        keepAliveTimer = null;
      }

      _eventController.add(
        SyncTransferActivityEvent(
          active: true,
          message:
              '[$displayName] Replaced database: ${result.inserted} game records applied. Confirming...',
        ),
      );

      // Adopt the initiator's revision ID so both devices share the same sync
      // code after this exchange.
      final adoptedRevisionId = syncRevisionId.isEmpty
          ? _currentSyncCode()
          : syncRevisionId;
      if (syncRevisionId.isNotEmpty) {
        await _setSetting(SettingsKeys.syncDbRevisionId, adoptedRevisionId);
      }
      final db = ref.read(databaseProvider);
      final senderDbTimestampMillis =
          (payload['dbTimestampMillis'] as num?)?.toInt() ?? 0;
      if (senderDbTimestampMillis > 0) {
        await _setSetting(
          SettingsKeys.syncDbTimestampMillis,
          senderDbTimestampMillis,
        );
        if (db != null) {
          await db.setSyncDbTimestampMillis(senderDbTimestampMillis);
        }
      }
      if (db != null && senderPeerId.isNotEmpty) {
        await db.savePeerSyncCheckpoint(
          peerId: senderPeerId,
          lastRevision: (payload['localRevision'] as num?)?.toInt() ?? 0,
          lastSyncAt: DateTime.fromMillisecondsSinceEpoch(
            senderDbTimestampMillis > 0
                ? senderDbTimestampMillis
                : DateTime.now().millisecondsSinceEpoch,
          ),
          remoteRevisionId: adoptedRevisionId,
        );
      }
      // Record the sync timestamp on the receiver side.
      await markSyncCompleted(
        authoritativeTimestampMillis: senderDbTimestampMillis > 0
            ? senderDbTimestampMillis
            : null,
      );

      // Send a lightweight confirmation — NO games — so the initiator never
      // applies our data back and accidentally restores anything it deleted.
      // Include steam cache so metadata stays bidirectional.
      final steamCache = await exportSteamCacheSnapshotForSync();
      final confirmedLocalState = await _getLocalSyncStateForPeer(senderPeerId);
      await sendLine({
        'syncApplied': true,
        'syncRevisionId': adoptedRevisionId,
        'localRevision': (confirmedLocalState['localRevision'] as int?) ?? 0,
        'dbTimestampMillis':
            (confirmedLocalState['localDbTimestamp'] as int?) ??
            DateTime.now().millisecondsSinceEpoch,
        'steamCache': steamCache,
      });
      await socket.flush();

      _eventController.add(SyncDataAppliedEvent(result));
      _eventController.add(const SyncTransferActivityEvent(active: false));
    } catch (e) {
      debugPrint('Sync server receive error: $e');
    } finally {
      await lineIter.cancel();
      socket.destroy();
      _receiverSyncInFlight = false;
    }
  }

  Future<void> stopDiscoveryResponder() async {
    _announceTimer?.cancel();
    _announceTimer = null;
    await _responderSub?.cancel();
    _responderSub = null;
    _responderSocket?.close();
    _responderSocket = null;
    await _syncServer?.close();
    _syncServer = null;
  }

  /// Completes any pending ping that is awaiting a pong via the responder socket.
  Future<void> _handleSyncPong(Map<String, dynamic> payload) async {
    final token = (payload['token'] as String?)?.trim();
    if (token == null || token.isEmpty) return;
    final pending = _pendingPongs[token];
    if (pending == null || pending.completer.isCompleted) return;

    final from = payload['from'];
    if (from is! Map) {
      return;
    }
    final fromMap = Map<String, dynamic>.from(from);
    final fromId = (fromMap['id'] as String?)?.trim() ?? '';
    if (fromId.isEmpty || fromId != pending.expectedPeerId) {
      return;
    }

    final isAuthentic = await _verifyTrustedControlPacketAuth(
      payload: payload,
      fromPeerId: fromId,
    );
    if (!isAuthentic) {
      return;
    }

    _pendingPongs.remove(token);
    pending.completer.complete(
      _PeerPingResult(
        reachable: true,
        remoteTrusted: payload['trusted'] == true,
        remoteDbName: (payload['dbName'] as String?)?.trim(),
        remoteRevision: (payload['localRevision'] as num?)?.toInt() ?? 0,
        remoteKnownLocalRevision:
            (payload['peerKnownRevision'] as num?)?.toInt() ?? 0,
        remoteKnownLocalSyncAtMillis:
            (payload['peerKnownSyncAt'] as num?)?.toInt() ?? 0,
        remoteSyncRevisionId: (payload['syncRevisionId'] as String?)?.trim(),
        remoteDbTimestampMillis:
            (payload['dbTimestampMillis'] as num?)?.toInt() ?? 0,
        remoteReceiverSyncInFlight: payload['receiverSyncInFlight'] == true,
      ),
    );
  }

  Future<void> _handleSyncPing(
    RawDatagramSocket socket,
    Datagram datagram,
    Map<String, dynamic> payload,
    String deviceId,
  ) async {
    final from = payload['from'];
    if (from is! Map) {
      return;
    }

    final fromMap = Map<String, dynamic>.from(from);
    final fromId = (fromMap['id'] as String?)?.trim() ?? '';
    if (fromId.isNotEmpty && fromId == deviceId) {
      return;
    }

    if (_isTrustedPeer(fromId)) {
      final isAuthentic = await _verifyTrustedControlPacketAuth(
        payload: payload,
        fromPeerId: fromId,
      );
      if (!isAuthentic) {
        return;
      }
    }

    final token = (payload['token'] as String?)?.trim();
    final replyPort = (payload['replyPort'] as num?)?.toInt() ?? datagram.port;
    final peerState = await _getLocalSyncStateForPeer(fromId);

    final pongPayload = await _attachControlAuthIfTrusted(
      payload: {
        'type': _syncPongType,
        'protocol': _protocolVersion,
        'token': token,
        'from': _localIdentityMap(deviceId),
        'localRevision': peerState['localRevision'],
        'dbTimestampMillis': peerState['localDbTimestamp'],
        'peerKnownRevision': peerState['peerKnownRevision'],
        'peerKnownSyncAt': peerState['peerKnownSyncAt'],
        'trusted': _isTrustedPeer(fromId),
        'dbName': _currentDatabaseName(),
        'syncRevisionId': _currentSyncCode(),
        'receiverSyncInFlight': _receiverSyncInFlight,
      },
      peerId: fromId,
    );
    final pongPacket = utf8.encode(jsonEncode(pongPayload));

    socket.send(pongPacket, datagram.address, replyPort);
  }

  TrustedSyncPeer? _resolveTargetPeer({
    required List<TrustedSyncPeer> trustedPeers,
    String? explicitPeerId,
    String? fallbackPeerId,
  }) {
    if (explicitPeerId != null && explicitPeerId.isNotEmpty) {
      for (final peer in trustedPeers) {
        if (peer.id == explicitPeerId) {
          return peer;
        }
      }
    }

    if (fallbackPeerId != null && fallbackPeerId.isNotEmpty) {
      for (final peer in trustedPeers) {
        if (peer.id == fallbackPeerId) {
          return peer;
        }
      }
    }

    return trustedPeers.first;
  }

  Future<_PeerPingResult> _pingPeer(TrustedSyncPeer peer) async {
    if (kIsWeb) {
      return const _PeerPingResult(reachable: false);
    }

    final targetHost = peer.host.trim();
    if (targetHost.isEmpty) {
      return const _PeerPingResult(reachable: false);
    }

    final localDeviceId = await _ensureDeviceId();
    final token = _uuid.v4();
    final completer = Completer<_PeerPingResult>();

    // Route pong replies through the already-open responder socket (port
    // 45871) rather than a new ephemeral port.  Windows Firewall has a
    // persistent rule for the responder socket and allows replies to it;
    // replies to short-lived ephemeral ports are often silently dropped,
    // which is why the ping always appeared to fail on Windows even when
    // the peer was reachable.
    final responderPort = _responderSocket?.port;
    final useResponderPort = responderPort != null && responderPort > 0;
    if (useResponderPort) {
      _pendingPongs[token] = _PendingPongState(
        expectedPeerId: peer.id,
        completer: completer,
      );
    }

    // Open a short-lived socket solely for sending the ping packet.
    // When the responder port is available it also acts as the fallback
    // receiver; otherwise it is the sole receiver.
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
      reusePort: false,
    );

    StreamSubscription<RawSocketEvent>? sub;
    if (!useResponderPort) {
      // Fallback: receive the pong on this ephemeral socket (original path,
      // used when the responder socket is not yet open).
      sub = socket.listen((event) {
        if (event != RawSocketEvent.read || completer.isCompleted) {
          return;
        }

        final datagram = socket.receive();
        if (datagram == null) {
          return;
        }

        final payload = _decodePacket(datagram.data);
        if (payload == null || payload['type'] != _syncPongType) {
          return;
        }

        final incomingToken = (payload['token'] as String?)?.trim();
        if (incomingToken != token) {
          return;
        }

        final from = payload['from'];
        if (from is! Map) {
          return;
        }

        final fromMap = Map<String, dynamic>.from(from);
        final fromId = (fromMap['id'] as String?)?.trim() ?? '';
        if (fromId.isEmpty || fromId != peer.id) {
          return;
        }

        unawaited(() async {
          final isAuthentic = await _verifyTrustedControlPacketAuth(
            payload: payload,
            fromPeerId: fromId,
          );
          if (!isAuthentic || completer.isCompleted) {
            return;
          }

          completer.complete(
            _PeerPingResult(
              reachable: true,
              remoteTrusted: payload['trusted'] == true,
              remoteDbName: (payload['dbName'] as String?)?.trim(),
              remoteRevision: (payload['localRevision'] as num?)?.toInt() ?? 0,
              remoteKnownLocalRevision:
                  (payload['peerKnownRevision'] as num?)?.toInt() ?? 0,
              remoteKnownLocalSyncAtMillis:
                  (payload['peerKnownSyncAt'] as num?)?.toInt() ?? 0,
              remoteSyncRevisionId: (payload['syncRevisionId'] as String?)
                  ?.trim(),
              remoteDbTimestampMillis:
                  (payload['dbTimestampMillis'] as num?)?.toInt() ?? 0,
              remoteReceiverSyncInFlight:
                  payload['receiverSyncInFlight'] == true,
            ),
          );
        }());
      });
    }

    final replyPort = useResponderPort ? responderPort : socket.port;
    final packetPayload = await _attachControlAuthIfTrusted(
      payload: {
        'type': _syncPingType,
        'protocol': _protocolVersion,
        'token': token,
        'replyPort': replyPort,
        'from': _localIdentityMap(localDeviceId),
      },
      peerId: peer.id,
    );
    final packet = utf8.encode(jsonEncode(packetPayload));

    socket.send(packet, InternetAddress(targetHost), peer.port);

    _PeerPingResult result = const _PeerPingResult(reachable: false);
    try {
      result = await completer.future.timeout(
        _syncPingTimeout,
        onTimeout: () => const _PeerPingResult(reachable: false),
      );
    } finally {
      if (useResponderPort) _pendingPongs.remove(token);
      await sub?.cancel();
      socket.close();
    }
    return result;
  }

  Future<DeviceSyncCodeCheckResult> checkSyncCode({String? peerId}) async {
    final settings = ref.read(settingsProvider);
    final trustedPeers = decodeTrustedPeers(
      settings[SettingsKeys.syncTrustedPeersJson] as String? ??
          DefaultSettings.syncTrustedPeersJson,
    );
    if (trustedPeers.isEmpty) {
      return const DeviceSyncCodeCheckResult(reachable: false);
    }

    var target = _resolveTargetPeer(
      trustedPeers: trustedPeers,
      explicitPeerId: peerId,
      fallbackPeerId: (settings[SettingsKeys.syncLastTrustedPeerId] as String?)
          ?.trim(),
    );
    if (target == null) {
      return const DeviceSyncCodeCheckResult(reachable: false);
    }

    _PeerPingResult ping;
    final announcedPeer = _freshAnnouncedPeerById(target.id);
    if (announcedPeer != null) {
      final candidate = _mergePeerFromDiscovery(
        trustedPeer: target,
        discoveredPeer: announcedPeer,
      );
      if (_peerEndpointChanged(target, candidate)) {
        final candidatePing = await _pingPeer(candidate);
        if (candidatePing.reachable) {
          target = candidate;
          ping = candidatePing;
        } else {
          ping = await _pingPeer(target);
        }
      } else {
        ping = await _pingPeer(target);
      }
    } else {
      ping = await _pingPeer(target);
    }
    final localState = await _getLocalSyncStateForPeer(target.id);
    final localRevision = localState['localRevision'] as int? ?? 0;
    final localKnownRemoteRevision =
        localState['peerKnownRevision'] as int? ?? 0;
    final localKnownRemoteSyncAtMillis =
        localState['peerKnownSyncAt'] as int? ?? 0;
    final localDbTimestampMillis = localState['localDbTimestamp'] as int? ?? 0;
    final localDbName = _currentDatabaseName();
    final localSyncRevisionId = _currentSyncCode();
    final remoteDbName = ping.remoteDbName;
    if (!ping.reachable) {
      return DeviceSyncCodeCheckResult(
        reachable: false,
        peer: target,
        localDbName: localDbName,
        localRevision: localRevision,
        localKnownRemoteRevision: localKnownRemoteRevision,
        localKnownRemoteSyncAtMillis: localKnownRemoteSyncAtMillis,
        localSyncRevisionId: localSyncRevisionId,
        remoteSyncRevisionId: (ping.remoteSyncRevisionId ?? '').trim(),
        localDbTimestampMillis: localDbTimestampMillis,
        remoteDbTimestampMillis: ping.remoteDbTimestampMillis,
        remoteReceiverSyncInFlight: ping.remoteReceiverSyncInFlight,
      );
    }

    final dbNameMismatch =
        remoteDbName != null &&
        remoteDbName.isNotEmpty &&
        localDbName.isNotEmpty &&
        remoteDbName != localDbName;
    final remoteSyncRevisionId = (ping.remoteSyncRevisionId ?? '').trim();

    return DeviceSyncCodeCheckResult(
      reachable: true,
      peer: target,
      localDbName: localDbName,
      remoteDbName: remoteDbName,
      dbNameMismatch: dbNameMismatch,
      localRevision: localRevision,
      remoteRevision: ping.remoteRevision,
      localKnownRemoteRevision: localKnownRemoteRevision,
      remoteKnownLocalRevision: ping.remoteKnownLocalRevision,
      localKnownRemoteSyncAtMillis: localKnownRemoteSyncAtMillis,
      remoteKnownLocalSyncAtMillis: ping.remoteKnownLocalSyncAtMillis,
      localSyncRevisionId: localSyncRevisionId,
      remoteSyncRevisionId: remoteSyncRevisionId,
      localDbTimestampMillis: localDbTimestampMillis,
      remoteDbTimestampMillis: ping.remoteDbTimestampMillis,
      remoteReceiverSyncInFlight: ping.remoteReceiverSyncInFlight,
    );
  }

  String _currentSyncCode() {
    final settings = ref.read(settingsProvider);
    final revisionId =
        (settings[SettingsKeys.syncDbRevisionId] as String?)?.trim() ?? '';
    return revisionId.isEmpty ? 'initial' : revisionId;
  }

  /// Returns just the filename (e.g. "UniKM_Games.db") of the active database
  /// so peers can detect when they are using different database files.
  String _currentDatabaseName() {
    final settings = ref.read(settingsProvider);
    final path = (settings[SettingsKeys.databasePath] as String?)?.trim() ?? '';
    if (path.isEmpty) return '';
    return p.basename(path);
  }

  void _startAnnounceLoop(String deviceId) {
    _announceTimer?.cancel();
    _announceTimer = Timer.periodic(_announceInterval, (_) {
      unawaited(_sendAnnounce(deviceId));
    });
    unawaited(_sendAnnounce(deviceId));
  }

  Future<void> _handleResponderControlPacket({
    required RawDatagramSocket socket,
    required Datagram datagram,
    required Map<String, dynamic> payload,
    required String deviceId,
  }) async {
    final type = payload['type'];
    if (type == _syncPongType) {
      await _handleSyncPong(payload);
      return;
    }
    if (type == _syncPingType) {
      await _handleSyncPing(socket, datagram, payload, deviceId);
      return;
    }
    if (type == _announceType || type == _discoverResponseType) {
      _handleAnnounce(datagram, payload, deviceId);
      return;
    }
    if (type == _untrustType) {
      unawaited(_handleUntrust(datagram, payload));
      return;
    }
    if (type == _pairCancelType) {
      _handlePairCancel(payload);
      return;
    }
    if (type == _pairCodeRejectedType) {
      _handlePairCodeRejected(datagram, payload);
      return;
    }
    if (type == _pairRequestType) {
      unawaited(_handlePairRequest(datagram, payload, deviceId));
      return;
    }
    if (type == _pairCommitType) {
      unawaited(_handlePairCommit(socket, datagram, payload, deviceId));
      return;
    }
    if (type == _pairFinalizeType) {
      unawaited(_handlePairFinalize(socket, datagram, payload, deviceId));
    }
  }

  void _handleAnnounce(
    Datagram datagram,
    Map<String, dynamic> payload,
    String deviceId,
  ) {
    final from = payload['from'];
    if (from is! Map) return;
    final fromMap = Map<String, dynamic>.from(from);
    final peerId = (fromMap['id'] as String?)?.trim() ?? '';
    if (peerId.isEmpty || peerId == deviceId) return;
    final peerName = (fromMap['name'] as String?)?.trim();
    final peerType = syncDeviceTypeFromWire(
      fromMap['deviceType'] as String? ?? fromMap['device_type'] as String?,
    );
    final port = (payload['port'] as num?)?.toInt() ?? defaultLanPort;
    _announcedPeers[peerId] = DiscoveredSyncPeer(
      id: peerId,
      name: _normalizeDeviceName(peerName, fallbackType: peerType),
      host: datagram.address.address,
      port: port,
      deviceType: peerType,
    );
    _announcedPeersSeenAt[peerId] = DateTime.now();
  }

  Future<void> _handleUntrust(
    Datagram datagram,
    Map<String, dynamic> payload,
  ) async {
    final from = payload['from'];
    if (from is! Map) return;
    final fromMap = Map<String, dynamic>.from(from);
    final fromId = (fromMap['id'] as String?)?.trim() ?? '';
    if (fromId.isEmpty || !_isTrustedPeer(fromId)) return;

    final isAuthentic = await _verifyTrustedControlPacketAuth(
      payload: payload,
      fromPeerId: fromId,
    );
    if (!isAuthentic) {
      return;
    }

    await removeTrustedPeer(fromId, notifyRemote: false);
    _eventController.add(PeerRemovedEvent(fromId));
  }

  Future<void> _handlePairRequest(
    Datagram datagram,
    Map<String, dynamic> payload,
    String deviceId,
  ) async {
    final requestId = (payload['requestId'] as String?)?.trim() ?? '';
    if (requestId.isEmpty) {
      return;
    }
    final from = payload['from'];
    if (from is! Map) {
      return;
    }
    final fromMap = Map<String, dynamic>.from(from);
    final fromId = (fromMap['id'] as String?)?.trim() ?? '';
    if (fromId.isEmpty || fromId == deviceId) {
      return;
    }

    final fromType = syncDeviceTypeFromWire(
      fromMap['deviceType'] as String? ?? fromMap['device_type'] as String?,
    );

    final initiatorStaticPubB64 = (payload['spub'] as String?)?.trim();
    String? receiverStaticPubB64;
    if (initiatorStaticPubB64 != null && initiatorStaticPubB64.isNotEmpty) {
      final localStaticPair = await _getOrGenerateStaticKeyPair();
      final localStaticPub = await localStaticPair.extractPublicKey();
      receiverStaticPubB64 = base64.encode(localStaticPub.bytes);
    }

    final replyPort = (payload['replyPort'] as num?)?.toInt() ?? datagram.port;
    _pendingPairRequests[requestId] = _IncomingPairRequestState(
      requestId: requestId,
      peer: DiscoveredSyncPeer(
        id: fromId,
        name: _normalizeDeviceName(
          (fromMap['name'] as String?)?.trim(),
          fallbackType: fromType,
        ),
        host: datagram.address.address,
        port: defaultLanPort,
        deviceType: fromType,
      ),
      sourceAddress: datagram.address,
      replyPort: replyPort,
      createdAt: DateTime.now(),
      initiatorStaticPubB64: initiatorStaticPubB64,
      receiverStaticPubB64: receiverStaticPubB64,
    );
    _eventController.add(
      PairRequestReceivedEvent(
        PendingPairRequest(
          requestId: requestId,
          peer: _pendingPairRequests[requestId]!.peer,
          requestedAt: _pendingPairRequests[requestId]!.createdAt,
        ),
      ),
    );
    _evictExpiredPairRequests();
  }

  Future<void> _handlePairCommit(
    RawDatagramSocket socket,
    Datagram datagram,
    Map<String, dynamic> payload,
    String deviceId,
  ) async {
    final requestId = (payload['requestId'] as String?)?.trim() ?? '';
    if (requestId.isEmpty) {
      return;
    }

    final request = _pendingPairRequests[requestId];
    if (request == null || !request.receiverAccepted) {
      return;
    }

    final from = payload['from'];
    if (from is! Map) {
      return;
    }
    final fromMap = Map<String, dynamic>.from(from);
    final fromId = (fromMap['id'] as String?)?.trim() ?? '';
    if (fromId.isEmpty || fromId != request.peer.id) {
      return;
    }
    if (datagram.address.address != request.sourceAddress.address) {
      return;
    }

    final initiatorSpub = (payload['spub'] as String?)?.trim() ?? '';
    final expectedInitiatorSpub = (request.initiatorStaticPubB64 ?? '').trim();
    final replyPort = (payload['replyPort'] as num?)?.toInt() ?? datagram.port;
    final commitOk = payload['ok'] == true;

    if (initiatorSpub.isEmpty ||
        (expectedInitiatorSpub.isNotEmpty &&
            initiatorSpub != expectedInitiatorSpub) ||
        !commitOk) {
      final nackPacket = utf8.encode(
        jsonEncode({
          'type': _pairCommitAckType,
          'protocol': _protocolVersion,
          'requestId': requestId,
          'accepted': false,
          'reason': 'invalid_commit',
          'from': _localIdentityMap(deviceId),
        }),
      );
      socket.send(nackPacket, datagram.address, replyPort);
      _pendingPairRequests.remove(requestId);
      return;
    }

    _pendingPairRequests[requestId] = request.copyWith(
      initiatorCommitAccepted: true,
      initiatorStaticPubB64: initiatorSpub,
    );

    // Include our own static public key in the ack so the initiator can pin us.
    var localStaticPubB64 = (request.receiverStaticPubB64 ?? '').trim();
    if (localStaticPubB64.isEmpty) {
      final localStaticPair = await _getOrGenerateStaticKeyPair();
      final localStaticPub = await localStaticPair.extractPublicKey();
      localStaticPubB64 = base64.encode(localStaticPub.bytes);
    }

    final ackPacket = utf8.encode(
      jsonEncode({
        'type': _pairCommitAckType,
        'protocol': _protocolVersion,
        'requestId': requestId,
        'accepted': true,
        'spub': localStaticPubB64,
        'ok': true,
        'from': _localIdentityMap(deviceId),
      }),
    );
    socket.send(ackPacket, datagram.address, replyPort);
  }

  Future<void> _handlePairFinalize(
    RawDatagramSocket socket,
    Datagram datagram,
    Map<String, dynamic> payload,
    String deviceId,
  ) async {
    final requestId = (payload['requestId'] as String?)?.trim() ?? '';
    if (requestId.isEmpty) {
      return;
    }

    final request = _pendingPairRequests[requestId];
    if (request == null ||
        !request.receiverAccepted ||
        !request.initiatorCommitAccepted) {
      return;
    }

    final from = payload['from'];
    if (from is! Map) {
      return;
    }
    final fromMap = Map<String, dynamic>.from(from);
    final fromId = (fromMap['id'] as String?)?.trim() ?? '';
    if (fromId.isEmpty || fromId != request.peer.id) {
      return;
    }
    if (datagram.address.address != request.sourceAddress.address) {
      return;
    }

    final finalizeOk = payload['ok'] == true;
    final initiatorSpub = (payload['spub'] as String?)?.trim() ?? '';
    final expectedInitiatorSpub = (request.initiatorStaticPubB64 ?? '').trim();
    final replyPort = (payload['replyPort'] as num?)?.toInt() ?? datagram.port;

    if (!finalizeOk ||
        initiatorSpub.isEmpty ||
        (expectedInitiatorSpub.isNotEmpty &&
            initiatorSpub != expectedInitiatorSpub)) {
      final nackPacket = utf8.encode(
        jsonEncode({
          'type': _pairFinalizeAckType,
          'protocol': _protocolVersion,
          'requestId': requestId,
          'accepted': false,
          'reason': 'invalid_finalize',
          'from': _localIdentityMap(deviceId),
        }),
      );
      socket.send(nackPacket, datagram.address, replyPort);
      _pendingPairRequests.remove(requestId);
      return;
    }

    final fromName = (fromMap['name'] as String?)?.trim();
    final fromType = syncDeviceTypeFromWire(
      fromMap['deviceType'] as String? ?? fromMap['device_type'] as String?,
    );
    final trusted = await _upsertTrustedPeer(
      DiscoveredSyncPeer(
        id: fromId,
        name: _normalizeDeviceName(
          (fromName == null || fromName.isEmpty) ? request.peer.name : fromName,
          fallbackType: fromType,
        ),
        host: datagram.address.address,
        port: defaultLanPort,
        deviceType: fromType == SyncDeviceType.unknown
            ? request.peer.deviceType
            : fromType,
      ),
      fingerprint: initiatorSpub,
    );
    _eventController.add(PeerTrustedEvent(trusted));

    var localStaticPubB64 = (request.receiverStaticPubB64 ?? '').trim();
    if (localStaticPubB64.isEmpty) {
      final localStaticPair = await _getOrGenerateStaticKeyPair();
      final localStaticPub = await localStaticPair.extractPublicKey();
      localStaticPubB64 = base64.encode(localStaticPub.bytes);
    }

    final ackPacket = utf8.encode(
      jsonEncode({
        'type': _pairFinalizeAckType,
        'protocol': _protocolVersion,
        'requestId': requestId,
        'accepted': true,
        'spub': localStaticPubB64,
        'ok': true,
        'from': _localIdentityMap(deviceId),
      }),
    );
    socket.send(ackPacket, datagram.address, replyPort);
    _pendingPairRequests.remove(requestId);
  }

  void _handlePairCancel(Map<String, dynamic> payload) {
    final requestId = (payload['requestId'] as String?)?.trim() ?? '';
    if (requestId.isEmpty) return;
    final request = _pendingPairRequests.remove(requestId);
    if (request != null) {
      _eventController.add(
        PairRequestCanceledEvent(
          PendingPairRequest(
            requestId: request.requestId,
            peer: request.peer,
            requestedAt: request.createdAt,
          ),
        ),
      );
    }
  }

  void _handlePairCodeRejected(
    Datagram datagram,
    Map<String, dynamic> payload,
  ) {
    final requestId = (payload['requestId'] as String?)?.trim() ?? '';
    if (requestId.isEmpty) {
      return;
    }

    final request = _pendingPairRequests[requestId];
    if (request == null || !request.receiverAccepted) {
      return;
    }

    final from = payload['from'];
    if (from is! Map) {
      return;
    }
    final fromMap = Map<String, dynamic>.from(from);
    final fromId = (fromMap['id'] as String?)?.trim() ?? '';
    if (fromId.isEmpty || fromId != request.peer.id) {
      return;
    }
    if (datagram.address.address != request.sourceAddress.address) {
      return;
    }

    _eventController.add(
      PairRequestCodeRejectedEvent(
        PendingPairRequest(
          requestId: request.requestId,
          peer: request.peer,
          requestedAt: request.createdAt,
        ),
        reason: (payload['reason'] as String?)?.trim(),
      ),
    );
  }

  Future<void> _sendPairCancel({
    required DiscoveredSyncPeer peer,
    required String requestId,
    required String localDeviceId,
  }) async {
    if (kIsWeb) return;
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
      reusePort: false,
    );
    try {
      final packet = utf8.encode(
        jsonEncode({
          'type': _pairCancelType,
          'protocol': _protocolVersion,
          'requestId': requestId,
          'from': _localIdentityMap(localDeviceId),
        }),
      );
      socket.send(packet, InternetAddress(peer.host), peer.port);
    } finally {
      socket.close();
    }
  }

  Future<void> _sendPairCodeRejected({
    required DiscoveredSyncPeer peer,
    required String requestId,
    required String localDeviceId,
  }) async {
    if (kIsWeb) return;
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
      reusePort: false,
    );
    try {
      final packet = utf8.encode(
        jsonEncode({
          'type': _pairCodeRejectedType,
          'protocol': _protocolVersion,
          'requestId': requestId,
          'reason': 'code_mismatch',
          'from': _localIdentityMap(localDeviceId),
        }),
      );
      socket.send(packet, InternetAddress(peer.host), peer.port);
    } finally {
      socket.close();
    }
  }

  /// Notifies the initiator that a pending pair request expired on our side.
  /// Sends a decision-rejection packet for requests that were never accepted
  /// (so the initiator's decision loop can resolve immediately) and a cancel
  /// packet for requests already accepted (where the initiator is waiting on
  /// a commit/finalize ack instead).
  Future<void> _notifyInitiatorOfTimeout(
    _IncomingPairRequestState request,
  ) async {
    if (kIsWeb) return;
    final localDeviceId = await _ensureDeviceId();
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
      reusePort: false,
    );
    try {
      final Map<String, dynamic> payload;
      if (request.receiverAccepted) {
        payload = {
          'type': _pairCancelType,
          'protocol': _protocolVersion,
          'requestId': request.requestId,
          'reason': 'timeout',
          'from': _localIdentityMap(localDeviceId),
        };
      } else {
        payload = {
          'type': _pairReceiverDecisionType,
          'protocol': _protocolVersion,
          'requestId': request.requestId,
          'accepted': false,
          'reason': 'timeout',
          'from': _localIdentityMap(localDeviceId),
        };
      }
      socket.send(
        utf8.encode(jsonEncode(payload)),
        request.sourceAddress,
        request.replyPort,
      );
    } finally {
      socket.close();
    }
  }

  bool _isTrustedPeer(String peerId) {
    if (peerId.isEmpty) {
      return false;
    }
    final trusted = decodeTrustedPeers(
      ref.read(settingsProvider)[SettingsKeys.syncTrustedPeersJson]
              as String? ??
          DefaultSettings.syncTrustedPeersJson,
    );
    return trusted.any((p) => p.id == peerId);
  }

  TrustedSyncPeer? _trustedPeerById(String peerId) {
    if (peerId.isEmpty) {
      return null;
    }
    final trusted = decodeTrustedPeers(
      ref.read(settingsProvider)[SettingsKeys.syncTrustedPeersJson]
              as String? ??
          DefaultSettings.syncTrustedPeersJson,
    );
    return trusted.where((p) => p.id == peerId).firstOrNull;
  }

  Object? _canonicalizeJson(Object? value) {
    if (value is Map) {
      final map = <String, Object?>{};
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      for (final key in keys) {
        map[key] = _canonicalizeJson(value[key]);
      }
      return map;
    }
    if (value is List) {
      return value.map(_canonicalizeJson).toList(growable: false);
    }
    return value;
  }

  String _canonicalPacketForAuth(Map<String, dynamic> payload) {
    final sanitized = Map<String, dynamic>.from(payload)..remove('auth');
    final canonical = _canonicalizeJson(sanitized);
    return jsonEncode(canonical);
  }

  bool _constantTimeBytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  Future<String> _computeControlPacketMac({
    required Map<String, dynamic> payload,
    required String remoteStaticPubB64,
  }) async {
    final localStaticPair = await _getOrGenerateStaticKeyPair();
    final remoteStaticPub = SyncCrypto.publicKeyFromBase64(remoteStaticPubB64);
    final shared = await _x25519.sharedSecretKey(
      keyPair: localStaticPair,
      remotePublicKey: remoteStaticPub,
    );
    final sharedBytes = await shared.extractBytes();
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode(_canonicalPacketForAuth(payload)),
      secretKey: SecretKey(sharedBytes),
    );
    return base64.encode(mac.bytes);
  }

  Future<Map<String, dynamic>> _attachControlAuthIfTrusted({
    required Map<String, dynamic> payload,
    required String peerId,
  }) async {
    final trustedPeer = _trustedPeerById(peerId);
    return _attachControlAuthForFingerprint(
      payload: payload,
      remoteStaticPubB64: trustedPeer?.fingerprint,
    );
  }

  Future<Map<String, dynamic>> _attachControlAuthForFingerprint({
    required Map<String, dynamic> payload,
    required String? remoteStaticPubB64,
  }) async {
    final remoteFingerprint = (remoteStaticPubB64 ?? '').trim();
    if (remoteFingerprint.isEmpty) {
      return payload;
    }

    final localStaticPair = await _getOrGenerateStaticKeyPair();
    final localStaticPub = await localStaticPair.extractPublicKey();
    final mac = await _computeControlPacketMac(
      payload: payload,
      remoteStaticPubB64: remoteFingerprint,
    );

    payload['auth'] = {
      'alg': _controlAuthAlg,
      'spub': base64.encode(localStaticPub.bytes),
      'mac': mac,
    };
    return payload;
  }

  Future<bool> _verifyTrustedControlPacketAuth({
    required Map<String, dynamic> payload,
    required String fromPeerId,
  }) async {
    final trustedPeer = _trustedPeerById(fromPeerId);
    final expectedFingerprint = (trustedPeer?.fingerprint ?? '').trim();
    if (expectedFingerprint.isEmpty) {
      return false;
    }

    final auth = payload['auth'];
    if (auth is! Map) {
      return false;
    }

    final authMap = Map<String, dynamic>.from(auth);
    final alg = (authMap['alg'] as String?)?.trim() ?? '';
    final senderStaticPubB64 = (authMap['spub'] as String?)?.trim() ?? '';
    final macB64 = (authMap['mac'] as String?)?.trim() ?? '';

    if (alg != _controlAuthAlg ||
        senderStaticPubB64.isEmpty ||
        macB64.isEmpty ||
        senderStaticPubB64 != expectedFingerprint) {
      return false;
    }

    List<int> receivedMac;
    try {
      receivedMac = base64.decode(macB64);
    } catch (_) {
      return false;
    }

    final expectedMacB64 = await _computeControlPacketMac(
      payload: payload,
      remoteStaticPubB64: senderStaticPubB64,
    );

    return _constantTimeBytesEqual(base64.decode(expectedMacB64), receivedMac);
  }

  Future<TrustedSyncPeer> _upsertTrustedPeer(
    DiscoveredSyncPeer peer, {
    String? fingerprint,
  }) async {
    final trusted = decodeTrustedPeers(
      ref.read(settingsProvider)[SettingsKeys.syncTrustedPeersJson]
              as String? ??
          DefaultSettings.syncTrustedPeersJson,
    );
    // Preserve an existing fingerprint if no new one is provided.
    final existing = trusted.where((p) => p.id == peer.id).firstOrNull;
    final upsert = TrustedSyncPeer(
      id: peer.id,
      name: peer.name,
      host: peer.host,
      port: peer.port,
      deviceType: peer.deviceType == SyncDeviceType.unknown
          ? existing?.deviceType ?? SyncDeviceType.unknown
          : peer.deviceType,
      fingerprint: fingerprint ?? existing?.fingerprint,
      lastSeenAtIso: DateTime.now().toIso8601String(),
    );
    final next = [...trusted.where((p) => p.id != upsert.id), upsert];

    await _setSetting(
      SettingsKeys.syncTrustedPeersJson,
      encodeTrustedPeers(next),
    );
    await _setSetting(SettingsKeys.syncLastTrustedPeerId, upsert.id);
    return upsert;
  }

  void _evictExpiredPairRequests() {
    final now = DateTime.now();
    final expired = _pendingPairRequests.values
        .where((r) => now.difference(r.createdAt) > _pairRequestLifetime)
        .toList(growable: false);

    for (final request in expired) {
      _pendingPairRequests.remove(request.requestId);
      _eventController.add(
        PairRequestTimedOutEvent(
          PendingPairRequest(
            requestId: request.requestId,
            peer: request.peer,
            requestedAt: request.createdAt,
          ),
        ),
      );
      unawaited(_notifyInitiatorOfTimeout(request));
    }
  }

  Future<void> _sendAnnounce(String deviceId) async {
    if (kIsWeb) {
      return;
    }

    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
      reusePort: false,
    );
    socket.broadcastEnabled = true;

    try {
      final packet = utf8.encode(
        jsonEncode({
          'type': _announceType,
          'protocol': _protocolVersion,
          'from': _localIdentityMap(deviceId),
          'port': defaultLanPort,
        }),
      );
      socket.send(packet, InternetAddress('255.255.255.255'), defaultLanPort);
    } finally {
      socket.close();
    }
  }

  Map<String, dynamic>? _decodePacket(List<int> data) {
    try {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String _currentDeviceName() {
    final fallbackType = _currentDeviceType();

    if (!_isPlaceholderName(_cachedDeviceName)) {
      return _cachedDeviceName!.trim();
    }

    if (kIsWeb) {
      return _defaultDeviceName(SyncDeviceType.web);
    }

    try {
      if (Platform.isWindows) {
        final computerName = Platform.environment['COMPUTERNAME'];
        if (!_isPlaceholderName(computerName)) {
          return computerName!.trim();
        }
      }

      if (Platform.isMacOS || Platform.isLinux) {
        final hostName = Platform.environment['HOSTNAME'];
        if (!_isPlaceholderName(hostName)) {
          return hostName!.trim();
        }
      }

      final host = Platform.localHostname.trim();
      if (!_isPlaceholderName(host)) {
        return host;
      }

      return _defaultDeviceName(fallbackType);
    } catch (_) {
      return _defaultDeviceName(fallbackType);
    }
  }

  /// Refreshes the cached device name using device_info_plus.
  /// Call this during service initialization or when device sync is enabled.
  Future<void> refreshDeviceName() async {
    _cachedDeviceName = await _getDetailedDeviceName();
  }

  /// Asynchronously gets the full device name using device_info_plus.
  /// This method provides more detailed device names including mobile devices.
  Future<String> _getDetailedDeviceName() async {
    final fallbackType = _currentDeviceType();
    if (kIsWeb) {
      return _defaultDeviceName(SyncDeviceType.web);
    }

    try {
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        final model = info.model.trim();
        if (!_isPlaceholderName(model)) {
          return model;
        }
        final device = info.device.trim();
        if (!_isPlaceholderName(device)) {
          return device;
        }
        return _defaultDeviceName(fallbackType);
      }

      if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        final name = info.name.trim();
        if (!_isPlaceholderName(name)) {
          return name;
        }
        final model = info.model.trim();
        if (!_isPlaceholderName(model)) {
          return model;
        }
        return _defaultDeviceName(fallbackType);
      }

      if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        final computerName = info.computerName.trim();
        if (!_isPlaceholderName(computerName)) {
          return computerName;
        }
        final envName = Platform.environment['COMPUTERNAME'];
        if (!_isPlaceholderName(envName)) {
          return envName!.trim();
        }
        return _defaultDeviceName(fallbackType);
      }

      if (Platform.isMacOS) {
        final info = await deviceInfo.macOsInfo;
        final computerName = info.computerName.trim();
        if (!_isPlaceholderName(computerName)) {
          return computerName;
        }
        return _defaultDeviceName(fallbackType);
      }

      if (Platform.isLinux) {
        final info = await deviceInfo.linuxInfo;
        final name = info.name.trim();
        if (!_isPlaceholderName(name)) {
          return name;
        }
        final hostname = Platform.environment['HOSTNAME'];
        if (!_isPlaceholderName(hostname)) {
          return hostname!.trim();
        }
        return _defaultDeviceName(fallbackType);
      }

      return _defaultDeviceName(fallbackType);
    } catch (_) {
      return _defaultDeviceName(fallbackType);
    }
  }

  // ── Encryption helpers ───────────────────────────────────────────────────

  /// Returns the local X25519 static key pair, generating and persisting it on
  /// first use.  The key pair authenticates this device during TCP sync
  /// handshakes and binds encrypted sessions to known peer identities.
  Future<SimpleKeyPair> _getOrGenerateStaticKeyPair() async {
    final settings = ref.read(settingsProvider);
    final storedPriv =
        (settings[SettingsKeys.syncStaticPrivateKey] as String?)?.trim() ?? '';
    final storedPub =
        (settings[SettingsKeys.syncStaticPublicKey] as String?)?.trim() ?? '';
    if (storedPriv.isNotEmpty && storedPub.isNotEmpty) {
      try {
        return await SyncCrypto.importKeyPair(storedPriv, storedPub);
      } catch (_) {
        // Fall through and regenerate if stored keys are corrupt.
      }
    }
    final pair = await SyncCrypto.generateKeyPair();
    await _setSetting(
      SettingsKeys.syncStaticPrivateKey,
      await SyncCrypto.exportPrivateKey(pair),
    );
    await _setSetting(
      SettingsKeys.syncStaticPublicKey,
      await SyncCrypto.exportPublicKey(pair),
    );
    return pair;
  }

  /// Performs the client-side encrypted handshake over [socket].
  ///
  /// Sends a client-hello JSON line, reads the server-hello, derives the shared
  /// AES-256-GCM session key, and strictly verifies the server identity key
  /// against the pinned fingerprint from pairing.
  ///
  /// Returns the derived [SecretKey] and an active [StreamIterator] positioned
  /// after the server-hello line.  The caller is responsible for cancelling the
  /// iterator when done.
  Future<({SecretKey sessionKey, StreamIterator<String> lineIter})>
  _performClientHandshake(
    Socket socket,
    TrustedSyncPeer targetPeer,
    String localDeviceId,
  ) async {
    final localEphemeral = await SyncCrypto.generateKeyPair();
    final localEphemeralPub = await localEphemeral.extractPublicKey();
    final localStaticPair = await _getOrGenerateStaticKeyPair();
    final localStaticPub = await localStaticPair.extractPublicKey();

    // Send client hello.
    socket.add(
      utf8.encode(
        '${jsonEncode({'v': 2, 'peerId': localDeviceId, 'eph': base64.encode(localEphemeralPub.bytes), 'spub': base64.encode(localStaticPub.bytes)})}\n',
      ),
    );
    await socket.flush();

    // Create a single StreamIterator for all subsequent reads from this socket.
    final lineIter = StreamIterator<String>(
      utf8.decoder.bind(socket).transform(const LineSplitter()),
    );

    // Read server hello.
    bool gotLine;
    try {
      gotLine = await lineIter.moveNext().timeout(const Duration(seconds: 10));
    } on TimeoutException {
      await lineIter.cancel();
      throw const DeviceSyncException(
        'Remote device did not respond to encrypted handshake.',
      );
    }
    if (!gotLine || lineIter.current.trim().isEmpty) {
      await lineIter.cancel();
      throw const DeviceSyncException(
        'Remote device closed connection during handshake.',
      );
    }

    Map<String, dynamic> serverHello;
    try {
      serverHello = jsonDecode(lineIter.current.trim()) as Map<String, dynamic>;
    } catch (_) {
      await lineIter.cancel();
      throw const DeviceSyncException(
        'Invalid handshake response from remote device.',
      );
    }
    if (serverHello['v'] != 2) {
      await lineIter.cancel();
      throw const DeviceSyncException(
        'Remote device does not support encrypted sync (v2). '
        'Please update UniKM on both devices.',
      );
    }

    final serverEphB64 = serverHello['eph'] as String? ?? '';
    final serverStaticPubB64 = serverHello['spub'] as String? ?? '';
    if (serverEphB64.isEmpty) {
      await lineIter.cancel();
      throw const DeviceSyncException(
        'Remote device sent an invalid handshake response.',
      );
    }

    final expectedFingerprint = (targetPeer.fingerprint ?? '').trim();
    if (expectedFingerprint.isEmpty) {
      await lineIter.cancel();
      throw const DeviceSyncException(
        'Remote identity key is missing for this pairing. '
        'Remove and re-pair before syncing.',
      );
    }
    if (serverStaticPubB64.isEmpty) {
      await lineIter.cancel();
      throw const DeviceSyncException(
        'Remote device did not provide identity key during handshake.',
      );
    }
    if (serverStaticPubB64 != expectedFingerprint) {
      await lineIter.cancel();
      throw const DeviceSyncException(
        'Remote identity verification failed — possible man-in-the-middle attack. '
        'Remove and re-pair with this device to restore trust.',
      );
    }

    final serverEphPub = SyncCrypto.publicKeyFromBase64(serverEphB64);
    final serverStaticPub = SyncCrypto.publicKeyFromBase64(serverStaticPubB64);

    final sessionKey = await SyncCrypto.deriveSessionKey(
      localEphemeral: localEphemeral,
      remoteEphemeralPub: serverEphPub,
      localStatic: localStaticPair,
      remoteStaticPub: serverStaticPub,
      clientEphemeralPubBytes: localEphemeralPub.bytes,
      serverEphemeralPubBytes: serverEphPub.bytes,
    );

    return (sessionKey: sessionKey, lineIter: lineIter);
  }

  /// Performs the server-side encrypted handshake.
  ///
  /// Parses the [clientHello] JSON that was already read from the socket,
  /// generates the server ephemeral key, sends the server-hello reply, then
  /// derives and returns the shared session key after strict fingerprint
  /// verification of the client identity key.
  ///
  /// Returns `null` if the client is not trusted or if key verification fails.
  Future<({SecretKey sessionKey})?> _performServerHandshake(
    Socket socket,
    Map<String, dynamic> clientHello,
  ) async {
    final clientPeerId = (clientHello['peerId'] as String?)?.trim() ?? '';
    final clientEphB64 = clientHello['eph'] as String? ?? '';
    final clientStaticPubB64 = clientHello['spub'] as String? ?? '';

    if (clientPeerId.isEmpty || clientEphB64.isEmpty) return null;
    if (!_isTrustedPeer(clientPeerId)) return null;

    // Get or generate server's static key pair.
    final serverStaticPair = await _getOrGenerateStaticKeyPair();
    final serverStaticPub = await serverStaticPair.extractPublicKey();

    // Generate a fresh ephemeral key for this session.
    final serverEphemeral = await SyncCrypto.generateKeyPair();
    final serverEphemeralPub = await serverEphemeral.extractPublicKey();

    // Send server hello.
    socket.add(
      utf8.encode(
        '${jsonEncode({'v': 2, 'eph': base64.encode(serverEphemeralPub.bytes), 'spub': base64.encode(serverStaticPub.bytes)})}\n',
      ),
    );
    await socket.flush();

    final clientEphPub = SyncCrypto.publicKeyFromBase64(clientEphB64);

    final trusted = decodeTrustedPeers(
      ref.read(settingsProvider)[SettingsKeys.syncTrustedPeersJson]
              as String? ??
          DefaultSettings.syncTrustedPeersJson,
    );
    final storedPeer = trusted.where((p) => p.id == clientPeerId).firstOrNull;
    final expectedFingerprint = (storedPeer?.fingerprint ?? '').trim();

    if (clientStaticPubB64.isEmpty) {
      debugPrint('Sync: missing client identity key for $clientPeerId');
      return null;
    }
    if (expectedFingerprint.isEmpty) {
      debugPrint(
        'Sync: stored fingerprint missing for $clientPeerId; re-pair required.',
      );
      return null;
    }
    if (clientStaticPubB64 != expectedFingerprint) {
      debugPrint('Sync: client identity verification failed for $clientPeerId');
      return null;
    }

    final clientStaticPub = SyncCrypto.publicKeyFromBase64(clientStaticPubB64);

    final sessionKey = await SyncCrypto.deriveSessionKey(
      localEphemeral: serverEphemeral,
      remoteEphemeralPub: clientEphPub,
      localStatic: serverStaticPair,
      remoteStaticPub: clientStaticPub,
      clientEphemeralPubBytes: clientEphPub.bytes,
      serverEphemeralPubBytes: serverEphemeralPub.bytes,
    );

    return (sessionKey: sessionKey);
  }
}
