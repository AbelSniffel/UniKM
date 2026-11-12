import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'tinted_card.dart';
import 'tinted_tiles.dart';

/// Shared database and backup row: a [TintedOptionTile] with an encryption
/// icon and optional actions, raised while it takes taps. Missing files are
/// tinted orange; the [highlighted] row is tinted more strongly and pressed in.
class DatabaseFileRow extends StatelessWidget {
  const DatabaseFileRow({
    super.key,
    required this.theme,
    required this.title,
    required this.subtitle,
    required this.isEncrypted,
    this.available = true,
    this.highlighted = false,
    this.onTap,
    this.actions = const [],
    this.margin = const EdgeInsets.only(bottom: 8),
  });

  final AppThemeData theme;
  final String title;
  final String subtitle;
  final bool isEncrypted;
  final bool available;
  final bool highlighted;
  final VoidCallback? onTap;
  final List<Widget> actions;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: TintedOptionTile(
      theme: theme,
      color: available ? theme.accent : Colors.orange,
      icon: !available
          ? Icons.warning_amber
          : isEncrypted
          ? Icons.lock
          : Icons.lock_open,
      title: title,
      details: Tooltip(
        message: subtitle,
        child: Text(
          subtitle,
          style: TintedCard.detailStyle(theme),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      trailing: actions.isEmpty
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: actions),
      highlighted: highlighted,
      onTap: available ? onTap : null,
    ),
  );
}
