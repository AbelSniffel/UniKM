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
import '../../features/sync/data/sync_firewall.dart';
import '../../features/sync/domain/sync_ports.dart';
import '../../features/sync/domain/sync_revocation.dart';

import '../database/database.dart';
import '../models/device_sync_models.dart';
import '../settings/settings_model.dart';
import 'backup_service.dart';
import 'database_switching.dart';
import 'steam_service.dart';
import 'sync_crypto.dart';
import 'sync_payload_codec.dart';

export '../../features/sync/data/sync_firewall.dart'
    show WindowsFirewallCheckResult, LinuxFirewallCheckResult;

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
    this.localContentDigest = '',
    this.remoteContentDigest = '',
    this.remoteSyncProtocol = 0,
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
  final String localContentDigest;
  final String remoteContentDigest;
  final int remoteSyncProtocol;

  bool get hasContentDigests =>
      localContentDigest.isNotEmpty && remoteContentDigest.isNotEmpty;
  bool get digestMismatch =>
      hasContentDigests && localContentDigest != remoteContentDigest;

  bool get hasConvergedSnapshot {
    if (hasContentDigests) return localContentDigest == remoteContentDigest;
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
  bool get matches =>
      reachable &&
      !dbNameMismatch &&
      !digestMismatch &&
      !localHasChanges &&
      !remoteHasChanges;
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
    this.remoteContentDigest = '',
    this.remoteSyncProtocol = 0,
  });

  factory _PeerPingResult.fromPong(Map<String, dynamic> payload) =>
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
        remoteContentDigest: payload['contentDigest'] as String? ?? '',
        remoteSyncProtocol: (payload['syncProtocol'] as num?)?.toInt() ?? 0,
      );

  final bool reachable;
  final bool remoteTrusted;
  final String? remoteDbName;
  final int remoteRevision;
  final int remoteKnownLocalRevision;
  final int remoteKnownLocalSyncAtMillis;
  final String? remoteSyncRevisionId;
  final int remoteDbTimestampMillis;
  final bool remoteReceiverSyncInFlight;
  final String remoteContentDigest;
  final int remoteSyncProtocol;
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
  DeviceSyncService({
    required this.ref,
    this.discoveryPort = defaultLanPort,
    this.transferPort = SyncPorts.transfer,
  }) : _codec = SyncPayloadCodec(getDatabase: () => ref.read(databaseProvider));

  final Ref ref;
  final int discoveryPort;
  final int transferPort;
  final SyncPayloadCodec _codec;
  bool _foreground = true;
  final _activeSyncSockets = <Socket>{};

  Future<void> setForeground(bool foreground) async {
    _foreground = foreground;
    if (!foreground) {
      for (final socket in _activeSyncSockets.toList()) {
        socket.destroy();
      }
      _activeSyncSockets.clear();
      await stopDiscoveryResponder();
    }
  }

  Future<Socket> _connectSyncSocket(String host, int port) async {
    if (!_foreground) throw const DeviceSyncException('Sync is paused.');
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 10),
    );
    socket.setOption(SocketOption.tcpNoDelay, true);
    if (!_foreground) {
      socket.destroy();
      throw const DeviceSyncException('Sync is paused.');
    }
    _trackSyncSocket(socket);
    return socket;
  }

  void _trackSyncSocket(Socket socket) {
    _activeSyncSockets.add(socket);
    unawaited(
      socket.done.then<void>(
        (_) {
          _activeSyncSockets.remove(socket);
        },
        onError: (Object _) {
          _activeSyncSockets.remove(socket);
        },
      ),
    );
  }

  final StreamController<SyncEvent> _eventController =
      StreamController<SyncEvent>.broadcast();

  /// Stream of events emitted by this service as sync lifecycle events occur.
  /// Subscribe in [DeviceSyncNotifier] to update UI state atomically.
  Stream<SyncEvent> get syncEvents => _eventController.stream;

  void _emitSyncEvent(SyncEvent event) {
    if (!_eventController.isClosed && ref.mounted) _eventController.add(event);
  }

  void _reportTransfer(String message) =>
      _emitSyncEvent(SyncTransferActivityEvent(active: true, message: message));

  SyncRevocationLedger get _revocationLedger => SyncRevocationLedger.decode(
    ref.read(settingsProvider)[SettingsKeys.syncRevokedPeersJson] as String?,
  );

  bool _acceptFreshControl(Map<String, dynamic> payload, String peerId) {
    final pairingId = _trustedPeerById(peerId)?.pairingId ?? '';
    // Existing pairings can still accept their legacy authenticated removal.
    if (pairingId.isEmpty && payload['messageId'] == null) return true;
    return _controlReplayGuard.accept(
      peerId: peerId,
      pairingId: pairingId,
      messageId: payload['messageId'] as String? ?? '',
      issuedAtMillis: (payload['issuedAtMillis'] as num?)?.toInt() ?? 0,
      nowMillis: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Direct hints are coalesced for a short burst. Lost UDP hints are repaired
  /// by periodic anti-entropy; hints never apply records or advance cursors.
  Future<void> notifyLocalDataChanged() async {
    if (!_foreground || _responderSocket == null) return;
    _changeSignalTimer ??= Timer(const Duration(milliseconds: 40), () {
      _changeSignalTimer = null;
      unawaited(_sendChangeSignals());
    });
  }

  Future<void> _sendChangeSignals() async {
    final socket = _responderSocket;
    if (!_foreground || socket == null) return;
    final localId = await _ensureDeviceId();
    if (!_foreground || !ref.mounted) return;
    final peers = decodeTrustedPeers(
      ref.read(settingsProvider)[SettingsKeys.syncTrustedPeersJson]
              as String? ??
          '[]',
    );
    await Future.wait(
      peers.map((peer) async {
        try {
          final endpoint = _freshAnnouncedPeerById(peer.id);
          final payload = await _attachControlAuthIfTrusted(
            payload: {
              'type': _changedType,
              'protocol': _protocolVersion,
              'from': _localIdentityMap(localId),
              'messageId': _uuid.v4(),
              'issuedAtMillis': DateTime.now().millisecondsSinceEpoch,
            },
            peerId: peer.id,
          );
          socket.send(
            utf8.encode(jsonEncode(payload)),
            InternetAddress(endpoint?.host ?? peer.host),
            endpoint?.port ?? peer.port,
          );
        } catch (_) {
          // An offline peer catches up using its durable revision checkpoint.
        }
      }),
    );
  }

  Future<void> dispose() async {
    await setForeground(false);
    await _eventController.close();
  }

  /// Cached device name to avoid repeated async lookups
  String? _cachedDeviceName;

  static const int defaultLanPort = SyncPorts.discovery;
  // Require the rebuilt protocol for every control and transfer path.
  static const int _protocolVersion = supportedDeviceSyncProtocol;
  static const String _incompatibleSyncMessage =
      'Update UniKM on both devices to use the reworked device sync.';
  static const Duration _discoveryWindow = Duration(milliseconds: 1200);
  static const Duration _announceInterval = Duration(seconds: 30);
  static const Duration _pairRequestTimeout = Duration(seconds: 30);
  static const Duration _pairCommitTimeout = Duration(seconds: 30);
  static const Duration _pairFinalizeTimeout = Duration(seconds: 30);
  static const Duration _pairRequestLifetime = Duration(minutes: 2);
  static const String _discoverType = 'unikm_sync_discover';
  static const String _discoverResponseType = 'unikm_sync_discover_response';
  static const String _announceType = 'unikm_sync_announce';
  static const String _offlineType = 'unikm_sync_offline';
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
  static const String _changedType = 'unikm_sync_changed';
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
  Future<void>? _responderStartup;
  Future<void>? _serverStartup;
  int _networkEpoch = 0;
  StreamSubscription<RawSocketEvent>? _responderSub;
  Timer? _announceTimer;
  final Map<String, _IncomingPairRequestState> _pendingPairRequests = {};
  final Map<String, List<int>> _pairDecisions = {};
  final Map<String, Completer<void>> _outgoingPairCancellations = {};
  final Set<String> _pairFinalizing = {};
  final Map<String, DiscoveredSyncPeer> _announcedPeers = {};

  /// Timestamp of the last announce received per peer, used to expire stale
  /// cache entries when a device goes offline.
  final Map<String, DateTime> _announcedPeersSeenAt = {};
  final Map<String, DateTime> _offlinePeersSeenAt = {};

  /// Completers waiting for a pong reply routed through the responder socket.
  final Map<String, _PendingPongState> _pendingPongs = {};
  ServerSocket? _syncServer;

  /// True while an incoming (receiver-role) sync is being handled.  Used by
  /// [DeviceSyncNotifier] to suppress competing initiator syncs that would
  /// race to overwrite the revision ID adopted from the incoming sender.
  int _incomingSyncCount = 0;
  bool get _receiverSyncInFlight => _incomingSyncCount > 0;
  bool get isReceiverSyncInFlight => _receiverSyncInFlight;
  final _controlReplayGuard = SyncControlReplayGuard();
  Future<SimpleKeyPair>? _staticKeyFuture;
  final Map<String, Future<SecretKey>> _controlKeys = {};
  Timer? _changeSignalTimer;

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
      'port': discoveryPort,
      'transferPort': transferPort,
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
      'contentDigest': db == null ? '' : await _codec.getDatasetDigest(),
    };
  }

  Future<DeviceSyncSnapshot> loadSnapshot() async {
    final settings = ref.read(settingsProvider);
    final deviceId = await _ensureDeviceId();

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

    if (enabled && _foreground) {
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
    if (!_foreground) return const [];
    if (kIsWeb) {
      return const [];
    }

    final deviceId = await _ensureDeviceId();
    await ensureDiscoveryResponder(deviceId: deviceId);

    final scanStartedAt = DateTime.now();
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
        final advertisedTransferPort = (payload['transferPort'] as num?)
            ?.toInt();

        discoveredById[peerId] = DiscoveredSyncPeer(
          id: peerId,
          name: _normalizeDeviceName(peerName, fallbackType: peerType),
          host: (host == null || host.isEmpty)
              ? datagram.address.address
              : host,
          port: port,
          transferPort: advertisedTransferPort,
          syncProtocol: (payload['protocol'] as num?)?.toInt() ?? 0,
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
    // A shutdown packet can arrive while this scan is still collecting replies.
    discoveredById.removeWhere((id, _) {
      final offlineAt = _offlinePeersSeenAt[id];
      return offlineAt != null && offlineAt.isAfter(scanStartedAt);
    });
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

  Future<void> _requirePairingCompatibility(
    DiscoveredSyncPeer peer,
    String localDeviceId,
  ) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final supported = Completer<void>();
    final address = InternetAddress(peer.host);
    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null || datagram.address.address != address.address) {
        return;
      }
      final packet = _decodePacket(datagram.data);
      if (packet == null ||
          packet['type'] != _discoverResponseType ||
          packet['protocol'] != _protocolVersion) {
        return;
      }
      final identity = packet['from'];
      if (identity is Map &&
          identity['id'] == peer.id &&
          !supported.isCompleted) {
        supported.complete();
      }
    });
    void probe() => socket.send(
      utf8.encode(
        jsonEncode({
          'type': _discoverType,
          'protocol': _protocolVersion,
          'from': _localIdentityMap(localDeviceId),
          'replyPort': socket.port,
        }),
      ),
      address,
      peer.port,
    );
    final retry = Timer(const Duration(milliseconds: 500), probe);
    try {
      probe();
      await supported.future.timeout(const Duration(milliseconds: 1500));
    } on TimeoutException {
      throw const DeviceSyncException(_incompatibleSyncMessage);
    } finally {
      retry.cancel();
      await subscription.cancel();
      socket.close();
    }
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

    await _requirePairingCompatibility(peer, localDeviceId);

    final requestId = _uuid.v4();
    final localStaticPair = await _getOrGenerateStaticKeyPair();
    final localStaticPub = await localStaticPair.extractPublicKey();
    final localStaticPubB64 = base64.encode(localStaticPub.bytes);
    final verificationCode = _generatePairVerificationCode();
    if (!_foreground ||
        !ref.mounted ||
        ref.read(settingsProvider)[SettingsKeys.syncEnabled] != true) {
      throw const DeviceSyncException('Pairing was canceled.');
    }

    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
      reusePort: false,
    );
    if (!_foreground || !ref.mounted) {
      socket.close();
      throw const DeviceSyncException('Pairing was canceled.');
    }
    final lifecycleCancellation = Completer<void>();
    _outgoingPairCancellations[requestId] = lifecycleCancellation;
    void requirePairingActive() {
      if (!_foreground ||
          !ref.mounted ||
          lifecycleCancellation.isCompleted ||
          ref.read(settingsProvider)[SettingsKeys.syncEnabled] != true) {
        throw const DeviceSyncException('Pairing was canceled.');
      }
    }

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

    var remoteDecisionSpub = '';
    Timer? retryTimer;
    List<int>? retryPacket;
    void sendStage(List<int> packet) {
      requirePairingActive();
      retryPacket = packet;
      socket.send(packet, InternetAddress(peer.host), peer.port);
      retryTimer ??= Timer.periodic(const Duration(milliseconds: 800), (_) {
        if (retryPacket != null &&
            _foreground &&
            ref.mounted &&
            !lifecycleCancellation.isCompleted) {
          socket.send(retryPacket!, InternetAddress(peer.host), peer.port);
        }
      });
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
      if (type == _pairCommitAckType || type == _pairFinalizeAckType) {
        unawaited(() async {
          if (!await _verifyControlAuthForFingerprint(
            payload: payload,
            expectedFingerprint: remoteDecisionSpub,
            pairingId: requestId,
          )) {
            return;
          }
          final completer = type == _pairCommitAckType
              ? commitAckCompleter
              : finalizeAckCompleter;
          if (!completer.isCompleted) {
            completer.complete(
              _PairAckResponse(
                accepted: payload['accepted'] == true,
                remoteStaticPubB64: payload['spub'] as String?,
              ),
            );
          }
        }());
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
      sendStage(pairRequestPacket);

      // Show code to sender now that request has been sent
      showVerificationCode?.call(verificationCode);

      // Keep waiting for receiver decisions until code verification succeeds,
      // the sender cancels, or the request is declined/times out.
      final Future<Object?> cancelFuture = onUserCancel == null
          ? lifecycleCancellation.future
          : Future.any<void>([onUserCancel, lifecycleCancellation.future]);
      var userCanceled = false;
      final stageCancellation = cancelFuture.then((_) {
        userCanceled = true;
        return const _PairAckResponse(accepted: false);
      });

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
          requirePairingActive();
          await _sendPairNotice(
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
          await _sendPairNotice(
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
          await _sendPairNotice(
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
          await _sendPairNotice(
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
          await _sendPairNotice(
            peer: peer,
            requestId: requestId,
            localDeviceId: localDeviceId,
            type: _pairCodeRejectedType,
            reason: 'code_mismatch',
          );
          continue;
        }

        break;
      }

      final pairCommitPacket = utf8.encode(
        jsonEncode(
          await _attachControlAuthForFingerprint(
            payload: {
              'type': _pairCommitType,
              'protocol': _protocolVersion,
              'requestId': requestId,
              'replyPort': socket.port,
              'spub': localStaticPubB64,
              'ok': true,
              'from': _localIdentityMap(localDeviceId),
            },
            remoteStaticPubB64: remoteDecisionSpub,
            pairingId: requestId,
          ),
        ),
      );
      sendStage(pairCommitPacket);

      final commitAck = await Future.any([
        commitAckCompleter.future.timeout(
          _pairCommitTimeout,
          onTimeout: () => const _PairAckResponse(accepted: false),
        ),
        stageCancellation,
      ]);
      if (!commitAck.accepted) {
        requirePairingActive();
        await _sendPairNotice(
          peer: peer,
          requestId: requestId,
          localDeviceId: localDeviceId,
        );
        if (userCanceled) {
          throw const DeviceSyncException('Pairing was canceled.');
        }
        throw const DeviceSyncException(
          'Pairing handshake timed out before receiver confirmation.',
        );
      }

      final remoteCommitAckSpub = (commitAck.remoteStaticPubB64 ?? '').trim();
      if (remoteCommitAckSpub.isNotEmpty &&
          remoteCommitAckSpub != remoteDecisionSpub) {
        await _sendPairNotice(
          peer: peer,
          requestId: requestId,
          localDeviceId: localDeviceId,
        );
        throw const DeviceSyncException(
          'Remote pairing identity changed during confirmation. Retry pairing.',
        );
      }

      requirePairingActive();
      // Prepare a durable rejection before finalizing. If the app stops after
      // the receiver commits, reconnection can still undo that partial pairing.
      await _setSetting(
        SettingsKeys.syncRevokedPeersJson,
        _revocationLedger
            .record(
              SyncRevocationRecord(
                peerId: peer.id,
                fingerprint: remoteDecisionSpub,
                pairingId: requestId,
                revokedAtMillis: DateTime.now().millisecondsSinceEpoch,
              ),
            )
            .encode(),
      );
      requirePairingActive();
      final pairFinalizePacket = utf8.encode(
        jsonEncode(
          await _attachControlAuthForFingerprint(
            payload: {
              'type': _pairFinalizeType,
              'protocol': _protocolVersion,
              'requestId': requestId,
              'replyPort': socket.port,
              'spub': localStaticPubB64,
              'ok': true,
              'from': _localIdentityMap(localDeviceId),
            },
            remoteStaticPubB64: remoteDecisionSpub,
            pairingId: requestId,
          ),
        ),
      );
      sendStage(pairFinalizePacket);

      final finalizeAck = await Future.any([
        finalizeAckCompleter.future.timeout(
          _pairFinalizeTimeout,
          onTimeout: () => const _PairAckResponse(accepted: false),
        ),
        stageCancellation,
      ]);
      if (!finalizeAck.accepted) {
        requirePairingActive();
        await _sendPairNotice(
          peer: peer,
          requestId: requestId,
          localDeviceId: localDeviceId,
        );
        // The receiver may have committed while its final ACK was lost. Keep
        // the authenticated rejection even though we never established trust.
        await _setSetting(
          SettingsKeys.syncRevokedPeersJson,
          _revocationLedger
              .record(
                SyncRevocationRecord(
                  peerId: peer.id,
                  fingerprint: remoteDecisionSpub,
                  pairingId: requestId,
                  revokedAtMillis: DateTime.now().millisecondsSinceEpoch,
                ),
              )
              .encode(),
        );
        await _sendUntrustPacket(
          TrustedSyncPeer(
            id: peer.id,
            name: peer.name,
            host: peer.host,
            port: peer.port,
            transferPort: peer.transferPort,
            deviceType: peer.deviceType,
            fingerprint: remoteDecisionSpub,
            pairingId: requestId,
          ),
          remoteFingerprint: remoteDecisionSpub,
        );
        if (userCanceled) {
          throw const DeviceSyncException('Pairing was canceled.');
        }
        throw const DeviceSyncException(
          'Pairing handshake timed out waiting for final receiver OK.',
        );
      }

      final remoteFinalizeSpub = (finalizeAck.remoteStaticPubB64 ?? '').trim();
      if (remoteFinalizeSpub.isNotEmpty &&
          remoteFinalizeSpub != remoteDecisionSpub) {
        await _sendPairNotice(
          peer: peer,
          requestId: requestId,
          localDeviceId: localDeviceId,
        );
        throw const DeviceSyncException(
          'Remote pairing identity changed during final confirmation. Retry pairing.',
        );
      }

      requirePairingActive();
      return _upsertTrustedPeer(
        DiscoveredSyncPeer(
          id: peer.id,
          name: peer.name,
          host: peer.host,
          port: peer.port,
          transferPort: peer.transferPort,
          deviceType: peer.deviceType,
        ),
        fingerprint: remoteDecisionSpub,
        pairingId: requestId,
      );
    } finally {
      _outgoingPairCancellations.remove(requestId);
      retryTimer?.cancel();
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

      _pairDecisions[requestId] = decisionPacket;
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
    final canceledRequests = _pendingPairRequests.values
        .where((request) => request.peer.id == peerId)
        .map((request) => request.requestId)
        .toList();
    for (final requestId in canceledRequests) {
      _pendingPairRequests.remove(requestId);
      _pairDecisions.remove(requestId);
    }
    final trusted = decodeTrustedPeers(
      ref.read(settingsProvider)[SettingsKeys.syncTrustedPeersJson]
              as String? ??
          DefaultSettings.syncTrustedPeersJson,
    );

    // Look up peer info before removing so we can notify them.
    final target = trusted.where((peer) => peer.id == peerId).firstOrNull;
    if (target == null) return;
    if ((target.fingerprint ?? '').isNotEmpty) {
      final ledger = _revocationLedger.record(
        SyncRevocationRecord(
          peerId: target.id,
          fingerprint: target.fingerprint!,
          pairingId: target.pairingId,
          revokedAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      // Persist the rejection key before removing trust or attempting delivery.
      await _setSetting(SettingsKeys.syncRevokedPeersJson, ledger.encode());
    }

    // Notify the removed peer before deleting local trust metadata so auth can
    // still be computed with the pinned fingerprint.
    if (notifyRemote && !kIsWeb) {
      try {
        await _sendUntrustPacket(target, remoteFingerprint: target.fingerprint);
      } catch (_) {
        // Reconnection will deliver the durable authenticated rejection.
      }
    }

    final latest = decodeTrustedPeers(
      ref.read(settingsProvider)[SettingsKeys.syncTrustedPeersJson]
              as String? ??
          '[]',
    );
    final next = latest
        .where(
          (peer) =>
              peer.id != peerId ||
              peer.pairingId != target.pairingId ||
              peer.fingerprint != target.fingerprint,
        )
        .toList(growable: false);
    await _setSetting(
      SettingsKeys.syncTrustedPeersJson,
      encodeTrustedPeers(next),
    );

    final currentLast =
        (ref.read(settingsProvider)[SettingsKeys.syncLastTrustedPeerId]
                as String?)
            ?.trim();
    if (currentLast == peerId && _trustedPeerById(peerId) == null) {
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
          'messageId': _uuid.v4(),
          'issuedAtMillis': DateTime.now().millisecondsSinceEpoch,
        },
        remoteStaticPubB64: remoteFingerprint,
        pairingId: peer.pairingId,
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
      final deviceId = await _ensureDeviceId();
      await _sendOffline(deviceId);
      await stopDiscoveryResponder();
    }
  }

  final SyncFirewall _firewall = SyncFirewall();

  Future<WindowsFirewallCheckResult?> checkWindowsFirewallAccess() =>
      _firewall.checkWindowsFirewallAccess();
  Future<bool> grantWindowsFirewallAccess() =>
      _firewall.grantWindowsFirewallAccess();
  Future<bool> openWindowsFirewallAllowedApps() =>
      _firewall.openWindowsFirewallAllowedApps();
  Future<bool> openWindowsFirewallAdvancedSettings() =>
      _firewall.openWindowsFirewallAdvancedSettings();
  Future<LinuxFirewallCheckResult?> checkLinuxFirewallAccess() =>
      _firewall.checkLinuxFirewallAccess();
  Future<bool> grantLinuxFirewallAccess() =>
      _firewall.grantLinuxFirewallAccess();
  Future<bool> clearLinuxFirewallAccess() =>
      _firewall.clearLinuxFirewallAccess();

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
    if (!kIsWeb && Platform.isLinux) {
      // NUL character is the only character not allowed in Linux filenames
      if (trimmed.contains('0')) {
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
      transferPort: discoveredPeer.transferPort,
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
    if (announcedPeer != null && !announcedPeer.isSyncCompatible) {
      throw const DeviceSyncException(_incompatibleSyncMessage);
    }
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
    if (matched != null && !matched.isSyncCompatible) {
      throw const DeviceSyncException(_incompatibleSyncMessage);
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

    // Resolve the target path: check the default DB directory first so that
    // well-known filenames (e.g. keys.db) are found in their canonical
    // location rather than the current DB's directory.
    final defaultDbPath = await AppDatabase.getDatabasePath();
    final defaultDbDir = p.dirname(defaultDbPath);
    var targetBasePath = p.join(defaultDbDir, normalizedRemoteName);
    if (!File(targetBasePath).existsSync()) {
      // Fallback: check the current DB's directory.
      final altPath = p.join(p.dirname(currentBasePath), normalizedRemoteName);
      if (File(altPath).existsSync()) {
        targetBasePath = altPath;
      }
    }

    _reportTransfer(
      '[${targetPeer.name}] Switching local database to "$normalizedRemoteName" to match remote...',
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

  /// Exchanges both captured deltas in one encrypted connection. Automatic
  /// sync never switches databases, copies revision IDs, or assumes clocks agree.
  Future<void> performAutomaticSync({
    required String peerId,
    bool fullScan = false,
    DeviceSyncCodeCheckResult? preflight,
  }) async {
    if (!_foreground ||
        ref.read(settingsProvider)[SettingsKeys.syncEnabled] != true) {
      throw const DeviceSyncException('Device sync is paused.');
    }
    var target = _trustedPeerById(peerId);
    final db = ref.read(databaseProvider);
    if (target == null || db == null) {
      throw const DeviceSyncException(
        'Paired device or database is unavailable.',
      );
    }
    final check = preflight ?? await checkSyncCode(peerId: peerId);
    target = check.peer ?? target;
    if (!check.reachable || !_isTrustedPeer(peerId)) {
      throw const DeviceSyncException(
        'Paired device is offline or was unpaired.',
      );
    }
    if (check.dbNameMismatch) {
      throw const DeviceSyncException('Devices are using different databases.');
    }
    if (check.remoteSyncProtocol != _protocolVersion) {
      throw const DeviceSyncException(
        'Update UniKM on the paired device to use automatic multi-device sync.',
      );
    }
    if (check.matches && !fullScan) return;
    final dbName = _currentDatabaseName();
    final localId = await _ensureDeviceId();
    // Repair equal/stale cursors whose content disagrees, e.g. after a restore.
    final repair =
        fullScan ||
        (check.digestMismatch &&
            !check.localHasChanges &&
            !check.remoteHasChanges) ||
        check.remoteKnownLocalRevision > check.localRevision ||
        check.localKnownRemoteRevision > check.remoteRevision;
    final request = await _codec.buildDeltaPayload(
      syncRevisionId: _currentSyncCode(),
      baseRevision: check.remoteKnownLocalRevision,
      baseSyncAtMillis: check.remoteKnownLocalSyncAtMillis,
      localRevision: check.localRevision,
      includeAllGames: repair,
      includeSteamCache: false,
    );
    request.addAll({
      'exchangeRequest': true,
      'syncProtocol': 3,
      'requestingPeerId': localId,
      'deviceName': _currentDeviceName(),
      'senderDbName': dbName,
      'expectedReceiverDbName': check.remoteDbName ?? dbName,
      'knownRemoteRevision': check.localKnownRemoteRevision,
      'knownRemoteSyncAt': check.localKnownRemoteSyncAtMillis,
      'requestFullDataset': repair,
    });
    if (ref.read(databaseProvider) != db || _currentDatabaseName() != dbName) {
      throw const DeviceSyncException('Database changed before sync.');
    }
    final socket = await _connectSyncSocket(
      target.host,
      target.transferPort ?? transferPort,
    );
    StreamIterator<String>? lines;
    _reportTransfer('Syncing with ${target.name}...');
    try {
      final handshake = await _performClientHandshake(socket, target, localId);
      lines = handshake.lineIter;
      socket.add(
        utf8.encode(
          '${await SyncCrypto.encrypt(jsonEncode(request), handshake.sessionKey)}\n',
        ),
      );
      await socket.flush();
      Map<String, dynamic>? response;
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (await lines.moveNext().timeout(const Duration(seconds: 30))) {
        if (DateTime.now().isAfter(deadline)) {
          throw const DeviceSyncException('Sync timed out.');
        }
        final value = jsonDecode(
          await SyncCrypto.decrypt(lines.current, handshake.sessionKey),
        );
        if (value is! Map) continue;
        if (value['keepAlive'] == true) continue;
        response = Map<String, dynamic>.from(value);
        break;
      }
      if (response == null ||
          response['syncProtocol'] != _protocolVersion ||
          response['syncApplied'] != true) {
        throw DeviceSyncException(
          response?['error'] as String? ??
              'Remote device did not confirm sync.',
        );
      }
      if (ref.read(databaseProvider) != db ||
          _currentDatabaseName() != dbName ||
          !_isTrustedPeer(peerId)) {
        throw const DeviceSyncException(
          'Database or pairing changed during sync.',
        );
      }
      final result = await db.transaction(() async {
        final applied = await _applyExchangePayload(db, response!);
        if (!_foreground ||
            !ref.mounted ||
            ref.read(databaseProvider) != db ||
            _trustedPeerById(peerId)?.pairingId != target!.pairingId) {
          throw const DeviceSyncException(
            'Database or pairing changed while applying sync.',
          );
        }
        await db.savePeerSyncCheckpoint(
          peerId: peerId,
          lastRevision: (response['localRevision'] as num?)?.toInt() ?? 0,
          lastSyncAt: DateTime.now(),
          remoteRevisionId: response['contentDigest'] as String? ?? '',
        );
        return applied;
      });
      await markSyncCompleted(peerId: peerId);
      _emitSyncEvent(SyncDataAppliedEvent(result));
    } finally {
      await lines?.cancel();
      socket.destroy();
      _emitSyncEvent(const SyncTransferActivityEvent(active: false));
    }
  }

  Future<SyncImportResult> _applyExchangePayload(
    AppDatabase database,
    Map<String, dynamic> payload,
  ) => SyncPayloadCodec(getDatabase: () => database).applyDeltaPayload(
    _payloadRecords(payload['games']),
    tombstones: _payloadRecords(payload['tombstones']),
  );

  List<Map<String, dynamic>> _payloadRecords(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList()
      : const [];

  void _requireManualSyncContext({
    required AppDatabase database,
    required String databaseName,
    required TrustedSyncPeer peer,
  }) {
    if (!_foreground || !ref.mounted) {
      throw const DeviceSyncException('Device sync is paused.');
    }
    final currentPeer = _trustedPeerById(peer.id);
    if (ref.read(databaseProvider) != database ||
        _currentDatabaseName() != databaseName ||
        currentPeer == null ||
        currentPeer.pairingId != peer.pairingId ||
        currentPeer.fingerprint != peer.fingerprint ||
        ref.read(settingsProvider)[SettingsKeys.syncEnabled] != true) {
      throw const DeviceSyncException(
        'Database or pairing changed during sync. Start sync again.',
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
      _reportTransfer(
        '[${targetPeer.name}] Saved address is unreachable. Refreshing peer address...',
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

    if (ping.remoteSyncProtocol != _protocolVersion) {
      throw const DeviceSyncException(_incompatibleSyncMessage);
    }

    // Backup-first safety guard — labeled so users can identify it on restore.
    _reportTransfer(
      '[${targetPeer.name}] Step 1/4: Creating pre-sync backup...',
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

    // Explicit pull alignment is complete. Every subsequent read/write must
    // remain bound to this database and this consent to pair.
    final manualDatabase = ref.read(databaseProvider);
    if (manualDatabase == null) {
      throw const DeviceSyncException('Database is not available.');
    }
    final manualDatabaseName = _currentDatabaseName();
    final manualCodec = SyncPayloadCodec(getDatabase: () => manualDatabase);
    void requireManualContext() => _requireManualSyncContext(
      database: manualDatabase,
      databaseName: manualDatabaseName,
      peer: targetPeer!,
    );
    requireManualContext();

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

    // ── Double-check: re-ping the peer to verify its active DB hasn't changed ──
    _reportTransfer(
      '[${targetPeer.name}] Verifying remote database is still the same...',
    );
    final recheckPing = await _pingPeer(targetPeer);
    requireManualContext();
    if (recheckPing.reachable) {
      final recheckRemoteDbName = (recheckPing.remoteDbName ?? '').trim();
      final currentLocalDbName = _currentDatabaseName();
      if (recheckRemoteDbName.isNotEmpty &&
          currentLocalDbName.isNotEmpty &&
          recheckRemoteDbName != currentLocalDbName) {
        _emitSyncEvent(
          DbMismatchDetectedEvent(
            peerId: targetPeer.id,
            peerName: targetPeer.name,
            localDbName: currentLocalDbName,
            remoteDbName: recheckRemoteDbName,
          ),
        );
        // For pull operations, the mismatch blocks sync because the local
        // DB must match the remote's.  For push operations the receiver
        // side will create / switch to the sender's DB name, so the
        // mismatch is expected and we continue.
        if (isPull) {
          throw DeviceSyncException(
            '[${targetPeer.name}] Sync aborted: remote device is using '
            '"$recheckRemoteDbName" but this device uses "$currentLocalDbName". '
            'Both devices must use the same active database file. '
            'Use the sync dialog to resolve the mismatch.',
          );
        }
      }
    }

    // ── Pull mode: ask the remote to send us their database ──────────────────
    if (isPull) {
      requireManualContext();
      Socket tcpSocketPull;
      StreamIterator<String>? pullLines;
      try {
        _reportTransfer(
          '[${targetPeer.name}] Step 2/4: Connecting to pull data...',
        );
        tcpSocketPull = await _connectSyncSocket(
          targetPeer.host,
          targetPeer.transferPort ?? transferPort,
        ).timeout(const Duration(seconds: 10));
      } catch (_) {
        throw DeviceSyncException(
          'Could not connect to ${targetPeer.name}. '
          'Make sure the remote device has sync enabled.',
        );
      }

      try {
        _reportTransfer(
          '[${targetPeer.name}] Step 3/4: Requesting remote database...',
        );

        // ── Encrypted handshake ──────────────────────────────────────────
        final (:sessionKey, :lineIter) = await _performClientHandshake(
          tcpSocketPull,
          targetPeer,
          localDeviceId,
        );
        pullLines = lineIter;
        requireManualContext();

        _reportTransfer(
          '[${targetPeer.name}] Step 4/4: Waiting for remote data...',
        );

        // Send encrypted pull request.
        final pullRequest = jsonEncode({
          'pullRequest': true,
          'syncProtocol': _protocolVersion,
          'requestFullDataset': fullScan,
          'syncRevisionId': _currentSyncCode(),
          'deviceName': _currentDeviceName(),
          'requestingPeerId': localDeviceId,
          'senderDbName': manualDatabaseName,
          'expectedReceiverDbName': expectedReceiverDbName,
          'knownRemoteRevision': localKnownRemoteRevision,
          'knownRemoteSyncAt': localKnownRemoteSyncAtMillis,
        });
        final encryptedPullRequest = await SyncCrypto.encrypt(
          pullRequest,
          sessionKey,
        );
        requireManualContext();
        tcpSocketPull.add(utf8.encode('$encryptedPullRequest\n'));
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
        if (remotePayload['syncProtocol'] != _protocolVersion) {
          throw const DeviceSyncException(_incompatibleSyncMessage);
        }
        requireManualContext();
        final responseDatabaseName = remotePayload['senderDbName'] as String?;
        if (responseDatabaseName != null &&
            responseDatabaseName.isNotEmpty &&
            responseDatabaseName != manualDatabaseName) {
          throw const DeviceSyncException(
            'Remote database changed during pull.',
          );
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

        _reportTransfer(
          remoteFullDataset
              ? '[${targetPeer.name}] Applying ${games.length} records and ${tombstones.length} deletions...'
              : '[${targetPeer.name}] Applying ${games.length} changed records and ${tombstones.length} deletions...',
        );

        final remoteRevisionId =
            (remotePayload['syncRevisionId'] as String?)?.trim() ?? '';
        final remoteDbTimestampMillis =
            (remotePayload['dbTimestampMillis'] as num?)?.toInt() ?? 0;
        final result = await manualDatabase.transaction(() async {
          requireManualContext();
          final applied = await manualCodec.applyDeltaPayload(
            games,
            tombstones: tombstones,
            lastSyncAt: localKnownRemoteSyncAtMillis <= 0
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    localKnownRemoteSyncAtMillis,
                  ),
          );
          requireManualContext();
          if (remoteDbTimestampMillis > 0) {
            await manualDatabase.setSyncDbTimestampMillis(
              remoteDbTimestampMillis,
            );
          }
          await manualDatabase.savePeerSyncCheckpoint(
            peerId: targetPeer!.id,
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
          requireManualContext();
          return applied;
        });
        requireManualContext();
        // Adopt the remote's revision ID only after its records commit.
        if (remoteRevisionId.isNotEmpty) {
          await _setSetting(SettingsKeys.syncDbRevisionId, remoteRevisionId);
        }
        if (remoteDbTimestampMillis > 0) {
          requireManualContext();
          await _setSetting(
            SettingsKeys.syncDbTimestampMillis,
            remoteDbTimestampMillis,
          );
        }
        requireManualContext();
        await markSyncCompleted(
          peerId: targetPeer.id,
          authoritativeTimestampMillis: remoteDbTimestampMillis > 0
              ? remoteDbTimestampMillis
              : null,
        );

        _emitSyncEvent(SyncDataAppliedEvent(result));
        _emitSyncEvent(const SyncTransferActivityEvent(active: false));
      } on TimeoutException {
        throw const DeviceSyncException(
          'Remote device stopped responding during pull.',
        );
      } finally {
        try {
          await pullLines?.cancel();
        } finally {
          tcpSocketPull.destroy();
        }
      }
      return;
    }

    // ── Push mode: serialize our database and send it to the peer ─────────
    final db = manualDatabase;
    requireManualContext();

    final currentRevisionId = _currentSyncCode();

    _reportTransfer(
      '[${targetPeer.name}] Step 2/4: Serialising local data snapshot...',
    );
    final builtPayload = await manualCodec.buildDeltaPayload(
      syncRevisionId: currentRevisionId,
      deviceName: _currentDeviceName(),
      baseRevision: remoteKnownLocalRevision,
      baseSyncAtMillis: remoteKnownLocalSyncAtMillis,
      localRevision: localRevision,
      includeAllGames: fullScan,
    );
    requireManualContext();
    if (expectedReceiverDbName.isNotEmpty) {
      builtPayload['expectedReceiverDbName'] = expectedReceiverDbName;
    }
    builtPayload['senderDbName'] = manualDatabaseName;
    builtPayload['requestingPeerId'] = localDeviceId;
    await _ensureExpectedRemoteDatabaseForPush(
      targetPeer: targetPeer,
      expectedRemoteDbName: expectedReceiverDbName,
    );
    var lastRound = await _pushDeltaRound(
      database: manualDatabase,
      databaseName: manualDatabaseName,
      targetPeer: targetPeer,
      localDeviceId: localDeviceId,
      builtPayload: builtPayload,
      expectedRevisionId: currentRevisionId,
      fallbackRemoteRevision: ping.remoteRevision,
    );

    var finalSyncedRevisionId = currentRevisionId;
    final firstRoundBaseSyncAt =
        (builtPayload['dbTimestampMillis'] as num?)?.toInt() ?? 0;
    final firstRoundLocalRevision =
        (builtPayload['localRevision'] as num?)?.toInt() ?? localRevision;

    requireManualContext();
    final localRevisionAfterFirstRound = await db.getLocalSyncRevision();
    if (localRevisionAfterFirstRound > firstRoundLocalRevision) {
      final followUpRevisionId = _currentSyncCode();
      final followUpPayload = await manualCodec.buildDeltaPayload(
        syncRevisionId: followUpRevisionId,
        deviceName: _currentDeviceName(),
        baseRevision: firstRoundLocalRevision,
        baseSyncAtMillis: firstRoundBaseSyncAt,
        localRevision: localRevisionAfterFirstRound,
      );
      requireManualContext();
      if (expectedReceiverDbName.isNotEmpty) {
        followUpPayload['expectedReceiverDbName'] = expectedReceiverDbName;
      }
      followUpPayload['senderDbName'] = manualDatabaseName;
      followUpPayload['requestingPeerId'] = localDeviceId;

      _reportTransfer(
        '[${targetPeer.name}] Mid-sync local edits detected. Sending follow-up delta...',
      );

      await _ensureExpectedRemoteDatabaseForPush(
        targetPeer: targetPeer,
        expectedRemoteDbName: expectedReceiverDbName,
      );

      lastRound = await _pushDeltaRound(
        database: manualDatabase,
        databaseName: manualDatabaseName,
        targetPeer: targetPeer,
        localDeviceId: localDeviceId,
        builtPayload: followUpPayload,
        expectedRevisionId: followUpRevisionId,
        fallbackRemoteRevision: lastRound.remoteLocalRevision,
      );

      finalSyncedRevisionId = followUpRevisionId;
    }

    _emitSyncEvent(const SyncTransferActivityEvent(active: false));
    requireManualContext();

    // Re-anchor our revision ID to the one we sent.  The receiver has adopted
    // this same ID, so both devices now share an identical code and the next
    // checkSyncCode poll returns `matches = true`.  Without this, a concurrent
    // incoming sync (receiver role on the same device) could have overwritten
    // syncDbRevisionId with the remote peer's old code, creating a permanent
    // mismatch that would trigger an infinite sync loop.
    await _setSetting(SettingsKeys.syncDbRevisionId, finalSyncedRevisionId);
    requireManualContext();
    await markSyncCompleted(
      peerId: targetPeer.id,
      authoritativeTimestampMillis: lastRound.confirmedTimestampMillis > 0
          ? lastRound.confirmedTimestampMillis
          : null,
    );
  }

  Future<({int confirmedTimestampMillis, int remoteLocalRevision})>
  _pushDeltaRound({
    required AppDatabase database,
    required String databaseName,
    required TrustedSyncPeer targetPeer,
    required String localDeviceId,
    required Map<String, dynamic> builtPayload,
    required String expectedRevisionId,
    required int fallbackRemoteRevision,
  }) async {
    void requireContext() => _requireManualSyncContext(
      database: database,
      databaseName: databaseName,
      peer: targetPeer,
    );
    requireContext();
    final payload = jsonEncode(builtPayload);
    final gameCount = (builtPayload['games'] as List?)?.length ?? 0;
    final deletedCount = (builtPayload['tombstones'] as List?)?.length ?? 0;
    final fullDataset = builtPayload['fullDataset'] == true;

    Socket tcpSocket;
    try {
      _reportTransfer('[${targetPeer.name}] Connecting for data transfer...');
      tcpSocket = await _connectSyncSocket(
        targetPeer.host,
        targetPeer.transferPort ?? transferPort,
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      throw DeviceSyncException(
        'Could not connect to ${targetPeer.name} for data transfer. '
        'Make sure the remote device has sync enabled.',
      );
    }

    _reportTransfer(
      fullDataset
          ? '[${targetPeer.name}] Sending $gameCount records and $deletedCount deletions...'
          : '[${targetPeer.name}] Sending $gameCount changed records and $deletedCount deletions...',
    );

    var confirmedTimestampMillis = 0;
    var remoteLocalRevision = fallbackRemoteRevision;
    StreamIterator<String>? pushLines;

    try {
      final (:sessionKey, :lineIter) = await _performClientHandshake(
        tcpSocket,
        targetPeer,
        localDeviceId,
      );
      pushLines = lineIter;
      final encryptedPayload = await SyncCrypto.encrypt(payload, sessionKey);
      requireContext();
      tcpSocket.add(utf8.encode('$encryptedPayload\n'));
      await tcpSocket.flush();

      _reportTransfer('[${targetPeer.name}] Waiting for confirmation...');

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
              _reportTransfer(
                '[${targetPeer.name}] Remote is still processing...',
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
          if (responsePayload['syncProtocol'] != _protocolVersion) {
            throw const DeviceSyncException(_incompatibleSyncMessage);
          }
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
          requireContext();
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

          // This confirmation acknowledges our outgoing records only. It
          // cannot advance the cursor for remote records we have not received.
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
      try {
        await pushLines?.cancel();
      } finally {
        tcpSocket.destroy();
      }
    }

    requireContext();

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
    if (!_foreground || kIsWeb) return;
    final pending = _responderStartup;
    if (pending != null) return pending;
    if (_responderSocket != null) return _startSyncServer();
    final startup = _initializeDiscoveryResponder(deviceId: deviceId);
    _responderStartup = startup;
    try {
      await startup;
    } finally {
      if (identical(_responderStartup, startup)) _responderStartup = null;
    }
  }

  Future<void> _initializeDiscoveryResponder({required String deviceId}) async {
    final epoch = _networkEpoch;

    // Bind to all network interfaces (0.0.0.0) to enable LAN discovery.
    // This will trigger Windows Firewall prompt on first run for portable versions.
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
      reusePort: false,
    );
    if (!_foreground || epoch != _networkEpoch) {
      socket.close();
      return;
    }
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
            ).catchError((Object error, StackTrace stack) {
              debugPrint('Sync control packet ignored: $error');
            }),
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
            'port': discoveryPort,
            'transferPort': transferPort,
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
    try {
      await _startSyncServer();
    } catch (_) {
      await stopDiscoveryResponder();
      rethrow;
    }
  }

  Future<void> _startSyncServer() async {
    if (!_foreground || kIsWeb || _syncServer != null) return;
    final pending = _serverStartup;
    if (pending != null) return pending;
    final startup = _initializeSyncServer();
    _serverStartup = startup;
    try {
      await startup;
    } finally {
      if (identical(_serverStartup, startup)) _serverStartup = null;
    }
  }

  Future<void> _initializeSyncServer() async {
    final epoch = _networkEpoch;
    try {
      // Bind to all network interfaces (0.0.0.0) to accept connections from LAN.
      // This will trigger Windows Firewall prompt on first run, allowing users
      // to grant network access for the portable version of the app.
      _syncServer = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        transferPort,
        shared: false,
      );
      if (!_foreground || epoch != _networkEpoch) {
        await _syncServer?.close();
        _syncServer = null;
        return;
      }
      _syncServer!.listen(
        _handleIncomingSyncConnection,
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {
      _syncServer = null;
      throw const DeviceSyncException(
        'Could not start device sync. The transfer port may already be in use.',
      );
    }
  }

  Future<void> _handleIncomingSyncConnection(Socket socket) async {
    if (!_foreground) {
      socket.destroy();
      return;
    }
    _trackSyncSocket(socket);
    // Set the flag synchronously before any await so that _pollSyncCode (which
    // runs on the timer) sees it immediately and does not launch a competing
    // initiator sync that would race to overwrite the revision ID we are about
    // to adopt from the incoming sender.
    _incomingSyncCount++;
    // Single StreamIterator for all reads on this socket.
    final lineIter = StreamIterator<String>(
      utf8.decoder.bind(socket).transform(const LineSplitter()),
    );
    try {
      _reportTransfer('Incoming sync: waiting for data...');

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
      if (payload == null || payload['syncProtocol'] != _protocolVersion) {
        return;
      }

      final syncRevisionId =
          (payload['syncRevisionId'] as String?)?.trim() ?? '';
      final senderPeerId =
          (payload['requestingPeerId'] as String?)?.trim() ?? '';
      // The encrypted payload cannot impersonate another paired device.
      if (senderPeerId != firstParsed['peerId']) return;
      final authenticatedPeer = _trustedPeerById(senderPeerId);
      if (authenticatedPeer == null ||
          authenticatedPeer.pairingId != (firstParsed['pairingId'] ?? '') ||
          authenticatedPeer.fingerprint != firstParsed['spub']) {
        return;
      }
      final senderName = (payload['deviceName'] as String?)?.trim() ?? '';
      final displayName = senderName.isNotEmpty ? senderName : 'remote device';

      // Helper: sends [json] to the client as an encrypted line.
      Future<void> sendLine(Map<String, dynamic> json) async {
        json['syncProtocol'] = _protocolVersion;
        final content = await SyncCrypto.encrypt(jsonEncode(json), sessionKey);
        socket.add(utf8.encode('$content\n'));
      }

      if (payload['exchangeRequest'] == true && payload['syncProtocol'] == 3) {
        final db = ref.read(databaseProvider);
        final dbName = _currentDatabaseName();
        if (db == null ||
            payload['senderDbName'] != dbName ||
            payload['expectedReceiverDbName'] != dbName) {
          await sendLine({
            'syncApplied': false,
            'error': 'Active database changed or does not match.',
          });
          await socket.flush();
          return;
        }
        final keepAlive = Timer.periodic(const Duration(seconds: 4), (_) async {
          try {
            await sendLine({'keepAlive': true});
            await socket.flush();
          } catch (_) {}
        });
        try {
          // Capture our outgoing changes before applying theirs. The cursor in
          // this response acknowledges only the records actually transferred.
          final response = await _codec.buildDeltaPayload(
            syncRevisionId: _currentSyncCode(),
            baseRevision:
                (payload['knownRemoteRevision'] as num?)?.toInt() ?? 0,
            baseSyncAtMillis:
                (payload['knownRemoteSyncAt'] as num?)?.toInt() ?? 0,
            localRevision: await db.getLocalSyncRevision(),
            includeAllGames: payload['requestFullDataset'] == true,
            includeSteamCache: false,
          );
          if (ref.read(databaseProvider) != db ||
              _currentDatabaseName() != dbName ||
              !_isTrustedPeer(senderPeerId)) {
            await sendLine({
              'syncApplied': false,
              'error': 'Database or pairing changed during sync.',
            });
            await socket.flush();
            return;
          }
          final result = await db.transaction(() async {
            final applied = await _applyExchangePayload(db, payload!);
            if (!_foreground ||
                !ref.mounted ||
                ref.read(databaseProvider) != db ||
                _trustedPeerById(senderPeerId)?.pairingId !=
                    (firstParsed!['pairingId'] ?? '')) {
              throw const DeviceSyncException(
                'Database or pairing changed while applying sync.',
              );
            }
            await db.savePeerSyncCheckpoint(
              peerId: senderPeerId,
              lastRevision: (payload['localRevision'] as num?)?.toInt() ?? 0,
              lastSyncAt: DateTime.now(),
              remoteRevisionId: payload['contentDigest'] as String? ?? '',
            );
            return applied;
          });
          await markSyncCompleted(peerId: senderPeerId);
          response['syncApplied'] = true;
          await sendLine(response);
          await socket.flush();
          _emitSyncEvent(SyncDataAppliedEvent(result));
        } finally {
          keepAlive.cancel();
        }
        return;
      }

      // ── Pull request: remote is asking US to push our database to them ──
      if (payload['pullRequest'] == true) {
        final requestFullDataset = payload['requestFullDataset'] == true;
        final pullDatabase = ref.read(databaseProvider);
        final pullDatabaseName = _currentDatabaseName();
        final expectedPullDatabase =
            payload['expectedReceiverDbName'] as String? ?? '';
        if (pullDatabase == null ||
            expectedPullDatabase.isNotEmpty &&
                expectedPullDatabase != pullDatabaseName) {
          throw const DeviceSyncException(
            'Remote database changed during pull.',
          );
        }
        void requirePullContext() => _requireManualSyncContext(
          database: pullDatabase,
          databaseName: pullDatabaseName,
          peer: authenticatedPeer,
        );
        requirePullContext();
        _reportTransfer(
          requestFullDataset
              ? '[$displayName] Pull request received. Sending full data snapshot...'
              : '[$displayName] Pull request received. Sending delta snapshot...',
        );
        final currentRevisionId = _currentSyncCode();
        final responsePayload =
            await SyncPayloadCodec(
              getDatabase: () => pullDatabase,
            ).buildDeltaPayload(
              syncRevisionId: currentRevisionId,
              deviceName: _currentDeviceName(),
              baseRevision:
                  (payload['knownRemoteRevision'] as num?)?.toInt() ?? 0,
              baseSyncAtMillis:
                  (payload['knownRemoteSyncAt'] as num?)?.toInt() ?? 0,
              localRevision: await pullDatabase.getLocalSyncRevision(),
              includeAllGames: requestFullDataset,
            );
        responsePayload['senderDbName'] = pullDatabaseName;
        requirePullContext();
        final encryptedResponse = await SyncCrypto.encrypt(
          jsonEncode(responsePayload),
          sessionKey,
        );
        requirePullContext();
        socket.add(utf8.encode('$encryptedResponse\n'));
        await socket.flush();
        // Serving a pull transfers no requester records. Do not acknowledge
        // the requester's revision using this device's local counter.
        _emitSyncEvent(const SyncTransferActivityEvent(active: false));
        return;
      }

      // ── Normal push: remote is sending their database to us ──
      final senderDbName = (payload['senderDbName'] as String?)?.trim() ?? '';
      final expectedReceiverDbName =
          (payload['expectedReceiverDbName'] as String?)?.trim() ?? '';

      // If the sender included its DB name and it differs from ours,
      // switch to (or create) the sender's database file first.
      var switchedBySenderDb = false;
      if (senderDbName.isNotEmpty) {
        if (!_isValidDatabaseFileName(senderDbName)) return;
        final activeReceiverDbName = _currentDatabaseName();
        if (activeReceiverDbName != senderDbName) {
          final switchCallback = ref.read(databaseSwitchCallbackProvider);
          if (switchCallback != null) {
            // Resolve the target path using the default DB directory so that
            // well-known filenames (e.g. keys.db) are found/created in their
            // canonical location rather than the current DB's directory.
            final defaultDbPath = await AppDatabase.getDatabasePath();
            final defaultDbDir = p.dirname(defaultDbPath);
            var targetBasePath = p.join(defaultDbDir, senderDbName);
            if (!File(targetBasePath).existsSync()) {
              // Also check the current DB's directory as a fallback.
              final currentBasePath =
                  ref.read(settingsProvider)[SettingsKeys.databasePath]
                      as String? ??
                  '';
              if (currentBasePath.isNotEmpty) {
                final altPath = p.join(
                  p.dirname(currentBasePath),
                  senderDbName,
                );
                if (File(altPath).existsSync()) {
                  targetBasePath = altPath;
                }
              }
            }
            _reportTransfer(
              '[$displayName] Switching database to "$senderDbName" '
              'to match sender...',
            );
            final targetFile = File(targetBasePath);
            if (targetFile.existsSync()) {
              await switchCallback(OpenDatabaseRequest(targetBasePath));
            } else {
              await switchCallback(
                CreateDatabaseRequest(path: targetBasePath, encrypted: false),
              );
            }
            switchedBySenderDb = true;
            _reportTransfer(
              '[$displayName] Database switched to "$senderDbName". '
              'Applying incoming data...',
            );
          }
        }
      }

      if (!switchedBySenderDb && expectedReceiverDbName.isNotEmpty) {
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
          _reportTransfer(
            '[$displayName] Sync blocked: active database changed from "$expectedReceiverDbName" to "$activeReceiverDbName".',
          );
          _emitSyncEvent(const SyncTransferActivityEvent(active: false));
          return;
        }
      }

      final receivingDatabase = ref.read(databaseProvider);
      final receivingDatabaseName = _currentDatabaseName();
      if (receivingDatabase == null ||
          senderDbName.isNotEmpty && senderDbName != receivingDatabaseName) {
        throw const DeviceSyncException(
          'Could not align the receiving database.',
        );
      }
      final receivingCodec = SyncPayloadCodec(
        getDatabase: () => receivingDatabase,
      );
      void requireReceivingContext() => _requireManualSyncContext(
        database: receivingDatabase,
        databaseName: receivingDatabaseName,
        peer: authenticatedPeer,
      );
      requireReceivingContext();

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

      _reportTransfer(
        incomingFullDataset
            ? '[$displayName] Received ${games.length} records and ${tombstones.length} deletions. Applying...'
            : '[$displayName] Received ${games.length} changed records and ${tombstones.length} deletions. Applying...',
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
      final adoptedRevisionId = syncRevisionId.isEmpty
          ? _currentSyncCode()
          : syncRevisionId;
      final senderDbTimestampMillis =
          (payload['dbTimestampMillis'] as num?)?.toInt() ?? 0;
      try {
        result = await receivingDatabase.transaction(() async {
          requireReceivingContext();
          final checkpoint = await receivingDatabase.getPeerSyncCheckpoint(
            senderPeerId,
          );
          final peerKnownSyncAtMillis = checkpoint?['lastSyncAt'] as int? ?? 0;
          final applied = await receivingCodec.applyDeltaPayload(
            games,
            tombstones: tombstones,
            lastSyncAt: peerKnownSyncAtMillis <= 0
                ? null
                : DateTime.fromMillisecondsSinceEpoch(peerKnownSyncAtMillis),
          );
          requireReceivingContext();
          if (senderDbTimestampMillis > 0) {
            await receivingDatabase.setSyncDbTimestampMillis(
              senderDbTimestampMillis,
            );
          }
          await receivingDatabase.savePeerSyncCheckpoint(
            peerId: senderPeerId,
            lastRevision: (payload!['localRevision'] as num?)?.toInt() ?? 0,
            lastSyncAt: DateTime.fromMillisecondsSinceEpoch(
              senderDbTimestampMillis > 0
                  ? senderDbTimestampMillis
                  : DateTime.now().millisecondsSinceEpoch,
            ),
            remoteRevisionId: adoptedRevisionId,
          );
          requireReceivingContext();
          return applied;
        });
      } finally {
        keepAliveTimer.cancel();
        keepAliveTimer = null;
      }

      _reportTransfer(
        '[$displayName] Replaced database: ${result.inserted} game records applied. Confirming...',
      );

      // Adopt the initiator's revision ID so both devices share the same sync
      // code after this exchange.
      requireReceivingContext();
      if (syncRevisionId.isNotEmpty) {
        await _setSetting(SettingsKeys.syncDbRevisionId, adoptedRevisionId);
      }
      if (senderDbTimestampMillis > 0) {
        requireReceivingContext();
        await _setSetting(
          SettingsKeys.syncDbTimestampMillis,
          senderDbTimestampMillis,
        );
      }
      // Record the sync timestamp on the receiver side.
      requireReceivingContext();
      await markSyncCompleted(
        authoritativeTimestampMillis: senderDbTimestampMillis > 0
            ? senderDbTimestampMillis
            : null,
      );

      // Send a lightweight confirmation — NO games — so the initiator never
      // applies our data back and accidentally restores anything it deleted.
      // Include steam cache so metadata stays bidirectional.
      final steamCache = await exportSteamCacheSnapshotForSync();
      requireReceivingContext();
      final confirmedLocalRevision = await receivingDatabase
          .getLocalSyncRevision();
      final confirmedDbTimestamp = await receivingDatabase
          .getSyncDbTimestampMillis();
      requireReceivingContext();
      await sendLine({
        'syncApplied': true,
        'syncProtocol': _protocolVersion,
        'syncRevisionId': adoptedRevisionId,
        'localRevision': confirmedLocalRevision,
        'dbTimestampMillis': confirmedDbTimestamp,
        'steamCache': steamCache,
      });
      await socket.flush();

      _emitSyncEvent(SyncDataAppliedEvent(result));
      _emitSyncEvent(const SyncTransferActivityEvent(active: false));
    } catch (e) {
      debugPrint('Sync server receive error: $e');
    } finally {
      await lineIter.cancel();
      socket.destroy();
      _incomingSyncCount--;
      if (!_receiverSyncInFlight) {
        _emitSyncEvent(const SyncTransferActivityEvent(active: false));
      }
    }
  }

  Future<void> stopDiscoveryResponder() async {
    _networkEpoch++;
    for (final cancellation in _outgoingPairCancellations.values) {
      if (!cancellation.isCompleted) cancellation.complete();
    }
    _changeSignalTimer?.cancel();
    _changeSignalTimer = null;
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

    if (payload['trusted'] == false) {
      await removeTrustedPeer(fromId, notifyRemote: false);
      _emitSyncEvent(PeerRemovedEvent(fromId));
    }

    _pendingPongs.remove(token);
    pending.completer.complete(_PeerPingResult.fromPong(payload));
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

    final revoked = _revocationLedger.find(
      fromId,
      pairingId: payload['pairingId'] as String? ?? '',
    );
    if (!_isTrustedPeer(fromId) ||
        (revoked != null &&
            _trustedPeerById(fromId)?.pairingId != revoked.pairingId)) {
      // A prepared rollback becomes a revocation only when finalization stops.
      if (revoked != null &&
          _outgoingPairCancellations.containsKey(revoked.pairingId)) {
        return;
      }
      if (revoked == null ||
          !await _verifyControlAuthForFingerprint(
            payload: payload,
            expectedFingerprint: revoked.fingerprint,
            pairingId: revoked.pairingId,
          )) {
        return;
      }
      final rejection = await _attachControlAuthForFingerprint(
        payload: {
          'type': _syncPongType,
          'protocol': _protocolVersion,
          'token': payload['token'],
          'from': _localIdentityMap(deviceId),
          'trusted': false,
          'syncProtocol': 3,
        },
        remoteStaticPubB64: revoked.fingerprint,
        pairingId: revoked.pairingId,
      );
      socket.send(
        utf8.encode(jsonEncode(rejection)),
        datagram.address,
        (payload['replyPort'] as num?)?.toInt() ?? datagram.port,
      );
      return;
    }
    if (!await _verifyTrustedControlPacketAuth(
      payload: payload,
      fromPeerId: fromId,
    )) {
      return;
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
        'contentDigest': peerState['contentDigest'],
        'syncProtocol': 3,
        'transferPort': transferPort,
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
      return null;
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
    final socket = useResponderPort
        ? _responderSocket!
        : await RawDatagramSocket.bind(
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

          completer.complete(_PeerPingResult.fromPong(payload));
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

    final retry = Timer(const Duration(milliseconds: 500), () {
      if (!completer.isCompleted && _foreground) {
        try {
          socket.send(packet, InternetAddress(targetHost), peer.port);
        } catch (_) {}
      }
    });
    try {
      return await completer.future.timeout(
        _syncPingTimeout,
        onTimeout: () => const _PeerPingResult(reachable: false),
      );
    } finally {
      retry.cancel();
      if (useResponderPort) _pendingPongs.remove(token);
      await sub?.cancel();
      if (!useResponderPort) socket.close();
    }
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
    if (ping.reachable && !ping.remoteTrusted) {
      if (_isTrustedPeer(target.id)) {
        await removeTrustedPeer(target.id, notifyRemote: false);
        _emitSyncEvent(PeerRemovedEvent(target.id));
      }
      return DeviceSyncCodeCheckResult(reachable: false, peer: target);
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

    final dbNameMismatch =
        remoteDbName != null &&
        remoteDbName.isNotEmpty &&
        localDbName.isNotEmpty &&
        remoteDbName != localDbName;
    final remoteSyncRevisionId = (ping.remoteSyncRevisionId ?? '').trim();

    return DeviceSyncCodeCheckResult(
      reachable: ping.reachable,
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
      localContentDigest: localState['contentDigest'] as String? ?? '',
      remoteContentDigest: ping.remoteContentDigest,
      remoteSyncProtocol: ping.remoteSyncProtocol,
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
    if (!_foreground) return;
    if (_announceTimer != null) return;
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
    if (type == _announceType || type == _discoverResponseType) {
      _handleAnnounce(datagram, payload, deviceId);
      return;
    }
    // Discovery can display older devices, but no control action may run.
    if (payload['protocol'] != _protocolVersion) return;
    if (type == _changedType) {
      final from = payload['from'];
      final peerId = from is Map ? from['id'] as String? ?? '' : '';
      if (await _verifyTrustedControlPacketAuth(
            payload: payload,
            fromPeerId: peerId,
          ) &&
          _acceptFreshControl(payload, peerId)) {
        _emitSyncEvent(SyncChangeAvailableEvent(peerId: peerId));
      }
      return;
    }
    if (type == _offlineType) {
      _handleOffline(datagram, payload, deviceId);
      return;
    }
    if (type == _syncPongType) {
      await _handleSyncPong(payload);
      return;
    }
    if (type == _syncPingType) {
      await _handleSyncPing(socket, datagram, payload, deviceId);
      return;
    }
    if (type == _untrustType) {
      await _handleUntrust(datagram, payload);
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
      await _handlePairRequest(datagram, payload, deviceId);
      return;
    }
    if (type == _pairCommitType) {
      await _handlePairCommit(socket, datagram, payload, deviceId);
      return;
    }
    if (type == _pairFinalizeType) {
      await _handlePairFinalize(socket, datagram, payload, deviceId);
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
    final previous = _freshAnnouncedPeerById(peerId);
    _announcedPeers[peerId] = DiscoveredSyncPeer(
      id: peerId,
      name: _normalizeDeviceName(peerName, fallbackType: peerType),
      host: datagram.address.address,
      port: port,
      transferPort: (payload['transferPort'] as num?)?.toInt(),
      syncProtocol: (payload['protocol'] as num?)?.toInt() ?? 0,
      deviceType: peerType,
    );
    _announcedPeersSeenAt[peerId] = DateTime.now();
    _offlinePeersSeenAt.remove(peerId);
    if (previous == null ||
        previous.host != datagram.address.address ||
        previous.port != port ||
        previous.syncProtocol != _announcedPeers[peerId]!.syncProtocol) {
      _emitSyncEvent(PeerAvailableEvent(_announcedPeers[peerId]!));
    }
  }

  void _handleOffline(
    Datagram datagram,
    Map<String, dynamic> payload,
    String deviceId,
  ) {
    final from = payload['from'];
    if (from is! Map) return;
    final peerId = (from['id'] as String?)?.trim() ?? '';
    if (peerId.isEmpty || peerId == deviceId) return;
    final knownHost =
        _announcedPeers[peerId]?.host ?? _trustedPeerById(peerId)?.host;
    if (knownHost != datagram.address.address) return;
    _announcedPeers.remove(peerId);
    _announcedPeersSeenAt.remove(peerId);
    _offlinePeersSeenAt[peerId] = DateTime.now();
    _emitSyncEvent(PeerOfflineEvent(peerId));
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
    if (!isAuthentic || !_acceptFreshControl(payload, fromId)) {
      return;
    }

    await removeTrustedPeer(fromId, notifyRemote: false);
    _emitSyncEvent(PeerRemovedEvent(fromId));
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
    if (_trustedPeerById(fromId)?.pairingId == requestId) return;

    final existing = _pendingPairRequests[requestId];
    if (existing != null) {
      if (existing.peer.id == fromId &&
          existing.sourceAddress.address == datagram.address.address &&
          existing.initiatorStaticPubB64 == payload['spub']) {
        final decision = _pairDecisions[requestId];
        if (decision != null) {
          _responderSocket?.send(
            decision,
            existing.sourceAddress,
            existing.replyPort,
          );
        }
      }
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
        port: (fromMap['port'] as num?)?.toInt() ?? defaultLanPort,
        transferPort: (fromMap['transferPort'] as num?)?.toInt(),
        deviceType: fromType,
      ),
      sourceAddress: datagram.address,
      replyPort: replyPort,
      createdAt: DateTime.now(),
      initiatorStaticPubB64: initiatorStaticPubB64,
      receiverStaticPubB64: receiverStaticPubB64,
    );
    _emitSyncEvent(
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

  /// Accept control packets only from the peer/address that opened this request.
  _IncomingPairRequestState? _acceptedPairRequest(
    Datagram datagram,
    Map<String, dynamic> payload,
  ) {
    final requestId = (payload['requestId'] as String?)?.trim() ?? '';
    if (requestId.isEmpty) {
      return null;
    }

    final request = _pendingPairRequests[requestId];
    if (request == null || !request.receiverAccepted) {
      return null;
    }

    final from = payload['from'];
    if (from is! Map) {
      return null;
    }
    final fromMap = Map<String, dynamic>.from(from);
    final fromId = (fromMap['id'] as String?)?.trim() ?? '';
    if (fromId.isEmpty || fromId != request.peer.id) {
      return null;
    }
    if (datagram.address.address != request.sourceAddress.address) {
      return null;
    }

    return request;
  }

  Future<void> _handlePairCommit(
    RawDatagramSocket socket,
    Datagram datagram,
    Map<String, dynamic> payload,
    String deviceId,
  ) async {
    final request = _acceptedPairRequest(datagram, payload);
    if (request == null) return;
    final requestId = request.requestId;

    final initiatorSpub = (payload['spub'] as String?)?.trim() ?? '';
    final expectedInitiatorSpub = (request.initiatorStaticPubB64 ?? '').trim();
    final replyPort = (payload['replyPort'] as num?)?.toInt() ?? datagram.port;
    if (!await _verifyControlAuthForFingerprint(
      payload: payload,
      expectedFingerprint: expectedInitiatorSpub,
      pairingId: requestId,
    )) {
      return;
    }
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
      jsonEncode(
        await _attachControlAuthForFingerprint(
          payload: {
            'type': _pairCommitAckType,
            'protocol': _protocolVersion,
            'requestId': requestId,
            'accepted': true,
            'spub': localStaticPubB64,
            'ok': true,
            'from': _localIdentityMap(deviceId),
          },
          remoteStaticPubB64: initiatorSpub,
          pairingId: requestId,
        ),
      ),
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

    final from = payload['from'];
    final fromId = from is Map ? from['id'] as String? ?? '' : '';
    final paired = _trustedPeerById(fromId);
    if (paired != null &&
        paired.pairingId == requestId &&
        await _verifyTrustedControlPacketAuth(
          payload: payload,
          fromPeerId: fromId,
        )) {
      final localPub = await (await _getOrGenerateStaticKeyPair())
          .extractPublicKey();
      final ack = await _attachControlAuthIfTrusted(
        payload: {
          'type': _pairFinalizeAckType,
          'protocol': _protocolVersion,
          'requestId': requestId,
          'accepted': true,
          'ok': true,
          'spub': base64.encode(localPub.bytes),
          'from': _localIdentityMap(deviceId),
        },
        peerId: fromId,
      );
      socket.send(
        utf8.encode(jsonEncode(ack)),
        datagram.address,
        (payload['replyPort'] as num?)?.toInt() ?? datagram.port,
      );
      return;
    }
    final request = _pendingPairRequests[requestId];
    if (request == null ||
        !request.receiverAccepted ||
        !request.initiatorCommitAccepted) {
      return;
    }

    if (from is! Map) {
      return;
    }
    final fromMap = Map<String, dynamic>.from(from);
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
    if (!await _verifyControlAuthForFingerprint(
      payload: payload,
      expectedFingerprint: expectedInitiatorSpub,
      pairingId: requestId,
    )) {
      return;
    }

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

    if (_pendingPairRequests[requestId] != request ||
        !_pairFinalizing.add(requestId)) {
      return;
    }
    try {
      final fromName = (fromMap['name'] as String?)?.trim();
      final fromType = syncDeviceTypeFromWire(
        fromMap['deviceType'] as String? ?? fromMap['device_type'] as String?,
      );
      final trusted = await _upsertTrustedPeer(
        DiscoveredSyncPeer(
          id: fromId,
          name: _normalizeDeviceName(
            (fromName == null || fromName.isEmpty)
                ? request.peer.name
                : fromName,
            fallbackType: fromType,
          ),
          host: datagram.address.address,
          port: (fromMap['port'] as num?)?.toInt() ?? defaultLanPort,
          transferPort: (fromMap['transferPort'] as num?)?.toInt(),
          deviceType: fromType == SyncDeviceType.unknown
              ? request.peer.deviceType
              : fromType,
        ),
        fingerprint: initiatorSpub,
        pairingId: requestId,
      );
      _emitSyncEvent(PeerTrustedEvent(trusted));

      var localStaticPubB64 = (request.receiverStaticPubB64 ?? '').trim();
      if (localStaticPubB64.isEmpty) {
        final localStaticPair = await _getOrGenerateStaticKeyPair();
        final localStaticPub = await localStaticPair.extractPublicKey();
        localStaticPubB64 = base64.encode(localStaticPub.bytes);
      }

      final ackPacket = utf8.encode(
        jsonEncode(
          await _attachControlAuthForFingerprint(
            payload: {
              'type': _pairFinalizeAckType,
              'protocol': _protocolVersion,
              'requestId': requestId,
              'accepted': true,
              'spub': localStaticPubB64,
              'ok': true,
              'from': _localIdentityMap(deviceId),
            },
            remoteStaticPubB64: initiatorSpub,
            pairingId: requestId,
          ),
        ),
      );
      socket.send(ackPacket, datagram.address, replyPort);
      _pendingPairRequests.remove(requestId);
      _pairDecisions.remove(requestId);
    } finally {
      _pairFinalizing.remove(requestId);
    }
  }

  void _handlePairCancel(Map<String, dynamic> payload) {
    final requestId = (payload['requestId'] as String?)?.trim() ?? '';
    if (requestId.isEmpty) return;
    final request = _pendingPairRequests.remove(requestId);
    _pairDecisions.remove(requestId);
    if (request != null) {
      _emitSyncEvent(
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
    final request = _acceptedPairRequest(datagram, payload);
    if (request == null) return;
    final requestId = request.requestId;
    _pairDecisions.remove(requestId);

    _emitSyncEvent(
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

  Future<void> _sendPairNotice({
    required DiscoveredSyncPeer peer,
    required String requestId,
    required String localDeviceId,
    String type = _pairCancelType,
    String? reason,
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
          'type': type,
          'protocol': _protocolVersion,
          'requestId': requestId,
          'reason': ?reason,
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
    final shared = await (_controlKeys[remoteStaticPubB64] ??=
        _deriveControlKey(remoteStaticPubB64));
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode(_canonicalPacketForAuth(payload)),
      secretKey: shared,
    );
    return base64.encode(mac.bytes);
  }

  Future<SecretKey> _deriveControlKey(String remoteStaticPubB64) async {
    final localStaticPair = await _getOrGenerateStaticKeyPair();
    final remoteStaticPub = SyncCrypto.publicKeyFromBase64(remoteStaticPubB64);
    final shared = await _x25519.sharedSecretKey(
      keyPair: localStaticPair,
      remotePublicKey: remoteStaticPub,
    );
    return shared;
  }

  Future<Map<String, dynamic>> _attachControlAuthIfTrusted({
    required Map<String, dynamic> payload,
    required String peerId,
  }) async {
    final trustedPeer = _trustedPeerById(peerId);
    return _attachControlAuthForFingerprint(
      payload: payload,
      remoteStaticPubB64: trustedPeer?.fingerprint,
      pairingId: trustedPeer?.pairingId ?? '',
    );
  }

  Future<Map<String, dynamic>> _attachControlAuthForFingerprint({
    required Map<String, dynamic> payload,
    required String? remoteStaticPubB64,
    String pairingId = '',
  }) async {
    final remoteFingerprint = (remoteStaticPubB64 ?? '').trim();
    if (remoteFingerprint.isEmpty) {
      return payload;
    }
    if (pairingId.isNotEmpty) payload['pairingId'] = pairingId;

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
    final authentic = await _verifyControlAuthForFingerprint(
      payload: payload,
      expectedFingerprint: expectedFingerprint,
      pairingId: trustedPeer?.pairingId ?? '',
    );
    if (!ref.mounted) return false;
    final current = _trustedPeerById(fromPeerId);
    return authentic &&
        current?.fingerprint == trustedPeer?.fingerprint &&
        current?.pairingId == trustedPeer?.pairingId;
  }

  Future<bool> _verifyControlAuthForFingerprint({
    required Map<String, dynamic> payload,
    required String expectedFingerprint,
    required String pairingId,
  }) async {
    if (expectedFingerprint.isEmpty) {
      return false;
    }
    if (pairingId.isNotEmpty && payload['pairingId'] != pairingId) return false;

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
    String? pairingId,
  }) async {
    final trusted = decodeTrustedPeers(
      ref.read(settingsProvider)[SettingsKeys.syncTrustedPeersJson]
              as String? ??
          DefaultSettings.syncTrustedPeersJson,
    );
    // Preserve an existing fingerprint if no new one is provided.
    final existing = trusted.where((p) => p.id == peer.id).firstOrNull;
    if (pairingId == null &&
        (existing == null ||
            (fingerprint != null && existing.fingerprint != fingerprint))) {
      throw const DeviceSyncException(
        'Device pairing changed while updating its address.',
      );
    }
    final upsert = TrustedSyncPeer(
      id: peer.id,
      name: peer.name,
      host: peer.host,
      port: peer.port,
      deviceType: peer.deviceType == SyncDeviceType.unknown
          ? existing?.deviceType ?? SyncDeviceType.unknown
          : peer.deviceType,
      fingerprint: fingerprint ?? existing?.fingerprint,
      pairingId: pairingId ?? existing?.pairingId ?? '',
      transferPort: peer.transferPort ?? existing?.transferPort,
      lastSeenAtIso: DateTime.now().toIso8601String(),
    );
    final next = [...trusted.where((p) => p.id != upsert.id), upsert];

    await _setSetting(
      SettingsKeys.syncTrustedPeersJson,
      encodeTrustedPeers(next),
    );
    final current = _trustedPeerById(peer.id);
    if (current == null ||
        current.pairingId != upsert.pairingId ||
        current.fingerprint != upsert.fingerprint) {
      return upsert;
    }
    await _setSetting(SettingsKeys.syncLastTrustedPeerId, upsert.id);
    if (pairingId != null &&
        _trustedPeerById(peer.id)?.pairingId == pairingId) {
      await _setSetting(
        SettingsKeys.syncRevokedPeersJson,
        _revocationLedger.removePeer(peer.id).encode(),
      );
    }
    return upsert;
  }

  void _evictExpiredPairRequests() {
    final now = DateTime.now();
    final expired = _pendingPairRequests.values
        .where((r) => now.difference(r.createdAt) > _pairRequestLifetime)
        .toList(growable: false);

    for (final request in expired) {
      _pendingPairRequests.remove(request.requestId);
      _pairDecisions.remove(request.requestId);
      _emitSyncEvent(
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
          'port': discoveryPort,
          'transferPort': transferPort,
        }),
      );
      socket.send(packet, InternetAddress('255.255.255.255'), defaultLanPort);
    } finally {
      socket.close();
    }
  }

  Future<void> _sendOffline(String deviceId) async {
    if (kIsWeb || _responderSocket == null) return;
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final packet = utf8.encode(
        jsonEncode({
          'type': _offlineType,
          'protocol': _protocolVersion,
          'from': _localIdentityMap(deviceId),
        }),
      );
      socket.send(packet, InternetAddress('255.255.255.255'), defaultLanPort);
      final settings = ref.read(settingsProvider);
      final trusted = decodeTrustedPeers(
        (settings[SettingsKeys.syncTrustedPeersJson] as String?) ??
            DefaultSettings.syncTrustedPeersJson,
      );
      for (final peer in trusted) {
        final address = InternetAddress.tryParse(peer.host);
        if (address != null) {
          socket.send(packet, address, peer.port);
        }
      }
    } catch (_) {
      // Going offline must still succeed if the network is unavailable.
    } finally {
      socket?.close();
    }
  }

  Map<String, dynamic>? _decodePacket(List<int> data) {
    try {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is Map &&
          (decoded['protocol'] == _protocolVersion ||
              decoded['type'] == _discoverType ||
              decoded['type'] == _discoverResponseType ||
              decoded['type'] == _announceType)) {
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
  Future<SimpleKeyPair> _getOrGenerateStaticKeyPair() =>
      _staticKeyFuture ??= _loadStaticKeyPair();

  Future<SimpleKeyPair> _loadStaticKeyPair() async {
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
    final token = _uuid.v4();
    socket.add(
      utf8.encode(
        '${jsonEncode({'v': 2, 'syncProtocol': _protocolVersion, 'peerId': localDeviceId, 'token': token, 'pairingId': targetPeer.pairingId, 'eph': base64.encode(localEphemeralPub.bytes), 'spub': base64.encode(localStaticPub.bytes)})}\n',
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
    if (serverHello['v'] != 2 ||
        serverHello['syncProtocol'] != _protocolVersion) {
      await lineIter.cancel();
      throw const DeviceSyncException(_incompatibleSyncMessage);
    }

    if (serverHello['revoked'] == true &&
        serverHello['token'] == token &&
        await _verifyControlAuthForFingerprint(
          payload: serverHello,
          expectedFingerprint: targetPeer.fingerprint ?? '',
          pairingId: targetPeer.pairingId,
        )) {
      await lineIter.cancel();
      if (_trustedPeerById(targetPeer.id)?.pairingId == targetPeer.pairingId) {
        await removeTrustedPeer(targetPeer.id, notifyRemote: false);
        _emitSyncEvent(PeerRemovedEvent(targetPeer.id));
      }
      throw const DeviceSyncException(
        'This device was unpaired by the remote device.',
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
    if (clientHello['syncProtocol'] != _protocolVersion) return null;
    final clientPeerId = (clientHello['peerId'] as String?)?.trim() ?? '';
    final clientEphB64 = clientHello['eph'] as String? ?? '';
    final clientStaticPubB64 = clientHello['spub'] as String? ?? '';

    if (clientPeerId.isEmpty || clientEphB64.isEmpty) return null;
    final revokedPairing = _revocationLedger.find(
      clientPeerId,
      fingerprint: clientStaticPubB64,
      pairingId: clientHello['pairingId'] as String? ?? '',
    );
    if (!_isTrustedPeer(clientPeerId) ||
        (revokedPairing != null &&
            _trustedPeerById(clientPeerId)?.pairingId !=
                revokedPairing.pairingId)) {
      if (revokedPairing != null &&
          _outgoingPairCancellations.containsKey(revokedPairing.pairingId)) {
        return null;
      }
      final revoked = _revocationLedger.find(
        clientPeerId,
        fingerprint: clientStaticPubB64,
        pairingId: clientHello['pairingId'] as String? ?? '',
      );
      if (revoked != null) {
        final rejection = await _attachControlAuthForFingerprint(
          payload: {
            'v': 2,
            'syncProtocol': _protocolVersion,
            'revoked': true,
            'token': clientHello['token'],
            'from': _localIdentityMap(await _ensureDeviceId()),
          },
          remoteStaticPubB64: revoked.fingerprint,
          pairingId: revoked.pairingId,
        );
        socket.add(utf8.encode('${jsonEncode(rejection)}\n'));
        await socket.flush();
      }
      return null;
    }
    final currentPeer = _trustedPeerById(clientPeerId)!;
    if ((currentPeer.pairingId.isNotEmpty &&
            clientHello['pairingId'] != currentPeer.pairingId) ||
        clientStaticPubB64 != currentPeer.fingerprint) {
      return null;
    }

    // Get or generate server's static key pair.
    final serverStaticPair = await _getOrGenerateStaticKeyPair();
    final serverStaticPub = await serverStaticPair.extractPublicKey();

    // Generate a fresh ephemeral key for this session.
    final serverEphemeral = await SyncCrypto.generateKeyPair();
    final serverEphemeralPub = await serverEphemeral.extractPublicKey();

    // Send server hello.
    socket.add(
      utf8.encode(
        '${jsonEncode({'v': 2, 'syncProtocol': _protocolVersion, 'eph': base64.encode(serverEphemeralPub.bytes), 'spub': base64.encode(serverStaticPub.bytes)})}\n',
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
