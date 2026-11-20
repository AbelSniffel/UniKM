import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import 'tinted_card.dart';
import 'tinted_tiles.dart';

/// Shared database and backup row: a [TintedOptionTile] with an encryption
/// icon and optional actions, raised while it takes taps. Missing files are
/// tinted orange; the [highlighted] row is tinted more strongly and pressed in.
class const DatabaseFileRow({
  super.key,
  required final String title,
  required final String subtitle,
  required final bool isEncrypted,
  final bool available = true,
  final bool highlighted = false,
  final VoidCallback? onTap,
  final List<Widget> actions = const [],
  final EdgeInsets margin = const EdgeInsets.only(bottom: 8),
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: TintedOptionTile(
      color: available ? context.appTheme.accent : Colors.orange,
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
          style: TintedCard.detailStyle(context.appTheme),
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
