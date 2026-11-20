import 'package:desktop_drop/desktop_drop.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/services/platform_file_actions.dart';
import '../../core/theme/app_theme.dart';
import 'notification_system.dart';
import 'window_drop_target.dart';

/// One file-selection surface for browsing and window-wide file drops.
/// Callers retain format validation and decide what selecting a file does.
class const FileDropField({
  super.key,
  required final String description,
  required final Future<void> Function() onBrowse,
  required final Future<void> Function(String) onFileSelected,
  required final String invalidDropMessage,
  final String? selectedName,
  final IconData selectedIcon = Icons.check_circle,
  final VoidCallback? onClear,
  final bool enabled = true,
  final bool active = true,
}) extends StatefulWidget {
  @override
  State<FileDropField> createState() => _FileDropFieldState();
}

class _FileDropFieldState extends State<FileDropField> {
  bool _hovering = false;
  bool _dragging = false;

  @override
  void didUpdateWidget(FileDropField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || !widget.active) {
      _hovering = false;
      _dragging = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final selected = widget.selectedName != null;
    final drop = PlatformFileActions.supportsDragAndDrop;
    final radius = BorderRadius.circular(theme.cornerRadius);
    final color = _dragging || selected ? theme.accent : theme.textSecondary;
    return MouseRegion(
      onEnter: (_) {
        if (widget.enabled) setState(() => _hovering = true);
      },
      onExit: (_) => setState(() => _hovering = false),
      child: WindowDropTarget(
        enable: drop && widget.enabled && widget.active,
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (details) async {
          setState(() => _dragging = false);
          if (details.files.length != 1 ||
              details.files.single is DropItemDirectory) {
            NotificationManager.instance.error(widget.invalidDropMessage);
            return;
          }
          await widget.onFileSelected(details.files.single.path);
        },
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: radius,
            onTap: widget.enabled ? widget.onBrowse : null,
            child: Ink(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  theme.accent.withValues(
                    alpha: _dragging ? 0.1 : (_hovering ? 0.05 : 0),
                  ),
                  theme.inputBackground,
                ),
                borderRadius: radius,
                border: Border.all(
                  color: _dragging
                      ? theme.accent
                      : _hovering
                      ? theme.accent.withValues(alpha: 0.5)
                      : selected
                      ? theme.accent
                      : theme.border,
                  width: _dragging ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _dragging
                        ? Icons.file_download
                        : selected
                        ? widget.selectedIcon
                        : Icons.folder_open,
                    color: color,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.selectedName ??
                              (_dragging
                                  ? 'Drop file here...'
                                  : drop
                                  ? 'Click to select or drag file here...'
                                  : 'Tap to select a file...'),
                          style: TextStyle(
                            color: _dragging
                                ? theme.accent
                                : selected
                                ? theme.textPrimary
                                : theme.textHint,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.description,
                          style: TextStyle(color: theme.textHint, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (selected && widget.onClear != null)
                    IconButton(
                      tooltip: 'Clear selection',
                      style: theme.compactIconButtonStyle,
                      onPressed: widget.enabled ? widget.onClear : null,
                      icon: const Icon(Icons.close, size: 20),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
