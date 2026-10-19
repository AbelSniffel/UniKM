import 'window_drop_target.dart';
import 'dart:io';
import 'dart:convert';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/services/platform_file_actions.dart';
import '../../core/theme/app_theme.dart';
import 'dialog_helpers.dart';
import 'corner_ribbon.dart';
import 'game_cover_image.dart';
import 'game_card_badges.dart';
import 'hover_builder.dart';
import 'notification_system.dart';
import 'used_overlay.dart';

/// A shared cover preview/editor. Image decoding stays inside GameCoverImage;
/// hovering and dragging only animate the frame around it.
class CoverImageCard extends StatefulWidget {
  const CoverImageCard({
    super.key,
    required this.theme,
    required this.controller,
    required this.onChanged,
    this.platformSelector,
    this.isDlc = false,
    this.isUsed = false,
    this.hasDeadline = false,
    this.deadlineDate,
  });

  final AppThemeData theme;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final Widget? platformSelector;
  final bool isDlc;
  final bool isUsed;
  final bool hasDeadline;
  final DateTime? deadlineDate;

  static const preferredWidth = 320.0;

  @override
  State<CoverImageCard> createState() => _CoverImageCardState();
}

class _CoverImageCardState extends State<CoverImageCard> {
  bool _dragging = false;
  bool _editing = false;
  int _selectionRevision = 0;

  Future<void> _editPath() async {
    if (_editing) return;
    final revision = ++_selectionRevision;
    final controller = widget.controller;
    setState(() => _editing = true);
    final path = await showAppDialog<String>(
      context: context,
      builder: (_) =>
          CoverPathDialog(theme: widget.theme, initialPath: controller.text),
    );
    if (!mounted) return;
    setState(() => _editing = false);
    if (path == null ||
        revision != _selectionRevision ||
        controller != widget.controller) {
      return;
    }
    controller.text = path;
    widget.onChanged();
  }

  Future<void> _acceptDrop(DropDoneDetails details) async {
    setState(() => _dragging = false);
    final revision = ++_selectionRevision;
    final controller = widget.controller;
    final paths = _droppedCoverPaths(details);
    if (paths.isEmpty) {
      NotificationManager.instance.error(
        'Could not read the dropped file. Click the cover to choose a JPG or PNG image.',
      );
      return;
    }
    if (paths.length != 1) {
      NotificationManager.instance.error('Drop one JPG or PNG image file.');
      return;
    }
    final path = paths.single;
    final valid = await _isCoverImageFile(path);
    if (!mounted ||
        revision != _selectionRevision ||
        controller != widget.controller) {
      return;
    }
    if (!valid) {
      NotificationManager.instance.error(
        'Cover images must be JPG or PNG files. This file was not added.',
      );
      return;
    }
    controller.text = path;
    widget.onChanged();
  }

