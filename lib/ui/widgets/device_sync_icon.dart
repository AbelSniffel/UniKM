import 'package:flutter/material.dart';

import '../../core/models/device_sync_models.dart';
import '../../core/theme/app_theme.dart';

/// The Device Sync button's icon, shared by the title bar and the library
/// header: sync off, no paired device online (a broken link), or the online
/// device's type in the accent, orange when its database differs. The color
/// is null while sync is off, so the button keeps its idle color.
({IconData icon, Color? color}) deviceSyncIcon(
  AppThemeData theme,
  DeviceSyncSnapshot? sync,
) {
  if (sync == null || !sync.enabled) {
    return (icon: Icons.sync_disabled, color: null);
  }
  final deviceIcon = _onlineDeviceIcon(sync);
  if (deviceIcon == null) {
    return (icon: Icons.link_off, color: theme.textSecondary);
  }
  return (
    icon: deviceIcon,
    color: sync.dbMismatchPeerIds.isNotEmpty ? Colors.orange : theme.accent,
  );
}

IconData? _onlineDeviceIcon(DeviceSyncSnapshot sync) {
  final trustedById = {for (final peer in sync.trustedPeers) peer.id: peer};
  final onlinePeers = sync.discoveredPeers
      .where((peer) => trustedById.containsKey(peer.id))
      .toList();
  if (onlinePeers.length > 1) return Icons.devices;
  if (onlinePeers.isEmpty) return null;
  final peer = onlinePeers.single;
  final type = peer.deviceType == SyncDeviceType.unknown
      ? trustedById[peer.id]!.deviceType
      : peer.deviceType;
  return switch (type) {
    SyncDeviceType.mobile => Icons.smartphone,
    SyncDeviceType.desktop => Icons.desktop_windows,
    SyncDeviceType.web => Icons.language,
    SyncDeviceType.unknown => Icons.devices_other,
  };
}
