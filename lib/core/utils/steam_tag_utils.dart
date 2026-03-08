library;

import '../../models/game.dart';
import '../database/database.dart';

class SteamTagUtils {
  SteamTagUtils._();

  static Future<List<Tag>> ensureSteamTags({
    required AppDatabase db,
    required Iterable<String> tagNames,
  }) async {
    final created = <Tag>[];
    final seen = <String>{};

    for (final tagName in tagNames) {
      final normalized = tagName.trim();
      if (normalized.isEmpty) {
        continue;
      }

      final key = normalized.toLowerCase();
      if (!seen.add(key)) {
        continue;
      }

      final entry = await db.getOrCreateTag(normalized, isSteamTag: true);
      created.add(Tag.fromEntry(entry));
    }

    return created;
  }

  static List<int> mergeCustomAndSteamTagIds({
    required Iterable<TagEntry> existingTagEntries,
    required Iterable<Tag> steamTags,
  }) {
    final customTagIds = existingTagEntries
        .where((t) => !t.isSteamTag)
        .map((t) => t.id);
    final steamTagIds = steamTags.map((t) => t.id);
    return [...{...customTagIds, ...steamTagIds}];
  }
}
