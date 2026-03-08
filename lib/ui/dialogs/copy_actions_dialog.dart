/// Dialog showing all available copy/redeem actions for selected games
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/game_clipboard.dart';
import '../../models/game.dart';
import '../../providers/app_providers.dart';

class CopyActionsDialog extends ConsumerWidget {
  const CopyActionsDialog({super.key, required this.targets});

  final List<Game> targets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final hasSteam = targets.any((g) => g.platform == 'Steam' && g.gameKey.isNotEmpty);

    Widget buildTile({required IconData icon, required String title, required VoidCallback onTap, Color? color}) {
      return ListTile(
        leading: Icon(icon, color: color ?? theme.textPrimary),
        title: Text(title, style: TextStyle(color: theme.textPrimary)),
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
      );
    }

    return AlertDialog(
      backgroundColor: theme.background,
      title: Text('Copy Options', style: TextStyle(color: theme.textPrimary)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            buildTile(
              icon: Icons.copy,
              title: 'Key Only',
              onTap: () => GameClipboard.copyKeysOnly(targets),
            ),
            buildTile(
              icon: Icons.copy,
              title: 'Title + Key',
              onTap: () => GameClipboard.copyTitleWithKey(targets),
            ),
            buildTile(
              icon: Icons.copy,
              title: 'Discord Spoiler',
              onTap: () => GameClipboard.copyDiscordSpoiler(targets),
            ),
            if (hasSteam) ...[
              const Divider(),
              buildTile(
                icon: Icons.link,
                title: 'Redeem Link Only',
                onTap: () => GameClipboard.copySteamLink(targets, includeTitle: false),
              ),
              buildTile(
                icon: Icons.link,
                title: 'Title + Redeem Link',
                onTap: () => GameClipboard.copySteamLink(targets, includeTitle: true),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        )
      ],
    );
  }
}
