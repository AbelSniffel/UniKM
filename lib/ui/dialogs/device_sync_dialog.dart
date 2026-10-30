library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/device_sync_models.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../providers/app_providers.dart';
import '../widgets/app_progress_indicator.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/tinted_tiles.dart';
import '../widgets/notification_system.dart';
import '../widgets/pair_code_widgets.dart';
import '../widgets/toggle_switch.dart';

Future<void> showDeviceSyncDialog(BuildContext context) => showAppDialog<void>(
  context: context,
  builder: (_) => const _DeviceSyncDialog(),
);

/// Shows the sync direction choice dialog for a trusted peer.
///
/// Returns `true` when the user chooses "Send",
/// `false` for "Receive", or `null` if dismissed.
Future<bool?> showChooseSyncDirectionDialog({
  required BuildContext context,
  required AppThemeData theme,
  required bool hasMismatch,
  required String peerName,
  required String peerId,
}) {
  return showAppDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => ThemedAlertDialog(
      theme: theme,
      maxWidth: kCompactDialogWidth,
      title: DialogHeader(
        icon: Icons.sync,
        title: 'Sync Library',
        theme: theme,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          TintedHeading(theme: theme, title: 'Sync with $peerName'),
          Consumer(
            builder: (context, ref, _) {
              final lastSync = ref.watch(syncPeerLastSyncProvider(peerId));
              return Text(
                'Last sync: ${lastSync.when(data: _formatLastSync, loading: () => 'Checking…', error: (_, _) => 'Unavailable')}',
                style: TextStyle(color: theme.textSecondary, fontSize: 12),
              );
            },
          ),
          if (hasMismatch)
            DialogBanner.warning(
              theme: theme,
              message:
                  'Different database files. Receiving will switch this device to $peerName\'s database filename before merging changes.',
            ),
          // Each direction merges its changes into the other library.
          TintedOptionTile(
            theme: theme,
            icon: Icons.download,
            title: 'Receive',
            subtitle: 'Merge $peerName\'s changes into this library',
            onTap: () => Navigator.pop(ctx, false),
          ),
          TintedOptionTile(
            theme: theme,
            icon: Icons.upload,
            title: 'Send',
            subtitle: 'Merge this library\'s changes into $peerName',
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    ),
  );
}

String _formatLastSync(DateTime? value) =>
    value == null ? 'Never' : formatDateTimeMinutes(value.toLocal());

void showOutgoingPairCodeDialog({
  required BuildContext context,
  required AppThemeData theme,
  required String peerName,
  required String verificationCode,
  required void Function() onCancel,
  required Future<void> pairingResult,
}) {
  if (!context.mounted) return;

  // Captured on the first builder call so we can close from outside.
  BuildContext? dialogCtx;
  bool cancelTriggered = false;

  void maybeClose() {
    final ctx = dialogCtx;
    if (ctx != null && ctx.mounted) Navigator.of(ctx).maybePop();
  }

  void cancel() {
    if (cancelTriggered) return;
    cancelTriggered = true;
    maybeClose();
    onCancel();
  }

  showAppDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      dialogCtx ??= ctx;
      return DialogInteractionScope(
        enableEnterToPrimary: false,
        onDismiss: cancel,
        child: ThemedAlertDialog(
          theme: theme,
          title: DialogHeader(
            icon: Icons.verified_user,
            title: 'Pairing Code',
            theme: theme,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter this code on $peerName to complete pairing.',
                style: TextStyle(color: theme.textSecondary),
              ),
              const SizedBox(height: 12),
              PairCodeDisplay(code: verificationCode, theme: theme),
              const SizedBox(height: 8),
              Text(
                'This dialog will close automatically when pairing completes.',
                style: TextStyle(color: theme.textSecondary, fontSize: 12),
              ),
            ],
          ),
          actions: [
            ElevatedButton(onPressed: cancel, child: const Text('Cancel')),
          ],
        ),
      );
    },
  );

  // Auto-close when pairing either succeeds or fails.
  // Use then/onError instead of whenComplete so the error is swallowed here
  // (it is already handled by the caller's catch block), preventing an
  // unhandled-future-error crash when the user cancels.
  pairingResult.then<void>((_) => maybeClose(), onError: (_) => maybeClose());
}

class _DeviceSyncDialog extends ConsumerStatefulWidget {
  const _DeviceSyncDialog();

