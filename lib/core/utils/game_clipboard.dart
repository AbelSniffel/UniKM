/// Shared clipboard operations for game data
///
/// Consolidates duplicate copy methods from game_card.dart and home_page.dart.
library;

import 'package:flutter/services.dart';

import '../../models/game.dart';
import '../../ui/widgets/notification_system.dart';

/// Static helper for copying game data to clipboard.
class GameClipboard {
  GameClipboard._();

  /// Copy only the game keys, one per line.
  static void copyKeysOnly(List<Game> targets) {
    final keys = targets
        .map((g) => g.gameKey)
        .where((k) => k.isNotEmpty)
        .join('\n');
    if (keys.isEmpty) return;

    Clipboard.setData(ClipboardData(text: keys));
    _notifyCopy(targets.length, 'key');
  }

  /// Copy "Title: Key" pairs, one per line.
  static void copyTitleWithKey(List<Game> targets) {
    final text = targets
        .where((g) => g.gameKey.isNotEmpty)
        .map((g) => '${g.title}: ${g.gameKey}')
        .join('\n');

    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    _notifyCopy(targets.length, 'title with key');
  }

  /// Copy "Title: ||Key||" (Discord spoiler format), one per line.
  static void copyDiscordSpoiler(List<Game> targets) {
    final text = targets
        .where((g) => g.gameKey.isNotEmpty)
        .map((g) => '${g.title}: ||${g.gameKey}||')
        .join('\n');

    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    _notifyCopy(targets.length, 'Discord spoiler');
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

    final lines = <String>[];
    for (final g in steamTargets) {
      final url =
          'https://store.steampowered.com/account/registerkey?key=${g.gameKey}';
      if (includeTitle) {
        lines.add('${g.title}: $url');
      } else {
        lines.add(url);
      }
    }

    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    _notifyCopy(lines.length, 'Steam redemption link');
  }

  static void _notifyCopy(int count, String type) {
    if (count == 1) {
      NotificationManager.instance.success('Copied $type');
    } else {
      NotificationManager.instance.success('Copied $count ${type}s');
    }
  }
}
