/// The app's scrollbar: styled by the scrollbar theme, with a track that follows
/// its corner radius (Material's [Scrollbar] always paints a rectangle) and
/// fades in while the thumb is hovered or dragged.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class AppScrollbar extends RawScrollbar {
  const AppScrollbar({
    super.key,
    required super.child,
    super.controller,
    super.thumbVisibility,
  });

  @override
  RawScrollbarState<AppScrollbar> createState() => _AppScrollbarState();
}

/// Gives every implicit desktop scrollbar (lists, grids, scroll views) the
/// [AppScrollbar] look.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => switch (getPlatform(context)) {
    TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows =>
      AppScrollbar(controller: details.controller, child: child),
    _ => super.buildScrollbar(context, child, details),
  };
}

class _AppScrollbarState extends RawScrollbarState<AppScrollbar> {
  // 0 idle, 1 hovered or dragged. The painter repaints on its own as this
  // runs, so nothing rebuilds.
  late final _emphasis = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..addListener(updateScrollbarPainter);
  bool _hovered = false;
  bool _dragged = false;

  void _setEmphasis({bool? hovered, bool? dragged}) {
    _hovered = hovered ?? _hovered;
    _dragged = dragged ?? _dragged;
    _hovered || _dragged ? _emphasis.forward() : _emphasis.reverse();
  }

  @override
  void updateScrollbarPainter() {
    super.updateScrollbarPainter();
    final theme = ScrollbarTheme.of(context);
    final active = {_dragged ? WidgetState.dragged : WidgetState.hovered};
    final track = theme.trackColor?.resolve(active) ?? Colors.transparent;
    scrollbarPainter
      ..color =
          Color.lerp(
            theme.thumbColor?.resolve({}),
            theme.thumbColor?.resolve(active),
            _emphasis.value,
          ) ??
          const Color(0x66BCBCBC)
      ..trackColor = track.withValues(alpha: track.a * _emphasis.value)
      ..trackBorderColor = Colors.transparent
      ..radius = theme.radius
      ..trackRadius = theme.radius
      ..thickness = theme.thickness?.resolve({}) ?? 8
      ..crossAxisMargin = theme.crossAxisMargin ?? 2
      ..mainAxisMargin = theme.mainAxisMargin ?? 0
      ..minLength = theme.minThumbLength ?? 48;
  }

  @override
  void handleThumbPressStart(Offset localPosition) {
    super.handleThumbPressStart(localPosition);
    _setEmphasis(dragged: true);
  }

  @override
  void handleThumbPressEnd(Offset localPosition, Velocity velocity) {
    super.handleThumbPressEnd(localPosition, velocity);
    _setEmphasis(dragged: false);
  }

  @override
  void handleHover(PointerHoverEvent event) {
    super.handleHover(event);
    _setEmphasis(
      hovered: isPointerOverScrollbar(
        event.position,
        event.kind,
        forHover: true,
      ),
    );
  }

  @override
  void handleHoverExit(PointerExitEvent event) {
    super.handleHoverExit(event);
    _setEmphasis(hovered: false);
  }

  @override
  void dispose() {
    _emphasis.dispose();
    super.dispose();
  }
}
