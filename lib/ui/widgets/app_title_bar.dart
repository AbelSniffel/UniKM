import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/device_sync_models.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../dialogs/device_sync_dialog.dart';
import '../dialogs/import_export_dialog.dart';
import '../pages/settings_sections/database_section.dart'
    show showChangeDatabaseDialog;
import 'popup_menu_helpers.dart';

Future<void> _toggleMaximized() async => await windowManager.isMaximized()
    ? windowManager.unmaximize()
    : windowManager.maximize();

/// The program title bar, shared by the main window and full-page tools.
class AppTitleBar extends ConsumerWidget {
  const AppTitleBar({super.key, required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // the dragging/ double‑tap region intentionally excludes the window buttons
    // so that their taps are delivered immediately rather than being delayed by
    // the ancestor gesture recognizer. an Expanded makes it stretch to take up
    // all remaining space.
    return Container(
      key: const Key('title-bar'),
      height: 32,
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(bottom: BorderSide(color: theme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: _toggleMaximized,
              behavior: HitTestBehavior.translucent,
              child: Row(
                children: [
                  // App icon and title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Icon(Icons.gamepad, size: 16, color: theme.accent),
                        const SizedBox(width: kElementHSpacing),
                        Text(
                          kAppName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Menu button with Import/Export options
                  _MenuButton(theme: theme),
                  _SyncButton(theme: theme),

                  const Spacer(),
                ],
              ),
            ),
          ),

          // Window controls remain outside of the gesture area that handles
          // double taps so they are responsive immediately.
          _WindowButton(
            icon: Icons.remove,
            theme: theme,
            onPressed: () => windowManager.minimize(),
          ),
          _WindowButton(
            icon: Icons.crop_square,
            theme: theme,
            onPressed: _toggleMaximized,
          ),
          _WindowButton(
            icon: Icons.close,
            theme: theme,
            hoverColor: theme.secondary,
            onPressed: () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}

/// Menu button with Import/Export options
class _MenuButton extends StatefulWidget {
  const _MenuButton({required this.theme});

  final AppThemeData theme;

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return AppMenuAnchor(
      theme: theme,
      menuChildren: [
        for (final (icon, label, open) in <(IconData, String, VoidCallback)>[
          (
            Icons.file_download,
            'Import Database',
            () => showImportDialog(context),
          ),
          (
            Icons.file_upload,
            'Export Database',
            () => showExportDialog(context),
          ),
          (
            Icons.swap_horiz,
            'Change Database',
            () => showChangeDatabaseDialog(context, theme),
          ),
        ])
          appMenuItem(
            theme,
            leading: Icon(icon, size: 18),
            onPressed: open,
            child: Text(label),
          ),
      ],
      builder: (context, controller, _) => _TitleBarActionButton(
        theme: theme,
        icon: Icons.menu,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

class _SyncButton extends ConsumerWidget {
  const _SyncButton({required this.theme});

  final AppThemeData theme;

  IconData? _connectedDeviceIcon(DeviceSyncSnapshot sync) {
    final trustedById = {for (final peer in sync.trustedPeers) peer.id: peer};
    final onlinePeers = sync.discoveredPeers
        .where((peer) => trustedById.containsKey(peer.id))
        .toList();
    if (onlinePeers.length > 1) return Icons.devices;
    if (onlinePeers.isEmpty) return null;
    final peer = onlinePeers.single;
    final trusted = trustedById[peer.id]!;
    final type = peer.deviceType == SyncDeviceType.unknown
        ? trusted.deviceType
        : peer.deviceType;
    return switch (type) {
      SyncDeviceType.mobile => Icons.smartphone,
      SyncDeviceType.desktop => Icons.desktop_windows,
      SyncDeviceType.web => Icons.language,
      SyncDeviceType.unknown => Icons.devices_other,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(deviceSyncProvider).asData?.value;
    final enabled = sync?.enabled ?? false;
    final hasMismatch = sync?.dbMismatchPeerIds.isNotEmpty ?? false;
    final deviceIcon = enabled && sync != null
        ? _connectedDeviceIcon(sync)
        : null;
    final iconData = !enabled
        ? Icons.sync_disabled
        : deviceIcon ?? Icons.link_off;
    final activeColor = hasMismatch && deviceIcon != null
        ? Colors.orange
        : deviceIcon != null
        ? theme.secondary
        : theme.textSecondary;

    return Tooltip(
      message: 'Device Sync',
      child: _TitleBarActionButton(
        theme: theme,
        icon: iconData,
        color: enabled ? activeColor.withValues(alpha: 0.9) : null,
        hoverIconColor: enabled ? activeColor : null,
        onPressed: () => showDeviceSyncDialog(context),
      ),
    );
  }
}

/// Shared pointer and hover handling for the title-bar menu and sync actions.
class _TitleBarActionButton extends StatefulWidget {
  const _TitleBarActionButton({
    required this.theme,
    required this.icon,
    required this.onPressed,
    this.color,
    this.hoverIconColor,
  });

  final AppThemeData theme;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;
  final Color? hoverIconColor;

  @override
  State<_TitleBarActionButton> createState() => _TitleBarActionButtonState();
}

class _TitleBarActionButtonState extends State<_TitleBarActionButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _isHovered = true),
    onExit: (_) => setState(() => _isHovered = false),
    child: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => setState(() => _isPressed = true),
      onPointerUp: (_) {
        if (_isPressed) widget.onPressed();
        setState(() => _isPressed = false);
      },
      onPointerCancel: (_) => setState(() => _isPressed = false),
      child: Container(
        width: 36,
        height: 32,
        color: _isHovered
            ? widget.theme.accent.withValues(alpha: 0.2)
            : Colors.transparent,
        child: Icon(
          widget.icon,
          size: 16,
          color: _isHovered
              ? widget.hoverIconColor ?? widget.theme.accent
              : widget.color ?? widget.theme.textSecondary,
        ),
      ),
    ),
  );
}

/// Window control button
class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.theme,
    required this.onPressed,
    this.hoverColor,
  });

  final IconData icon;
  final AppThemeData theme;
  final VoidCallback onPressed;
  final Color? hoverColor;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _isHovered = true),
    onExit: (_) => setState(() => _isHovered = false),
    child: GestureDetector(
      onTap: widget.onPressed,
      child: Container(
        width: 46,
        height: 32,
        color: _isHovered
            ? (widget.hoverColor ?? widget.theme.accent).withValues(alpha: 0.2)
            : Colors.transparent,
        child: Icon(
          widget.icon,
          size: 16,
          color: _isHovered
              ? (widget.hoverColor ?? widget.theme.accent)
              : widget.theme.textSecondary,
        ),
      ),
    ),
  );
}
