/// Dialog showing all available copy/redeem actions for selected games
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/game_clipboard.dart';
import '../../core/settings/settings_model.dart';
import '../../models/game.dart';
import '../../providers/app_providers.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/section_groupbox.dart';

Future<void> showCopyActionsDialog(BuildContext context, List<Game> targets) =>
    showAppDialog<void>(
      context: context,
      builder: (_) => CopyActionsDialog(targets: targets),
    );

class CopyActionsDialog extends ConsumerWidget {
  const CopyActionsDialog({super.key, required this.targets});

  final List<Game> targets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final hasSteam = targets.any(
      (g) => g.platform == 'Steam' && g.gameKey.isNotEmpty,
    );

    // A groupbox of copy actions; each closes the dialog, then copies.
    Widget group(
      String title,
      IconData icon,
      List<(String, VoidCallback)> actions,
    ) => SectionGroupBox(
      title: title,
      titleIcon: icon,
      titleLocation: SectionTitleLocation.top,
      theme: theme,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (label, copy) in actions)
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(theme.cornerRadius),
              ),
              title: Text(label, style: TextStyle(color: theme.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                copy();
              },
            ),
        ],
      ),
    );

    return ThemedAlertDialog(
      theme: theme,
      title: DialogHeader(
        icon: Icons.copy,
        title: 'Copy Options',
        theme: theme,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            group('Keys', Icons.key, [
              ('Key Only', () => GameClipboard.copyKeysOnly(targets)),
              ('Title + Key', () => GameClipboard.copyTitleWithKey(targets)),
              (
                'Discord Spoiler',
                () => GameClipboard.copyDiscordSpoiler(targets),
              ),
            ]),
            if (hasSteam) ...[
              const SizedBox(height: kDialogSpacing),
              group('Redeem Links', Icons.link, [
                (
                  'Redeem Link Only',
                  () =>
                      GameClipboard.copySteamLink(targets, includeTitle: false),
                ),
                (
                  'Title + Redeem Link',
                  () =>
                      GameClipboard.copySteamLink(targets, includeTitle: true),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
