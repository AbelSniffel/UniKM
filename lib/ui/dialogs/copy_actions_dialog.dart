/// Dialog showing all available copy/redeem actions for selected games
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/game_clipboard.dart';
import '../../models/game.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/game_selection_actions.dart';
import '../widgets/tinted_tiles.dart';

Future<void> showCopyActionsDialog(BuildContext context, List<Game> targets) =>
    showAppDialog<void>(
      context: context,
      builder: (_) => CopyActionsDialog(targets: targets),
    );

class const CopyActionsDialog({super.key, required final List<Game> targets})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final redeemable = targets
        .where((g) => redeemPageUrl(g.platform, g.gameKey) != null)
        .length;
    // Outlives this dialog for the redeem notice's Mark as Used action.
    final container = ProviderScope.containerOf(context, listen: false);

    return ThemedAlertDialog(
      maxWidth: 440,
      title: DialogHeader(icon: Icons.copy, title: 'Copy Options'),
      contentSpacing: 16,
      contentChildren: [
        _ActionGroup('Keys', targets.length, [
          (
            Icons.key,
            'Key Only',
            'KEY',
            () => GameClipboard.copyKeysOnly(targets),
          ),
          (
            Icons.short_text,
            'Title + Key',
            'Title: KEY',
            () => GameClipboard.copyTitleWithKey(targets),
          ),
          (
            Icons.visibility_off_outlined,
            'Discord Spoiler',
            'Title: ||KEY||',
            () => GameClipboard.copyDiscordSpoiler(targets),
          ),
        ]),
        if (redeemable > 0)
          _ActionGroup('Redeem Links', redeemable, [
            (
              Icons.open_in_new,
              'Open Redeem Page',
              'Opens in your browser',
              () => GameSelectionActions.openRedeemPages(container, targets),
            ),
            (
              Icons.link,
              'Redeem Link Only',
              'https://…',
              () => GameClipboard.copyRedeemLink(targets),
            ),
            (
              Icons.add_link,
              'Title + Redeem Link',
              'Title: https://…',
              () => GameClipboard.copyRedeemLink(targets, includeTitle: true),
            ),
          ]),
      ],
    );
  }
}

/// One copy action: its icon, label, what it gives and what it does.
typedef _CopyAction = (
  IconData icon,
  String label,
  String format,
  VoidCallback run,
);

/// A titled list of tinted action tiles, with how many keys they cover.
class const _ActionGroup(
  final String title,
  final int count,
  final List<_CopyAction> actions,
) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 8,
    children: [
      TintedHeading(
        title: title,
        trailing: count == 1 ? '1 key' : '$count keys',
      ),
      for (final (icon, label, format, run) in actions)
        // Closes the dialog, then runs the action.
        TintedOptionTile(
          icon: icon,
          title: label,
          subtitle: format,
          onTap: () {
            Navigator.pop(context);
            run();
          },
        ),
    ],
  );
}
