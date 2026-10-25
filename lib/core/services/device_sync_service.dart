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
import '../../features/sync/domain/sync_ports.dart';
import '../../features/sync/domain/sync_revocation.dart';

import '../database/database.dart';
import '../models/device_sync_models.dart';
import '../settings/settings_model.dart';
import '../utils/format_utils.dart';
import 'backup_service.dart';
import 'database_switching.dart';
import 'steam_service.dart';
import 'sync_crypto.dart';
import 'sync_entry_fingerprint.dart';
import 'sync_frames.dart';
import 'sync_payload_codec.dart';

export '../../features/sync/data/sync_firewall.dart'
    show WindowsFirewallCheckResult, LinuxFirewallCheckResult;

class DeviceSyncException implements Exception {
  const DeviceSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Pairing stopped without failing: canceled, declined or timed out.
/// [status] is the short outcome shown as the device sync status.
class PairingEndedException extends DeviceSyncException {
  const PairingEndedException.canceled()
    : status = 'Pairing canceled.',
      super('Pairing was canceled.');

  const PairingEndedException.declined()
    : status = 'Pairing request was declined.',
      super('Pairing request was declined.');

  const PairingEndedException.timedOut([
    super.message = 'Pairing request timed out after 30 seconds.',
  ]) : status = 'Pairing request timed out.';

  final String status;
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

  PendingPairRequest get pending => PendingPairRequest(
    requestId: requestId,
    peer: peer,
    requestedAt: createdAt,
  );

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

/// Which side of a session sends records: the initiator, the receiver, or
/// both. Manual sync pushes or pulls; automatic sync exchanges.
enum _SyncMode {
  exchange,
  push,
  pull;

  bool get initiatorSends => this != pull;
  bool get initiatorReceives => this != push;
}

/// Emits [SyncProgressEvent]s for one transfer, throttled so byte counts do
/// not flood the UI. Nothing is shown until the reporter is [visible].
class _ProgressReporter {
  _ProgressReporter(this._emit, {required this.title, this.visible = true});

  final void Function(SyncEvent event) _emit;
  final String id = const Uuid().v4();
  String title;
  bool visible;
  String _message = '';
  double _progress = 0;
  bool _ended = false;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  static const Duration _minInterval = Duration(milliseconds: 150);

  void update(String message, double progress, {bool throttle = false}) {
    if (_ended) return;
    _message = message;
    _progress = math.max(_progress, progress.clamp(0.0, 1.0));
    final now = DateTime.now();
    if (!visible || throttle && now.difference(_lastEmit) < _minInterval) {
      return;
    }
    _lastEmit = now;
    _emit(
      SyncProgressEvent(
        transferId: id,
        title: title,
        message: _message,
        progress: _progress,
      ),
    );
  }

  /// Maps [done] of [total] bytes onto the [from]–[to] share of the bar.
  void bytes(
    String verb,
    int done,
    int total, {
    required double from,
    required double to,
  }) {
    if (total <= 0) return;
    final fraction = (done / total).clamp(0.0, 1.0);
    update(
      '$verb ${formatFileSize(math.min(done, total))} of ${formatFileSize(total)}...',
      from + (to - from) * fraction,
      throttle: done < total,
    );
  }

  /// Shows the reporter from now on, repeating the latest state.
  void show() {
    if (visible) return;
    visible = true;
    update(_message, _progress);
  }

  void finish(String message) => _end(message, failed: false);

  void fail(String message) => _end(message, failed: true);

  void _end(String message, {required bool failed}) {
    if (_ended) return;
    _ended = true;
    if (!visible) return;
    _emit(
      SyncProgressEvent(
        transferId: id,
        title: title,
        message: message,
        progress: failed ? _progress : 1,
        finished: !failed,
        failed: failed,
      ),
    );
  }
}

/// Whether [fileName] is a plain database file name safe to create here.
@visibleForTesting
bool isValidSyncDatabaseFileName(String fileName) {
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
    if (trimmed.contains('\x00')) {
      return false;
    }
  }
  return true;
}

class DeviceSyncService {
  DeviceSyncService({
    required this.ref,
    this.discoveryPort = defaultLanPort,
    this.transferPort = SyncPorts.transfer,
    this.imagesRoot,
  }) {
    _codec = _codecFor(() => ref.read(databaseProvider));
  }

  final Ref ref;
  final int discoveryPort;
  final int transferPort;

  /// Overrides where synced cover images are stored (tests use a temp folder).
  final Future<Directory> Function()? imagesRoot;
  late final SyncPayloadCodec _codec;

  SyncPayloadCodec _codecFor(AppDatabase? Function() getDatabase) =>
      SyncPayloadCodec(getDatabase: getDatabase, imagesRoot: imagesRoot);
  bool _foreground = true;
  final _activeSyncSockets = <Socket>{};

