import 'dart:convert';

import '../../../models/game.dart';
import 'library_import.dart';

/// Retains the backup dialog's established JSON, CSV, and plain-text layouts,
/// including optional notes/tags and its JSON export timestamp.
class LibraryBackupExporter {
  LibraryBackupExporter({
    this.includeTags = true,
    this.includeNotes = true,
    DateTime? exportedAt,
  }) : exportedAt = exportedAt ?? DateTime.now();

  final bool includeTags;
  final bool includeNotes;
  final DateTime exportedAt;

  String encode(List<Game> games, List<Tag> tags, String format) {
    final tagNamesById = {for (final tag in tags) tag.id: tag.name};
    return switch (format) {
      'json' => _json(games, tagNamesById),
      'csv' => _csv(games, tagNamesById),
      _ => _text(games),
    };
  }

  Iterable<String> _tagNames(Game game, Map<int, String> names) =>
      game.tags.map((tag) => names[tag.id]).whereType<String>();

  String _json(List<Game> games, Map<int, String> tagNamesById) =>
      const JsonEncoder.withIndent('  ').convert({
        'exported_at': exportedAt.toIso8601String(),
        'games': [
          for (final game in games)
            {
              'title': game.title,
              'key': game.gameKey,
              'platform': game.platform,
              'is_used': game.isUsed,
              'is_dlc': game.isDlc,
              'rating': game.rating,
              if (includeTags && game.tagIds.isNotEmpty)
                'tags': _tagNames(game, tagNamesById).toList(),
              if (includeNotes) 'notes': game.notes,
              'cover_image': game.coverImage,
              if (game.hasDeadline && game.deadlineDate != null)
                'deadline': game.deadlineDate!.toIso8601String(),
            },
        ],
      });

  String _csv(List<Game> games, Map<int, String> tagNamesById) =>
      libraryCsv.encode([
        [
          'Title',
          'Key',
          'Platform',
          'Used',
          'DLC',
          'Rating',
          if (includeTags) 'Tags',
          if (includeNotes) 'Notes',
        ],
        for (final game in games)
          [
            game.title,
            game.gameKey,
            game.platform,
            game.isUsed ? 'Yes' : 'No',
            game.isDlc ? 'Yes' : 'No',
            game.rating.toString(),
            if (includeTags) _tagNames(game, tagNamesById).join(';'),
            if (includeNotes) game.notes,
          ],
      ]);

  String _text(List<Game> games) =>
      games.map((game) => '${game.title} | ${game.gameKey}\n').join();
}
