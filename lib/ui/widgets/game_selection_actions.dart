/// Shared game-card action handlers used by both [GameCard] and [SelectionRibbon].
///
/// All methods accept an explicit [targets] list so each call site can determine
/// its own scope (single card vs. all selected games) independently.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import '../../providers/app_providers.dart';
import '../dialogs/copy_actions_dialog.dart';
import '../dialogs/delete_games_dialog.dart';
import '../dialogs/game_editor_dialog.dart';
import '../dialogs/steam_lookup_dialog.dart';
import '../widgets/notification_system.dart';

abstract final class GameSelectionActions {
  static bool _syncOperationLocked(WidgetRef ref, {required String action}) {
    if (!ref.read(deviceSyncServiceProvider).isReceiverSyncInFlight) {
      return false;
    }
    NotificationManager.instance.warning(
      'Cannot $action while device sync is in progress',
    );
    return true;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Details
  // ───────────────────────────────────────────────────────────────────────────

  /// Opens the Game Editor dialog for [targets], or all currently-selected
  /// games when [targets] is omitted.
  ///
  /// [initialGame] is the game to show first (defaults to [targets.first]).
  static void openDetails(
    BuildContext context,
    WidgetRef ref, {
    required List<Game> targets,
    Game? initialGame,
  }) {
    if (_syncOperationLocked(ref, action: 'edit games')) return;
    if (ref.read(batchFetchProvider).isActive) {
      NotificationManager.instance.info(
        'Please wait for the Steam fetch to complete before opening Game Editor',
      );
      return;
    }
    if (targets.isEmpty) {
      NotificationManager.instance.info('No games selected');
      return;
    }

    showGameEditorDialog(
      context,
      initialGame ?? targets.first,
      gameIds: [for (final game in targets) game.id],
      onViewedGame: (gameId) => markGameAsViewed(ref, gameId),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Copy
  // ───────────────────────────────────────────────────────────────────────────

  static void showCopyDialog(
    BuildContext context,
    WidgetRef ref,
    List<Game> targets,
  ) {
    if (targets.isEmpty) {
      NotificationManager.instance.info('No games selected');
      return;
    }
    showCopyActionsDialog(context, targets);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Steam page
  // ───────────────────────────────────────────────────────────────────────────

  static Future<void> openSteamPages(WidgetRef ref, List<Game> targets) async {
    if (targets.isEmpty) {
      NotificationManager.instance.info('No Steam games selected');
      return;
    }

    for (final game in targets) {
      final url = game.steamAppId.isNotEmpty
          ? Uri.parse(steamAppPageUrl(game.steamAppId))
          : Uri.parse(steamSearchPageUrl(game.title));

      try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } catch (_) {
        NotificationManager.instance.error(
          'Failed to open Steam page for ${game.title}',
        );
      }
    }

    NotificationManager.instance.info(
      targets.length == 1
          ? 'Opened Steam page for ${targets.first.title}'
          : 'Opened Steam pages for ${targets.length} games',
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Steam data fetch
  // ───────────────────────────────────────────────────────────────────────────

  static Future<void> fetchSteamData(
    BuildContext context,
    WidgetRef ref,
    List<Game> targets,
  ) async {
    final steamTargets = targets.where((g) => g.platform == 'Steam').toList();

    if (steamTargets.isEmpty) {
      NotificationManager.instance.info('No Steam games selected');
      return;
    }

    if (ref.read(batchFetchProvider).isActive) {
      NotificationManager.instance.info('A fetch is already in progress');
      return;
    }

    await (steamTargets.length == 1
        ? performSingleSteamLookup(context, ref, steamTargets.first)
        : performSteamBatchLookup(context, steamTargets));
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Toggle used
  // ───────────────────────────────────────────────────────────────────────────

  static Future<void> toggleUsed(
    WidgetRef ref,
    List<Game> targets,
    bool nextValue,
  ) async {
    if (_syncOperationLocked(ref, action: 'edit games')) return;
    if (ref.read(batchFetchProvider).isActive) {
      NotificationManager.instance.warning(
        'Cannot edit games while Steam data fetch is in progress',
      );
      return;
    }

    final ok = await ref
        .read(gamesProvider.notifier)
        .setGamesUsed(targets.map((g) => g.id).toList(), nextValue);

    if (!ok) {
      final error = ref.read(gamesProvider.select((s) => s.error));
      NotificationManager.instance.error(error ?? 'Failed to update games');
      return;
    }

    final status = nextValue ? 'used' : 'unused';
    NotificationManager.instance.info(
      targets.length == 1
          ? 'Marked as $status'
          : 'Marked ${targets.length} games as $status',
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Delete
  // ───────────────────────────────────────────────────────────────────────────

  static Future<void> deleteGames(
    BuildContext context,
    WidgetRef ref,
    AppThemeData theme,
    List<Game> targets,
  ) async {
    if (_syncOperationLocked(ref, action: 'delete games')) return;
    if (ref.read(batchFetchProvider).isActive) {
      NotificationManager.instance.warning(
        'Cannot delete games while Steam data fetch is in progress',
      );
      return;
    }

    if (targets.isEmpty) return;
    final confirmed = await showDeleteGamesDialog(
      context,
      theme,
      targets.length,
      gameTitle: targets.length == 1 ? targets.first.title : null,
    );
    if (!confirmed) return;

    final ids = targets.map((g) => g.id).toList();
    final ok = await ref.read(gamesProvider.notifier).deleteGames(ids);

    if (!ok) {
      final error = ref.read(gamesProvider.select((s) => s.error));
      NotificationManager.instance.error(error ?? 'Failed to delete games');
      return;
    }

    NotificationManager.instance.success(
      targets.length == 1
          ? 'Deleted: ${targets.first.title}'
          : 'Deleted ${targets.length} games',
    );
  }
}
