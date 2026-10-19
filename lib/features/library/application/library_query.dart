import '../../../models/game.dart';
import '../../../core/settings/settings_model.dart';
import '../../../shared/time/calendar_date.dart';

/// Searchable values are normalized once per library snapshot. Ordering is
/// cached across filter edits and invalidated by sort mode or calendar day.
class LibraryQueryIndex {
  LibraryQueryIndex(List<Game> games, {LibraryQueryIndex? previous})
    : games = List.unmodifiable(games) {
    for (var i = 0; i < games.length; i++) {
      final game = games[i];
      final old = previous != null && i < previous.games.length
          ? previous.games[i]
          : null;
      final sameId = old?.id == game.id;
      // Ordinary edits retain database row order. Reuse their normalized
      // strings and tag sets without retaining the previous index itself.
      _titles[game.id] = sameId && old!.title == game.title
          ? previous!._titles[game.id]!
          : game.title.toLowerCase();
      _keys[game.id] = sameId && old!.gameKey == game.gameKey
          ? previous!._keys[game.id]!
          : game.gameKey.toLowerCase();
      if (game.tags.isNotEmpty) {
        _tags[game.id] = sameId && identical(old!.tags, game.tags)
            ? previous!._tags[game.id]!
            : {for (final tag in game.tags) tag.id};
      }
    }
    // Metadata edits normally leave the sort keys unchanged. Carry forward
    // the existing order, replacing only game references, without sorting.
    if (previous?._ordered != null && games.length == previous!.games.length) {
      final replacements = <int, Game>{};
      var sameOrder = true;
      for (var i = 0; i < games.length; i++) {
        final old = previous.games[i];
        final next = games[i];
        if (old.id != next.id ||
            _sortKey(old, previous._mode!) != _sortKey(next, previous._mode!)) {
          sameOrder = false;
          break;
        }
        if (!identical(old, next)) replacements[next.id] = next;
      }
      if (sameOrder) {
        _mode = previous._mode;
        _day = previous._day;
        _ordered = replacements.isEmpty
            ? previous._ordered
            : List.unmodifiable(
                previous._ordered!.map((game) => replacements[game.id] ?? game),
              );
      }
    }
  }

  static Object _sortKey(Game game, GameSortMode mode) => switch (mode) {
    GameSortMode.titleAZ || GameSortMode.titleZA => game.title,
    GameSortMode.platformAZ || GameSortMode.platformZA => game.platform,
    GameSortMode.dateNewest || GameSortMode.dateOldest => game.dateAdded,
    GameSortMode.ratingHigh || GameSortMode.ratingLow => game.reviewScore,
    GameSortMode.deadlineFirst => (
      game.hasDeadline,
      game.deadlineDate,
      game.title,
    ),
  };

  final List<Game> games;
  final _titles = <int, String>{};
  final _keys = <int, String>{};
  final _tags = <int, Set<int>>{};
  List<Game>? _ordered;
  GameSortMode? _mode;
  DateTime? _day;

  List<Game> select({
    required String searchQuery,
    required String? platformFilter,
    required List<int> tagFilters,
    required bool showDeadlineOnly,
    required bool showDlcOnly,
    required bool showUsedOnly,
    required bool showNoPicturesOnly,
    required bool showNoTagsOnly,
    required GameSortMode sortMode,
    DateTime? now,
  }) {
    final instant = now ?? DateTime.now();
    final day = calendarDay(instant);
    if (_ordered == null || _mode != sortMode || _day != day) {
      _ordered = _sortGames(games, sortMode, instant);
      _mode = sortMode;
      _day = day;
    }
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty &&
        (platformFilter == null || platformFilter.isEmpty) &&
        tagFilters.isEmpty &&
        !showDeadlineOnly &&
        !showDlcOnly &&
        !showUsedOnly &&
        !showNoPicturesOnly &&
        !showNoTagsOnly) {
      return _ordered!;
    }
    return List.unmodifiable(
      _ordered!.where((game) {
        if (query.isNotEmpty &&
            !_titles[game.id]!.contains(query) &&
            !_keys[game.id]!.contains(query)) {
          return false;
        }
        if (platformFilter != null &&
            platformFilter.isNotEmpty &&
            game.platform != platformFilter) {
          return false;
        }
        if (tagFilters.isNotEmpty) {
          final tags = _tags[game.id];
          if (tags == null || !tagFilters.every(tags.contains)) return false;
        }
        return (!showDeadlineOnly || game.hasDeadline) &&
            (!showDlcOnly || game.isDlc) &&
            (!showUsedOnly || game.isUsed) &&
            (!showNoPicturesOnly || !game.hasCoverImage) &&
            (!showNoTagsOnly || game.tags.isEmpty);
      }),
    );
  }

  static List<Game> _sortGames(
    List<Game> games,
    GameSortMode mode,
    DateTime now,
  ) {
    final sorted = List<Game>.from(games);

    switch (mode) {
      case GameSortMode.deadlineFirst:
        // Compute calendar-day expiry once per game, rather than allocating
        // dates for every comparison in the O(n log n) sort.
        final today = calendarDay(now);
        final expired = <int>{
          for (final game in games)
            if (game.hasDeadline &&
                game.deadlineDate != null &&
                calendarDay(game.deadlineDate!).isBefore(today))
              game.id,
        };
        sorted.sort((a, b) {
          // Games with deadlines come before games without deadlines
          if (a.hasDeadline && !b.hasDeadline) return -1;
          if (!a.hasDeadline && b.hasDeadline) return 1;

          // If both have deadlines, prefer non-expired items first so
          // "about to expire" games are pushed to the top. Expired
          // games should appear after active deadlines but still before
          // games without any deadline.
          if (a.hasDeadline && b.hasDeadline) {
            final aExpired = expired.contains(a.id);
            final bExpired = expired.contains(b.id);
            if (aExpired && !bExpired) return 1; // expired -> later
            if (!aExpired && bExpired) return -1; // active -> earlier

            // Both active or both expired: fall back to chronological order
            return (a.deadlineDate ?? now).compareTo(b.deadlineDate ?? now);
          }

          return a.title.compareTo(b.title);
        });
        break;
      case GameSortMode.titleAZ:
        sorted.sort((a, b) => a.title.compareTo(b.title));
        break;
      case GameSortMode.titleZA:
        sorted.sort((a, b) => b.title.compareTo(a.title));
        break;
      case GameSortMode.platformAZ:
        sorted.sort((a, b) => a.platform.compareTo(b.platform));
        break;
      case GameSortMode.platformZA:
        sorted.sort((a, b) => b.platform.compareTo(a.platform));
        break;
      case GameSortMode.dateNewest:
        sorted.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
        break;
      case GameSortMode.dateOldest:
        sorted.sort((a, b) => a.dateAdded.compareTo(b.dateAdded));
        break;
      case GameSortMode.ratingHigh:
        sorted.sort((a, b) => b.reviewScore.compareTo(a.reviewScore));
        break;
      case GameSortMode.ratingLow:
        sorted.sort((a, b) => a.reviewScore.compareTo(b.reviewScore));
        break;
    }

    return List.unmodifiable(sorted);
  }
}
