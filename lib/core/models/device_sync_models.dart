library;

import 'dart:convert';

/// Version 4 compares per-record hashes before transferring, deduplicates
/// covers and compresses payloads. Older builds cannot read its messages.
const supportedDeviceSyncProtocol = 4;

// ---------------------------------------------------------------------------
// Sync snapshot — UI state for the device sync dialog and notifier.
// ---------------------------------------------------------------------------

class DeviceSyncSnapshot {
  const DeviceSyncSnapshot({
    required this.enabled,
    required this.autoOnStartup,
    required this.deviceId,
    required this.status,
    required this.trustedPeers,
    required this.discoveredPeers,
    required this.pendingPairRequests,
    required this.lastSyncAt,
    this.lastTrustedPeerId,
    this.statusMessage,
    this.firewallStatusMessage,
    this.dbMismatchPeerIds = const {},
    this.activeSyncPeerId,
  });

  final bool enabled;
  final bool autoOnStartup;
  final String deviceId;
  final DeviceSyncStatus status;
  final List<TrustedSyncPeer> trustedPeers;
  final List<DiscoveredSyncPeer> discoveredPeers;
  final List<PendingPairRequest> pendingPairRequests;
  final DateTime? lastSyncAt;
  final String? lastTrustedPeerId;
  final String? statusMessage;
  final String? firewallStatusMessage;

  /// Peer IDs whose active database file differs from ours.
  /// Auto-sync is suppressed for these peers until files match.
  final Set<String> dbMismatchPeerIds;

  /// The peer ID currently being synced (initiator side only).
  /// Null when no sync is in progress.
  final String? activeSyncPeerId;

  DeviceSyncSnapshot copyWith({
    bool? enabled,
    bool? autoOnStartup,
    String? deviceId,
    DeviceSyncStatus? status,
    List<TrustedSyncPeer>? trustedPeers,
    List<DiscoveredSyncPeer>? discoveredPeers,
    List<PendingPairRequest>? pendingPairRequests,
    DateTime? lastSyncAt,
    bool clearLastSyncAt = false,
    String? lastTrustedPeerId,
    bool clearLastTrustedPeerId = false,
    String? statusMessage,
    bool clearStatusMessage = false,
    String? firewallStatusMessage,
    bool clearFirewallStatusMessage = false,
    Set<String>? dbMismatchPeerIds,
    String? activeSyncPeerId,
    bool clearActiveSyncPeerId = false,
  }) => DeviceSyncSnapshot(
    enabled: enabled ?? this.enabled,
    autoOnStartup: autoOnStartup ?? this.autoOnStartup,
    deviceId: deviceId ?? this.deviceId,
    status: status ?? this.status,
    trustedPeers: trustedPeers ?? this.trustedPeers,
    discoveredPeers: discoveredPeers ?? this.discoveredPeers,
    pendingPairRequests: pendingPairRequests ?? this.pendingPairRequests,
    lastSyncAt: clearLastSyncAt ? null : (lastSyncAt ?? this.lastSyncAt),
    lastTrustedPeerId: clearLastTrustedPeerId
        ? null
        : (lastTrustedPeerId ?? this.lastTrustedPeerId),
    statusMessage: clearStatusMessage
        ? null
        : (statusMessage ?? this.statusMessage),
    firewallStatusMessage: clearFirewallStatusMessage
        ? null
        : (firewallStatusMessage ?? this.firewallStatusMessage),
    dbMismatchPeerIds: dbMismatchPeerIds ?? this.dbMismatchPeerIds,
    activeSyncPeerId: clearActiveSyncPeerId
        ? null
        : (activeSyncPeerId ?? this.activeSyncPeerId),
  );
}

// ---------------------------------------------------------------------------
// Sync import result — summary of what happened when remote games were applied.
// ---------------------------------------------------------------------------

class SyncImportResult {
  const SyncImportResult({
    required this.inserted,
    required this.updated,
    required this.conflicts,
    this.deleted = 0,
  });

  /// Games that were new on the remote and inserted locally.
  final int inserted;

  /// Games that existed locally but were replaced by the fresher remote copy.
  final int updated;

  /// Competing edits detected. Modern sync deterministically resolves their
  /// logical versions; legacy sync retains protected local edits.
  final int conflicts;
  final int deleted;

  bool get hasConflicts => conflicts > 0;
  int get total => inserted + updated + deleted;
}

// ---------------------------------------------------------------------------
// Sync events — emitted by DeviceSyncService to notify the UI layer.
// ---------------------------------------------------------------------------

abstract class SyncEvent {
  const SyncEvent();
}

class PeerTrustedEvent extends SyncEvent {
  const PeerTrustedEvent(this.peer);
  final TrustedSyncPeer peer;
}

class PeerRemovedEvent extends SyncEvent {
  const PeerRemovedEvent(this.peerId);
  final String peerId;
}

class PeerOfflineEvent extends SyncEvent {
  const PeerOfflineEvent(this.peerId);
  final String peerId;
}

/// A hint to check a peer's authenticated state, never a data mutation itself.
class SyncChangeAvailableEvent extends SyncEvent {
  const SyncChangeAvailableEvent({this.peerId});
  final String? peerId;
}

class PeerAvailableEvent extends SyncEvent {
  const PeerAvailableEvent(this.peer);
  final DiscoveredSyncPeer peer;
}

class SyncDataAppliedEvent extends SyncEvent {
  const SyncDataAppliedEvent(this.result);
  final SyncImportResult result;
}