  @override
  ConsumerState<_DeviceSyncDialog> createState() => _DeviceSyncDialogState();
}

class _DeviceSyncDialogState extends ConsumerState<_DeviceSyncDialog> {
  bool _refreshing = false;

  Future<void> _refreshDiscovery() async {
    if (_refreshing) return;
    final notifier = ref.read(deviceSyncProvider.notifier);
    setState(() => _refreshing = true);
    try {
      await notifier.discoverPeers();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  // Discovery runs only while this dialog is open. Captured up front so
  // dispose never reads providers.
  late final DeviceSyncNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(deviceSyncProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final snapshot = ref.read(deviceSyncProvider).asData?.value;
      if (snapshot?.enabled == true) _notifier.startDiscovery();
    });
  }

  @override
  void dispose() {
    _notifier.stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final syncAsync = ref.watch(deviceSyncProvider);
    final isDesktop =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.fuchsia);
    final notifier = ref.read(deviceSyncProvider.notifier);
    final snapshot = syncAsync.asData?.value;
    final isRefreshing =
        _refreshing || snapshot?.status == DeviceSyncStatus.discovering;
    final canRefresh =
        snapshot != null &&
        snapshot.enabled &&
        !isRefreshing &&
        snapshot.status != DeviceSyncStatus.syncing &&
        snapshot.status != DeviceSyncStatus.connecting;

    Future<void> grantFirewallAccess() async {
      final granted = await notifier.grantFirewallAccess();
      if (granted) {
        NotificationManager.instance.success(
          'Firewall rules added for UniKM. Rechecked firewall status.',
        );
        return;
      }
      if (context.mounted) {
        NotificationManager.instance.error(
          'Could not add firewall rules (request canceled or failed).',
        );
      }
    }

    return ThemedAlertDialog(
      theme: theme,
      maxWidth: 680,
      title: DialogHeader(icon: Icons.lan, title: 'Device Sync', theme: theme),
      titleActions: [
        Tooltip(
          message: 'Enable Local Device Sync',
          child: Semantics(
            label: 'Enable Local Device Sync',
            child: AppToggleSwitch(
              theme: theme,
              value: syncAsync.asData?.value.enabled ?? false,
              onChanged: syncAsync.asData == null ? null : notifier.setEnabled,
            ),
          ),
        ),
        if (isDesktop)
          IconButton(
            tooltip: 'Grant Firewall Access',
            icon: const Icon(Icons.admin_panel_settings_outlined),
            onPressed: grantFirewallAccess,
          ),
      ],
      content: syncAsync.when(
        loading: () => const SizedBox(
          height: 160,
          child: Center(child: AppCircularProgressIndicator(size: 24)),
        ),
        error: (error, _) => _ErrorView(error: error.toString(), theme: theme),
        data: (sync) =>
            _SyncContent(sync: sync, theme: theme, refreshing: _refreshing),
      ),
      actions: [
        ElevatedButton.icon(
          onPressed: canRefresh ? _refreshDiscovery : null,
          icon: isRefreshing
              ? const AppCircularProgressIndicator(size: 18)
              : const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      ],
    );
  }
}

class _SyncContent extends ConsumerWidget {
  const _SyncContent({
    required this.sync,
    required this.theme,
    required this.refreshing,
  });

  final DeviceSyncSnapshot sync;
  final AppThemeData theme;
  final bool refreshing;

  IconData _statusIcon(DeviceSyncStatus status) => switch (status) {
    DeviceSyncStatus.discovering => Icons.radar,
    DeviceSyncStatus.syncing => Icons.sync,
    DeviceSyncStatus.error => Icons.link_off,
    _ => Icons.link,
  };

  static const _placeholderNames = {
    '',
    'localhost',
    '127.0.0.1',
    '::1',
    '0.0.0.0',
    'unknown',
  };
  static const _genericDeviceNames = {
    '',
    'unikm device',
    'mobile device',
    'desktop device',
    'android device',
    'ios device',
    'windows pc',
    'linux pc',
    'mac',
  };

  bool _isPlaceholderName(String value) =>
      _placeholderNames.contains(value.toLowerCase());

  bool _isGenericDeviceName(String value) =>
      _genericDeviceNames.contains(value.toLowerCase());

