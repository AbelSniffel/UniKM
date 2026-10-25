/// Reusable hover state builder widget
///
/// Eliminates the repeated pattern of:
/// - bool _isHovered = false;
/// - MouseRegion with onEnter/onExit setState calls
library;

import 'package:flutter/material.dart';

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
class HoverBuilder extends StatefulWidget {
  const HoverBuilder({
    super.key,
    required this.builder,
    this.onEnter,
    this.onExit,
    this.cursor = SystemMouseCursors.basic,
    this.enabled = true,
  });

  /// Builder function that receives the current hover state.
  final Widget Function(BuildContext context, bool isHovered) builder;

  /// Optional callback when mouse enters the region.
  final VoidCallback? onEnter;

  /// Optional callback when mouse exits the region.
  final VoidCallback? onExit;

  /// The mouse cursor to use when hovering. Defaults to [SystemMouseCursors.basic].
  final MouseCursor cursor;

  /// Whether hover detection is enabled. When false, [builder] always receives false.
  final bool enabled;

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