  Future<void> setForeground(bool foreground) async {
    // Peers stop contacting a device that is going to the background.
    if (!foreground && _foreground && _responderSocket != null) {
      await _sendOffline(await _ensureDeviceId());
    }
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

  // Decoded settings are reused while their stored JSON is unchanged, so the
  // many lookups during a sync, some inside transactions, skip re-parsing.
  String? _trustedPeersJson;
  List<TrustedSyncPeer> _trustedPeerList = const [];
  Map<String, TrustedSyncPeer> _trustedById = const {};
  String? _revocationJson;
  SyncRevocationLedger? _revocationCache;

  List<TrustedSyncPeer> get _trustedPeers {
    final raw =
        ref.read(settingsProvider)[SettingsKeys.syncTrustedPeersJson]
            as String? ??
        DefaultSettings.syncTrustedPeersJson;
    if (raw != _trustedPeersJson) {
      _trustedPeersJson = raw;
      _trustedPeerList = decodeTrustedPeers(raw);
      _trustedById = {for (final peer in _trustedPeerList) peer.id: peer};
    }
    return _trustedPeerList;
  }

  SyncRevocationLedger get _revocationLedger {
    final raw =
        ref.read(settingsProvider)[SettingsKeys.syncRevokedPeersJson]
            as String?;
    if (_revocationCache == null || raw != _revocationJson) {
      _revocationJson = raw;
      _revocationCache = SyncRevocationLedger.decode(raw);
    }
    return _revocationCache!;
  }

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
  ///
  /// [skipPeerId] already has the change (it came from that peer). A peer is
  /// skipped only if every change in the burst came from it.
  Future<void> notifyLocalDataChanged({String? skipPeerId}) async {
    if (!_foreground || _responderSocket == null) return;
    final skip = {?skipPeerId};
    _signalSkip = _signalSkip?.intersection(skip) ?? skip;
    _changeSignalTimer ??= Timer(const Duration(milliseconds: 40), () {
      _changeSignalTimer = null;
      final skipped = _signalSkip ?? const {};
      _signalSkip = null;
      unawaited(_sendChangeSignals(skipped));
    });
  }

  Set<String>? _signalSkip;
  ({int revision, String peerId})? _appliedRevision;

  /// The peer whose records produced [revision], if it came from a sync.
  /// That peer already has the change, so it is neither signalled nor
  /// re-checked; other peers still are, so changes relay onward.
  String? peerThatProduced(int revision) =>
      _appliedRevision?.revision == revision ? _appliedRevision?.peerId : null;

  Future<void> _sendChangeSignals(Set<String> skipped) async {
    final socket = _responderSocket;
    if (!_foreground || socket == null) return;
    final localId = await _ensureDeviceId();
    if (!_foreground || !ref.mounted) return;
    final peers = _trustedPeers.where((peer) => !skipped.contains(peer.id));
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

  /// How long an announced or discovered address is preferred over the saved one.
  static const Duration _announceFreshness = Duration(minutes: 3);
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

  static const _placeholderNames = {
    'localhost',
    '127.0.0.1',
    '::1',
    '0.0.0.0',
    'unknown',
    'device',
  };

  bool _isPlaceholderName(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    return normalized.isEmpty || _placeholderNames.contains(normalized);
  }

  /// The first of [names] that is a real device name, trimmed.
  String? _firstRealName(Iterable<String?> names) =>
      names.where((name) => !_isPlaceholderName(name)).firstOrNull?.trim();

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

    final trustedPeers = _trustedPeers;

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
      _announceOnline(deviceId);
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
        final packet = _receivePacket(socket!, event);
        if (packet == null) return;
        final (:datagram, :payload) = packet;

        final type = payload['type'];
        if (type != _discoverResponseType && type != _announceType) {
          return;
        }

        final fromMap = _sender(payload);
        if (fromMap == null) return;
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
    for (final entry in _announcedPeers.entries) {
      final seenAt = _announcedPeersSeenAt[entry.key];
      if (seenAt == null || now.difference(seenAt) > _announceFreshness) {
        continue;
      }
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
        .map((e) => e.pending)
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
    final localStaticPubB64 = await _localStaticPubB64();
    final verificationCode = _generatePairVerificationCode();
    if (!_foreground ||
        !ref.mounted ||
        ref.read(settingsProvider)[SettingsKeys.syncEnabled] != true) {
      throw const PairingEndedException.canceled();
    }

    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
      reusePort: false,
    );
    if (!_foreground || !ref.mounted) {
      socket.close();
      throw const PairingEndedException.canceled();
    }
    final lifecycleCancellation = Completer<void>();
    _outgoingPairCancellations[requestId] = lifecycleCancellation;
    void requirePairingActive() {
      if (!_foreground ||
          !ref.mounted ||
          lifecycleCancellation.isCompleted ||
          ref.read(settingsProvider)[SettingsKeys.syncEnabled] != true) {
        throw const PairingEndedException.canceled();
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
      final packet = _receivePacket(socket, event);
      if (packet == null) return;
      final (:datagram, :payload) = packet;

      final incomingRequestId = (payload['requestId'] as String?)?.trim();
      if (incomingRequestId != requestId) {
        return;
      }

      final fromId = _senderId(payload);
      if (fromId == null) return;
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

      // Each failure below tells the receiver to drop the request first.
      Future<void> sendCancel() => _sendPairNotice(
        peer: peer,
        requestId: requestId,
        localDeviceId: localDeviceId,
      );
      Future<Never> abort(String message) async {
        await sendCancel();
        throw DeviceSyncException(message);
      }

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
          await sendCancel();
          final reason = (decision.declineReason ?? '').toLowerCase();
          if (reason.contains('user_cancel') || reason.contains('cancel')) {
            throw const PairingEndedException.canceled();
          }
          if (reason.contains('timeout')) {
            throw const PairingEndedException.timedOut();
          }
          throw const PairingEndedException.declined();
        }

        final incomingRemoteSpub = (decision.remoteStaticPubB64 ?? '').trim();
        if (incomingRemoteSpub.isEmpty) {
          await abort(
            'Remote device did not provide a pairing verification key. Update UniKM on both devices and retry.',
          );
        }

        if (remoteDecisionSpub.isEmpty) {
          remoteDecisionSpub = incomingRemoteSpub;
        } else if (incomingRemoteSpub != remoteDecisionSpub) {
          await abort(
            'Remote pairing identity changed during code verification. Retry pairing.',
          );
        }

        final encryptedProof = (decision.encryptedCodeProof ?? '').trim();
        if (encryptedProof.isEmpty) {
          await abort(
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

      // Sends one authenticated confirmation stage and waits for its ACK.
      // False means it was not confirmed in time (or the user canceled).
      Future<bool> confirmStage(
        String type,
        Completer<_PairAckResponse> ack,
        Duration timeout, {
        required String identityChangedMessage,
      }) async {
        sendStage(
          utf8.encode(
            jsonEncode(
              await _attachControlAuthForFingerprint(
                payload: {
                  'type': type,
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
          ),
        );
        final response = await Future.any([
          ack.future.timeout(
            timeout,
            onTimeout: () => const _PairAckResponse(accepted: false),
          ),
          stageCancellation,
        ]);
        if (!response.accepted) {
          requirePairingActive();
          await sendCancel();
          return false;
        }
        final remoteSpub = (response.remoteStaticPubB64 ?? '').trim();
        if (remoteSpub.isNotEmpty && remoteSpub != remoteDecisionSpub) {
          await abort(identityChangedMessage);
        }
        return true;
      }

      // A durable rejection of this pairing. The finalize stage prepares it
      // first so reconnection can undo a receiver that committed while this
      // device stopped, and keeps it if the final ACK never arrives.
      Future<void> recordRevocation() => _setSetting(
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

      if (!await confirmStage(
        _pairCommitType,
        commitAckCompleter,
        _pairCommitTimeout,
        identityChangedMessage:
            'Remote pairing identity changed during confirmation. Retry pairing.',
      )) {
        throw userCanceled
            ? const PairingEndedException.canceled()
            : const PairingEndedException.timedOut(
                'Pairing handshake timed out before receiver confirmation.',
              );
      }

      requirePairingActive();
      await recordRevocation();
      requirePairingActive();
      if (!await confirmStage(
        _pairFinalizeType,
        finalizeAckCompleter,
        _pairFinalizeTimeout,
        identityChangedMessage:
            'Remote pairing identity changed during final confirmation. Retry pairing.',
      )) {
        // The receiver may have committed while its final ACK was lost. Keep
        // the authenticated rejection even though we never established trust.
        await recordRevocation();
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
        throw userCanceled
            ? const PairingEndedException.canceled()
            : const PairingEndedException.timedOut(
                'Pairing handshake timed out waiting for final receiver OK.',
              );
      }

      requirePairingActive();
      return _upsertTrustedPeer(
        peer,
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
        localStaticPubB64 = await _localStaticPubB64();
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
    final trusted = _trustedPeers;

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

    final latest = _trustedPeers;
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
    final payload = await _attachControlAuthForFingerprint(
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
    await _sendOnce(payload, InternetAddress(peer.host), peer.port);
  }

  /// Sends one control packet from a short-lived socket.
  Future<void> _sendOnce(
    Map<String, dynamic> payload,
    InternetAddress address,
    int port,
  ) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      socket.send(utf8.encode(jsonEncode(payload)), address, port);
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
      _announceOnline(deviceId);
    } else {
      final deviceId = await _ensureDeviceId();
      await _sendOffline(deviceId);
      await stopDiscoveryResponder();
    }
  }

  Future<void> setAutoOnStartup(bool value) async {
    await _setSetting(SettingsKeys.syncAutoOnStartup, value);
  }

  /// Records a completed sync once: timestamps, the active peer, and (for
  /// manual sync) the revision ID both devices now share.
  Future<void> markSyncCompleted({
    String? peerId,
    int? authoritativeTimestampMillis,
    String? adoptRevisionId,
  }) async {
    if (adoptRevisionId != null && adoptRevisionId.isNotEmpty) {
      await _setSetting(SettingsKeys.syncDbRevisionId, adoptRevisionId);
    }
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
    if (announced == null ||
        seenAt == null ||
        DateTime.now().difference(seenAt) > _announceFreshness) {
      return null;
    }
    return announced;
  }

  /// Saves the address [discovered] reports for [peer] once the peer answers
  /// there as paired. Returns [peer] when nothing changed and null when the
  /// new address does not answer.
  Future<TrustedSyncPeer?> _adoptDiscoveredEndpoint(
    TrustedSyncPeer peer,
    DiscoveredSyncPeer discovered,
  ) async {
    if (!discovered.isSyncCompatible) {
      throw const DeviceSyncException(_incompatibleSyncMessage);
    }
    final refreshed = _mergePeerFromDiscovery(
      trustedPeer: peer,
      discoveredPeer: discovered,
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

  Future<TrustedSyncPeer> _resolveTrustedPeerEndpoint(
    TrustedSyncPeer peer,
  ) async {
    final announcedPeer = _freshAnnouncedPeerById(peer.id);
    if (announcedPeer == null) return peer;
    return await _adoptDiscoveredEndpoint(peer, announcedPeer) ?? peer;
  }

  /// An authenticated signal comes from the paired device's current address,
  /// so a changed address is saved without waiting for an announcement.
  Future<void> _learnPeerAddress(String peerId, Datagram datagram) async {
    final peer = _trustedPeerById(peerId);
    final host = datagram.address.address;
    if (peer == null || (peer.host == host && peer.port == datagram.port)) {
      return;
    }
    await _setSetting(
      SettingsKeys.syncTrustedPeersJson,
      encodeTrustedPeers([
        for (final trusted in _trustedPeers)
          trusted.id == peerId
              ? trusted.copyWith(host: host, port: datagram.port)
              : trusted,
      ]),
    );
  }

  /// Looks for a paired device that stopped answering at its saved address.
  /// Returns whether a new address was found and saved.
  Future<bool> rediscoverPeer(String peerId) async {
    final peer = _trustedPeerById(peerId);
    if (peer == null) return false;
    try {
      final found = await _rediscoverTrustedPeerEndpoint(peer);
      return found != null && _peerEndpointChanged(peer, found);
    } catch (_) {
      return false;
    }
  }

  Future<TrustedSyncPeer?> _rediscoverTrustedPeerEndpoint(
    TrustedSyncPeer peer,
  ) async {
    final matched = (await discoverPeers())
        .where((candidate) => candidate.id == peer.id)
        .firstOrNull;
    return matched == null ? null : _adoptDiscoveredEndpoint(peer, matched);
  }

  Future<void> _alignLocalDatabaseToRemoteNameForPull({
    required TrustedSyncPeer targetPeer,
    required String? remoteDbName,
  }) async {
    final name = (remoteDbName ?? '').trim();
    final currentBasePath =
        (ref.read(settingsProvider)[SettingsKeys.databasePath] as String?)
            ?.trim() ??
        '';
    if (name.isEmpty ||
        currentBasePath.isEmpty ||
        p.basename(currentBasePath) == name) {
      return;
    }
    if (!isValidSyncDatabaseFileName(name)) {
      throw DeviceSyncException(
        'Remote database file "$name" is not a valid filename on this device.',
      );
    }
    _reportTransfer(
      '[${targetPeer.name}] Switching local database to "$name" to match remote...',
    );
    try {
      await _switchToDatabaseNamed(name);
    } on DeviceSyncException {
      rethrow;
    } catch (error) {
      throw DeviceSyncException(
        'Could not switch to remote database file "$name": $error',
      );
    }
  }

  /// Opens (or creates) database file [name], looking in the default database
  /// folder first so well-known names resolve to their usual location, then
  /// beside the current database.
  Future<void> _switchToDatabaseNamed(String name) async {
    final switchCallback = ref.read(databaseSwitchCallbackProvider);
    if (switchCallback == null) {
      throw const DeviceSyncException(
        'Unable to switch database file automatically right now. Please retry.',
      );
    }
    final current =
        (ref.read(settingsProvider)[SettingsKeys.databasePath] as String?)
            ?.trim() ??
        '';
    var target = p.join(p.dirname(await AppDatabase.getDatabasePath()), name);
    if (!File(target).existsSync() && current.isNotEmpty) {
      final beside = p.join(p.dirname(current), name);
      if (File(beside).existsSync()) target = beside;
    }
    await switchCallback(
      File(target).existsSync()
          ? OpenDatabaseRequest(target)
          : CreateDatabaseRequest(path: target, encrypted: false),
    );
  }

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
    // Background syncs stay quiet unless they turn out to move a lot of data.
    final progress = _ProgressReporter(
      _emitSyncEvent,
      title: 'Syncing with ${target.name}',
      visible: fullScan,
    );
    _reportTransfer('Syncing with ${target.name}...');
    try {
      await _runSession(
        peer: target,
        mode: _SyncMode.exchange,
        database: db,
        databaseName: _currentDatabaseName(),
        expectedRemoteDbName: check.remoteDbName ?? _currentDatabaseName(),
        progress: progress,
      );
    } catch (error) {
      progress.fail('Sync with ${target.name} failed: $error');
      rethrow;
    } finally {
      _emitSyncEvent(const SyncTransferActivityEvent(active: false));
    }
  }

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
    final progress = _ProgressReporter(
      _emitSyncEvent,
      title: isPull ? 'Receiving library' : 'Sending library',
    );
    try {
      await _performManualSync(
        peerId: peerId,
        isPull: isPull,
        fullScan: fullScan,
        progress: progress,
      );
    } catch (error) {
      progress.fail('Sync failed: $error');
      rethrow;
    }
  }

  Future<void> _performManualSync({
    required String? peerId,
    required bool isPull,
    required bool fullScan,
    required _ProgressReporter progress,
  }) async {
    final settings = ref.read(settingsProvider);
    final enabled =
        (settings[SettingsKeys.syncEnabled] as bool?) ??
        DefaultSettings.syncEnabled;
    if (!enabled) {
      throw const DeviceSyncException('Device sync is disabled.');
    }

    final trustedPeers = _trustedPeers;
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

    progress.title = isPull
        ? 'Receiving from ${targetPeer.name}'
        : 'Sending to ${targetPeer.name}';
    progress.update('Creating pre-sync backup...', 0.02);
    // Labelled so it can be found in the Backup Manager to undo this sync.
    _reportTransfer('[${targetPeer.name}] Creating pre-sync backup...');
    await ref
        .read(backupServiceProvider)
        .createBackup(kind: BackupKind.preSync, peerName: targetPeer.name);

    // A pull adopts the remote database file before applying anything.
    final remoteDbName = (ping.remoteDbName ?? '').trim();
    if (isPull) {
      await _alignLocalDatabaseToRemoteNameForPull(
        targetPeer: targetPeer,
        remoteDbName: remoteDbName,
      );
    }
    final database = ref.read(databaseProvider);
    if (database == null) {
      throw const DeviceSyncException('Database is not available.');
    }
    final databaseName = _currentDatabaseName();
    if (remoteDbName.isNotEmpty &&
        databaseName.isNotEmpty &&
        remoteDbName != databaseName) {
      _emitSyncEvent(
        DbMismatchDetectedEvent(
          peerId: targetPeer.id,
          peerName: targetPeer.name,
          localDbName: databaseName,
          remoteDbName: remoteDbName,
        ),
      );
      // A push makes the receiver switch to this device's database instead.
      if (isPull) {
        throw DeviceSyncException(
          '[${targetPeer.name}] Sync aborted: remote device is using '
          '"$remoteDbName" but this device uses "$databaseName". '
          'Both devices must use the same active database file. '
          'Use the sync dialog to resolve the mismatch.',
        );
      }
    }
    try {
      await _runSession(
        peer: targetPeer,
        mode: isPull ? _SyncMode.pull : _SyncMode.push,
        database: database,
        databaseName: databaseName,
        expectedRemoteDbName: remoteDbName,
        progress: progress,
        manual: true,
      );
    } finally {
      _emitSyncEvent(const SyncTransferActivityEvent(active: false));
    }
  }

  // ── Sync sessions ─────────────────────────────────────────────────────────

  /// One encrypted session with [peer]. The request carries this device's
  /// bucket digests; the reply carries the peer's records for buckets that
  /// differ (unless pushing) and the buckets it wants back (unless pulling).
  /// Each side captures what it sends before applying what it receives.
  /// A manual push repeats on the same connection if local edits landed
  /// meanwhile.
  Future<void> _runSession({
    required TrustedSyncPeer peer,
    required _SyncMode mode,
    required AppDatabase database,
    required String databaseName,
    required String expectedRemoteDbName,
    required _ProgressReporter progress,
    bool manual = false,
  }) async {
    void requireContext() => _requireManualSyncContext(
      database: database,
      databaseName: databaseName,
      peer: peer,
    );
    requireContext();
    final codec = _codecFor(() => database);
    final localId = await _ensureDeviceId();
    final Socket socket;
    try {
      socket = await _connectSyncSocket(
        peer.host,
        peer.transferPort ?? transferPort,
      );
    } catch (_) {
      throw DeviceSyncException(
        'Could not connect to ${peer.name}. '
        'Make sure the remote device has sync enabled.',
      );
    }
    final SyncChannel channel;
    try {
      channel = await _performClientHandshake(socket, peer, localId);
    } catch (_) {
      socket.destroy();
      rethrow;
    }
    final steamDigest = manual ? await _steamCacheDigest() : null;
    final sent = <String>[];
    var received = _noChanges;
    try {
      for (var round = 0; ; round++) {
        requireContext();
        progress.update('Comparing databases...', 0.05);
        await codec.getDatasetDigest();
        final count = SyncPayloadCodec.bucketCountFor(codec.hashedRecordCount);
        final local = await codec.getBucketDigests(count);
        final revisionId = _currentSyncCode();
        await channel.sendJson({
          't': 'sync',
          'mode': mode.name,
          'syncProtocol': _protocolVersion,
          'requestingPeerId': localId,
          'deviceName': _currentDeviceName(),
          'senderDbName': databaseName,
          'expectedReceiverDbName': expectedRemoteDbName,
          'syncRevisionId': revisionId,
          'interactive': manual || progress.visible,
          'buckets': local.digests,
          if (mode.initiatorReceives)
            'storedCovers': await codec.getLocalCoverDigests(),
          'steamCacheDigest': ?steamDigest,
        });
        progress.update('Waiting for ${peer.name}...', 0.1);
        final response = _requireReply(
          await channel.readPayload(
            onKeepAlive: () =>
                progress.update('${peer.name} is comparing databases...', 0.12),
            onProgress: (done, total) =>
                progress.bytes('Receiving', done, total, from: 0.12, to: 0.5),
          ),
          peer,
        );
        requireContext();
        if (_isLargeTransfer(response)) progress.show();

        // Send ours before applying theirs, so their records never echo back.
        int? sentRevision;
        if (mode.initiatorSends) {
          final outgoing = await codec.buildDeltaPayload(
            syncRevisionId: revisionId,
            deviceName: _currentDeviceName(),
            includeSteamCache:
                steamDigest != null &&
                response['steamCacheDigest'] != steamDigest,
            onlyBuckets: (
              count: count,
              buckets: {
                ...(response['want'] as List? ?? const []).whereType<int>(),
              },
              hashedRevision: local.revision,
            ),
            peerCovers: {
              ...(response['storedCovers'] as List? ?? const [])
                  .whereType<String>(),
            },
          );
          requireContext();
          sentRevision = outgoing['localRevision'] as int;
          final summary = _changeSummary(outgoing);
          sent.add(summary);
          if (_isLargeTransfer(outgoing)) progress.show();
          _reportTransfer('[${peer.name}] Sending $summary...');
          progress.update('Sending $summary...', 0.5);
          await channel.sendPayload(
            outgoing,
            onProgress: (done, total) =>
                progress.bytes('Sending', done, total, from: 0.5, to: 0.75),
          );
        }

        if (mode.initiatorReceives) {
          received = _changeSummary(response);
          _reportTransfer('[${peer.name}] Applying $received...');
          progress.update('Applying $received...', 0.8);
          final remoteTimestamp =
              (response['dbTimestampMillis'] as num?)?.toInt() ?? 0;
          final result = await _applyPayload(
            response,
            peer: peer,
            database: database,
            codec: codec,
            requireContext: requireContext,
            manual: manual,
          );
          await markSyncCompleted(
            peerId: peer.id,
            authoritativeTimestampMillis: manual && remoteTimestamp > 0
                ? remoteTimestamp
                : null,
            adoptRevisionId: manual
                ? response['syncRevisionId'] as String?
                : null,
          );
          _emitSyncEvent(SyncDataAppliedEvent(result));
        }

        if (mode.initiatorSends) {
          progress.update('Waiting for ${peer.name} to apply changes...', 0.9);
          final ack = _requireReply(
            await channel.readJson(
              onKeepAlive: () =>
                  progress.update('${peer.name} is applying changes...', 0.92),
            ),
            peer,
          );
          if (ack['syncApplied'] != true) {
            throw const DeviceSyncException(
              'Remote device did not confirm sync.',
            );
          }
          requireContext();
          if (ack['steamCache'] case final Map cache) {
            await mergeSteamCacheSnapshotFromSync(
              Map<String, dynamic>.from(cache),
            );
          }
          if (mode == _SyncMode.push) {
            // The receiver adopted the revision ID sent, so both now match.
            final timestamp = (ack['dbTimestampMillis'] as num?)?.toInt() ?? 0;
            await markSyncCompleted(
              peerId: peer.id,
              authoritativeTimestampMillis: timestamp > 0 ? timestamp : null,
              adoptRevisionId: revisionId,
            );
          }
        }

        final editedMeanwhile =
            mode == _SyncMode.push &&
            sentRevision != null &&
            await database.getLocalSyncRevision() > sentRevision;
        if (!editedMeanwhile || round >= 2) break;
        _reportTransfer(
          '[${peer.name}] Mid-sync local edits detected. Sending follow-up delta...',
        );
      }
      progress.finish(switch (mode) {
        _SyncMode.exchange =>
          'Databases match. Sent ${sent.single}, received $received.',
        _SyncMode.pull => _transferOutcome(
          'Received',
          received,
          'from',
          peer.name,
        ),
        _SyncMode.push => _transferOutcome(
          'Sent',
          sent.join(', then '),
          'to',
          peer.name,
        ),
      });
    } on TimeoutException {
      throw DeviceSyncException('${peer.name} stopped responding during sync.');
    } on SyncFrameException catch (error) {
      throw DeviceSyncException(error.message);
    } finally {
      await channel.close();
    }
  }

  /// Applies a peer's records with its checkpoint in one transaction that
  /// rolls back if the database or pairing changes meanwhile.
  Future<SyncImportResult> _applyPayload(
    Map<String, dynamic> payload, {
    required TrustedSyncPeer peer,
    required AppDatabase database,
    required SyncPayloadCodec codec,
    required void Function() requireContext,
    required bool manual,
  }) async {
    if (payload['steamCache'] case final Map cache) {
      await mergeSteamCacheSnapshotFromSync(Map<String, dynamic>.from(cache));
    }
    final remoteTimestamp =
        (payload['dbTimestampMillis'] as num?)?.toInt() ?? 0;
    return database
        .transaction(() async {
          requireContext();
          // Manual sync judges competing edits against the last sync time.
          final checkpoint = manual
              ? await database.getPeerSyncCheckpoint(peer.id)
              : null;
          final knownSyncAt = checkpoint?['lastSyncAt'] as int?;
          final applied = await codec.applyDeltaPayload(
            _payloadRecords(payload['games']),
            tombstones: _payloadRecords(payload['tombstones']),
            covers: payload['covers'] as Map<String, SyncCover>? ?? const {},
            lastSyncAt: knownSyncAt == null || knownSyncAt <= 0
                ? null
                : DateTime.fromMillisecondsSinceEpoch(knownSyncAt),
          );
          requireContext();
          await database.savePeerSyncCheckpoint(
            peerId: peer.id,
            lastRevision: (payload['localRevision'] as num?)?.toInt() ?? 0,
            lastSyncAt: manual && remoteTimestamp > 0
                ? DateTime.fromMillisecondsSinceEpoch(remoteTimestamp)
                : DateTime.now(),
            remoteRevisionId: manual
                ? payload['syncRevisionId'] as String? ?? ''
                : payload['contentDigest'] as String? ?? '',
          );
          requireContext();
          return applied;
        })
        .then((applied) async {
          _appliedRevision = (
            revision: await database.getLocalSyncRevision(),
            peerId: peer.id,
          );
          return applied;
        });
  }

  /// A reply from the peer, or the reason it could not serve the session.
  Map<String, dynamic> _requireReply(
    Map<String, dynamic>? reply,
    TrustedSyncPeer peer,
  ) {
    if (reply == null) {
      throw const DeviceSyncException('Remote device did not confirm sync.');
    }
    if (reply['syncProtocol'] != _protocolVersion) {
      throw const DeviceSyncException(_incompatibleSyncMessage);
    }
    if (reply['errorCode'] == 'receiver_db_changed') {
      throw DeviceSyncException(
        '[${peer.name}] Sync cancelled because the receiver switched active '
        'database from "${reply['expectedReceiverDbName']}" to '
        '"${reply['receiverDbName']}" before apply. '
        'Please recheck and start sync again.',
      );
    }
    final error = (reply['error'] as String?)?.trim() ?? '';
    if (error.isNotEmpty) throw DeviceSyncException('[${peer.name}] $error');
    return reply;
  }

  /// Steam metadata travels only when the two caches differ.
  Future<String> _steamCacheDigest() async => SyncEntryFingerprint.hashBytes(
    utf8.encode(jsonEncode(_canonicalizeJson(await _codec.exportSteamCache()))),
  );

  // ── Transfer helpers ──────────────────────────────────────────────────────

  /// Automatic syncs moving at least this many records show a progress
  /// notification; smaller ones stay in the background.
  static const int _progressNotifyRecords = 100;

  static bool _isLargeTransfer(Map<String, dynamic> payload) =>
      ((payload['games'] as List?)?.length ?? 0) +
          ((payload['tombstones'] as List?)?.length ?? 0) >=
      _progressNotifyRecords;

  static String _transferOutcome(
    String verb,
    String summary,
    String preposition,
    String peerName,
  ) => summary == _noChanges
      ? 'Databases already match $peerName.'
      : '$verb $summary $preposition $peerName.';

  static const String _noChanges = 'no changes';

  static String _changeSummary(Map<String, dynamic> payload) {
    final games = (payload['games'] as List?)?.length ?? 0;
    final deletions = (payload['tombstones'] as List?)?.length ?? 0;
    if (games == 0 && deletions == 0) return _noChanges;
    final parts = [
      if (games > 0) '$games record${games == 1 ? '' : 's'}',
      if (deletions > 0) '$deletions deletion${deletions == 1 ? '' : 's'}',
    ];
    return parts.join(' and ');
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
        final packet = _receivePacket(socket, event);
        if (packet == null) return;
        final (:datagram, :payload) = packet;

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

        final fromId = _senderId(payload);
        if (fromId == null) return;
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
    // Counted before any await so a competing initiator sync sees it at once.
    _incomingSyncCount++;
    final reader = SyncByteReader(socket);
    // Shown once the peer asks for it, or once the transfer proves large.
    final progress = _ProgressReporter(
      _emitSyncEvent,
      title: 'Syncing',
      visible: false,
    );
    try {
      _reportTransfer('Incoming sync: waiting for data...');
      final Map<String, dynamic> hello;
      try {
        final line = await reader.readLine();
        if (line == null || line.isEmpty) return;
        hello = jsonDecode(line) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
      if (hello['v'] != 2) {
        debugPrint('Sync: rejected non-v2 connection on encrypted channel.');
        return;
      }
      final handshake = await _performServerHandshake(socket, hello);
      if (handshake == null) return;
      final channel = SyncChannel(
        socket,
        reader,
        handshake.sessionKey,
        client: false,
      );
      final peerId = hello['peerId'] as String? ?? '';
      progress.title =
          'Syncing with ${_trustedPeerById(peerId)?.name ?? 'paired device'}';
      while (true) {
        // The peer cannot impersonate another paired device, and an unpair
        // during the session ends it.
        final request = await channel.readJson(
          idle: const Duration(seconds: 60),
        );
        final peer = _trustedPeerById(peerId);
        final mode = _SyncMode.values.asNameMap()[request?['mode']];
        if (request == null ||
            mode == null ||
            request['t'] != 'sync' ||
            request['syncProtocol'] != _protocolVersion ||
            request['requestingPeerId'] != peerId ||
            peer == null ||
            peer.pairingId != (hello['pairingId'] ?? '') ||
            peer.fingerprint != hello['spub']) {
          return;
        }
        final keepAlive = Timer.periodic(
          const Duration(seconds: 4),
          (_) => unawaited(channel.keepAlive().catchError((Object _) {})),
        );
        try {
          if (!await _serveSession(channel, request, mode, peer, progress)) {
            return;
          }
        } finally {
          keepAlive.cancel();
        }
      }
    } catch (e) {
      debugPrint('Sync server receive error: $e');
      progress.fail('Sync failed: $e');
    } finally {
      await reader.cancel();
      socket.destroy();
      _incomingSyncCount--;
      if (!_receiverSyncInFlight) {
        _emitSyncEvent(const SyncTransferActivityEvent(active: false));
      }
    }
  }

  /// Serves one request; false ends the connection.
  Future<bool> _serveSession(
    SyncChannel channel,
    Map<String, dynamic> request,
    _SyncMode mode,
    TrustedSyncPeer peer,
    _ProgressReporter progress,
  ) async {
    final senderName = (request['deviceName'] as String?)?.trim() ?? '';
    final displayName = peer.name.trim().isNotEmpty
        ? peer.name
        : senderName.isNotEmpty
        ? senderName
        : 'remote device';
    progress.title = switch (mode) {
      _SyncMode.pull => 'Sending to $displayName',
      _SyncMode.exchange => 'Syncing with $displayName',
      _SyncMode.push => 'Receiving from $displayName',
    };
    if (request['interactive'] == true) progress.show();
    final senderDbName = (request['senderDbName'] as String?)?.trim() ?? '';
    final expected =
        (request['expectedReceiverDbName'] as String?)?.trim() ?? '';

    // A push switches this device to (or creates) the sender's database file.
    var switched = false;
    if (mode == _SyncMode.push &&
        senderDbName.isNotEmpty &&
        senderDbName != _currentDatabaseName()) {
      if (!isValidSyncDatabaseFileName(senderDbName)) return false;
      _reportTransfer(
        '[$displayName] Switching database to "$senderDbName" to match sender...',
      );
      await _switchToDatabaseNamed(senderDbName);
      switched = true;
    }
    final database = ref.read(databaseProvider);
    final dbName = _currentDatabaseName();
    Future<bool> refuse(Map<String, dynamic> reply, String reason) async {
      await channel.sendPayload({
        'syncProtocol': _protocolVersion,
        'syncApplied': false,
        ...reply,
      });
      _reportTransfer('[$displayName] $reason');
      progress.fail(reason);
      return false;
    }

    if (mode == _SyncMode.push &&
        !switched &&
        expected.isNotEmpty &&
        expected != dbName) {
      return refuse({
        'errorCode': 'receiver_db_changed',
        'error':
            'Receiver active database changed before apply. Sync cancelled.',
        'expectedReceiverDbName': expected,
        'receiverDbName': dbName,
      }, 'Sync blocked: the active database changed.');
    }
    final error = switch (mode) {
      _ when database == null => 'Database is not available.',
      _SyncMode.exchange when senderDbName != dbName || expected != dbName =>
        'Active database changed or does not match.',
      _SyncMode.pull when expected.isNotEmpty && expected != dbName =>
        'Remote database changed during pull.',
      _SyncMode.push when senderDbName.isNotEmpty && senderDbName != dbName =>
        'Could not align the receiving database.',
      _ => null,
    };
    if (error != null) return refuse({'error': error}, error);

    final db = database!;
    void requireContext() => _requireManualSyncContext(
      database: db,
      databaseName: dbName,
      peer: peer,
    );
    requireContext();
    final codec = _codecFor(() => db);
    final remoteBuckets = request['buckets'] as List? ?? const [];
    if (remoteBuckets.isEmpty || remoteBuckets.length > 4096) return false;
    progress.update('Comparing databases...', 0.05);
    final local = await codec.getBucketDigests(remoteBuckets.length);
    final differing = SyncPayloadCodec.differingBuckets(
      local.digests,
      remoteBuckets,
    );
    final peerSteamDigest = request['steamCacheDigest'] as String?;
    final steamDigest = peerSteamDigest == null
        ? null
        : await _steamCacheDigest();
    // Captured before the peer's records are applied.
    final response = mode.initiatorReceives
        ? await codec.buildDeltaPayload(
            syncRevisionId: _currentSyncCode(),
            deviceName: _currentDeviceName(),
            includeSteamCache:
                steamDigest != null && steamDigest != peerSteamDigest,
            onlyBuckets: (
              count: remoteBuckets.length,
              buckets: differing,
              hashedRevision: local.revision,
            ),
            peerCovers: {
              ...(request['storedCovers'] as List? ?? const [])
                  .whereType<String>(),
            },
          )
        : <String, dynamic>{'syncProtocol': _protocolVersion};
    response['senderDbName'] = dbName;
    if (mode.initiatorSends) {
      response['want'] = differing.toList(growable: false);
      response['storedCovers'] = await codec.getLocalCoverDigests();
      if (steamDigest != null) response['steamCacheDigest'] = steamDigest;
    }
    requireContext();
    final sent = _changeSummary(response);
    if (_isLargeTransfer(response)) progress.show();
    if (mode.initiatorReceives) {
      _reportTransfer('[$displayName] Sending $sent...');
    }
    progress.update('Sending $sent...', 0.1);
    await channel.sendPayload(
      response,
      onProgress: (done, total) =>
          progress.bytes('Sending', done, total, from: 0.1, to: 0.5),
    );
    if (!mode.initiatorSends) {
      progress.finish(_transferOutcome('Sent', sent, 'to', displayName));
      return true;
    }

    final payload = await channel.readPayload(
      idle: const Duration(seconds: 60),
      onProgress: (done, total) =>
          progress.bytes('Receiving', done, total, from: 0.5, to: 0.8),
    );
    if (payload == null || payload['syncProtocol'] != _protocolVersion) {
      return false;
    }
    final received = _changeSummary(payload);
    if (_isLargeTransfer(payload)) progress.show();
    _reportTransfer('[$displayName] Received $received. Applying...');
    progress.update('Applying $received...', 0.85);
    final manual = mode == _SyncMode.push;
    final result = await _applyPayload(
      payload,
      peer: peer,
      database: db,
      codec: codec,
      requireContext: requireContext,
      manual: manual,
    );
    final senderTimestamp =
        (payload['dbTimestampMillis'] as num?)?.toInt() ?? 0;
    final adopted = payload['syncRevisionId'] as String?;
    await markSyncCompleted(
      peerId: manual ? null : peer.id,
      authoritativeTimestampMillis: manual && senderTimestamp > 0
          ? senderTimestamp
          : null,
      adoptRevisionId: manual ? adopted : null,
    );
    requireContext();
    // The merged Steam cache goes back only when it still differs.
    final returnSteamCache =
        steamDigest != null && await _steamCacheDigest() != peerSteamDigest;
    await channel.sendJson({
      'syncProtocol': _protocolVersion,
      'syncApplied': true,
      'syncRevisionId': manual ? adopted : _currentSyncCode(),
      'localRevision': await db.getLocalSyncRevision(),
      'dbTimestampMillis': await db.getSyncDbTimestampMillis(),
      if (returnSteamCache) 'steamCache': await _codec.exportSteamCache(),
    });
    _emitSyncEvent(SyncDataAppliedEvent(result));
    progress.finish(
      mode == _SyncMode.exchange
          ? 'Databases match. Received $received, sent $sent.'
          : _transferOutcome('Received', received, 'from', displayName),
    );
    return true;
  }

  Future<void> stopDiscoveryResponder() async {
    _networkEpoch++;
    for (final cancellation in _outgoingPairCancellations.values) {
      if (!cancellation.isCompleted) cancellation.complete();
    }
    _changeSignalTimer?.cancel();
    _changeSignalTimer = null;
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

    final fromId = _senderId(payload);
    if (fromId == null) return;
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
    final fromId = _senderId(payload);
    if (fromId == null) return;
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
          'syncProtocol': _protocolVersion,
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
        'syncProtocol': _protocolVersion,
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
    TrustedSyncPeer? byId(String id) =>
        trustedPeers.where((peer) => peer.id == id).firstOrNull;
    if (explicitPeerId != null && explicitPeerId.isNotEmpty) {
      return byId(explicitPeerId);
    }
    final fallback = fallbackPeerId != null && fallbackPeerId.isNotEmpty
        ? byId(fallbackPeerId)
        : null;
    return fallback ?? trustedPeers.first;
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
        if (completer.isCompleted) return;
        final payload = _receivePacket(socket, event)?.payload;
        if (payload == null || payload['type'] != _syncPongType) return;

        final incomingToken = (payload['token'] as String?)?.trim();
        if (incomingToken != token) {
          return;
        }

        final fromId = _senderId(payload);
        if (fromId == null) return;
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
    final trustedPeers = _trustedPeers;
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

    // Prefer a freshly announced address when the peer answers there.
    _PeerPingResult? ping;
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
        }
      }
    }
    ping ??= await _pingPeer(target);
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

  /// One announcement when this device comes online (start, resume, enable)
  /// lets paired devices pick up a new address; there is no periodic loop.
  void _announceOnline(String deviceId) {
    if (_foreground) unawaited(_sendAnnounce(deviceId));
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
    switch (type) {
      case _changedType:
        final from = payload['from'];
        final peerId = from is Map ? from['id'] as String? ?? '' : '';
        if (await _verifyTrustedControlPacketAuth(
              payload: payload,
              fromPeerId: peerId,
            ) &&
            _acceptFreshControl(payload, peerId)) {
          await _learnPeerAddress(peerId, datagram);
          _emitSyncEvent(SyncChangeAvailableEvent(peerId: peerId));
        }
      case _offlineType:
        _handleOffline(datagram, payload, deviceId);
      case _syncPongType:
        await _handleSyncPong(payload);
      case _syncPingType:
        await _handleSyncPing(socket, datagram, payload, deviceId);
      case _untrustType:
        await _handleUntrust(datagram, payload);
      case _pairCancelType:
        _handlePairCancel(payload);
      case _pairCodeRejectedType:
        _handlePairCodeRejected(datagram, payload);
      case _pairRequestType:
        await _handlePairRequest(datagram, payload, deviceId);
      case _pairCommitType:
        await _handlePairCommit(socket, datagram, payload, deviceId);
      case _pairFinalizeType:
        await _handlePairFinalize(socket, datagram, payload, deviceId);
    }
  }

  void _handleAnnounce(
    Datagram datagram,
    Map<String, dynamic> payload,
    String deviceId,
  ) {
    final fromMap = _sender(payload);
    if (fromMap == null) return;
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
    final fromId = _senderId(payload);
    if (fromId == null) return;
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
    final fromMap = _sender(payload);
    if (fromMap == null) return;
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
    final receiverStaticPubB64 =
        initiatorStaticPubB64 != null && initiatorStaticPubB64.isNotEmpty
        ? await _localStaticPubB64()
        : null;

    final replyPort = (payload['replyPort'] as num?)?.toInt() ?? datagram.port;
    final request = _pendingPairRequests[requestId] = _IncomingPairRequestState(
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
    _emitSyncEvent(PairRequestReceivedEvent(request.pending));
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

    final fromId = _senderId(payload);
    if (fromId == null) return null;
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
      localStaticPubB64 = await _localStaticPubB64();
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
      final ack = await _attachControlAuthIfTrusted(
        payload: {
          'type': _pairFinalizeAckType,
          'protocol': _protocolVersion,
          'requestId': requestId,
          'accepted': true,
          'ok': true,
          'spub': await _localStaticPubB64(),
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
        localStaticPubB64 = await _localStaticPubB64();
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
      _emitSyncEvent(PairRequestCanceledEvent(request.pending));
    }
  }

  void _handlePairCodeRejected(
    Datagram datagram,
    Map<String, dynamic> payload,
  ) {
    final request = _acceptedPairRequest(datagram, payload);
    if (request == null) return;
    _pairDecisions.remove(request.requestId);
    _emitSyncEvent(
      PairRequestCodeRejectedEvent(
        request.pending,
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
    await _sendOnce(
      {
        'type': type,
        'protocol': _protocolVersion,
        'requestId': requestId,
        'reason': ?reason,
        'from': _localIdentityMap(localDeviceId),
      },
      InternetAddress(peer.host),
      peer.port,
    );
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
    await _sendOnce(
      {
        'type': request.receiverAccepted
            ? _pairCancelType
            : _pairReceiverDecisionType,
        'protocol': _protocolVersion,
        'requestId': request.requestId,
        if (!request.receiverAccepted) 'accepted': false,
        'reason': 'timeout',
        'from': _localIdentityMap(localDeviceId),
      },
      request.sourceAddress,
      request.replyPort,
    );
  }

  bool _isTrustedPeer(String peerId) => _trustedPeerById(peerId) != null;

  TrustedSyncPeer? _trustedPeerById(String peerId) {
    _trustedPeers;
    return _trustedById[peerId];
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
    return _x25519.sharedSecretKey(
      keyPair: localStaticPair,
      remotePublicKey: remoteStaticPub,
    );
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

    final localStaticPubB64 = await _localStaticPubB64();
    final mac = await _computeControlPacketMac(
      payload: payload,
      remoteStaticPubB64: remoteFingerprint,
    );

    payload['auth'] = {
      'alg': _controlAuthAlg,
      'spub': localStaticPubB64,
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
    final trusted = _trustedPeers;
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
      _emitSyncEvent(PairRequestTimedOutEvent(request.pending));
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
      for (final peer in _trustedPeers) {
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

  /// The sender identity a control packet carries, if well formed.
  static Map<String, dynamic>? _sender(Map<String, dynamic> payload) =>
      payload['from'] is Map
      ? Map<String, dynamic>.from(payload['from'] as Map)
      : null;

  /// The trimmed sender id of a control packet; null without a sender and
  /// empty when the sender carries no id.
  static String? _senderId(Map<String, dynamic> payload) {
    final sender = _sender(payload);
    return sender == null ? null : (sender['id'] as String?)?.trim() ?? '';
  }

  /// The next datagram on [socket] and its control packet, when [event] is a
  /// read that carries a packet [_decodePacket] accepts.
  ({Datagram datagram, Map<String, dynamic> payload})? _receivePacket(
    RawDatagramSocket socket,
    RawSocketEvent event,
  ) {
    if (event != RawSocketEvent.read) return null;
    final datagram = socket.receive();
    if (datagram == null) return null;
    final payload = _decodePacket(datagram.data);
    return payload == null ? null : (datagram: datagram, payload: payload);
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
      return _firstRealName([
            if (Platform.isWindows) Platform.environment['COMPUTERNAME'],
            if (Platform.isMacOS || Platform.isLinux)
              Platform.environment['HOSTNAME'],
          ]) ??
          _firstRealName([Platform.localHostname]) ??
          _defaultDeviceName(fallbackType);
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
      final List<String?> names;
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        names = [info.model, info.device];
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        names = [info.name, info.model];
      } else if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        names = [info.computerName, Platform.environment['COMPUTERNAME']];
      } else if (Platform.isMacOS) {
        names = [(await deviceInfo.macOsInfo).computerName];
      } else if (Platform.isLinux) {
        final info = await deviceInfo.linuxInfo;
        names = [info.name, Platform.environment['HOSTNAME']];
      } else {
        names = const [];
      }
      return _firstRealName(names) ?? _defaultDeviceName(fallbackType);
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

  /// This device's static public key as sent in pairing and control packets.
  Future<String> _localStaticPubB64() async => base64.encode(
    (await (await _getOrGenerateStaticKeyPair()).extractPublicKey()).bytes,
  );

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
  Future<SyncChannel> _performClientHandshake(
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

    // One reader serves the hello line and every frame after it.
    final reader = SyncByteReader(socket);
    Future<Never> fail(String message) async {
      await reader.cancel();
      throw DeviceSyncException(message);
    }

    String? line;
    try {
      line = await reader.readLine();
    } on TimeoutException {
      return fail('Remote device did not respond to encrypted handshake.');
    }
    if (line == null || line.isEmpty) {
      return fail('Remote device closed connection during handshake.');
    }

    Map<String, dynamic> serverHello;
    try {
      serverHello = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return fail('Invalid handshake response from remote device.');
    }
    if (serverHello['v'] != 2 ||
        serverHello['syncProtocol'] != _protocolVersion) {
      return fail(_incompatibleSyncMessage);
    }

    if (serverHello['revoked'] == true &&
        serverHello['token'] == token &&
        await _verifyControlAuthForFingerprint(
          payload: serverHello,
          expectedFingerprint: targetPeer.fingerprint ?? '',
          pairingId: targetPeer.pairingId,
        )) {
      await reader.cancel();
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
      return fail('Remote device sent an invalid handshake response.');
    }

    final expectedFingerprint = (targetPeer.fingerprint ?? '').trim();
    if (expectedFingerprint.isEmpty) {
      return fail(
        'Remote identity key is missing for this pairing. '
        'Remove and re-pair before syncing.',
      );
    }
    if (serverStaticPubB64.isEmpty) {
      return fail(
        'Remote device did not provide identity key during handshake.',
      );
    }
    if (serverStaticPubB64 != expectedFingerprint) {
      return fail(
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

    return SyncChannel(socket, reader, sessionKey, client: true);
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
      if (revokedPairing case final revoked?) {
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
    // One identity check: the stored key must exist and match exactly.
    final currentPeer = _trustedPeerById(clientPeerId)!;
    final expectedFingerprint = (currentPeer.fingerprint ?? '').trim();
    if (expectedFingerprint.isEmpty ||
        clientStaticPubB64 != expectedFingerprint ||
        (currentPeer.pairingId.isNotEmpty &&
            clientHello['pairingId'] != currentPeer.pairingId)) {
      debugPrint('Sync: client identity verification failed for $clientPeerId');
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
