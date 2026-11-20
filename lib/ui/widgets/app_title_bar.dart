import 'package:material_ui/material_ui.dart';
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
class const AppTitleBar({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.appTheme;
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
                  _MenuButton(),
                  const _SyncButton(),

                  const Spacer(),
                ],
              ),
            ),
          ),

          // Window controls remain outside of the gesture area that handles
          // double taps so they are responsive immediately.
          _TitleBarActionButton(
            icon: Icons.remove,
            width: 46,
            onPressed: windowManager.minimize,
          ),
          _TitleBarActionButton(
            icon: Icons.crop_square,
            width: 46,
            onPressed: _toggleMaximized,
          ),
          _TitleBarActionButton(
            icon: Icons.close,
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
class const _MenuButton() extends StatefulWidget {
  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return AppMenuAnchor(
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
            () => showChangeDatabaseDialog(context),
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
        icon: Icons.menu,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

class const _SyncButton() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (:icon, :color) = deviceSyncIcon(
      context.appTheme,
      ref.watch(deviceSyncProvider).asData?.value,
    );

    return Tooltip(
      message: 'Device Sync',
      child: _TitleBarActionButton(
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
class const _TitleBarActionButton({
  required final IconData icon,
  required final VoidCallback onPressed,
  final double width = 36,
  final Color? color,

  /// Tints the hover background and, unless [hoverIconColor] is set, the icon.
  final Color? hoverColor,
  final Color? hoverIconColor,
}) extends StatefulWidget {
  @override
  State<_TitleBarActionButton> createState() => _TitleBarActionButtonState();
}

class _TitleBarActionButtonState extends State<_TitleBarActionButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final hover = widget.hoverColor ?? theme.accent;
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
                : widget.color ?? theme.textSecondary,
          ),
        ),
      ),
    );
  }
}
