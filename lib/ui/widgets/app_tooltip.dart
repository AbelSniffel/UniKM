/// Custom tooltip widget with animations
/// Matches the original Python custom tooltip
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';

/// Custom tooltip with fade/slide animations
class AppTooltip extends ConsumerStatefulWidget {
  const AppTooltip({
    super.key,
    required this.message,
    required this.child,
    required this.theme,
    this.animation,
    this.showDelay,
    this.richMessage,
    this.preferBelow = true,
  });

  final String message;
  final Widget child;
  final AppThemeData theme;
  /// Optional override. When null, uses `SettingsKeys.tooltipAnimation`.
  final TooltipAnimation? animation;

  /// Optional override. When null, uses `SettingsKeys.tooltipShowDelay`.
  final int? showDelay;
  final InlineSpan? richMessage;
  final bool preferBelow;

  @override
  ConsumerState<AppTooltip> createState() => _AppTooltipState();
}

class _AppTooltipState extends ConsumerState<AppTooltip> {
  final _overlayController = OverlayPortalController();
  Timer? _showTimer;
  Timer? _hideTimer;
  final _link = LayerLink();

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  void _show() {
    _hideTimer?.cancel();
    final tooltipSettings = ref.read(tooltipSettingsProvider);
    final delayMs = widget.showDelay ?? tooltipSettings.showDelay;

    _showTimer = Timer(Duration(milliseconds: delayMs), () {
      if (mounted) {
        _overlayController.show();
      }
    });
  }

  void _hide() {
    _showTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: kTooltipHideDelay), () {
      if (mounted) {
        _overlayController.hide();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: _buildTooltip,
        child: MouseRegion(
          onEnter: (_) => _show(),
          onExit: (_) => _hide(),
          child: widget.child,
        ),
      ),
    );
  }

  Widget _buildTooltip(BuildContext context) {
    final tooltipSettings = ref.watch(tooltipSettingsProvider);
    final effectiveAnimation = widget.animation ?? tooltipSettings.animation;

    final tooltipContent = Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: widget.theme.surfaceElevated,
        borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
        border: Border.all(color: widget.theme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: widget.richMessage != null
          ? Text.rich(
              TextSpan(children: [widget.richMessage!]),
              style: TextStyle(color: widget.theme.textPrimary),
            )
          : Text(
              widget.message,
              style: TextStyle(color: widget.theme.textPrimary),
            ),
    );

    Widget animatedTooltip;
    if (effectiveAnimation == TooltipAnimation.fade) {
      animatedTooltip = tooltipContent.animate()
          .fadeIn(duration: const Duration(milliseconds: 150));
    } else {
      animatedTooltip = tooltipContent.animate()
          .fadeIn(duration: const Duration(milliseconds: 150))
          .slideY(
            begin: widget.preferBelow ? -0.2 : 0.2,
            end: 0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
    }

    return CompositedTransformFollower(
      link: _link,
      targetAnchor: widget.preferBelow ? Alignment.bottomCenter : Alignment.topCenter,
      followerAnchor: widget.preferBelow ? Alignment.topCenter : Alignment.bottomCenter,
      offset: Offset(0, widget.preferBelow ? kTooltipOffset : -kTooltipOffset),
      child: MouseRegion(
        onEnter: (_) {
          _hideTimer?.cancel();
        },
        onExit: (_) => _hide(),
        child: animatedTooltip,
      ),
    );
  }
}
