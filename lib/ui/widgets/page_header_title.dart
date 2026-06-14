/// Shared page header title with icon and consistent styling.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';

class PageHeaderTitle extends StatelessWidget {
  const PageHeaderTitle({
    super.key,
    required this.title,
    required this.icon,
    required this.theme,
    this.showTitle = true,
    this.tooltip,
    this.iconColor,
    this.textColor,
  });

  final String title;
  final IconData icon;
  final AppThemeData theme;
  final bool showTitle;
  final String? tooltip;
  final Color? iconColor;
  final Color? textColor;

  static const double _iconSize = kIconSizeHeader;
  static const double _spacing = kElementHSpacing;
  static const double _fontSize = 20;

  @override
  Widget build(BuildContext context) {
    final resolvedIconColor = iconColor ?? theme.accent;
    final resolvedTextColor = textColor ?? theme.textPrimary;
    final iconWidget = Icon(icon, size: _iconSize, color: resolvedIconColor);
    final wrappedIcon = tooltip == null
        ? iconWidget
        : Tooltip(message: tooltip!, child: iconWidget);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        wrappedIcon,
        if (showTitle) ...[
          const SizedBox(width: _spacing),
          Text(
            title,
            style: TextStyle(
              color: resolvedTextColor,
              fontSize: _fontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ],
    );
  }
}