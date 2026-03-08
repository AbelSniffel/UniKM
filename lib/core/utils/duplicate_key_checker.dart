library;

import '../../models/game.dart';

class DuplicateKeyChecker {
  DuplicateKeyChecker._();

  static String normalize(String key) => key.toLowerCase().trim();

  static Map<String, Game> buildExistingKeyMap(Iterable<Game> existingGames) {
    final map = <String, Game>{};
    for (final game in existingGames) {
      map[normalize(game.gameKey)] = game;
    }
    return map;
  }

  static Game? findExistingByKey(
    String key,
    Iterable<Game> existingGames,
  ) {
    final normalized = normalize(key);
    for (final game in existingGames) {
      if (normalize(game.gameKey) == normalized) {
        return game;
      }
    }
    return null;
  }

  static Map<String, Game> findDuplicatesByInputKeys(
    Iterable<String> inputKeys,
    Iterable<Game> existingGames,
  ) {
    final existingByNormalizedKey = buildExistingKeyMap(existingGames);
    final duplicates = <String, Game>{};

    for (final inputKey in inputKeys) {
      final existing = existingByNormalizedKey[normalize(inputKey)];
      if (existing != null) {
        duplicates[inputKey] = existing;
      }
    }

    return duplicates;
  }
}
