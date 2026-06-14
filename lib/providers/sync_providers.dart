library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/device_sync_models.dart';
import '../core/services/device_sync_service.dart';

final deviceSyncServiceProvider = Provider<DeviceSyncService>((ref) {
  return DeviceSyncService(ref: ref);
});

class DeviceSyncNotifier extends AsyncNotifier<DeviceSyncSnapshot> {
  /// Single periodic timer that drives both peer discovery and sync-code polling.
  Timer? _backgroundTimer;

  /// Subscription to the service's event stream for atomic UI state updates.
  StreamSubscription<SyncEvent>? _eventsSub;

  bool _autoSyncInFlight = false;
  bool _discoverInFlight = false;
  static const Duration _autoSyncDebounce = Duration(seconds: 12);
  DateTime? _lastAutoSyncAttemptAt;

  String? _windowsFirewallGuidance(WindowsFirewallCheckResult? result) {
    if (result == null) {
      return null;
    }
    if (!result.available) {
      return 'UniKM could not inspect Windows Firewall automatically. '
          'Use Grant Firewall Access, or allow this executable on both Private and Public networks.';
    }
    if (result.hasPrivateAllow && !result.hasPublicAllow) {
      return 'Windows Firewall currently allows UniKM on Private networks only. '
          'Enable Public too for Device Sync to work reliably.';
    }
    if (!result.hasPrivateAllow && result.hasPublicAllow) {
      return 'Windows Firewall currently allows UniKM on Public networks only. '
          'Enable Private too for Device Sync.';
    }
    if (!result.hasPrivateAllow && !result.hasPublicAllow) {
      return 'Windows Firewall has no inbound allow rule for this UniKM executable yet. '
          'Use Grant Firewall Access, then recheck.';
    }
    return null;
  }

  @override
  Future<DeviceSyncSnapshot> build() async {
    ref.onDispose(() {
      _backgroundTimer?.cancel();
      _backgroundTimer = null;
      _eventsSub?.cancel();
      _eventsSub = null;
    });

    final service = ref.read(deviceSyncServiceProvider);

    // Subscribe to service events so state updates are atomic and decoupled
    // from the transport layer.
    _eventsSub = service.syncEvents.listen((event) {
      final current = state.value;
      if (current == null) return;

      if (event is PeerTrustedEvent) {
        final peer = event.peer;
        final updated = [
          ...current.trustedPeers.where((p) => p.id != peer.id),
          peer,
        ];
        state = AsyncData(
          current.copyWith(
            trustedPeers: updated,
            pendingPairRequests: service.getPendingPairRequests(),
            statusMessage: 'Paired with ${peer.name}.',
          ),
        );
        _ensureBackgroundTimer(state.value ?? current);
      } else if (event is PeerRemovedEvent) {
        final updated = current.trustedPeers
            .where((p) => p.id != event.peerId)
            .toList();
        final removedActivePeer = current.lastTrustedPeerId == event.peerId;
        final hasNoTrustedPeers = updated.isEmpty;
        final nextMismatchIds = Set<String>.from(current.dbMismatchPeerIds)
          ..remove(event.peerId);
        state = AsyncData(
          current.copyWith(
            trustedPeers: updated,
            status: (removedActivePeer || hasNoTrustedPeers)
                ? DeviceSyncStatus.idle
                : current.status,
            clearLastTrustedPeerId: removedActivePeer || hasNoTrustedPeers,
            dbMismatchPeerIds: nextMismatchIds,
            pendingPairRequests: service.getPendingPairRequests(),
            statusMessage: 'A device removed its pairing with this device.',
          ),
        );
        _ensureBackgroundTimer(state.value ?? current);
      } else if (event is SyncDataAppliedEvent) {
        final result = event.result;
        final conflictNote = result.hasConflicts
            ? ' (${result.conflicts} conflict${result.conflicts > 1 ? 's' : ''} kept local)'
            : '';
        state = AsyncData(
          current.copyWith(
            status: DeviceSyncStatus.connected,
            pendingPairRequests: service.getPendingPairRequests(),
            statusMessage:
                'Sync data received. ${result.inserted} added, ${result.updated} updated$conflictNote.',
          ),
        );
      } else if (event is SyncTransferActivityEvent) {
        state = AsyncData(
          current.copyWith(
            status: event.active
                ? DeviceSyncStatus.syncing
                : DeviceSyncStatus.connected,
            statusMessage: event.active
                ? (event.message ?? 'Sync in progress...')
                : 'Sync completed.',
          ),
        );
      } else if (event is PairRequestReceivedEvent) {
        state = AsyncData(
          current.copyWith(
            pendingPairRequests: service.getPendingPairRequests(),
            status: DeviceSyncStatus.connecting,
            statusMessage:
                'Incoming pair request from ${event.request.peer.name}.',
          ),
        );
      } else if (event is PairRequestTimedOutEvent) {
        state = AsyncData(
          current.copyWith(
            pendingPairRequests: service.getPendingPairRequests(),
            status: DeviceSyncStatus.idle,
            statusMessage:
                'Pairing request from ${event.request.peer.name} timed out.',
          ),
        );
      } else if (event is PairRequestCanceledEvent) {
        state = AsyncData(
          current.copyWith(
            pendingPairRequests: service.getPendingPairRequests(),
            status: DeviceSyncStatus.idle,
            statusMessage:
                'Pairing request from ${event.request.peer.name} was canceled.',
          ),
        );
      } else if (event is PairRequestCodeRejectedEvent) {
        final pending = service.getPendingPairRequests();
        state = AsyncValue.data(
          current.copyWith(
            status: DeviceSyncStatus.connecting,
            pendingPairRequests: pending,
            statusMessage:
                'Code was rejected by ${event.request.peer.name}. Try sending it again.',
          ),
        );
      }
    });

    final snapshot = await service.loadSnapshot();
    _ensureBackgroundTimer(snapshot);
    if (snapshot.enabled) {
      unawaited(_runBackgroundCycle());
      unawaited(Future<void>.microtask(recheckWindowsFirewallAccess));
    }
    return snapshot;
  }

