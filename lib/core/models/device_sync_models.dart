library;

import 'dart:convert';

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
  }) {
    return DeviceSyncSnapshot(
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
}

// ---------------------------------------------------------------------------
// Sync import result — summary of what happened when remote games were applied.
// ---------------------------------------------------------------------------

class SyncImportResult {
  const SyncImportResult({
    required this.inserted,
    required this.updated,
    required this.conflicts,
  });

  /// Games that were new on the remote and inserted locally.
  final int inserted;

  /// Games that existed locally but were replaced by the fresher remote copy.
  final int updated;

  /// Games where both devices had local changes since the last sync;
  /// the remote version was skipped to avoid data loss.
  final int conflicts;

  bool get hasConflicts => conflicts > 0;
  int get total => inserted + updated;
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

class SyncDataAppliedEvent extends SyncEvent {
  const SyncDataAppliedEvent(this.result);
  final SyncImportResult result;
}

class SyncTransferActivityEvent extends SyncEvent {
  const SyncTransferActivityEvent({required this.active, this.message});
  final bool active;
  final String? message;
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

SyncDeviceType syncDeviceTypeFromWire(String? value) {
  final normalized = value?.trim().toLowerCase() ?? '';
  return switch (normalized) {
    'desktop' => SyncDeviceType.desktop,
    'mobile' => SyncDeviceType.mobile,
    'web' => SyncDeviceType.web,
    _ => SyncDeviceType.unknown,
  };
}

String syncDeviceTypeToWire(SyncDeviceType value) {
  return switch (value) {
    SyncDeviceType.desktop => 'desktop',
    SyncDeviceType.mobile => 'mobile',
    SyncDeviceType.web => 'web',
    SyncDeviceType.unknown => 'unknown',
  };
}

class TrustedSyncPeer {
  const TrustedSyncPeer({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.deviceType = SyncDeviceType.unknown,
    this.fingerprint,
    this.lastSeenAtIso,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final SyncDeviceType deviceType;
  final String? fingerprint;
  final String? lastSeenAtIso;

  Map<String, dynamic> toJson() {
    final payload = <String, dynamic>{
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'fingerprint': fingerprint,
      'last_seen_at_iso': lastSeenAtIso,
    };
    if (deviceType != SyncDeviceType.unknown) {
      payload['device_type'] = syncDeviceTypeToWire(deviceType);
    }
    return payload;
  }

  factory TrustedSyncPeer.fromJson(Map<String, dynamic> json) {
    return TrustedSyncPeer(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'Unknown Device',
      host: (json['host'] as String?) ?? '',
      port: (json['port'] as num?)?.toInt() ?? 0,
      deviceType: syncDeviceTypeFromWire(
        json['device_type'] as String? ?? json['deviceType'] as String?,
      ),
      fingerprint: json['fingerprint'] as String?,
      lastSeenAtIso: json['last_seen_at_iso'] as String?,
    );
  }

  TrustedSyncPeer copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    SyncDeviceType? deviceType,
    String? fingerprint,
    String? lastSeenAtIso,
  }) {
    return TrustedSyncPeer(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      deviceType: deviceType ?? this.deviceType,
      fingerprint: fingerprint ?? this.fingerprint,
      lastSeenAtIso: lastSeenAtIso ?? this.lastSeenAtIso,
    );
  }
}

class DiscoveredSyncPeer {
  const DiscoveredSyncPeer({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.deviceType = SyncDeviceType.unknown,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final SyncDeviceType deviceType;

  TrustedSyncPeer toTrustedPeer() {
    return TrustedSyncPeer(
      id: id,
      name: name,
      host: host,
      port: port,
      deviceType: deviceType,
      lastSeenAtIso: DateTime.now().toIso8601String(),
    );
  }
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
  if (raw.trim().isEmpty) {
    return const [];
  }

  try {
    final parsed = jsonDecode(raw);
    if (parsed is! List) {
      return const [];
    }
    return parsed
        .whereType<Map>()
        .map((e) => TrustedSyncPeer.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id.isNotEmpty)
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

String encodeTrustedPeers(List<TrustedSyncPeer> peers) {
  final payload = peers.map((p) => p.toJson()).toList(growable: false);
  return jsonEncode(payload);
}
