/// A change remains dirty until an attempt covering that generation completes.
/// New edits during a transfer therefore cannot be cleared by its completion.
class PeerSyncWork {
  const PeerSyncWork({required this.peerId, required this.generation});

  final String peerId;
  final int generation;
}

enum PeerSyncOutcome { settled, deferred, failed }

class _PendingPeerSync {
  _PendingPeerSync({
    required this.generation,
    required this.readyAt,
    required this.order,
  });

  int generation;
  DateTime readyAt;
  int order;
  int failures = 0;
}

/// Single-flight, fair work queue with per-device failure backoff.
///
/// Clock and timer ownership belongs to the caller, so this state machine is
/// deterministic and can be tested without real sockets or wall-clock delays.
class PeerSyncQueue {
  PeerSyncQueue({
    this.coalesceWindow = const Duration(milliseconds: 100),
    this.retryDelay = const Duration(seconds: 1),
    this.maximumRetryDelay = const Duration(seconds: 30),
    this.deferDelay = const Duration(seconds: 1),
  });

  final Duration coalesceWindow;
  final Duration retryDelay;
  final Duration maximumRetryDelay;
  final Duration deferDelay;
  final Set<String> _peers = {};
  final Map<String, _PendingPeerSync> _pending = {};
  int _generation = 0;
  int _order = 0;
  PeerSyncWork? _active;

  bool get hasPendingWork => _pending.isNotEmpty;
  bool get isActive => _active != null;

  void replacePeers(Iterable<String> peerIds) {
    _peers
      ..clear()
      ..addAll(peerIds.where((id) => id.isNotEmpty));
    _pending.removeWhere((id, _) => !_peers.contains(id));
  }

  void clear() => _pending.clear();

  void markAllDirty(DateTime now, {bool immediate = false}) {
    for (final peerId in _peers) {
      markDirty(peerId, now, immediate: immediate);
    }
  }

  void markDirty(
    String peerId,
    DateTime now, {
    bool immediate = false,
    bool resetBackoff = false,
  }) {
    if (!_peers.contains(peerId)) return;
    final readyAt = immediate ? now : now.add(coalesceWindow);
    final existing = _pending[peerId];
    if (existing == null) {
      _pending[peerId] = _PendingPeerSync(
        generation: ++_generation,
        readyAt: readyAt,
        order: ++_order,
      );
      return;
    }
    existing.generation = ++_generation;
    // Ordinary edits must not repeatedly wake an unreachable device. A fresh
    // availability/change signal from that device explicitly resets backoff.
    if (resetBackoff) {
      existing.failures = 0;
      existing.readyAt = readyAt;
    } else if (existing.failures == 0 && readyAt.isBefore(existing.readyAt)) {
      existing.readyAt = readyAt;
    }
  }

  DateTime? get nextReadyAt {
    if (_active != null) return null;
    DateTime? earliest;
    for (final work in _pending.values) {
      if (earliest == null || work.readyAt.isBefore(earliest)) {
        earliest = work.readyAt;
      }
    }
    return earliest;
  }

  PeerSyncWork? takeNext(DateTime now) {
    if (_active != null) return null;
    MapEntry<String, _PendingPeerSync>? next;
    for (final entry in _pending.entries) {
      if (entry.value.readyAt.isAfter(now)) continue;
      if (next == null || entry.value.order < next.value.order) next = entry;
    }
    if (next == null) return null;
    next.value.order = ++_order;
    return _active = PeerSyncWork(
      peerId: next.key,
      generation: next.value.generation,
    );
  }

  void complete(PeerSyncWork work, DateTime now, PeerSyncOutcome outcome) {
    if (!identical(work, _active)) return;
    _active = null;
    final pending = _pending[work.peerId];
    if (pending == null) return;
    switch (outcome) {
      case PeerSyncOutcome.settled:
        pending.failures = 0;
        if (pending.generation == work.generation) {
          _pending.remove(work.peerId);
        }
      case PeerSyncOutcome.deferred:
        pending.readyAt = now.add(deferDelay);
      case PeerSyncOutcome.failed:
        pending.failures++;
        var delayMillis = retryDelay.inMilliseconds;
        // Bound multiplication as well as the resulting delay.
        for (var i = 1; i < pending.failures; i++) {
          if (delayMillis >= maximumRetryDelay.inMilliseconds) break;
          delayMillis *= 2;
        }
        pending.readyAt = now.add(
          Duration(
            milliseconds: delayMillis.clamp(
              0,
              maximumRetryDelay.inMilliseconds,
            ),
          ),
        );
    }
  }
}

/// Concurrent writers use a stable election, so each pair exchanges once.
/// A peer with only remote changes may still pull the bidirectional exchange.
bool shouldInitiatePeerSync({
  required String localDeviceId,
  required String peerDeviceId,
  required bool localHasChanges,
  required bool remoteHasChanges,
}) {
  return !localHasChanges ||
      !remoteHasChanges ||
      localDeviceId.compareTo(peerDeviceId) <= 0;
}
