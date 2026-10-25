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

    Widget buildTile({required String title, required VoidCallback onTap}) {
      return ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(theme.cornerRadius),
        ),
        title: Text(title, style: TextStyle(color: theme.textPrimary)),
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
      );
    }

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
            SectionGroupBox(
              title: 'Keys',
              titleIcon: Icons.key,
              titleLocation: SectionTitleLocation.top,
              theme: theme,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  buildTile(
                    title: 'Key Only',
                    onTap: () => GameClipboard.copyKeysOnly(targets),
                  ),
                  buildTile(
                    title: 'Title + Key',
                    onTap: () => GameClipboard.copyTitleWithKey(targets),
                  ),
                  buildTile(
                    title: 'Discord Spoiler',
                    onTap: () => GameClipboard.copyDiscordSpoiler(targets),
                  ),
                ],
              ),
            ),
            if (hasSteam) ...[
              const SizedBox(height: kDialogSpacing),
              SectionGroupBox(
                title: 'Redeem Links',
                titleIcon: Icons.link,
                titleLocation: SectionTitleLocation.top,
                theme: theme,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    buildTile(
                      title: 'Redeem Link Only',
                      onTap: () => GameClipboard.copySteamLink(
                        targets,
                        includeTitle: false,
                      ),
                    ),
                    buildTile(
                      title: 'Title + Redeem Link',
                      onTap: () => GameClipboard.copySteamLink(
                        targets,
                        includeTitle: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
