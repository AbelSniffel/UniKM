library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/device_sync_models.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../widgets/app_progress_indicator.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/notification_system.dart';
import '../widgets/pair_code_widgets.dart';
import '../widgets/section_groupbox.dart';
import '../widgets/groupbox_family_title.dart';
import '../widgets/settings_header_actions.dart';
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
  const directionButtonStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

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
        children: [
          Text(
            'Sync with $peerName',
            style: TextStyle(
              color: theme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose where to send changes. Changes are merged into the destination library.',
            style: TextStyle(color: theme.textSecondary),
          ),
          const SizedBox(height: 16),
          Consumer(
            builder: (context, ref, _) {
              final lastSync = ref.watch(syncPeerLastSyncProvider(peerId));
              return Text(
                'Last sync: ${lastSync.when(data: _formatLastSync, loading: () => 'Checking…', error: (_, _) => 'Unavailable')}',
                style: TextStyle(color: theme.textSecondary, fontSize: 12),
              );
            },
          ),
          if (hasMismatch) ...[
            const SizedBox(height: 16),
            DialogBanner.warning(
              theme: theme,
              message:
                  'Different database files. Receiving will switch this device to $peerName\'s database filename before merging changes.',
            ),
          ],
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  textStyle: directionButtonStyle,
                ),
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Receive'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  textStyle: directionButtonStyle,
                ),
                icon: const Icon(Icons.upload, size: 18),
                label: const Text('Send'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

String _formatLastSync(DateTime? value) {
  if (value == null) return 'Never';
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

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
      ],
      content: syncAsync.when(
        loading: () => const SizedBox(
          height: 160,
          child: Center(child: AppCircularProgressIndicator(size: 24)),
        ),
        error: (error, _) => _ErrorView(error: error.toString(), theme: theme),
        data: (sync) => _SyncContent(
          sync: sync,
          theme: theme,
          onGrantFirewallAccess: isDesktop ? grantFirewallAccess : null,
          refreshing: _refreshing,
          onRefresh: _refreshDiscovery,
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _SyncContent extends ConsumerWidget {
  const _SyncContent({
    required this.sync,
    required this.theme,
    this.onGrantFirewallAccess,
    required this.refreshing,
    required this.onRefresh,
  });

  final DeviceSyncSnapshot sync;
  final AppThemeData theme;
  final VoidCallback? onGrantFirewallAccess;
  final bool refreshing;
  final VoidCallback onRefresh;

  IconData _statusIcon(DeviceSyncStatus status) => switch (status) {
    DeviceSyncStatus.discovering => Icons.radar,
    DeviceSyncStatus.syncing => Icons.sync,
    DeviceSyncStatus.error => Icons.link_off,
    _ => Icons.link,
  };

  bool _isPlaceholderName(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) return true;
    return normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1' ||
        normalized == '0.0.0.0' ||
        normalized == 'unknown';
  }

  bool _isGenericDeviceName(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) return true;
    return normalized == 'unikm device' ||
        normalized == 'mobile device' ||
        normalized == 'desktop device' ||
        normalized == 'android device' ||
        normalized == 'ios device' ||
        normalized == 'windows pc' ||
        normalized == 'linux pc' ||
        normalized == 'mac';
  }

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
    final looksMobile =
        lower.contains('iphone') ||
        lower.contains('ipad') ||
        lower.contains('android') ||
        lower.contains('pixel') ||
        lower.contains('galaxy') ||
        lower.contains('phone') ||
        lower.contains('mobile');
    return looksMobile ? SyncDeviceType.mobile : SyncDeviceType.desktop;
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

    final rows = byId.values.toList(growable: false)
      ..sort((a, b) {
        final aRank = a.pendingRequest != null
            ? 0
            : (a.trusted != null ? 1 : 2);
        final bRank = b.pendingRequest != null
            ? 0
            : (b.trusted != null ? 1 : 2);
        if (aRank != bRank) return aRank.compareTo(bRank);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return rows;
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
        sync.status == DeviceSyncStatus.discovering ||
        sync.status == DeviceSyncStatus.connecting;
    // Treat messages that indicate a failure/rejection as a "broken link" state
    // even when the status itself is idle (e.g. "Pair request declined.").
    final isNegativeMessage =
        sync.statusMessage?.toLowerCase().contains('declined') == true ||
        sync.statusMessage?.toLowerCase().contains('failed') == true;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupBoxFamilyTitle(
          theme: theme,
          title: 'Device List',
          icon: Icons.devices_outlined,
          trailingBuilder: (expanded) => SettingsHeaderActions(
            theme: theme,
            expanded: expanded,
            children: [
              if (onGrantFirewallAccess != null)
                AppNavigationButton(
                  theme: theme,
                  isSelected: false,
                  isEnabled: true,
                  isHorizontal: true,
                  tooltipMessage: 'Grant Firewall Access',
                  iconData: Icons.admin_panel_settings_outlined,
                  iconSize: 20,
                  minWidth: 40,
                  minHeight: 36,
                  onTap: onGrantFirewallAccess,
                ),
              AppNavigationButton(
                theme: theme,
                isSelected: false,
                isEnabled: sync.enabled && !isBusy,
                isHorizontal: true,
                tooltipMessage: 'Refresh device discovery',
                iconData: isRefreshing ? null : Icons.refresh,
                iconSize: 20,
                minWidth: 40,
                minHeight: 36,
                onTap: sync.enabled && !isBusy ? onRefresh : null,
                iconBuilder: isRefreshing
                    ? (context, color, size) => SizedBox(
                        width: size,
                        height: size,
                        child: AppCircularProgressIndicator(color: color),
                      )
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: kGroupBoxSpacing),
        SectionGroupBox(
          title: '',
          showTitle: false,
          theme: theme,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: unifiedRows.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'No devices found yet. Searching the local network while this window is open.',
                      style: TextStyle(
                        color: theme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: unifiedRows.length,
                    itemBuilder: (_, i) {
                      final row = unifiedRows[i];
                      final visual = _deviceVisual(row);
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Consumer(
                          builder: (context, ref, _) {
                            final lastSync = row.trusted == null
                                ? null
                                : ref.watch(syncPeerLastSyncProvider(row.id));
                            return Tooltip(
                              message: lastSync == null
                                  ? ''
                                  : 'Last sync: ${lastSync.when(data: _formatLastSync, loading: () => 'Checking…', error: (_, _) => 'Unavailable')}',
                              child: Icon(
                                _deviceTypeIcon(row),
                                color: visual.color,
                              ),
                            );
                          },
                        ),
                        title: Text(row.name, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${row.host}:${row.port} \u2022 ${visual.label}',
                        ),
                        trailing: _buildRowActions(context, row, ref, notifier),
                      );
                    },
                  ),
          ),
        ),
        if (hasStatus)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
            child: Row(
              children: [
                if (isBusy)
                  const AppCircularProgressIndicator(strokeWidth: 2, size: 14)
                else
                  Icon(
                    isNegativeMessage
                        ? Icons.link_off
                        : _statusIcon(sync.status),
                    size: 14,
                    color:
                        (sync.status == DeviceSyncStatus.error ||
                            isNegativeMessage)
                        ? theme.error
                        : theme.secondary,
                  ),
                const SizedBox(width: 6),
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
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: SelectableText(
              'Device ID: ${sync.deviceId}',
              style: TextStyle(color: theme.textSecondary, fontSize: 11),
            ),
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
