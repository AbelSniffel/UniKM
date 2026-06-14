library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/device_sync_models.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../pages/settings_sections/settings_common.dart';
import '../widgets/app_progress_indicator.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/notification_system.dart';
import '../widgets/pair_code_widgets.dart';
import '../widgets/section_groupbox.dart';

Future<void> showDeviceSyncDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _DeviceSyncDialog(),
  );
}

/// Shows the sync direction choice dialog for a trusted peer.
///
/// Returns `true` when the user chooses "This Device" (push),
/// `false` for "Remote Device" (pull), or `null` if dismissed.
Future<bool?> _showChooseSyncDirectionDialog({
  required BuildContext context,
  required AppThemeData theme,
  required bool hasMismatch,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => ThemedAlertDialog(
      theme: theme,
      title: DialogHeader(
        icon: hasMismatch ? Icons.warning_amber_rounded : Icons.sync,
        title: hasMismatch ? 'Database Mismatch' : 'Choose Sync Direction',
        theme: theme,
      ),
      content: Text(
        hasMismatch
            ? 'These devices have different database files. '
                  'Choose which device\'s data to sync from — changes will be merged in. '
                  'If you choose Remote Device, this device will switch to the remote database filename before syncing.'
            : 'Choose which device\'s data to sync from. '
                  'Changes from the selected device will be merged in.',
        style: TextStyle(color: theme.textSecondary),
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, false),
                icon: const Icon(Icons.download),
                label: const Text('Remote Device'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.upload),
                label: const Text('This Device'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

void _showOutgoingPairCodeDialog({
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

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      dialogCtx ??= ctx;
      return DialogInteractionScope(
        enableEnterToPrimary: false,
        onDismiss: () {
          if (cancelTriggered) return;
          cancelTriggered = true;
          maybeClose();
          onCancel();
        },
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
              PairCodeDisplay(
                code: verificationCode,
                theme: theme,
              ),
              const SizedBox(height: 8),
              Text(
                'This dialog will close automatically when pairing completes.',
                style: TextStyle(color: theme.textSecondary, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (cancelTriggered) return;
                cancelTriggered = true;
                maybeClose();
                onCancel();
              },
              child: const Text('Cancel'),
            ),
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final snapshot = ref.read(deviceSyncProvider).asData?.value;
      if (snapshot?.enabled == true) {
        unawaited(ref.read(deviceSyncProvider.notifier).discoverPeers());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final syncAsync = ref.watch(deviceSyncProvider);
    final isWindows =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final notifier = ref.read(deviceSyncProvider.notifier);

    Future<void> grantFirewallAccess() async {
      final granted = await notifier.grantWindowsFirewallAccess();
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
        if (isWindows)
          IconButton(
            icon: const Icon(Icons.admin_panel_settings_outlined),
            tooltip: 'Grant Firewall Access',
            onPressed: grantFirewallAccess,
          ),
      ],
      content: syncAsync.when(
        loading: () => const SizedBox(
          height: 160,
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: AppCircularProgressIndicator(),
            ),
          ),
        ),
        error: (error, _) => _ErrorView(error: error.toString(), theme: theme),
        data: (sync) => _SyncContent(sync: sync, theme: theme),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _SyncContent extends ConsumerWidget {
  const _SyncContent({required this.sync, required this.theme});

  final DeviceSyncSnapshot sync;
  final AppThemeData theme;

  String _formatLastSync(DateTime? value) {
    if (value == null) return 'Never';
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  IconData _statusIcon(DeviceSyncStatus status) {
    return switch (status) {
      DeviceSyncStatus.discovering => Icons.radar,
      DeviceSyncStatus.syncing => Icons.sync,
      DeviceSyncStatus.error => Icons.link_off,
      _ => Icons.link,
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
        normalized == 'unknown';
  }

  bool _isGenericDeviceName(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) {
      return true;
    }
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

    if (firstUsable) {
      return first;
    }
    if (secondUsable) {
      return second;
    }
    if (!_isPlaceholderName(first)) {
      return first;
    }
    if (!_isPlaceholderName(second)) {
      return second;
    }
    return 'UniKM Device';
  }

  SyncDeviceType _effectiveDeviceType(_UnifiedDeviceRow row) {
    final trustedType = row.trusted?.deviceType ?? SyncDeviceType.unknown;
    if (trustedType != SyncDeviceType.unknown) {
      return trustedType;
    }

    final discoveredType = row.discovered?.deviceType ?? SyncDeviceType.unknown;
    if (discoveredType != SyncDeviceType.unknown) {
      return discoveredType;
    }

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

  IconData _deviceTypeIcon(_UnifiedDeviceRow row) {
    return _effectiveDeviceType(row) == SyncDeviceType.mobile
        ? Icons.smartphone
        : Icons.desktop_windows;
  }

  ({IconData icon, Color color, String label}) _deviceVisual(
    _UnifiedDeviceRow row,
  ) {
    if (row.pendingRequest != null) {
      return (
        icon: Icons.handshake,
        color: theme.accent,
        label: 'Incoming Pair Request',
      );
    }

    if (row.trusted != null) {
      if (!sync.enabled) {
        return (icon: Icons.link, color: theme.textSecondary, label: 'Trusted');
      }
      // DB mismatch takes highest priority — warn regardless of online state.
      if (sync.dbMismatchPeerIds.contains(row.id)) {
        return (icon: Icons.link, color: Colors.orange, label: 'DB Mismatch');
      }
      // Sync is currently in progress with this specific device.
      if (sync.activeSyncPeerId == row.id) {
        return (icon: Icons.sync, color: theme.secondary, label: 'Syncing...');
      }
      // Device responded to the last discovery scan — it is reachable.
      if (row.discovered != null) {
        return (icon: Icons.link, color: theme.secondary, label: 'Online');
      }
      // Trusted but did not respond to discovery — offline.
      return (
        icon: Icons.link_off,
        color: theme.textSecondary,
        label: 'Offline',
      );
    }

    return (
      icon: Icons.devices,
      color: theme.textSecondary,
      label: 'Discovered',
    );
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
    final hasStatus =
        sync.statusMessage != null && sync.statusMessage!.isNotEmpty;
    final isBusy =
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
        // ── Top groupbox: device list ─────────────────────────────────────
        SectionGroupBox(
          title: 'Devices',
          titleIcon: Icons.devices,
          theme: theme,
          groupPosition: SectionGroupPosition.first,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Device list
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: unifiedRows.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'No devices found yet. Device discovery runs automatically while sync is enabled.',
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
                            leading: Tooltip(
                              message: row.trusted != null
                                  ? 'Last sync: ${_formatLastSync(sync.lastSyncAt)}'
                                  : '',
                              child: Icon(visual.icon, color: visual.color),
                            ),
                            title: Row(
                              children: [
                                Icon(
                                  _deviceTypeIcon(row),
                                  size: 16,
                                  color: theme.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    row.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              '${row.host}:${row.port} \u2022 ${visual.label}',
                            ),
                            trailing: _buildRowActions(
                              context,
                              row,
                              ref,
                              notifier,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        // ── Bottom groupbox: sync settings ────────────────────────────────
        SectionGroupBox(
          title: 'Sync Settings',
          titleIcon: Icons.settings,
          theme: theme,
          groupPosition: SectionGroupPosition.last,
          alternateBackground: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ToggleSettingRow(
                theme: theme,
                label: 'Enable Local Device Sync',
                description:
                    'Allows LAN discovery and manual sync between paired devices.',
                value: sync.enabled,
                onChanged: (value) {
                  notifier.setEnabled(value);
                },
              ),
              if (!kIsWeb &&
                  defaultTargetPlatform == TargetPlatform.windows) ...[
                const SizedBox(height: 10),
                if (sync.firewallStatusMessage != null &&
                    sync.firewallStatusMessage!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.surface.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.warning.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              color: theme.warning,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                sync.firewallStatusMessage!,
                                style: TextStyle(
                                  color: theme.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final granted = await notifier
                                .grantWindowsFirewallAccess();
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
                          },
                          icon: const Icon(
                            Icons.admin_panel_settings_outlined,
                            size: 16,
                          ),
                          label: const Text('Grant Firewall Access'),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (hasStatus)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
            child: Row(
              children: [
                if (isBusy)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: AppCircularProgressIndicator(strokeWidth: 2),
                  )
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
        // ── Device ID info (between groupboxes and footer) ─────────────────
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 4),
          child: Text(
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
    if (row.pendingRequest != null) {
      // Pending requests are handled via the global Pair Request prompt
      // No action buttons shown here
      return const SizedBox.shrink();
    }

    if (row.trusted != null) {
      Future<void> runSync() async {
        final hasMismatch = sync.dbMismatchPeerIds.contains(row.id);
        final bool? choice = await _showChooseSyncDirectionDialog(
          context: context,
          theme: theme,
          hasMismatch: hasMismatch,
        );
        if (choice == null) return;
        final isPull = !choice;
        try {
          await notifier.manualSync(
            peerId: row.id,
            isPull: isPull,
            fullScan: true,
          );
          NotificationManager.instance.success(
            isPull ? 'Scan pull completed.' : 'Scan sync completed.',
          );
        } catch (error) {
          NotificationManager.instance.error('Sync failed: $error');
        }
      }

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: runSync,
            tooltip: 'Scan & recover missing data',
            icon: const Icon(Icons.manage_search),
          ),
          IconButton(
            onPressed: () => notifier.removeTrustedPeer(row.id),
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
                    _showOutgoingPairCodeDialog(
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
                .then((result) {
                  pairingCompleter.complete();
                })
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
  Widget build(BuildContext context) {
    return SizedBox(
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
}
