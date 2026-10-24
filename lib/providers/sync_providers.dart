library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/database.dart';
import '../core/models/device_sync_models.dart';
import '../core/services/device_sync_service.dart';
import '../features/sync/data/sync_firewall.dart';
import '../features/sync/domain/peer_sync_queue.dart';
import '../features/sync/domain/sync_ports.dart';
import 'database_providers.dart';

/// Platform firewall checks and rules for the sync ports.
final syncFirewallProvider = Provider<SyncFirewall>((ref) => SyncFirewall());

/// Shown when two paired devices have different active database files open.
String syncDatabaseMismatchMessage(
  String peerName,
  String? remoteDbName,
  String? localDbName,
) =>
    'DB mismatch: $peerName is using "$remoteDbName" '
    'but this device uses "$localDbName". '
    'Both devices must use the same active database file.';

final deviceSyncServiceProvider = Provider<DeviceSyncService>((ref) {
  final service = DeviceSyncService(ref: ref);
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

/// The last sync with this peer in the currently open database.
final syncPeerLastSyncProvider = FutureProvider.autoDispose
    .family<DateTime?, String>((ref, peerId) async {
      final database = ref.watch(databaseProvider);
      final latest = ref.watch(
        deviceSyncProvider.select(
          (snapshot) =>
              (snapshot.value?.lastSyncAt, snapshot.value?.lastTrustedPeerId),
        ),
      );
      if (database == null) return latest.$2 == peerId ? latest.$1 : null;
      final checkpoint = await database.getPeerSyncCheckpoint(peerId);
      final timestamp = checkpoint?['lastSyncAt'] as int?;
      if (timestamp != null && timestamp > 0) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
      return null;
    });

class DeviceSyncNotifier extends AsyncNotifier<DeviceSyncSnapshot> {
  /// A slow safety-net check complements direct change and availability
  /// signals; discovery runs only while the Device Sync dialog is open.
  Timer? _backgroundTimer;
  Timer? _discoveryTimer;
  final Map<String, DateTime> _lastRediscovery = {};
  Timer? _queueTimer;
  final PeerSyncQueue _syncQueue = PeerSyncQueue();

  /// Subscription to the service's event stream for atomic UI state updates.
  StreamSubscription<SyncEvent>? _eventsSub;
  StreamSubscription<int>? _databaseChangesSub;
  AppDatabase? _watchedDatabase;
  bool _hasObservedDatabase = false;
  int? _lastDatabaseRevision;
  Completer<void>? _automaticCycleDone;

  bool _foreground = true;

  Future<void> setForeground(bool foreground) async {
    _foreground = foreground;
    final service = ref.read(deviceSyncServiceProvider);
    if (!foreground) {
      _backgroundTimer?.cancel();
      _backgroundTimer = null;
      _queueTimer?.cancel();
      _queueTimer = null;
      await service.setForeground(false);
    } else {
      await service.setForeground(true);
      if (!ref.mounted || !_foreground) return;
      await refreshSnapshot();
      if (ref.mounted && _foreground) await _runBackgroundCycle();
    }
  }

  bool _autoSyncInFlight = false;
  bool _manualSyncInFlight = false;
  bool _discoverInFlight = false;
  static const Duration _recoveryInterval = Duration(minutes: 5);
  static const Duration _discoveryInterval = Duration(seconds: 5);

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

  String? _linuxFirewallGuidance(LinuxFirewallCheckResult? result) {
    if (result == null) {
      return null;
    }
    if (!result.available || !result.active) {
      // No firewall tool detected or firewall is not active — nothing blocking.
      return null;
    }
    if (!result.fullyAllowed) {
      final missing = <String>[];
      if (!result.udpPortAllowed) {
        missing.add('UDP ${SyncPorts.discovery} (discovery)');
      }
      if (!result.tcpPortAllowed) {
        missing.add('TCP ${SyncPorts.transfer} (data transfer)');
      }
      return 'Firewall may be blocking Device Sync ports: ${missing.join(", ")}. '
          'Use Grant Firewall Access to allow these ports.';
    }
    return null;
  }

  @override
  Future<DeviceSyncSnapshot> build() async {
    ref.onDispose(() {
      _backgroundTimer?.cancel();
      _backgroundTimer = null;
      _queueTimer?.cancel();
      _queueTimer = null;
      _eventsSub?.cancel();
      _eventsSub = null;
      _databaseChangesSub?.cancel();
      _databaseChangesSub = null;
      _watchedDatabase = null;
    });

    final service = ref.read(deviceSyncServiceProvider);
    ref.listen(databaseProvider, (previous, next) => _watchDatabase(next));
    _watchDatabase(ref.read(databaseProvider));

    // Subscribe to service events so state updates are atomic and decoupled
    // from the transport layer.
    _eventsSub = service.syncEvents.listen((event) {
      final latest = state.value;
      if (latest == null) return;
      // Every event may follow a pairing change, so pending requests refresh.
      final current = latest.copyWith();

      if (event is SyncChangeAvailableEvent) {
        if (event.peerId == null) {
          _markAllPeersDirty();
        } else {
          _markPeerDirty(event.peerId!, resetBackoff: true);
        }
      } else if (event is PeerAvailableEvent) {
        final peer = event.peer;
        state = AsyncData(
          current.copyWith(
            discoveredPeers: [
              ...current.discoveredPeers.where((item) => item.id != peer.id),
              peer,
            ],
          ),
        );
        _markPeerDirty(peer.id, immediate: true, resetBackoff: true);
      } else if (event is PeerTrustedEvent) {
        final peer = event.peer;
        final updated = [
          ...current.trustedPeers.where((p) => p.id != peer.id),
          peer,
        ];
        state = AsyncData(
          current.copyWith(
            trustedPeers: updated,
            statusMessage: 'Paired with ${peer.name}.',
          ),
        );
        _ensureBackgroundTimer(state.value ?? current);
        _markPeerDirty(peer.id, immediate: true, resetBackoff: true);
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
            statusMessage: 'A device removed its pairing with this device.',
          ),
        );
        _ensureBackgroundTimer(state.value ?? current);
      } else if (event is PeerOfflineEvent) {
        final wasDiscovered = current.discoveredPeers.any(
          (peer) => peer.id == event.peerId,
        );
        if (!wasDiscovered) return;
        state = AsyncData(
          current.copyWith(
            discoveredPeers: current.discoveredPeers
                .where((peer) => peer.id != event.peerId)
                .toList(growable: false),
            status: current.status == DeviceSyncStatus.connected
                ? DeviceSyncStatus.idle
                : current.status,
            statusMessage: 'Device is offline.',
          ),
        );
      } else if (event is SyncDataAppliedEvent) {
        final result = event.result;
        final conflictNote = result.hasConflicts
            ? ' (${result.conflicts} competing edit${result.conflicts > 1 ? 's' : ''} detected)'
            : '';
        state = AsyncData(
          current.copyWith(
            status: DeviceSyncStatus.connected,
            statusMessage:
                'Sync data received. ${result.inserted} added, ${result.updated} updated, ${result.deleted} removed$conflictNote.',
          ),
        );
      } else if (event is SyncTransferActivityEvent) {
        state = AsyncData(
          current.copyWith(
            status: event.active
                ? DeviceSyncStatus.syncing
                : current.dbMismatchPeerIds.isEmpty
                ? DeviceSyncStatus.connected
                : DeviceSyncStatus.error,
            statusMessage: event.active
                ? (event.message ?? 'Sync in progress...')
                : 'Sync completed.',
          ),
        );
        if (!event.active) _scheduleQueuedSync();
      } else if (event is PairRequestReceivedEvent) {
        state = AsyncData(
          current.copyWith(
            status: DeviceSyncStatus.connecting,
            statusMessage:
                'Incoming pair request from ${event.request.peer.name}.',
          ),
        );
      } else if (event is PairRequestTimedOutEvent) {
        state = AsyncData(
          current.copyWith(
            status: DeviceSyncStatus.idle,
            statusMessage:
                'Pairing request from ${event.request.peer.name} timed out.',
          ),
        );
      } else if (event is PairRequestCanceledEvent) {
        state = AsyncData(
          current.copyWith(
            status: DeviceSyncStatus.idle,
            statusMessage:
                'Pairing request from ${event.request.peer.name} was canceled.',
          ),
        );
      } else if (event is PairRequestCodeRejectedEvent) {
        state = AsyncData(
          current.copyWith(
            status: DeviceSyncStatus.connecting,
            statusMessage:
                'Code was rejected by ${event.request.peer.name}. Try sending it again.',
          ),
        );
      } else if (event is DbMismatchDetectedEvent) {
        final nextMismatchIds = Set<String>.from(current.dbMismatchPeerIds)
          ..add(event.peerId);
        state = AsyncData(
          current.copyWith(
            status: DeviceSyncStatus.error,
            dbMismatchPeerIds: nextMismatchIds,
            statusMessage: syncDatabaseMismatchMessage(
              event.peerName,
              event.remoteDbName,
              event.localDbName,
            ),
          ),
        );
      }
    });

    final snapshot = await service.loadSnapshot();
    _ensureBackgroundTimer(snapshot);
    if (snapshot.enabled) {
      // AsyncNotifier publishes the returned snapshot before this turn runs.
      unawaited(Future<void>.delayed(Duration.zero, _runBackgroundCycle));
      unawaited(Future<void>.microtask(recheckFirewallAccess));
    }
    return snapshot;
  }

  Future<void> refreshSnapshot() async {
    final previous = state.value;
    final refreshed = await AsyncValue.guard(
      () => ref.read(deviceSyncServiceProvider).loadSnapshot(),
    );
    if (!ref.mounted) return;
    final loaded = refreshed.value;
    // Keep the latest live peer list, including offline events received while
    // the settings snapshot was loading. Discovery will refresh it next.
    final livePeers = state.value?.discoveredPeers ?? previous?.discoveredPeers;
    final latest = loaded?.copyWith(
      discoveredPeers: loaded.enabled ? (livePeers ?? const []) : const [],
    );
    if (latest != null) {
      state = AsyncData(latest);
      _ensureBackgroundTimer(latest);
    } else if (previous == null) {
      state = refreshed;
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
      if (value && ref.read(databaseProvider) != null) {
        unawaited(_runBackgroundCycle());
        unawaited(recheckFirewallAccess());
      }
    }
  }

  Future<void> recheckFirewallAccess() async {
    final current = state.value;
    if (current == null) return;

    String? guidance;

    if (defaultTargetPlatform == TargetPlatform.windows) {
      final result = await ref
          .read(syncFirewallProvider)
          .checkWindowsFirewallAccess();
      guidance = _windowsFirewallGuidance(result);
    } else if (defaultTargetPlatform == TargetPlatform.linux) {
      final result = await ref
          .read(syncFirewallProvider)
          .checkLinuxFirewallAccess();
      guidance = _linuxFirewallGuidance(result);
    }

    final latest = state.value ?? current;

    state = AsyncData(
      guidance == null
          ? latest.copyWith(clearFirewallStatusMessage: true)
          : latest.copyWith(firewallStatusMessage: guidance),
    );
  }

  Future<bool> openWindowsFirewallAllowedApps() =>
      ref.read(syncFirewallProvider).openWindowsFirewallAllowedApps();

  Future<bool> openWindowsFirewallAdvancedSettings() =>
      ref.read(syncFirewallProvider).openWindowsFirewallAdvancedSettings();

  Future<bool> grantLinuxFirewallAccess() => grantFirewallAccess();

  Future<bool> grantFirewallAccess() async {
    final firewall = ref.read(syncFirewallProvider);
    final granted = switch (defaultTargetPlatform) {
      TargetPlatform.windows => await firewall.grantWindowsFirewallAccess(),
      TargetPlatform.linux => await firewall.grantLinuxFirewallAccess(),
      _ => null,
    };
    if (granted == null) return false;
    await recheckFirewallAccess();
    return granted;
  }

  Future<bool> clearLinuxFirewallAccess() async {
    final cleared = await ref
        .read(syncFirewallProvider)
        .clearLinuxFirewallAccess();
    await recheckFirewallAccess();
    return cleared;
  }

  Future<void> setAutoOnStartup(bool value) async {
    await ref.read(deviceSyncServiceProvider).setAutoOnStartup(value);
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(autoOnStartup: value));
    }
  }

  void _watchDatabase(AppDatabase? database) {
    if (identical(database, _watchedDatabase)) return;
    _databaseChangesSub?.cancel();
    _watchedDatabase = database;
    _lastDatabaseRevision = null;
    if (database == null) {
      _databaseChangesSub = null;
      _queueTimer?.cancel();
      _queueTimer = null;
      return;
    }
    final isDatabaseSwitch = _hasObservedDatabase;
    _hasObservedDatabase = true;
    _databaseChangesSub = database.watchSyncRevision().listen(
      (revision) {
        if (!ref.mounted || !identical(database, _watchedDatabase)) return;
        final previous = _lastDatabaseRevision;
        _lastDatabaseRevision = revision;
        if (previous == null) {
          _markAllPeersDirty(immediate: true);
          if (isDatabaseSwitch && state.value?.enabled == true && _foreground) {
            unawaited(_announceDatabaseChange());
          }
          return;
        }
        if (revision == previous) return;
        // Records just received from a peer are not echoed back to it.
        final source = ref
            .read(deviceSyncServiceProvider)
            .peerThatProduced(revision);
        _markAllPeersDirty(except: source);
        final current = state.value;
        if (current?.enabled == true && _foreground) {
          unawaited(_announceDatabaseChange(skipPeerId: source));
        }
      },
      onError: (Object _, StackTrace _) {
        // Periodic anti-entropy still recovers if a database watch is interrupted.
      },
    );
  }

  Future<void> _announceDatabaseChange({String? skipPeerId}) async {
    try {
      await ref
          .read(deviceSyncServiceProvider)
          .notifyLocalDataChanged(skipPeerId: skipPeerId);
    } catch (_) {
      // Direct notifications are a latency optimization. The dirty queue and
      // periodic checks retain the work when a notification cannot be delivered.
    }
  }

  void _ensureBackgroundTimer(DeviceSyncSnapshot snapshot) {
    _syncQueue.replacePeers(snapshot.trustedPeers.map((peer) => peer.id));
    if (!snapshot.enabled || !_foreground) {
      _backgroundTimer?.cancel();
      _backgroundTimer = null;
      _queueTimer?.cancel();
      _queueTimer = null;
      if (!snapshot.enabled) _syncQueue.clear();
      return;
    }
    if (snapshot.trustedPeers.isEmpty) {
      _backgroundTimer?.cancel();
      _backgroundTimer = null;
    } else {
      _backgroundTimer ??= Timer.periodic(
        _recoveryInterval,
        (_) => _runSafetyNet(),
      );
    }
    _scheduleQueuedSync();
  }

  void _markAllPeersDirty({bool immediate = false, String? except}) {
    final current = state.value;
    if (current == null || !current.enabled) return;
    _replaceCompatiblePeers(current);
    _syncQueue.markAllDirty(
      DateTime.now(),
      immediate: immediate,
      except: except,
    );
    _scheduleQueuedSync();
  }

  void _markPeerDirty(
    String peerId, {
    bool immediate = false,
    bool resetBackoff = false,
  }) {
    final current = state.value;
    if (current == null || !current.enabled) return;
    _replaceCompatiblePeers(current);
    _syncQueue.markDirty(
      peerId,
      DateTime.now(),
      immediate: immediate,
      resetBackoff: resetBackoff,
    );
    _scheduleQueuedSync();
  }

  void _replaceCompatiblePeers(DeviceSyncSnapshot snapshot) {
    final incompatibleIds = snapshot.discoveredPeers
        .where((peer) => !peer.isSyncCompatible)
        .map((peer) => peer.id)
        .toSet();
    _syncQueue.replacePeers(
      snapshot.trustedPeers
          .where((peer) => !incompatibleIds.contains(peer.id))
          .map((peer) => peer.id),
    );
  }

  /// Startup, resume and enabling check every paired device once. Edits
  /// reach peers through direct change signals, not periodic scans.
  Future<void> _runBackgroundCycle() async {
    if (!_foreground || !ref.mounted || state.value?.enabled != true) return;
    if (ref.read(databaseProvider) == null) return;
    _markAllPeersDirty(immediate: true);
  }

  /// Repairs a lost change signal or a silent address change. Only one side
  /// of each pair checks (the lower device ID), so idle pairs stay quiet.
  void _runSafetyNet() {
    final current = state.value;
    if (current == null || !_foreground) return;
    for (final peer in current.trustedPeers) {
      if (current.deviceId.compareTo(peer.id) < 0) {
        _markPeerDirty(peer.id, immediate: true);
      }
    }
  }

  /// Scans for devices while the Device Sync dialog is open. Devices with
  /// sync enabled answer the scan, so the dialog can list and pair them.
  void startDiscovery() {
    if (_discoveryTimer != null) return;
    unawaited(discoverPeers());
    _discoveryTimer = Timer.periodic(
      _discoveryInterval,
      (_) => unawaited(discoverPeers()),
    );
  }

  void stopDiscovery() {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
  }

  void _scheduleQueuedSync({Duration? minimumDelay}) {
    _queueTimer?.cancel();
    _queueTimer = null;
    if (!ref.mounted ||
        !_foreground ||
        state.value?.enabled != true ||
        _autoSyncInFlight ||
        _manualSyncInFlight ||
        ref.read(databaseProvider) == null) {
      return;
    }
    final readyAt = _syncQueue.nextReadyAt;
    if (readyAt == null) return;
    var delay = readyAt.difference(DateTime.now());
    if (delay.isNegative) delay = Duration.zero;
    if (minimumDelay != null && delay < minimumDelay) delay = minimumDelay;
    _queueTimer = Timer(delay, () {
      _queueTimer = null;
      unawaited(_drainSyncQueue());
    });
  }

  Future<void> _drainSyncQueue() async {
    if (!ref.mounted ||
        !_foreground ||
        state.value?.enabled != true ||
        _autoSyncInFlight ||
        _manualSyncInFlight ||
        ref.read(databaseProvider) == null) {
      return;
    }
    final service = ref.read(deviceSyncServiceProvider);
    if (service.isReceiverSyncInFlight) {
      _scheduleQueuedSync(minimumDelay: const Duration(seconds: 1));
      return;
    }
    _autoSyncInFlight = true;
    final done = Completer<void>();
    _automaticCycleDone = done;
    try {
      while (ref.mounted &&
          _foreground &&
          state.value?.enabled == true &&
          !_manualSyncInFlight &&
          ref.read(databaseProvider) != null &&
          !service.isReceiverSyncInFlight) {
        final work = _syncQueue.takeNext(DateTime.now());
        if (work == null) break;
        var outcome = PeerSyncOutcome.failed;
        try {
          outcome = await _reconcilePeer(work.peerId);
        } catch (error) {
          if (ref.mounted) {
            final latest = state.value;
            if (latest != null) {
              state = AsyncData(
                latest.copyWith(
                  status: DeviceSyncStatus.error,
                  clearActiveSyncPeerId: true,
                  statusMessage: 'Device sync will retry: $error',
                ),
              );
            }
          }
        } finally {
          _syncQueue.complete(work, DateTime.now(), outcome);
        }
      }
    } finally {
      _autoSyncInFlight = false;
      done.complete();
      if (identical(done, _automaticCycleDone)) _automaticCycleDone = null;
      _scheduleQueuedSync(
        minimumDelay: service.isReceiverSyncInFlight
            ? const Duration(seconds: 1)
            : null,
      );
    }
  }

  Future<PeerSyncOutcome> _reconcilePeer(String peerId) async {
    final current = state.value;
    if (current == null ||
        current.discoveredPeers.any(
          (peer) => peer.id == peerId && !peer.isSyncCompatible,
        ) ||
        !current.trustedPeers.any((peer) => peer.id == peerId)) {
      return PeerSyncOutcome.settled;
    }
    final peer = current.trustedPeers.firstWhere((peer) => peer.id == peerId);
    final service = ref.read(deviceSyncServiceProvider);
    final result = await service.checkSyncCode(peerId: peerId);
    if (!ref.mounted) return PeerSyncOutcome.deferred;
    final latest = state.value ?? current;
    if (!latest.trustedPeers.any((peer) => peer.id == peerId)) {
      return PeerSyncOutcome.settled;
    }
    if (!result.reachable) {
      // An unreachable device may have a new address: look for it, but at
      // most once per safety-net interval so an offline device is not hunted.
      final last = _lastRediscovery[peerId];
      final now = DateTime.now();
      if (last == null || now.difference(last) >= _recoveryInterval) {
        _lastRediscovery[peerId] = now;
        if (await service.rediscoverPeer(peerId) && ref.mounted) {
          return _reconcilePeer(peerId);
        }
      }
      if (!ref.mounted) return PeerSyncOutcome.deferred;
      state = AsyncData(
        latest.copyWith(
          status: DeviceSyncStatus.idle,
          statusMessage:
              '${peer.name} is offline. Sync will resume when it reconnects.',
        ),
      );
      return PeerSyncOutcome.failed;
    }
    final mismatches = Set<String>.from(latest.dbMismatchPeerIds)
      ..removeWhere((id) => !latest.trustedPeers.any((peer) => peer.id == id));
    if (result.dbNameMismatch) {
      mismatches.add(peerId);
      state = AsyncData(
        latest.copyWith(
          status: DeviceSyncStatus.error,
          dbMismatchPeerIds: mismatches,
          statusMessage: syncDatabaseMismatchMessage(
            peer.name,
            result.remoteDbName,
            result.localDbName,
          ),
        ),
      );
      return PeerSyncOutcome.settled;
    }
    mismatches.remove(peerId);
    state = AsyncData(latest.copyWith(dbMismatchPeerIds: mismatches));
    if (service.isReceiverSyncInFlight || result.remoteReceiverSyncInFlight) {
      return PeerSyncOutcome.deferred;
    }
    if (result.matches) {
      state = AsyncData(
        (state.value ?? latest).copyWith(
          status: mismatches.isEmpty
              ? DeviceSyncStatus.connected
              : DeviceSyncStatus.error,
          statusMessage: mismatches.isEmpty
              ? 'Databases match ${peer.name}.'
              : 'Database mismatch detected on ${mismatches.length} paired device(s).',
        ),
      );
      return PeerSyncOutcome.settled;
    }
    if (!shouldInitiatePeerSync(
      localDeviceId: latest.deviceId,
      peerDeviceId: result.peer?.id ?? peerId,
      localHasChanges: result.localHasChanges,
      remoteHasChanges: result.remoteHasChanges,
    )) {
      return PeerSyncOutcome.deferred;
    }
    if (!_foreground || !latest.enabled || ref.read(databaseProvider) == null) {
      return PeerSyncOutcome.deferred;
    }
    state = AsyncData(
      (state.value ?? latest).copyWith(
        status: DeviceSyncStatus.syncing,
        activeSyncPeerId: peerId,
        statusMessage: 'Syncing with ${peer.name}...',
      ),
    );
    await service.performAutomaticSync(peerId: peerId, preflight: result);
    if (!ref.mounted) return PeerSyncOutcome.settled;
    final refreshed = await service.loadSnapshot();
    if (!ref.mounted) return PeerSyncOutcome.settled;
    final afterTransfer = state.value ?? latest;
    state = AsyncData(
      refreshed.copyWith(
        status: afterTransfer.dbMismatchPeerIds.isEmpty
            ? DeviceSyncStatus.connected
            : DeviceSyncStatus.error,
        clearActiveSyncPeerId: true,
        discoveredPeers: afterTransfer.discoveredPeers,
        dbMismatchPeerIds: afterTransfer.dbMismatchPeerIds,
        pendingPairRequests: service.getPendingPairRequests(),
        statusMessage: 'Synced with ${peer.name}.',
      ),
    );
    _ensureBackgroundTimer(state.value!);
    return PeerSyncOutcome.settled;
  }

  Future<void> discoverPeers() async {
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null || !current.enabled || _discoverInFlight) return;
    _discoverInFlight = true;

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
    } finally {
      _discoverInFlight = false;
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
      _markPeerDirty(trusted.id, immediate: true, resetBackoff: true);
    } on PairingEndedException catch (ended) {
      state = AsyncData(
        current.copyWith(
          status: DeviceSyncStatus.idle,
          pendingPairRequests: ref
              .read(deviceSyncServiceProvider)
              .getPendingPairRequests(),
          statusMessage: ended.status,
        ),
      );
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
    if (state.value == null || _manualSyncInFlight) return;
    // Reserve the transport before waiting, so automatic work finishes its
    // current peer and yields. A user's requested sync is never silently lost.
    _manualSyncInFlight = true;
    _queueTimer?.cancel();
    _queueTimer = null;
    await _automaticCycleDone?.future;
    if (!ref.mounted) {
      _manualSyncInFlight = false;
      return;
    }
    final current = state.value!;

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
      // A completed session proves both devices now use the same database:
      // a pull aborts on a mismatch and a push switches the receiver.
      final nextMismatch = Set<String>.from(
        (state.value ?? current).dbMismatchPeerIds,
      )..remove(activePeerId);

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
      _manualSyncInFlight = false;
      _scheduleQueuedSync();
    }
  }
}

final deviceSyncProvider =
    AsyncNotifierProvider<DeviceSyncNotifier, DeviceSyncSnapshot>(
      DeviceSyncNotifier.new,
    );
