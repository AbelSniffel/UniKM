import 'package:material_ui/material_ui.dart';

import 'app_action_button.dart';

/// Options below the image card in both game editors.
class const GameOptionsRow({
  super.key,
  required final bool isDlc,
  required final ValueChanged<bool> onDlcChanged,
  required final bool isUsed,
  required final ValueChanged<bool> onUsedChanged,
  required final Widget deadline,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppActionButton(
          label: 'DLC',
          selected: isDlc,
          onTap: () => onDlcChanged(!isDlc),
        ),
        AppActionButton(
          label: 'Used',
          selected: isUsed,
          onTap: () => onUsedChanged(!isUsed),
        ),
        deadline,
      ],
    );
  }
}
