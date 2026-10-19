import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'app_tag_chip.dart';

/// Options below the image card in both game editors.
class GameOptionsRow extends StatelessWidget {
  const GameOptionsRow({
    super.key,
    required this.theme,
    required this.isDlc,
    required this.onDlcChanged,
    required this.isUsed,
    required this.onUsedChanged,
    required this.deadline,
  });

  final AppThemeData theme;
  final bool isDlc;
  final ValueChanged<bool> onDlcChanged;
  final bool isUsed;
  final ValueChanged<bool> onUsedChanged;
  final Widget deadline;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      AppOptionChip(
        theme: theme,
        label: 'DLC',
        isSelected: isDlc,
        onTap: () => onDlcChanged(!isDlc),
      ),
      AppOptionChip(
        theme: theme,
        label: 'Used',
        isSelected: isUsed,
        onTap: () => onUsedChanged(!isUsed),
      ),
      deadline,
    ],
  );
}
