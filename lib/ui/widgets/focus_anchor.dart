import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Holds keyboard focus whenever focus falls back to the page itself, as
/// after a text field lets go or a focused control goes away. Shortcuts only
/// reach the focused widget and those around it, so the page alone would
/// pass keys by every shortcut inside it.
class FocusAnchor extends StatefulWidget {
  const FocusAnchor({super.key, required this.child, this.onKeyEvent});

  final Widget child;
  final FocusOnKeyEventCallback? onKeyEvent;

  @override
  State<FocusAnchor> createState() => _FocusAnchorState();
}

class _FocusAnchorState extends State<FocusAnchor> {
  final _node = FocusNode(debugLabel: 'FocusAnchor');

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_holdFocus);
  }

  void _holdFocus() {
    final primary = FocusManager.instance.primaryFocus;
    // Only this page's own scopes: a dialog's keeps its focus.
    if (primary == null ||
        primary is FocusScopeNode && _node.ancestors.contains(primary)) {
      if (_node.context != null) _node.requestFocus();
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_holdFocus);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _node,
    autofocus: true,
    onKeyEvent: widget.onKeyEvent,
    child: widget.child,
  );
}

/// Lets a text field go when a click lands outside it, as Flutter does, but
/// only once the click has been handled: whatever the click focused, such
/// as the game list, keeps that focus instead of the page taking it.
class DeferredTapOutsideAction
    extends ContextAction<EditableTextTapOutsideIntent> {
  @override
  void invoke(EditableTextTapOutsideIntent intent, [BuildContext? context]) {
    // Like Flutter's own action, a touch leaves the field focused on phones.
    final mobile = switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => true,
      _ => false,
    };
    if (mobile &&
        !kIsWeb &&
        intent.pointerDownEvent.kind == PointerDeviceKind.touch) {
      return;
    }
    // Focus the click requested is applied in a microtask queued before
    // this one.
    final node = intent.focusNode;
    scheduleMicrotask(() {
      if (node.hasFocus) node.unfocus();
    });
  }
}