  String _preferredPeerName(String primary, String? secondary) {
    final first = primary.trim();
    final second = secondary?.trim() ?? '';
    final firstUsable =
        !_isPlaceholderName(first) && !_isGenericDeviceName(first);
    final secondUsable =
        !_isPlaceholderName(second) && !_isGenericDeviceName(second);

    if (firstUsable) return first;
    if (secondUsable) return second;
    if (!_isPlaceholderName(first)) return first;
    if (!_isPlaceholderName(second)) return second;
    return 'UniKM Device';
  }

  SyncDeviceType _effectiveDeviceType(_UnifiedDeviceRow row) {
    final trustedType = row.trusted?.deviceType ?? SyncDeviceType.unknown;
    if (trustedType != SyncDeviceType.unknown) return trustedType;

    final discoveredType = row.discovered?.deviceType ?? SyncDeviceType.unknown;
    if (discoveredType != SyncDeviceType.unknown) return discoveredType;

    final lower = row.name.toLowerCase();
    const mobileHints = [
      'iphone',
      'ipad',
      'android',
      'pixel',
      'galaxy',
      'phone',
      'mobile',
    ];
    return mobileHints.any(lower.contains)
        ? SyncDeviceType.mobile
        : SyncDeviceType.desktop;
  }

  IconData _deviceTypeIcon(_UnifiedDeviceRow row) =>
      _effectiveDeviceType(row) == SyncDeviceType.mobile
      ? Icons.smartphone
      : Icons.desktop_windows;

  ({Color color, String label}) _deviceVisual(_UnifiedDeviceRow row) {
    if (row.discovered?.isSyncCompatible == false) {
      return (color: theme.textSecondary, label: 'Incompatible sync version');
    }
    if (row.pendingRequest != null) {
      return (color: theme.accent, label: 'Incoming Pair Request');
    }

    if (row.trusted != null) {
      if (!sync.enabled) return (color: theme.textSecondary, label: 'Trusted');
      // DB mismatch takes highest priority — warn regardless of online state.
      if (sync.dbMismatchPeerIds.contains(row.id)) {
        return (color: Colors.orange, label: 'DB Mismatch');
      }
      // Sync is currently in progress with this specific device.
      if (sync.activeSyncPeerId == row.id) {
        return (color: theme.secondary, label: 'Syncing...');
      }
      // Device responded to the last discovery scan — it is reachable.
      if (row.discovered != null) {
        return (color: theme.secondary, label: 'Online');
      }
      // Trusted but did not respond to discovery — offline.
      return (color: theme.textSecondary, label: 'Offline');
    }

    return (color: theme.textSecondary, label: 'Discovered');
  }

