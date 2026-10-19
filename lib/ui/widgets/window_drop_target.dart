import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';

/// Receives file drops anywhere in the window while this area is active.
/// The most recently mounted visible target owns the drop, so dialogs take
/// precedence and retained tabs or pages cannot import the same file twice.
class WindowDropTarget extends StatefulWidget {
  const WindowDropTarget({
    super.key,
    required this.child,
    this.enable = true,
    this.onDragEntered,
    this.onDragExited,
    this.onDragDone,
  });

  final Widget child;
  final bool enable;
  final OnDragCallback<DropEventDetails>? onDragEntered;
  final OnDragCallback<DropEventDetails>? onDragExited;
  final OnDragDoneCallback? onDragDone;

  @override
  State<WindowDropTarget> createState() => _WindowDropTargetState();
}

class _WindowDropTargetState extends State<WindowDropTarget> {
  static final _targets = <_WindowDropTargetState>[];
  static _WindowDropTargetState? _dragging;

  @override
  void initState() {
    super.initState();
    if (_targets.isEmpty) {
      DesktopDrop.instance.init();
      DesktopDrop.instance.addRawDropEventListener(_dispatch);
    }
    _targets.add(this);
  }

  bool get _active {
    if (!mounted ||
        !widget.enable ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    var visible = true;
    context.visitAncestorElements((element) {
      final ancestor = element.widget;
      if (ancestor is Offstage && ancestor.offstage ||
          ancestor is IgnorePointer && ancestor.ignoring ||
          ancestor is AbsorbPointer && ancestor.absorbing) {
        visible = false;
        return false;
      }
      return true;
    });
    return visible;
  }

  static void _dispatch(DropEvent event) {
    final target = _targets.reversed.where((t) => t._active).firstOrNull;
    final previous = _dragging;
    if (previous != null &&
        (previous != target ||
            event is DropExitEvent ||
            event is DropDoneEvent)) {
      _dragging = null;
      if (previous.mounted) {
        previous.widget.onDragExited?.call(previous._details(event));
      }
    }
    if (target == null || event is DropExitEvent) return;
    if (event is DropDoneEvent) {
      final details = target._details(event);
      target.widget.onDragDone?.call(
        DropDoneDetails(
          files: event.files,
          localPosition: details.localPosition,
          globalPosition: details.globalPosition,
          rawText: event.rawText,
        ),
      );
    } else if (_dragging != target) {
      _dragging = target;
      target.widget.onDragEntered?.call(target._details(event));
    }
  }

  DropEventDetails _details(DropEvent event) {
    final point = Platform.isWindows || Platform.isAndroid
        ? event.location / MediaQuery.devicePixelRatioOf(context)
        : event.location;
    final box = context.findRenderObject();
    return DropEventDetails(
      globalPosition: point,
      localPosition: box is RenderBox ? box.globalToLocal(point) : point,
    );
  }

  @override
  void dispose() {
    if (_dragging == this) _dragging = null;
    _targets.remove(this);
    if (_targets.isEmpty) {
      DesktopDrop.instance.removeRawDropEventListener(_dispatch);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
