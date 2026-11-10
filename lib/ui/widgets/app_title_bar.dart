import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../dialogs/device_sync_dialog.dart';
import '../dialogs/import_export_dialog.dart';
import '../pages/settings_sections/database_section.dart'
    show showChangeDatabaseDialog;
import 'device_sync_icon.dart';
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
          _TitleBarActionButton(
            icon: Icons.remove,
            theme: theme,
            width: 46,
            onPressed: windowManager.minimize,
          ),
          _TitleBarActionButton(
            icon: Icons.crop_square,
            theme: theme,
            width: 46,
            onPressed: _toggleMaximized,
          ),
          _TitleBarActionButton(
            icon: Icons.close,
            theme: theme,
            width: 46,
            hoverColor: theme.secondary,
            onPressed: windowManager.close,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (:icon, :color) = deviceSyncIcon(
      theme,
      ref.watch(deviceSyncProvider).asData?.value,
    );

    return Tooltip(
      message: 'Device Sync',
      child: _TitleBarActionButton(
        theme: theme,
        icon: icon,
        color: color?.withValues(alpha: 0.9),
        hoverIconColor: color,
        onPressed: () => showDeviceSyncDialog(context),
      ),
    );
  }
}

/// Shared pointer and hover handling for the title-bar actions and the
/// window buttons.
class _TitleBarActionButton extends StatefulWidget {
  const _TitleBarActionButton({
    required this.theme,
    required this.icon,
    required this.onPressed,
    this.width = 36,
    this.color,
    this.hoverColor,
    this.hoverIconColor,
  });

  final AppThemeData theme;
  final IconData icon;
  final VoidCallback onPressed;
  final double width;
  final Color? color;

  /// Tints the hover background and, unless [hoverIconColor] is set, the icon.
  final Color? hoverColor;
  final Color? hoverIconColor;

  @override
  State<_TitleBarActionButton> createState() => _TitleBarActionButtonState();
}

class _TitleBarActionButtonState extends State<_TitleBarActionButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final hover = widget.hoverColor ?? widget.theme.accent;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => setState(() => _isPressed = true),
        onPointerUp: (event) {
          // Releasing outside the button cancels the press.
          final box = context.findRenderObject()! as RenderBox;
          final inside = box.paintBounds.contains(
            box.globalToLocal(event.position),
          );
          if (_isPressed && inside) widget.onPressed();
          setState(() => _isPressed = false);
        },
        onPointerCancel: (_) => setState(() => _isPressed = false),
        child: Container(
          width: widget.width,
          height: 32,
          color: _isHovered ? hover.withValues(alpha: 0.2) : Colors.transparent,
          child: Icon(
            widget.icon,
            size: 16,
            color: _isHovered
                ? widget.hoverIconColor ?? hover
                : widget.color ?? widget.theme.textSecondary,
          ),
        ),
      ),
    );
  }
}