class SyncTransferActivityEvent extends SyncEvent {
  const SyncTransferActivityEvent({required this.active, this.message});
  final bool active;
  final String? message;
}

/// Progress of one sync transfer, shown as a notification that stays until
/// the transfer ends. [progress] runs from 0 to 1.
class SyncProgressEvent extends SyncEvent {
  const SyncProgressEvent({
    required this.transferId,
    required this.title,
    required this.message,
    this.progress = 0,
    this.finished = false,
    this.failed = false,
  });
  final String transferId;
  final String title;
  final String message;
  final double progress;
  final bool finished;
  final bool failed;
}

class PairRequestReceivedEvent extends SyncEvent {
  const PairRequestReceivedEvent(this.request);
  final PendingPairRequest request;
}

class PairRequestTimedOutEvent extends SyncEvent {
  const PairRequestTimedOutEvent(this.request);
  final PendingPairRequest request;
}

class PairRequestCanceledEvent extends SyncEvent {
  const PairRequestCanceledEvent(this.request);
  final PendingPairRequest request;
}

class PairRequestCodeRejectedEvent extends SyncEvent {
  const PairRequestCodeRejectedEvent(this.request, {this.reason});
  final PendingPairRequest request;
  final String? reason;
}

class DbMismatchDetectedEvent extends SyncEvent {
  const DbMismatchDetectedEvent({
    required this.peerId,
    required this.peerName,
    required this.localDbName,
    required this.remoteDbName,
  });
  final String peerId;
  final String peerName;
  final String localDbName;
  final String remoteDbName;
}

// ---------------------------------------------------------------------------

enum DeviceSyncStatus {
  idle,
  discovering,
  connecting,
  connected,
  syncing,
  error,
}

enum SyncDeviceType { desktop, mobile, web, unknown }

// The wire names are the enum names.
SyncDeviceType syncDeviceTypeFromWire(String? value) =>
    SyncDeviceType.values.asNameMap()[value?.trim().toLowerCase()] ??
    SyncDeviceType.unknown;

String syncDeviceTypeToWire(SyncDeviceType value) => value.name;

class TrustedSyncPeer {
  const TrustedSyncPeer({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.deviceType = SyncDeviceType.unknown,
    this.fingerprint,
    this.pairingId = '',
    this.transferPort,
    this.lastSeenAtIso,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final SyncDeviceType deviceType;
  final String? fingerprint;

  /// Identifies this consent to pair; old removal messages cannot revoke it.
  final String pairingId;
  final int? transferPort;
  final String? lastSeenAtIso;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'fingerprint': fingerprint,
    'pairing_id': pairingId,
    if (transferPort != null) 'transfer_port': transferPort,
    'last_seen_at_iso': lastSeenAtIso,
    if (deviceType != SyncDeviceType.unknown)
      'device_type': syncDeviceTypeToWire(deviceType),
  };

  factory TrustedSyncPeer.fromJson(Map<String, dynamic> json) =>
      TrustedSyncPeer(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? 'Unknown Device',
        host: (json['host'] as String?) ?? '',
        port: (json['port'] as num?)?.toInt() ?? 0,
        deviceType: syncDeviceTypeFromWire(
          json['device_type'] as String? ?? json['deviceType'] as String?,
        ),
        fingerprint: json['fingerprint'] as String?,
        pairingId: json['pairing_id'] as String? ?? '',
        transferPort: (json['transfer_port'] as num?)?.toInt(),
        lastSeenAtIso: json['last_seen_at_iso'] as String?,
      );

  TrustedSyncPeer copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    SyncDeviceType? deviceType,
    String? fingerprint,
    String? pairingId,
    int? transferPort,
    String? lastSeenAtIso,
  }) => TrustedSyncPeer(
    id: id ?? this.id,
    name: name ?? this.name,
    host: host ?? this.host,
    port: port ?? this.port,
    deviceType: deviceType ?? this.deviceType,
    fingerprint: fingerprint ?? this.fingerprint,
    pairingId: pairingId ?? this.pairingId,
    transferPort: transferPort ?? this.transferPort,
    lastSeenAtIso: lastSeenAtIso ?? this.lastSeenAtIso,
  );
}

class DiscoveredSyncPeer {
  const DiscoveredSyncPeer({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.transferPort,
    this.syncProtocol = supportedDeviceSyncProtocol,
    this.deviceType = SyncDeviceType.unknown,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final int? transferPort;
  final int syncProtocol;

  bool get isSyncCompatible => syncProtocol == supportedDeviceSyncProtocol;
  final SyncDeviceType deviceType;

  TrustedSyncPeer toTrustedPeer() => TrustedSyncPeer(
    id: id,
    name: name,
    host: host,
    port: port,
    transferPort: transferPort,
    deviceType: deviceType,
    lastSeenAtIso: DateTime.now().toIso8601String(),
  );
}

class PendingPairRequest {
  const PendingPairRequest({
    required this.requestId,
    required this.peer,
    required this.requestedAt,
  });

  final String requestId;
  final DiscoveredSyncPeer peer;
  final DateTime requestedAt;
}

List<TrustedSyncPeer> decodeTrustedPeers(String raw) {
  if (raw.trim().isEmpty) return const [];

  try {
    final parsed = jsonDecode(raw);
    if (parsed is! List) return const [];
    return parsed
        .whereType<Map>()
        .map((e) => TrustedSyncPeer.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id.isNotEmpty)
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

String encodeTrustedPeers(List<TrustedSyncPeer> peers) =>
    jsonEncode([for (final peer in peers) peer.toJson()]);
