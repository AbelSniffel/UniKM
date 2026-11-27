/// Reusable hover state builder widget.
library;

import 'package:material_ui/material_ui.dart';

/// A builder widget that provides hover state management.
///
/// This widget encapsulates the common hover pattern used throughout the app,
/// reducing boilerplate code and ensuring consistent hover behavior.
///
/// Example usage:
/// ```dart
/// HoverBuilder(
///   builder: (context, isHovered) => Container(
///     color: isHovered ? Colors.blue : Colors.grey,
///     child: Text('Hover me!'),
///   ),
/// )
/// ```
class const HoverBuilder({
  super.key,

  /// Builder function that receives the current hover state.
  required final Widget Function(BuildContext context, bool isHovered) builder,

  /// Optional callback when mouse enters the region.
  final VoidCallback? onEnter,

  /// Optional callback when mouse exits the region.
  final VoidCallback? onExit,

  /// The mouse cursor to use when hovering. Defaults to [SystemMouseCursors.basic].
  final MouseCursor cursor = SystemMouseCursors.basic,

  /// Whether hover detection is enabled. When false, [builder] always receives false.
  final bool enabled = true,
}) extends StatefulWidget {
  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _isHovered = false;

  void _onEnter(PointerEvent _) {
    if (!widget.enabled) return;
    setState(() => _isHovered = true);
    widget.onEnter?.call();
  }

  void _onExit(PointerEvent _) {
    if (!widget.enabled) return;
    setState(() => _isHovered = false);
    widget.onExit?.call();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.cursor,
    onEnter: widget.enabled ? _onEnter : null,
    onExit: widget.enabled ? _onExit : null,
    opaque: false,
    child: widget.builder(context, _isHovered && widget.enabled),
  );
}