  void _clearSelection() {
    ++_selectionRevision;
    widget.controller.clear();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final routeVisible = ModalRoute.of(context)?.isCurrent ?? true;
    return WindowDropTarget(
      enable:
          PlatformFileActions.supportsDragAndDrop && routeVisible && !_editing,
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _acceptDrop,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.controller,
        builder: (context, value, _) {
          final path = value.text.trim();
          final image = RepaintBoundary(
            child: GameCoverImage(theme: theme, coverImage: path),
          );
          return HoverBuilder(
            cursor: SystemMouseCursors.click,
            builder: (context, hovered) => AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(theme.cornerRadius),
                color: theme.surface,
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(theme.cornerRadius),
                border: Border.all(
                  color: _dragging || hovered ? theme.accent : theme.border,
                  width: _dragging || hovered ? 2 : 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: LayoutBuilder(
                  builder: (context, constraints) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (constraints.hasTightHeight)
                        Expanded(child: _buildPreview(theme, image, hovered))
                      else
                        AspectRatio(
                          aspectRatio: 2,
                          child: _buildPreview(theme, image, hovered),
                        ),
                      Tooltip(
                        message: path.isEmpty
                            ? 'Choose an image or drop JPG / PNG'
                            : path,
                        child: InkWell(
                          onTap: _editPath,
                          child: Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    path.isEmpty
                                        ? 'Choose an image or drop JPG / PNG'
                                        : path,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: theme.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              if (path.isNotEmpty)
                                IconButton(
                                  tooltip: 'Clear selection',
                                  style: theme.compactIconButtonStyle,
                                  onPressed: _editing ? null : _clearSelection,
                                  icon: const Icon(Icons.close, size: 18),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPreview(AppThemeData theme, Widget image, bool hovered) => Stack(
    fit: StackFit.expand,
    children: [
      image,
      if (widget.isUsed)
        LayoutBuilder(
          builder: (context, constraints) => UsedOverlay(
            key: const ValueKey('cover-used-overlay'),
            theme: theme,
            patternSize: constraints.biggest,
            gridView: true,
          ),
        ),
      Semantics(
        button: true,
        label: 'Change cover image',
        child: InkWell(
          key: const ValueKey('cover-image-edit'),
          onTap: _editPath,
          child: Center(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: hovered || _dragging ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(theme.cornerRadius),
                  ),
                  child: _dragging
                      ? Text(
                          'Drop JPG / PNG',
                          style: TextStyle(color: theme.textPrimary),
                        )
                      : Icon(Icons.edit_rounded, color: theme.accent, size: 28),
                ),
              ),
            ),
          ),
        ),
      ),
      if (widget.isDlc)
        Positioned(
          left: 0,
          top: 0,
          child: IgnorePointer(
            child: CornerRibbon(
              label: 'DLC',
              color: theme.accent,
              textColor: theme.primaryButtonText,
              bandHeight: 25,
              bandWidth: 162.5,
            ),
          ),
        ),
      if (widget.hasDeadline)
        Positioned(
          key: const ValueKey('cover-deadline-badge'),
          left: 8,
          bottom: 8,
          child: GameCardBadges.deadlineBadge(
            theme,
            widget.deadlineDate,
            showIcon: true,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minHeight: kBadgeHeight,
          ),
        ),
      if (widget.platformSelector != null)
        Positioned(
          right: 5,
          top: 5,
          child: Material(
            color: theme.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(theme.cornerRadius),
            child: widget.platformSelector,
          ),
        ),
    ],
  );
}

// Linux file managers may send a text/uri-list, a plain path, or duplicate
// representations of one file. Ignore transport noise, not additional files.
List<String> _droppedCoverPaths(DropDoneDetails details) {
  final paths = <String>{};
  void add(String raw) {
    final value = raw.replaceAll('\u0000', '').trim();
    if (value.isEmpty || value.startsWith('#')) return;
    try {
      final uri = Uri.tryParse(value);
      final path = uri?.scheme == 'file' ? uri!.toFilePath() : value;
      if (p.isAbsolute(path)) paths.add(p.normalize(path));
    } on FormatException {
      // Unsupported URI payloads cannot identify a local image file.
    } on UnsupportedError {
      // A remote file URI cannot be opened on this platform.
    }
  }

  for (final item in details.files) {
    add(item.path);
  }
  // A portal key is opaque (not an absolute path), so it is never mistaken
  // for a filename. The plugin resolves portal transfers before this callback.
  for (final line in const LineSplitter().convert(details.rawText ?? '')) {
    add(line);
  }
  return paths.toList(growable: false);
}

// Read only the signature, not the full image. Reject renamed text files and
// directories as well as unsupported extensions before replacing the path.
Future<bool> _isCoverImageFile(String path) async {
  final extension = path.split('.').last.toLowerCase();
  if (!['jpg', 'jpeg', 'png'].contains(extension)) return false;
  try {
    if (await FileSystemEntity.type(path) != FileSystemEntityType.file) {
      return false;
    }
    final file = await File(path).open();
    try {
      final bytes = await file.read(8);
      if (extension == 'png') {
        const signature = [137, 80, 78, 71, 13, 10, 26, 10];
        return bytes.length == 8 &&
            List.generate(8, (i) => bytes[i] == signature[i]).every((b) => b);
      }
      return bytes.length >= 3 &&
          bytes[0] == 255 &&
          bytes[1] == 216 &&
          bytes[2] == 255;
    } finally {
      await file.close();
    }
  } on FileSystemException {
    return false;
  }
}

class CoverPathDialog extends StatefulWidget {
  const CoverPathDialog({
    super.key,
    required this.theme,
    required this.initialPath,
  });
  final AppThemeData theme;
  final String initialPath;

  @override
  State<CoverPathDialog> createState() => _CoverPathDialogState();
}

class _CoverPathDialogState extends State<CoverPathDialog> {
  late final _controller = TextEditingController(text: widget.initialPath);
  String? _error;
  bool _picking = false;

  Future<void> _acceptDrop(DropDoneDetails details) async {
    final paths = _droppedCoverPaths(details);
    if (paths.length != 1 || !await _isCoverImageFile(paths.single)) {
      if (mounted) setState(() => _error = 'Drop one JPG or PNG image file.');
      return;
    }
    if (!mounted) return;
    _controller.text = paths.single;
    setState(() => _error = null);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    final path = _controller.text.trim();
    final uri = Uri.tryParse(path);
    final windowsPath = RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path);
    if (uri != null &&
        uri.hasScheme &&
        !windowsPath &&
        !['http', 'https', 'file'].contains(uri.scheme)) {
      setState(
        () => _error = 'Use a local file path or an HTTP/HTTPS image URL.',
      );
      return;
    }
    Navigator.pop(context, path);
  }

  Future<void> _browse() async {
    setState(() => _picking = true);
    try {
      final result = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Cover images (JPG/PNG)',
            extensions: ['jpg', 'jpeg', 'png'],
            mimeTypes: ['image/jpeg', 'image/png'],
            uniformTypeIdentifiers: ['public.jpeg', 'public.png'],
          ),
        ],
      );
      if (!mounted || result == null) return;
      final valid = await _isCoverImageFile(result.path);
      if (!mounted) return;
      if (!valid) {
        setState(() => _error = 'Choose a JPG or PNG image file.');
        return;
      }
      _controller.text = result.path;
      setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open the image picker.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) => DialogInteractionScope(
    onPrimaryAction: _picking ? null : _apply,
    onDismiss: () => Navigator.pop(context),
    child: WindowDropTarget(
      enable: PlatformFileActions.supportsDragAndDrop && !_picking,
      onDragDone: _acceptDrop,
      child: ThemedAlertDialog(
        theme: widget.theme,
        maxWidth: 480,
        title: DialogHeader(
          title: 'Cover Image Path',
          icon: Icons.image_outlined,
          theme: widget.theme,
        ),
        content: TextField(
          controller: _controller,
          autofocus: true,
          enabled: !_picking,
          style: TextStyle(color: widget.theme.textPrimary),
          decoration: InputDecoration(
            labelText: 'File path or image URL',
            hintText: 'https://… or /path/to/cover.png',
            errorText: _error,
            suffixIcon: IconButton(
              tooltip: 'Choose JPG or PNG file',
              onPressed: _picking ? null : _browse,
              icon: const Icon(Icons.folder_open),
            ),
          ),
          onSubmitted: (_) => _apply(),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _picking
                      ? null
                      : () {
                          _controller.clear();
                          _apply();
                        },
                  child: const Text('Remove Image'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _picking ? null : _apply,
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
