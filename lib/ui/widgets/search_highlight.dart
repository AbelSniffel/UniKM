import 'dart:async';

import 'package:flutter/material.dart';

/// Briefly highlights a settings search match, then fades without unmounting it.
class SearchHighlight extends StatefulWidget {
  const SearchHighlight({
    super.key,
    required this.query,
    required this.isMatch,
    required this.builder,
  });

  final String query;
  final bool isMatch;
  final Widget Function(BuildContext context, double value) builder;

  @override
  State<SearchHighlight> createState() => _SearchHighlightState();
}

class _SearchHighlightState extends State<SearchHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _fadeTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
      value: 0,
    );
    _syncHighlight();
  }

  @override
  void didUpdateWidget(covariant SearchHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query ||
        oldWidget.isMatch != widget.isMatch) {
      _syncHighlight();
    }
  }

  void _syncHighlight() {
    _fadeTimer?.cancel();
    if (widget.query.trim().isEmpty || !widget.isMatch) {
      _controller.animateTo(0);
      return;
    }
    _controller.value = 1;
    _fadeTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) _controller.animateTo(0);
    });
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => widget.builder(
      context,
      Curves.easeOutCubic.transform(_controller.value),
    ),
  );
}