  List<_UnifiedDeviceRow> _buildUnifiedRows() {
    final byId = <String, _UnifiedDeviceRow>{};

    for (final peer in sync.discoveredPeers) {
      byId[peer.id] = _UnifiedDeviceRow(
        id: peer.id,
        name: peer.name,
        host: peer.host,
        port: peer.port,
        discovered: peer,
      );
    }

    for (final peer in sync.trustedPeers) {
      final existing = byId[peer.id];
      byId[peer.id] = _UnifiedDeviceRow(
        id: peer.id,
        name: _preferredPeerName(peer.name, existing?.name),
        host: peer.host,
        port: peer.port,
        discovered: existing?.discovered,
        trusted: peer,
      );
    }

    for (final request in sync.pendingPairRequests) {
      final peer = request.peer;
      final existing = byId[peer.id];
      byId[peer.id] = _UnifiedDeviceRow(
        id: peer.id,
        name: _preferredPeerName(peer.name, existing?.name),
        host: peer.host,
        port: peer.port,
        discovered: existing?.discovered,
        trusted: existing?.trusted,
        pendingRequest: request,
      );
    }

    int rank(_UnifiedDeviceRow row) =>
        row.pendingRequest != null ? 0 : (row.trusted != null ? 1 : 2);
    return byId.values.toList(growable: false)..sort(
      (a, b) => rank(a) != rank(b)
          ? rank(a).compareTo(rank(b))
          : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(deviceSyncProvider.notifier);
    final unifiedRows = _buildUnifiedRows();
    final showDeviceId = ref.watch(showSyncDeviceIdProvider);
    final hasStatus =
        sync.statusMessage != null && sync.statusMessage!.isNotEmpty;
    final isRefreshing =
        refreshing || sync.status == DeviceSyncStatus.discovering;
    final isBusy =
        isRefreshing ||
        sync.status == DeviceSyncStatus.syncing ||
        sync.status == DeviceSyncStatus.connecting;
    // Treat messages that indicate a failure/rejection as a "broken link" state
    // even when the status itself is idle (e.g. "Pair request declined.").
    final isNegativeMessage =
        sync.statusMessage?.toLowerCase().contains('declined') == true ||
        sync.statusMessage?.toLowerCase().contains('failed') == true;

    final statusColor =
        sync.status == DeviceSyncStatus.error || isNegativeMessage
        ? theme.error
        : theme.secondary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        TintedHeading(
          theme: theme,
          title: 'Devices',
          trailing: '${unifiedRows.length}',
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: unifiedRows.isEmpty
              ? Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.accent.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(theme.cornerRadius),
                  ),
                  child: Row(
                    spacing: 12,
                    children: [
                      Icon(Icons.radar, color: theme.textHint),
                      Expanded(
                        child: Text(
                          'No devices found yet. Searching the local network while this window is open.',
                          style: TextStyle(
                            color: theme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: unifiedRows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final row = unifiedRows[i];
                    final visual = _deviceVisual(row);
                    return _DeviceTile(
                      key: ValueKey(row.id),
                      theme: theme,
                      icon: _deviceTypeIcon(row),
                      color: visual.color,
                      name: row.name,
                      address: '${row.host}:${row.port}',
                      status: visual.label,
                      pairedId: row.trusted == null ? null : row.id,
                      actions: _buildRowActions(context, row, ref, notifier),
                    );
                  },
                ),
        ),
        if (hasStatus)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(theme.cornerRadius),
            ),
            child: Row(
              spacing: 8,
              children: [
                if (isBusy)
                  const AppCircularProgressIndicator(strokeWidth: 2, size: 14)
                else
                  Icon(
                    isNegativeMessage
                        ? Icons.link_off
                        : _statusIcon(sync.status),
                    size: 16,
                    color: statusColor,
                  ),
                Expanded(
                  child: Text(
                    sync.statusMessage!,
                    style: TextStyle(color: theme.textSecondary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        if (showDeviceId)
          SelectableText(
            'Device ID: ${sync.deviceId}',
            style: TextStyle(color: theme.textSecondary, fontSize: 11),
          ),
      ],
    );
  }

  Widget _buildRowActions(
    BuildContext context,
    _UnifiedDeviceRow row,
    WidgetRef ref,
    DeviceSyncNotifier notifier,
  ) {
    if (row.discovered?.isSyncCompatible == false) {
      return _IncompatibleSyncInfoButton(theme: theme);
    }
    if (row.pendingRequest != null) {
      // Pending requests are handled via the global Pair Request prompt
      // No action buttons shown here
      return const SizedBox.shrink();
    }

    if (row.trusted != null) {
      Future<void> runSync() async {
        // Background discovery already tracks mismatches. Opening the chooser
        // must not wait on another network round trip; manualSync validates the
        // live peer and database before transferring anything.
        final hasMismatch = sync.dbMismatchPeerIds.contains(row.id);
        final bool? choice = await showChooseSyncDirectionDialog(
          context: context,
          theme: theme,
          hasMismatch: hasMismatch,
          peerName: row.name,
          peerId: row.id,
        );
        if (choice == null) return;
        final isPull = !choice;
        try {
          // The sync's progress notification reports success or failure.
          await notifier.manualSync(
            peerId: row.id,
            isPull: isPull,
            fullScan: true,
          );
        } catch (_) {}
      }

      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: kElementHSpacing,
        children: [
          IconButton(
            onPressed:
                sync.enabled &&
                    row.discovered != null &&
                    sync.activeSyncPeerId == null &&
                    sync.status != DeviceSyncStatus.syncing &&
                    sync.status != DeviceSyncStatus.connecting
                ? runSync
                : null,
            tooltip: 'Sync',
            // ListTile supplies an IconTheme color that otherwise also applies
            // to disabled buttons. Resolve both states explicitly here.
            style: IconButton.styleFrom(
              foregroundColor: theme.textPrimary,
              disabledForegroundColor: theme.textPrimary.withValues(
                alpha: 0.38,
              ),
            ),
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            onPressed: () async {
              final confirmed = await showConfirmDialog(
                context: context,
                theme: theme,
                title: 'Unpair Device',
                titleIcon: Icons.link_off,
                message: 'Are you sure you want to unpair "${row.name}"?',
                confirmLabel: 'Unpair',
                showCancel: true,
                confirmIcon: Icons.link_off,
                destructive: true,
              );
              if (!confirmed || !context.mounted) return;
              try {
                await notifier.removeTrustedPeer(row.id);
              } catch (error) {
                NotificationManager.instance.error('Unpair failed: $error');
              }
            },
            tooltip: 'Remove',
            icon: const Icon(Icons.link_off),
          ),
        ],
      );
    }

    final discovered = row.discovered;
    if (discovered != null) {
      return TextButton.icon(
        onPressed: () async {
          try {
            final pairingCompleter = Completer<void>();
            final cancelCompleter = Completer<void>();

            final pairingFuture = ref
                .read(deviceSyncProvider.notifier)
                .requestPairing(
                  discovered,
                  showVerificationCode: (verificationCode) {
                    showOutgoingPairCodeDialog(
                      context: context,
                      theme: theme,
                      peerName: discovered.name,
                      verificationCode: verificationCode,
                      onCancel: () {
                        if (!cancelCompleter.isCompleted) {
                          cancelCompleter.complete();
                        }
                      },
                      pairingResult: pairingCompleter.future,
                    );
                  },
                  onUserCancel: cancelCompleter.future,
                );

            await pairingFuture
                .then((result) => pairingCompleter.complete())
                .catchError((error) {
                  pairingCompleter.completeError(error);
                  throw error;
                });
          } catch (error) {
            NotificationManager.instance.error('Pairing failed: $error');
          }
        },
        icon: const Icon(Icons.link, size: 16),
        label: const Text('Pair'),
      );
    }

    return const SizedBox.shrink();
  }
}

/// A device as a tinted tile: its type icon in a square tinted with its
/// state's colour, its name, address and state, and its actions. Paired
/// devices show their last sync on hovering the icon.
class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    super.key,
    required this.theme,
    required this.icon,
    required this.color,
    required this.name,
    required this.address,
    required this.status,
    required this.pairedId,
    required this.actions,
  });

  final AppThemeData theme;
  final IconData icon;
  final Color color;
  final String name;
  final String address;
  final String status;

  /// The peer id of a paired device, for its last sync.
  final String? pairedId;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(theme.cornerRadius);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.08),
        borderRadius: radius,
      ),
      child: Row(
        spacing: 12,
        children: [
          Consumer(
            builder: (context, ref, _) {
              final pairedId = this.pairedId;
              return Tooltip(
                message: pairedId == null
                    ? ''
                    : 'Last sync: ${ref.watch(syncPeerLastSyncProvider(pairedId)).when(data: _formatLastSync, loading: () => 'Checking…', error: (_, _) => 'Unavailable')}',
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: radius,
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
              );
            },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '$address  ·  '),
                      TextSpan(
                        text: status,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  style: TextStyle(color: theme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          actions,
        ],
      ),
    );
  }
}