  Future<void> refreshSnapshot() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(deviceSyncServiceProvider).loadSnapshot(),
    );
    final latest = state.value;
    if (latest != null) {
      _ensureBackgroundTimer(latest);
    }
  }

  Future<void> setEnabled(bool value) async {
    await ref.read(deviceSyncServiceProvider).setEnabled(value);
    final current = state.value;
    if (current != null) {
      final next = value
          ? current.copyWith(enabled: true)
          : current.copyWith(
              enabled: false,
              status: DeviceSyncStatus.idle,
              discoveredPeers: const [],
              clearStatusMessage: true,
              clearFirewallStatusMessage: true,
            );
      state = AsyncData(next);
      _ensureBackgroundTimer(next);
      if (value) {
        unawaited(_runBackgroundCycle());
        unawaited(recheckWindowsFirewallAccess());
      }
    }
  }

  Future<void> recheckWindowsFirewallAccess() async {
    final current = state.value;
    if (current == null) return;

    final result = await ref
        .read(deviceSyncServiceProvider)
        .checkWindowsFirewallAccess();
    final guidance = _windowsFirewallGuidance(result);
    final latest = state.value ?? current;

    state = AsyncData(
      guidance == null
          ? latest.copyWith(clearFirewallStatusMessage: true)
          : latest.copyWith(firewallStatusMessage: guidance),
    );
  }

  Future<bool> openWindowsFirewallAllowedApps() {
    return ref.read(deviceSyncServiceProvider).openWindowsFirewallAllowedApps();
  }

  Future<bool> openWindowsFirewallAdvancedSettings() {
    return ref
        .read(deviceSyncServiceProvider)
        .openWindowsFirewallAdvancedSettings();
  }

  Future<bool> grantWindowsFirewallAccess() async {
    final granted = await ref
        .read(deviceSyncServiceProvider)
        .grantWindowsFirewallAccess();
    await recheckWindowsFirewallAccess();
    return granted;
  }

  Future<void> setAutoOnStartup(bool value) async {
    await ref.read(deviceSyncServiceProvider).setAutoOnStartup(value);
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(autoOnStartup: value));
    }
  }

  void _ensureBackgroundTimer(DeviceSyncSnapshot snapshot) {
    if (!snapshot.enabled) {
      _backgroundTimer?.cancel();
      _backgroundTimer = null;
      return;
    }
    if (_backgroundTimer != null) return;
    _backgroundTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_runBackgroundCycle());
    });
  }

  /// Single coordinator cycle: runs peer discovery followed by sync-code
  /// polling. Both tasks are fire-and-forget so they do not block each other.
  Future<void> _runBackgroundCycle() async {
    unawaited(_backgroundDiscover());
    final current = state.value;
    if (current != null && current.trustedPeers.isNotEmpty) {
      unawaited(_pollSyncCode());
    }
  }

  Future<void> _backgroundDiscover() async {
    final current = state.value;
    if (current == null || !current.enabled) return;

    if (_discoverInFlight) return;
    _discoverInFlight = true;

    try {
      final peers = await ref.read(deviceSyncServiceProvider).discoverPeers();
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          discoveredPeers: peers,
          pendingPairRequests: ref
              .read(deviceSyncServiceProvider)
              .getPendingPairRequests(),
        ),
      );
    } catch (_) {
      // Keep the previous discovery snapshot on transient network errors.
    } finally {
      _discoverInFlight = false;
    }
  }

  Future<void> _pollSyncCode() async {
    final current = state.value;
    if (current == null ||
        !current.enabled ||
        current.trustedPeers.isEmpty ||
        _autoSyncInFlight ||
        // If this device is currently acting as a receiver, suppress any
        // competing initiator sync.  Without this guard the background timer
        // could detect a revision mismatch mid-receive, launch a concurrent
        // initiator sync, and have its re-anchor overwrite the revision ID
        // the receiver path is about to adopt — causing an infinite loop.
        ref.read(deviceSyncServiceProvider).isReceiverSyncInFlight) {
      return;
    }

    final service = ref.read(deviceSyncServiceProvider);
    final latest = state.value ?? current;
    final pending = service.getPendingPairRequests();

    final syncTargets = <TrustedSyncPeer>[];
    var unreachableCount = 0;
    var remoteInitiatorCount = 0;
    final nextMismatch = Set<String>.from(
      latest.dbMismatchPeerIds,
    )..removeWhere((id) => current.trustedPeers.every((peer) => peer.id != id));

    for (final trustedPeer in current.trustedPeers) {
      final result = await service.checkSyncCode(peerId: trustedPeer.id);

      if (!result.reachable) {
        unreachableCount++;
        continue;
      }

      if (result.dbNameMismatch) {
        nextMismatch.add(trustedPeer.id);
        continue;
      }

      // A reachable peer without mismatch should immediately clear any stale
      // mismatch badge from prior checks.
      nextMismatch.remove(trustedPeer.id);

      // If the peer is currently receiving/applying sync data, let it finish
      // before making any initiator decision.
      if (result.remoteReceiverSyncInFlight) {
        remoteInitiatorCount++;
        continue;
      }

      if (result.matches) {
        continue;
      }

      final bool shouldBackOff;
      if (!result.localHasChanges && result.remoteHasChanges) {
        shouldBackOff = true;
      } else if (result.localHasChanges && !result.remoteHasChanges) {
        shouldBackOff = false;
      } else {
        final remoteId = result.peer?.id ?? trustedPeer.id;
        shouldBackOff =
            remoteId.isNotEmpty && current.deviceId.compareTo(remoteId) > 0;
      }

      if (shouldBackOff) {
        remoteInitiatorCount++;
        continue;
      }

      syncTargets.add(trustedPeer);
    }

    final mismatchCount = nextMismatch.length;

    if (mismatchCount > 0) {
      state = AsyncData(
        (state.value ?? latest).copyWith(
          status: DeviceSyncStatus.error,
          pendingPairRequests: pending,
          statusMessage:
              'Database mismatch detected on $mismatchCount paired device(s). '
              'Auto-sync skipped for those devices.',
          dbMismatchPeerIds: nextMismatch,
        ),
      );
      if (syncTargets.isEmpty) {
        return;
      }
    }

    if (syncTargets.isEmpty) {
      final discoveredPeerIds = (state.value ?? latest).discoveredPeers
          .map((peer) => peer.id)
          .toSet();
      final unreachableDiscovered = current.trustedPeers
          .where((peer) => discoveredPeerIds.contains(peer.id))
          .length;

      if (unreachableCount > 0 && unreachableDiscovered == 0) {
        state = AsyncData(
          (state.value ?? latest).copyWith(
            status: DeviceSyncStatus.error,
            pendingPairRequests: pending,
            statusMessage:
                'Trusted device is offline. Sync will resume when it is reachable.',
            dbMismatchPeerIds: nextMismatch,
          ),
        );
        return;
      }

      if (remoteInitiatorCount > 0) {
        state = AsyncData(
          (state.value ?? latest).copyWith(
            status: DeviceSyncStatus.syncing,
            pendingPairRequests: pending,
            statusMessage:
                'Changes detected. Waiting for $remoteInitiatorCount paired device(s) to initiate sync...',
            dbMismatchPeerIds: nextMismatch,
          ),
        );
        return;
      }

      state = AsyncData(
        (state.value ?? latest).copyWith(
          status: DeviceSyncStatus.connected,
          pendingPairRequests: pending,
          statusMessage: 'Paired devices are in sync.',
          dbMismatchPeerIds: nextMismatch,
        ),
      );
      return;
    }

    final now = DateTime.now();
    final lastAttempt = _lastAutoSyncAttemptAt;
    if (lastAttempt != null &&
        now.difference(lastAttempt) < _autoSyncDebounce) {
      state = AsyncData(
        (state.value ?? latest).copyWith(
          status: DeviceSyncStatus.syncing,
          pendingPairRequests: pending,
          statusMessage:
              'Changes detected on ${syncTargets.length} device(s). Waiting before next auto-sync...',
          dbMismatchPeerIds: nextMismatch,
        ),
      );
      return;
    }

    state = AsyncData(
      (state.value ?? latest).copyWith(
        status: DeviceSyncStatus.syncing,
        pendingPairRequests: pending,
        statusMessage:
            'Changes detected. Auto-syncing ${syncTargets.length} paired device(s)...',
        dbMismatchPeerIds: nextMismatch,
      ),
    );

    _autoSyncInFlight = true;
    _lastAutoSyncAttemptAt = now;
    try {
      final failures = <String>[];
      for (final peer in syncTargets) {
        // Show which specific device is currently syncing.
        final syncing = state.value ?? latest;
        state = AsyncData(syncing.copyWith(activeSyncPeerId: peer.id));
        try {
          await service.performManualSync(peerId: peer.id);
        } catch (error) {
          failures.add('${peer.name}: $error');
        }
      }

      final refreshed = await service.loadSnapshot();
      // Preserve the current discoveredPeers — loadSnapshot() always returns
      // an empty list because discovery state lives only in memory.
      final liveDiscovered = state.value?.discoveredPeers ?? const [];
      if (failures.isNotEmpty) {
        state = AsyncData(
          refreshed.copyWith(
            status: DeviceSyncStatus.error,
            discoveredPeers: liveDiscovered,
            pendingPairRequests: service.getPendingPairRequests(),
            statusMessage:
                'Auto-sync completed with ${failures.length} failure(s): ${failures.join(' | ')}',
          ),
        );
        return;
      }

      state = AsyncData(
        refreshed.copyWith(
          status: DeviceSyncStatus.connected,
          clearActiveSyncPeerId: true,
          discoveredPeers: liveDiscovered,
          pendingPairRequests: service.getPendingPairRequests(),
          statusMessage: 'Auto-sync completed successfully.',
        ),
      );
    } catch (error) {
      final latestOnError = state.value ?? latest;
      state = AsyncData(
        latestOnError.copyWith(
          status: DeviceSyncStatus.error,
          clearActiveSyncPeerId: true,
          statusMessage: 'Auto-sync failed: $error',
        ),
      );
    } finally {
      _autoSyncInFlight = false;
    }
  }

  Future<void> discoverPeers() async {
    final current = state.value;
    if (current == null) return;

    state = AsyncData(
      current.copyWith(
        status: DeviceSyncStatus.discovering,
        statusMessage: 'Scanning local network...',
      ),
    );

    try {
      final peers = await ref.read(deviceSyncServiceProvider).discoverPeers();
      final latest = state.value ?? current;

      state = AsyncData(
        latest.copyWith(
          status: DeviceSyncStatus.idle,
          discoveredPeers: peers,
          pendingPairRequests: ref
              .read(deviceSyncServiceProvider)
              .getPendingPairRequests(),
          statusMessage: peers.isEmpty
              ? 'No devices found.'
              : 'Found ${peers.length} available device(s).',
        ),
      );
    } catch (error) {
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          status: DeviceSyncStatus.error,
          statusMessage: 'Device discovery failed: $error',
        ),
      );
    }
  }

  Future<void> requestPairing(
    DiscoveredSyncPeer peer, {
    void Function(String verificationCode)? showVerificationCode,
    Future<void>? onUserCancel,
  }) async {
    final current = state.value;
    if (current == null) return;
    try {
      final trusted = await ref
          .read(deviceSyncServiceProvider)
          .requestPairing(
            peer,
            showVerificationCode: showVerificationCode,
            onUserCancel: onUserCancel,
          );

      final nextTrusted = [
        ...current.trustedPeers.where((p) => p.id != trusted.id),
        trusted,
      ];

      state = AsyncData(
        current.copyWith(
          trustedPeers: nextTrusted,
          pendingPairRequests: ref
              .read(deviceSyncServiceProvider)
              .getPendingPairRequests(),
          statusMessage: 'Paired with ${trusted.name}.',
        ),
      );
      _ensureBackgroundTimer(state.value ?? current);
    } on DeviceSyncException catch (error) {
      final text = error.toString().toLowerCase();
      if (text.contains('timed out')) {
        state = AsyncData(
          current.copyWith(
            status: DeviceSyncStatus.idle,
            pendingPairRequests: ref
                .read(deviceSyncServiceProvider)
                .getPendingPairRequests(),
            statusMessage: 'Pairing request timed out.',
          ),
        );
        return;
      }
      if (text.contains('declined')) {
        state = AsyncData(
          current.copyWith(
            status: DeviceSyncStatus.idle,
            pendingPairRequests: ref
                .read(deviceSyncServiceProvider)
                .getPendingPairRequests(),
            statusMessage: 'Pairing request was declined.',
          ),
        );
        return;
      }
      if (text.contains('canceled') || text.contains('cancel')) {
        state = AsyncData(
          current.copyWith(
            status: DeviceSyncStatus.idle,
            pendingPairRequests: ref
                .read(deviceSyncServiceProvider)
                .getPendingPairRequests(),
            statusMessage: 'Pairing canceled.',
          ),
        );
        return;
      }
      rethrow;
    }
  }

  Future<void> respondToPairRequest({
    required String requestId,
    required bool accept,
    String? enteredVerificationCode,
  }) async {
    await ref
        .read(deviceSyncServiceProvider)
        .respondToPairRequest(
          requestId: requestId,
          accept: accept,
          enteredVerificationCode: enteredVerificationCode,
        );
    final current = state.value;
    if (current == null) {
      return;
    }

    final latestSnapshot = await ref
        .read(deviceSyncServiceProvider)
        .loadSnapshot();
    state = AsyncData(
      latestSnapshot.copyWith(
        status: accept ? DeviceSyncStatus.connecting : DeviceSyncStatus.idle,
        statusMessage: accept
            ? 'Pair confirmation sent. Waiting for handshake completion...'
            : 'Pair request declined.',
        discoveredPeers: current.discoveredPeers,
      ),
    );
    _ensureBackgroundTimer(state.value ?? current);
  }

  Future<void> removeTrustedPeer(String peerId) async {
    await ref.read(deviceSyncServiceProvider).removeTrustedPeer(peerId);
    final current = state.value;
    if (current == null) return;

    final nextTrusted = current.trustedPeers
        .where((p) => p.id != peerId)
        .toList(growable: false);
    final removedActivePeer = current.lastTrustedPeerId == peerId;
    final nextMismatchIds = current.dbMismatchPeerIds
        .where((id) => id != peerId)
        .toSet();

    state = AsyncData(
      current.copyWith(
        trustedPeers: nextTrusted,
        status: DeviceSyncStatus.idle,
        clearLastTrustedPeerId: removedActivePeer || nextTrusted.isEmpty,
        dbMismatchPeerIds: nextMismatchIds,
        pendingPairRequests: ref
            .read(deviceSyncServiceProvider)
            .getPendingPairRequests(),
        statusMessage: 'Device removed.',
      ),
    );
    _ensureBackgroundTimer(state.value ?? current);
  }

  Future<void> manualSync({
    String? peerId,
    bool isPull = false,
    bool fullScan = false,
  }) async {
    final current = state.value;
    if (current == null) return;

    if (_autoSyncInFlight) {
      return;
    }
    _autoSyncInFlight = true;

    state = AsyncData(
      current.copyWith(
        status: DeviceSyncStatus.syncing,
        activeSyncPeerId: peerId,
        statusMessage: fullScan
            ? (isPull
                  ? 'Creating backup and scanning remote database...'
                  : 'Creating backup and scanning databases for missing data...')
            : (isPull
                  ? 'Creating backup and pulling from remote...'
                  : 'Creating backup and syncing...'),
      ),
    );

    try {
      await ref
          .read(deviceSyncServiceProvider)
          .performManualSync(
            peerId: peerId,
            isPull: isPull,
            fullScan: fullScan,
          );

      final latest = await ref.read(deviceSyncServiceProvider).loadSnapshot();
      final liveDiscovered = state.value?.discoveredPeers ?? const [];
      final activePeerId =
          peerId ?? latest.lastTrustedPeerId ?? current.lastTrustedPeerId;
      final nextMismatch = Set<String>.from(
        (state.value ?? current).dbMismatchPeerIds,
      );

      if (activePeerId != null && activePeerId.isNotEmpty) {
        final postSync = await ref
            .read(deviceSyncServiceProvider)
            .checkSyncCode(peerId: activePeerId);
        if (postSync.reachable && postSync.dbNameMismatch) {
          nextMismatch.add(activePeerId);
        } else if (postSync.reachable) {
          nextMismatch.remove(activePeerId);
        }
      }

      state = AsyncData(
        latest.copyWith(
          status: DeviceSyncStatus.connected,
          clearActiveSyncPeerId: true,
          discoveredPeers: liveDiscovered,
          dbMismatchPeerIds: nextMismatch,
          pendingPairRequests: ref
              .read(deviceSyncServiceProvider)
              .getPendingPairRequests(),
          statusMessage: fullScan
              ? 'Scan sync completed successfully.'
              : 'Sync completed successfully.',
        ),
      );
    } catch (error) {
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          status: DeviceSyncStatus.error,
          clearActiveSyncPeerId: true,
          statusMessage: error.toString(),
        ),
      );
      rethrow;
    } finally {
      _autoSyncInFlight = false;
    }
  }
}

final deviceSyncProvider =
    AsyncNotifierProvider<DeviceSyncNotifier, DeviceSyncSnapshot>(
      DeviceSyncNotifier.new,
    );
