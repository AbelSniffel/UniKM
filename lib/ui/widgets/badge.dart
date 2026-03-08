/// Badge system for adding badges to any widget
/// Matches the original Python badge system with 5 positions
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Badge position options
enum BadgePosition {
  topRight,
  topLeft,
  bottomRight,
  bottomLeft,
  centerRight,
}

/// Badge type options
enum BadgeType {
  text,
  count,
  dot,
}

/// Badge widget that can be added to any widget
class Badge extends StatelessWidget {
  const Badge({
    super.key,
    required this.child,
    this.label,
    this.count,
    this.type = BadgeType.text,
    this.position = BadgePosition.topRight,
    this.backgroundColor,
    this.textColor,
    this.showBadge = true,
    this.theme,
    this.fit = StackFit.loose,
  });

  /// The widget to add the badge to
  final Widget child;
  
  /// Text label for text badges
  final String? label;
  
  /// Count for count badges
  final int? count;
  
  /// Type of badge
  final BadgeType type;
  
  /// Position of the badge
  final BadgePosition position;
  
  /// Background color (uses theme accent if not specified)
  final Color? backgroundColor;
  
  /// Text color (uses contrasting color if not specified)
  final Color? textColor;
  
  /// Whether to show the badge
  final bool showBadge;
  
  /// Theme for styling
  final AppThemeData? theme;

  /// Stack fit for the badge container
  final StackFit fit;

  @override
  Widget build(BuildContext context) {
    if (!showBadge) return child;
    
    // Hide count badges with count <= 0
    if (type == BadgeType.count && (count == null || count! <= 0)) {
      return child;
    }
    
    return Stack(
      clipBehavior: Clip.none,
      fit: fit,
      children: [
        child,
        Positioned(
          top: _getTop(),
          bottom: _getBottom(),
          left: _getLeft(),
          right: _getRight(),
          child: _buildBadge(context),
        ),
      ],
    );
  }

  double? _getTop() {
    switch (position) {
      case BadgePosition.topRight:
      case BadgePosition.topLeft:
        return -6;
      case BadgePosition.centerRight:
        return null;
      case BadgePosition.bottomRight:
      case BadgePosition.bottomLeft:
        return null;
    }
  }

  double? _getBottom() {
    switch (position) {
      case BadgePosition.topRight:
      case BadgePosition.topLeft:
        return null;
      case BadgePosition.centerRight:
        return null;
      case BadgePosition.bottomRight:
      case BadgePosition.bottomLeft:
        return -6;
    }
  }

  double? _getLeft() {
    switch (position) {
      case BadgePosition.topRight:
      case BadgePosition.bottomRight:
      case BadgePosition.centerRight:
        return null;
      case BadgePosition.topLeft:
      case BadgePosition.bottomLeft:
        return -6;
    }
  }

  double? _getRight() {
    switch (position) {
      case BadgePosition.topRight:
      case BadgePosition.bottomRight:
        return -6;
      case BadgePosition.centerRight:
        return -10;
      case BadgePosition.topLeft:
      case BadgePosition.bottomLeft:
        return null;
    }
  }

  Widget _buildBadge(BuildContext context) {
    final bgColor = backgroundColor ?? 
        theme?.accent ?? 
        Theme.of(context).colorScheme.primary;
    
    final fgColor = textColor ?? 
        (bgColor.computeLuminance() > 0.5 ? Colors.black : Colors.white);

    switch (type) {
      case BadgeType.dot:
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: theme?.surface ?? Theme.of(context).scaffoldBackgroundColor,
              width: 1.5,
            ),
          ),
        );
        
      case BadgeType.count:
        final displayCount = count! > 99 ? '99+' : count.toString();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          constraints: const BoxConstraints(minWidth: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme?.surface ?? Theme.of(context).scaffoldBackgroundColor,
              width: 1.5,
            ),
          ),
          child: Text(
            displayCount,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: fgColor,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
        
      case BadgeType.text:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme?.surface ?? Theme.of(context).scaffoldBackgroundColor,
              width: 1.5,
            ),
          ),
          child: Text(
            label ?? '',
            style: TextStyle(
              color: fgColor,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
    }
  }
}

/// Extension to easily add badges to any widget
extension BadgeExtension on Widget {
  /// Add a text badge
  Widget withTextBadge(
    String text, {
    BadgePosition position = BadgePosition.topRight,
    Color? backgroundColor,
    Color? textColor,
    bool show = true,
    AppThemeData? theme,
  }) {
    return Badge(
      label: text,
      type: BadgeType.text,
      position: position,
      backgroundColor: backgroundColor,
      textColor: textColor,
      showBadge: show,
      theme: theme,
      child: this,
    );
  }

  /// Add a count badge
  Widget withCountBadge(
    int count, {
    BadgePosition position = BadgePosition.topRight,
    Color? backgroundColor,
    Color? textColor,
    bool show = true,
    AppThemeData? theme,
    StackFit fit = StackFit.loose,
  }) {
    return Badge(
      count: count,
      type: BadgeType.count,
      position: position,
      backgroundColor: backgroundColor,
      textColor: textColor,
      showBadge: show,
      theme: theme,
      fit: fit,
      child: this,
    );
  }

  /// Add a dot badge
  Widget withDotBadge({
    BadgePosition position = BadgePosition.topRight,
    Color? backgroundColor,
    bool show = true,
    AppThemeData? theme,
  }) {
    return Badge(
      type: BadgeType.dot,
      position: position,
      backgroundColor: backgroundColor,
      showBadge: show,
      theme: theme,
      child: this,
    );
  }
}