class _UnifiedDeviceRow {
  const _UnifiedDeviceRow({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.discovered,
    this.trusted,
    this.pendingRequest,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final DiscoveredSyncPeer? discovered;
  final TrustedSyncPeer? trusted;
  final PendingPairRequest? pendingRequest;
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.theme});

  final String error;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 120,
    child: Center(
      child: Text(
        error,
        style: TextStyle(color: theme.error),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

// Match the click-to-show info buttons used on the settings page.
class _IncompatibleSyncInfoButton extends StatefulWidget {
  const _IncompatibleSyncInfoButton({required this.theme});

  final AppThemeData theme;

  @override
  State<_IncompatibleSyncInfoButton> createState() =>
      _IncompatibleSyncInfoButtonState();
}

class _IncompatibleSyncInfoButtonState
    extends State<_IncompatibleSyncInfoButton> {
  final _tooltipKey = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) => Tooltip(
    key: _tooltipKey,
    message:
        'This device is running an incompatible sync version. '
        'Update UniKM on both devices to use pairing and device sync.',
    child: IconButton(
      style: widget.theme.compactIconButtonStyle,
      icon: const Icon(Icons.info_outline, size: 26),
      color: widget.theme.accent,
      onPressed: () => _tooltipKey.currentState?.ensureTooltipVisible(),
    ),
  );
}
