library;

import 'dart:convert';

/// Version 4 compares per-record hashes before transferring, deduplicates
/// covers and compresses payloads. Older builds cannot read its messages.
const supportedDeviceSyncProtocol = 4;

// ---------------------------------------------------------------------------
// Sync snapshot — UI state for the device sync dialog and notifier.
// ---------------------------------------------------------------------------

class const DeviceSyncSnapshot({
  required final bool enabled,
  required final bool autoOnStartup,
  required final String deviceId,
  required final DeviceSyncStatus status,
  required final List<TrustedSyncPeer> trustedPeers,
  required final List<DiscoveredSyncPeer> discoveredPeers,
  required final List<PendingPairRequest> pendingPairRequests,
  required final DateTime? lastSyncAt,
  final String? lastTrustedPeerId,
  final String? statusMessage,
  final String? firewallStatusMessage,

  /// Peer IDs whose active database file differs from ours.
  /// Auto-sync is suppressed for these peers until files match.
  final Set<String> dbMismatchPeerIds = const {},

  /// The peer ID currently being synced (initiator side only).
  /// Null when no sync is in progress.
  final String? activeSyncPeerId,
}) {
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

class const SyncImportResult({
  /// Games that were new on the remote and inserted locally.
  required final int inserted,

  /// Games that existed locally but were replaced by the fresher remote copy.
  required final int updated,

  /// Competing edits detected. Modern sync deterministically resolves their
  /// logical versions; legacy sync retains protected local edits.
  required final int conflicts,
  final int deleted = 0,
}) {
  bool get hasConflicts => conflicts > 0;
  int get total => inserted + updated + deleted;
}

// ---------------------------------------------------------------------------
// Sync events — emitted by DeviceSyncService to notify the UI layer.
// ---------------------------------------------------------------------------

abstract class const SyncEvent();

class const PeerTrustedEvent(final TrustedSyncPeer peer) extends SyncEvent;

class const PeerRemovedEvent(final String peerId) extends SyncEvent;

class const PeerOfflineEvent(final String peerId) extends SyncEvent;

/// A hint to check a peer's authenticated state, never a data mutation itself.
class const SyncChangeAvailableEvent({final String? peerId})
    extends SyncEvent {}

class const PeerAvailableEvent(final DiscoveredSyncPeer peer)
    extends SyncEvent {}

class const SyncDataAppliedEvent(final SyncImportResult result)
    extends SyncEvent {}

class const SyncTransferActivityEvent({
  required final bool active,
  final String? message,
}) extends SyncEvent;

/// Progress of one sync transfer, shown as a notification that stays until
/// the transfer ends. [progress] runs from 0 to 1.
class const SyncProgressEvent({
  required final String transferId,
  required final String title,
  required final String message,
  final double progress = 0,
  final bool finished = false,
  final bool failed = false,
}) extends SyncEvent;

class const PairRequestReceivedEvent(final PendingPairRequest request)
    extends SyncEvent {}

class const PairRequestTimedOutEvent(final PendingPairRequest request)
    extends SyncEvent {}

class const PairRequestCanceledEvent(final PendingPairRequest request)
    extends SyncEvent {}

class const DbMismatchDetectedEvent({
  required final String peerId,
  required final String peerName,
  required final String localDbName,
  required final String remoteDbName,
}) extends SyncEvent;

// ---------------------------------------------------------------------------

enum DeviceSyncStatus() {
  idle,
  discovering,
  connecting,
  connected,
  syncing,
  error,
}

enum SyncDeviceType() {
  desktop,
  mobile,
  web,
  unknown,
}

// The wire names are the enum names.
SyncDeviceType syncDeviceTypeFromWire(String? value) =>
    SyncDeviceType.values.asNameMap()[value?.trim().toLowerCase()] ??
    SyncDeviceType.unknown;

String syncDeviceTypeToWire(SyncDeviceType value) => value.name;

class const TrustedSyncPeer({
  required final String id,
  required final String name,
  required final String host,
  required final int port,
  final SyncDeviceType deviceType = SyncDeviceType.unknown,
  final String? fingerprint,

  /// Identifies this consent to pair; old removal messages cannot revoke it.
  final String pairingId = '',
  final int? transferPort,
  final String? lastSeenAtIso,
}) {
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

class const DiscoveredSyncPeer({
  required final String id,
  required final String name,
  required final String host,
  required final int port,
  final int? transferPort,
  final int syncProtocol = supportedDeviceSyncProtocol,
  final SyncDeviceType deviceType = SyncDeviceType.unknown,
}) {
  bool get isSyncCompatible => syncProtocol == supportedDeviceSyncProtocol;
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

class const PendingPairRequest({
  required final String requestId,
  required final DiscoveredSyncPeer peer,
  required final DateTime requestedAt,

  /// The 6-digit code both devices show; the user checks that they match.
  required final String code,
});

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
