/// Shared clipboard operations for game data
///
/// Consolidates duplicate copy methods from game_card.dart and home_page.dart.
library;

import '../../core/constants/app_constants.dart';
import '../../core/services/key_privacy.dart';
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
    KeyPrivacy.copy(text);
    _notifyCopy(targets.length, type);
  }

  /// Copy redeem links for Steam and GOG keys.
  static void copyRedeemLink(List<Game> targets, {bool includeTitle = false}) {
    final links = [
      for (final game in targets)
        if (redeemPageUrl(game.platform, game.gameKey) case final url?)
          includeTitle ? '${game.title}: $url' : url,
    ];
    if (links.isEmpty) {
      NotificationManager.instance.info('No Steam or GOG keys selected');
      return;
    }
    KeyPrivacy.copy(links.join('\n'));
    _notifyCopy(links.length, 'redeem link');
  }

  static void _notifyCopy(int count, String type) {
    if (count == 1) {
      NotificationManager.instance.success('Copied $type');
    } else {
      NotificationManager.instance.success('Copied $count ${type}s');
    }
  }
}
