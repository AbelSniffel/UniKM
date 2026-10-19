/// Shared clipboard operations for game data
///
/// Consolidates duplicate copy methods from game_card.dart and home_page.dart.
library;

import 'package:flutter/services.dart';

import '../../core/constants/app_constants.dart';
import '../../models/game.dart';
import '../../ui/widgets/notification_system.dart';

/// Static helper for copying game data to clipboard.
class GameClipboard {
  GameClipboard._();

  /// Copy only the game keys, one per line.
  static void copyKeysOnly(List<Game> targets) =>
      _copy(targets, (game) => game.gameKey, 'key');

  /// Copy "Title: Key" pairs, one per line.
  static void copyTitleWithKey(List<Game> targets) => _copy(
    targets,
    (game) => '${game.title}: ${game.gameKey}',
    'title with key',
  );

  /// Copy "Title: ||Key||" (Discord spoiler format), one per line.
  static void copyDiscordSpoiler(List<Game> targets) => _copy(
    targets,
    (game) => '${game.title}: ||${game.gameKey}||',
    'Discord spoiler',
  );

  static void _copy(
    List<Game> targets,
    String Function(Game) format,
    String type,
  ) {
    final text = targets
        .where((game) => game.gameKey.isNotEmpty)
        .map(format)
        .join('\n');
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    _notifyCopy(targets.length, type);
  }

  /// Copy Steam redemption links for Steam-platform games.
  static void copySteamLink(List<Game> targets, {bool includeTitle = false}) {
    final steamTargets = targets
        .where((g) => g.platform == 'Steam' && g.gameKey.isNotEmpty)
        .toList();
    if (steamTargets.isEmpty) {
      NotificationManager.instance.info('No Steam games with keys selected');
      return;
    }

    _copy(steamTargets, (game) {
      final url = steamRegisterKeyPageUrl(game.gameKey);
      return includeTitle ? '${game.title}: $url' : url;
    }, 'Steam redemption link');
  }

  static void _notifyCopy(int count, String type) {
    if (count == 1) {
      NotificationManager.instance.success('Copied $type');
    } else {
      NotificationManager.instance.success('Copied $count ${type}s');
    }
  }
}
