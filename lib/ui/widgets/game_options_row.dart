import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'app_action_button.dart';

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
      AppActionButton(
        theme: theme,
        label: 'DLC',
        selected: isDlc,
        onTap: () => onDlcChanged(!isDlc),
      ),
      AppActionButton(
        theme: theme,
        label: 'Used',
        selected: isUsed,
        onTap: () => onUsedChanged(!isUsed),
      ),
      deadline,
    ],
  );
}
