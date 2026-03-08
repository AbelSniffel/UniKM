/// Native animated game card widget (replaces flutter_animate for entry animations)
/// Only animates once on initial build, then displays static content
library;

import 'package:flutter/material.dart';

class AnimatedGameCard extends StatefulWidget {
  const AnimatedGameCard({
    super.key,
    required this.child,
    required this.delay,
    this.slideX = false,
  });

  final Widget child;
  final Duration delay;
  final bool slideX; // true for list view (slide X), false for grid (scale)

  @override
  State<AnimatedGameCard> createState() => _AnimatedGameCardState();
}

class _AnimatedGameCardState extends State<AnimatedGameCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _transformAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _transformAnimation = widget.slideX
        ? Tween<double>(begin: 0.05, end: 0.0).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOut),
          )
        : Tween<double>(begin: 0.9, end: 1.0).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOut),
          );

    // Start animation after delay
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Capture the width ONCE per layout pass outside the AnimatedBuilder so
    // animations don't re-subscribe to every MediaQuery change on each frame.
    // MediaQuery.sizeOf is also cheaper: it only rebuilds on size changes,
    // not on unrelated MediaQuery field changes (text scale, padding, etc.).
    final slideWidth =
        widget.slideX ? MediaQuery.sizeOf(context).width : 0.0;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final transform = widget.slideX
            ? Matrix4.translationValues(
                _transformAnimation.value * slideWidth,
                0,
                0,
              )
            : Matrix4.diagonal3Values(
                _transformAnimation.value,
                _transformAnimation.value,
                1.0,
              );

        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform(
            transform: transform,
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
