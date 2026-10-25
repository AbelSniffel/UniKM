/// Riverpod providers for game list state, filtering, sorting, and selection.
library;

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/database.dart';
import '../core/settings/settings_model.dart';
import '../models/game.dart';
import '../features/library/application/library_query.dart';
import '../features/library/data/library_repository.dart';
import 'database_providers.dart';
import 'settings_providers.dart';

// =============================================================================
// GAMES STATE
// =============================================================================

/// Bump the sync DB revision ID to signal that local data has changed.
/// Call this after any add, update, or remove operation.
Future<void> _bumpSyncDbRevision(Ref ref, AppDatabase db) async {
  try {
    final revision = await db.getLocalSyncRevision();
    final timestamp = await db.getSyncDbTimestampMillis();
    if (!ref.mounted || !identical(ref.read(databaseProvider), db)) return;
    await ref.read(settingsProvider.notifier).setMany({
      SettingsKeys.syncDbRevisionId: revision.toString(),
      SettingsKeys.syncDbTimestampMillis: timestamp,
    });
  } catch (_) {
    // The transactional database revision remains authoritative.
  }
}

/// State for the games list with filtering and sorting
class GamesState {
  static const _unset = Object();

  const GamesState({
    this.games = const [],
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
    this.platformFilter,
    this.tagFilters = const [],
    this.showDeadlineOnly = false,
    this.showDlcOnly = false,
    this.showUsedOnly = false,
    this.showNoPicturesOnly = false,
    this.showNoTagsOnly = false,
    this.sortMode = GameSortMode.deadlineFirst,
    this.selectedGameIds = const {},
    this.filteredGames = const [],
    this.queryIndex,
  });

  final List<Game> games;
  final bool isLoading;
  final String? error;
  final String searchQuery;
  final String? platformFilter;
  final List<int> tagFilters;
  final bool showDeadlineOnly;
  final bool showDlcOnly;
  final bool showUsedOnly;
  final bool showNoPicturesOnly;
  final bool showNoTagsOnly;
  final GameSortMode sortMode;
  final Set<int> selectedGameIds;
  final List<Game> filteredGames;
  final LibraryQueryIndex? queryIndex;

  GamesState copyWith({
    List<Game>? games,
    bool? isLoading,
    String? error,
    String? searchQuery,
    Object? platformFilter = _unset,
    List<int>? tagFilters,
    bool? showDeadlineOnly,
    bool? showDlcOnly,
    bool? showUsedOnly,
    bool? showNoPicturesOnly,
    bool? showNoTagsOnly,
    GameSortMode? sortMode,
    Set<int>? selectedGameIds,
  }) {
    final nextGames = games ?? this.games;
    final nextSearchQuery = searchQuery ?? this.searchQuery;
    final nextPlatformFilter = platformFilter == _unset
        ? this.platformFilter
        : platformFilter as String?;
    final nextTagFilters = tagFilters ?? this.tagFilters;
    final nextShowDeadlineOnly = showDeadlineOnly ?? this.showDeadlineOnly;
    final nextShowDlcOnly = showDlcOnly ?? this.showDlcOnly;
    final nextShowUsedOnly = showUsedOnly ?? this.showUsedOnly;
    final nextShowNoPicturesOnly =
        showNoPicturesOnly ?? this.showNoPicturesOnly;
    final nextShowNoTagsOnly = showNoTagsOnly ?? this.showNoTagsOnly;
    final nextSortMode = sortMode ?? this.sortMode;

    // Check if re-filtering is needed.
    // If only selectedGameIds or isLoading/error changed, we can reuse result.
    final needsRefilter =
        games != null ||
        searchQuery != null ||
        platformFilter != _unset ||
        tagFilters != null ||
        showDeadlineOnly != null ||
        showDlcOnly != null ||
        showUsedOnly != null ||
        showNoPicturesOnly != null ||
        showNoTagsOnly != null ||
        sortMode != null;

    final nextIndex = games != null || queryIndex == null
        ? LibraryQueryIndex(nextGames, previous: queryIndex)
        : queryIndex!;
    final nextFilteredGames = needsRefilter
        ? nextIndex.select(
            searchQuery: nextSearchQuery,
            platformFilter: nextPlatformFilter,
            tagFilters: nextTagFilters,
            showDeadlineOnly: nextShowDeadlineOnly,
            showDlcOnly: nextShowDlcOnly,
            showUsedOnly: nextShowUsedOnly,
            showNoPicturesOnly: nextShowNoPicturesOnly,
            showNoTagsOnly: nextShowNoTagsOnly,
            sortMode: nextSortMode,
          )
        : filteredGames;

    return GamesState(
      games: nextGames,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      searchQuery: nextSearchQuery,
      platformFilter: nextPlatformFilter,
      tagFilters: nextTagFilters,
      showDeadlineOnly: nextShowDeadlineOnly,
      showDlcOnly: nextShowDlcOnly,
      showUsedOnly: nextShowUsedOnly,
      showNoPicturesOnly: nextShowNoPicturesOnly,
      showNoTagsOnly: nextShowNoTagsOnly,
      sortMode: nextSortMode,
      selectedGameIds: selectedGameIds ?? this.selectedGameIds,
      filteredGames: nextFilteredGames,
      queryIndex: nextIndex,
    );
  }
}

// =============================================================================
// GAMES NOTIFIER
// =============================================================================

/// Games state notifier
class GamesNotifier extends Notifier<GamesState> {
  GamesState _cachedState = const GamesState();
  static const int _loadChunkSize = 200;

  @override
  set state(GamesState value) {
    _cachedState = value;
    super.state = value;
  }

  /// Tracks if a load is already in progress to prevent duplicate calls
  bool _isLoadingInProgress = false;
  int _loadGeneration = 0;
  int _snapshotEpoch = 0;
  AppDatabase? _activeDatabase;
  StreamSubscription<List<Game>>? _snapshots;
  Timer? _searchDebounce;
  Timer? _midnightTimer;

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(next.difference(now), () {
      if (!ref.mounted) return;
      state = state.copyWith(sortMode: state.sortMode);
      _scheduleMidnight();
    });
  }

  Future<void> _yieldToUi() => Future<void>.delayed(Duration.zero);

  Future<List<Game>> _buildGamesInChunks(
    List<GameEntry> entries,
    Map<int, List<TagEntry>> tagsByGame,
  ) async {
    final games = <Game>[];

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final tagEntries = tagsByGame[entry.id] ?? const <TagEntry>[];
      final tags = tagEntries.map((t) => Tag.fromEntry(t)).toList();
      games.add(Game.fromEntry(entry, tags: tags));

      if (i != 0 && i % _loadChunkSize == 0) await _yieldToUi();
    }

    return games;
  }

  void _setLoadedState(List<Game> games) {
    var selection = state.selectedGameIds;
    if (selection.isNotEmpty) {
      final validIds = games.map((g) => g.id).toSet();
      final remaining = selection.where(validIds.contains).toSet();
      if (remaining.length != selection.length) selection = remaining;
    }
    state = state.copyWith(
      games: games,
      isLoading: false,
      selectedGameIds: selection,
    );
  }

  @override
  GamesState build() {
    // Watch the database state so we reload when the database changes
    final dbState = ref.watch(databaseNotifierProvider);
    ref.onDispose(() {
      _searchDebounce?.cancel();
      _midnightTimer?.cancel();
      _snapshots?.cancel();
      _snapshots = null;
    });
    _scheduleMidnight();

    if (!identical(_activeDatabase, dbState.database)) {
      _activeDatabase = dbState.database;
      _loadGeneration++;
      _isLoadingInProgress = false;
      _cachedState = _cachedState.copyWith(
        games: const [],
        selectedGameIds: {},
        isLoading: true,
      );
    }

    // Read initial sort mode from settings.
    final sortMode = ref.read(gameSortModeSettingProvider);

    // If database isn't ready yet, return loading state
    if (dbState.database == null) {
      return _cachedState = _cachedState.copyWith(
        sortMode: sortMode,
        isLoading: true,
      );
    }

    _snapshots = LibraryRepository(dbState.database!).watchSnapshot().listen(
      (games) {
        if (ref.mounted &&
            identical(ref.read(databaseProvider), dbState.database)) {
          _snapshotEpoch++;
          _setLoadedState(games);
        }
      },
      onError: (Object error) {
        if (ref.mounted &&
            identical(ref.read(databaseProvider), dbState.database)) {
          state = state.copyWith(isLoading: false, error: error.toString());
        }
      },
    );

    // Preserve existing loaded data across rebuilds to avoid loading flicker.
    return _cachedState = _cachedState.copyWith(
      sortMode: sortMode,
      isLoading: _cachedState.games.isEmpty && !_isLoadingInProgress
          ? true
          : null,
    );
  }

  /// Load all games from database
  Future<void> _loadGames() async {
    final generation = ++_loadGeneration;
    final snapshotEpoch = _snapshotEpoch;
    final db = ref.read(databaseProvider);
    if (db == null) return;
    bool isCurrent() =>
        ref.mounted &&
        generation == _loadGeneration &&
        identical(ref.read(databaseProvider), db);
    _isLoadingInProgress = true;

    try {
      state = state.copyWith(isLoading: true, error: null);

      final entries = await db.getAllGames();

      // Batch fetch all tags in a single query (eliminates N+1)
      final gameIds = entries.map((e) => e.id).toList();
      final tagsByGame = await db.getTagsForGames(gameIds);

      final games = await _buildGamesInChunks(entries, tagsByGame);
      if (isCurrent() && snapshotEpoch == _snapshotEpoch) {
        _setLoadedState(games);
      }
    } catch (e) {
      if (isCurrent()) {
        state = state.copyWith(error: e.toString(), isLoading: false);
      }
    } finally {
      if (isCurrent()) _isLoadingInProgress = false;
    }
  }

  /// Public method to load games (for initial load)
  Future<void> loadGames() => _loadGames();

  /// Refresh games from database
  Future<void> refresh() => _loadGames();

  /// Add a new game
  Future<Game?> addGame({
    required String title,
    required String gameKey,
    required String platform,
    String notes = '',
    String coverImage = '',
    bool hasDeadline = false,
    DateTime? deadlineDate,
    bool isDlc = false,
    bool isUsed = false,
    String steamAppId = '',
    int reviewScore = 0,
    int reviewCount = 0,
    List<int> tagIds = const [],
    int? replaceId,
  }) async {
    final operationDatabase = _activeDatabase;
    try {
      final db = ref.read(requireDatabaseProvider);

      final id = await LibraryRepository(db).saveNewGame(
        GamesCompanion.insert(
          title: title,
          gameKey: gameKey,
          platform: Value(platform),
          notes: Value(notes),
          coverImage: Value(coverImage),
          hasDeadline: Value(hasDeadline),
          deadlineDate: Value(deadlineDate),
          isDlc: Value(isDlc),
          isUsed: Value(isUsed),
          steamAppId: Value(steamAppId),
          reviewScore: Value(reviewScore),
          reviewCount: Value(reviewCount),
          updatedAt: Value(DateTime.now()),
        ),
        tagIds: tagIds,
        replaceId: replaceId,
      );

      final entry = await db.getGameById(id);
      if (entry == null) return null;

      final tagEntries = await db.getTagsForGame(id);
      final tags = tagEntries.map((t) => Tag.fromEntry(t)).toList();
      final newGame = Game.fromEntry(entry, tags: tags);
      if (!ref.mounted || !identical(ref.read(databaseProvider), db)) {
        return newGame;
      }

      await persistEncryptedDbIfNeeded(ref, database: db);
      unawaited(_bumpSyncDbRevision(ref, db));
      return newGame;
    } catch (e) {
      if (ref.mounted &&
          identical(ref.read(databaseProvider), operationDatabase)) {
        state = state.copyWith(error: e.toString());
      }
      return null;
    }
  }

  /// Game edits share session checks, encrypted persistence, and error handling.
  Future<T> _mutate<T>(
    Future<T> Function(AppDatabase db) action, {
    required T failure,
  }) async {
    final operationDatabase = _activeDatabase;
    try {
      final db = ref.read(requireDatabaseProvider);
      final result = await action(db);
      if (!ref.mounted || !identical(ref.read(databaseProvider), db)) {
        return failure;
      }
      await persistEncryptedDbIfNeeded(ref, database: db);
      unawaited(_bumpSyncDbRevision(ref, db));
      return result;
    } catch (e) {
      if (ref.mounted &&
          identical(ref.read(databaseProvider), operationDatabase)) {
        state = state.copyWith(error: e.toString());
      }
      return failure;
    }
  }

  /// Update a game
  Future<bool> updateGame(Game game, {List<int>? tagIds}) async =>
      _mutate((db) async {
        final updatedAt = DateTime.now();

        await LibraryRepository(db).updateGame(
          GameEntry(
            id: game.id,
            title: game.title,
            gameKey: game.gameKey,
            platform: game.platform,
            dateAdded: game.dateAdded,
            updatedAt: updatedAt,
            notes: game.notes,
            isUsed: game.isUsed,
            coverImage: game.coverImage,
            hasDeadline: game.hasDeadline,
            deadlineDate: game.deadlineDate,
            isDlc: game.isDlc,
            steamAppId: game.steamAppId,
            developer: game.developer,
            reviewScore: game.reviewScore,
            reviewCount: game.reviewCount,
          ),
          tagIds: tagIds,
        );

        return true;
      }, failure: false);

  /// Delete a single game
  Future<bool> deleteGame(int id) => deleteGames([id]);

  /// Delete games
  Future<bool> deleteGames(List<int> ids) async => _mutate((db) async {
    await db.transaction(() async {
      await db.deleteGames(ids);
      await db.deleteUnusedNonUserTags();
    });
    return true;
  }, failure: false);

  /// Mark games as used/unused. Completion acknowledges persistence even for
  /// callers using the legacy background-save option.
  Future<bool> setGamesUsed(
    List<int> ids,
    bool isUsed, {
    bool persistInBackground = false,
  }) async => _mutate((db) async {
    await db.setGamesUsed(ids, isUsed);
    return true;
  }, failure: false);

  /// Clear Steam-derived metadata and Steam tags for the given games.
  ///
  /// Keeps custom tags intact while removing:
  /// - cover image
  /// - Steam AppID
  /// - developer
  /// - review score/count
  /// - DLC flag
  /// - Steam tags
  Future<int> clearSteamMetadata(List<int> ids) async {
    if (ids.isEmpty) return 0;

    return _mutate((db) async {
      final now = DateTime.now();

      await db.transaction(() async {
        final tagsByGame = await db.getTagsForGames(ids);
        for (final id in ids) {
          final tagEntries = tagsByGame[id] ?? const <TagEntry>[];
          final customTagIds = tagEntries
              .where((tag) => !tag.isSteamTag)
              .map((tag) => tag.id)
              .toList(growable: false);

          await db.updateGameFields(
            id,
            coverImage: '',
            isDlc: false,
            steamAppId: '',
            developer: '',
            reviewScore: 0,
            reviewCount: 0,
            updatedAt: now,
          );
          await db.setTagsForGame(id, customTagIds);
        }
        await db.deleteUnusedNonUserTags();
      });

      return ids.length;
    }, failure: 0);
  }

  /// Refresh a single game entry (for partial updates)
  Future<void> refreshGame(int id) async {
    final db = _activeDatabase;
    if (db == null) return;
    final generation = _loadGeneration;
    final epoch = _snapshotEpoch;
    try {
      final game = await db.transaction(() async {
        final entry = await db.getGameById(id);
        if (entry == null) return null;
        return Game.fromEntry(
          entry,
          tags: [
            for (final tag in await db.getTagsForGame(id)) Tag.fromEntry(tag),
          ],
        );
      });
      if (!ref.mounted ||
          generation != _loadGeneration ||
          !identical(_activeDatabase, db) ||
          epoch != _snapshotEpoch) {
        return;
      }
      final index = state.games.indexWhere((game) => game.id == id);
      if (index < 0 && game == null ||
          index >= 0 && state.games[index] == game) {
        return;
      }
      final games = [...state.games];
      if (index >= 0) {
        if (game == null) {
          games.removeAt(index);
        } else {
          games[index] = game;
        }
      } else {
        games.add(game!);
        games.sort((a, b) => a.id.compareTo(b.id));
      }
      _setLoadedState(games);
    } catch (e) {
      if (ref.mounted &&
          generation == _loadGeneration &&
          identical(_activeDatabase, db)) {
        state = state.copyWith(error: e.toString());
      }
    }
  }

  // ===========================================================================
  // FILTERING
  // ===========================================================================

  void setSearchQuery(String query) {
    _searchDebounce?.cancel();
    state = state.copyWith(searchQuery: query);
  }

  void setSearchQueryDebounced(String query) {
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      setSearchQuery(query);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 40), () {
      if (ref.mounted) setSearchQuery(query);
    });
  }

  // Empty strings become null so the filter is never stored as '' and
  // "All Platforms" reliably clears the filter.
  void setPlatformFilter(String? platform) => state = state.copyWith(
    platformFilter: platform?.isEmpty == true ? null : platform,
  );

  void setTagFilters(List<int> tagIds) =>
      state = state.copyWith(tagFilters: tagIds);

  void toggleTagFilter(int tagId) {
    final current = List<int>.from(state.tagFilters);
    if (!current.remove(tagId)) current.add(tagId);
    state = state.copyWith(tagFilters: current);
  }

  void setShowDeadlineOnly(bool value) =>
      state = state.copyWith(showDeadlineOnly: value);

  void setShowDlcOnly(bool value) => state = state.copyWith(showDlcOnly: value);

  void setShowUsedOnly(bool value) =>
      state = state.copyWith(showUsedOnly: value);

  void setShowNoPicturesOnly(bool value) =>
      state = state.copyWith(showNoPicturesOnly: value);

  void setShowNoTagsOnly(bool value) =>
      state = state.copyWith(showNoTagsOnly: value);

  void clearAllFilters() {
    _searchDebounce?.cancel();
    state = state.copyWith(
      searchQuery: '',
      platformFilter: null,
      tagFilters: [],
      showDeadlineOnly: false,
      showDlcOnly: false,
      showUsedOnly: false,
      showNoPicturesOnly: false,
      showNoTagsOnly: false,
    );
  }

  // ===========================================================================
  // SORTING
  // ===========================================================================

  Future<void> setSortMode(GameSortMode mode) async {
    state = state.copyWith(sortMode: mode);
    await ref
        .read(settingsProvider.notifier)
        .set(SettingsKeys.gameSortMode, mode);
  }

  // ===========================================================================
  // SELECTION
  // ===========================================================================

  void selectGame(int id) {
    if (state.selectedGameIds.contains(id)) return;
    state = state.copyWith(selectedGameIds: {...state.selectedGameIds, id});
  }

  void deselectGame(int id) {
    if (!state.selectedGameIds.contains(id)) return;
    final newSelection = Set<int>.from(state.selectedGameIds)..remove(id);
    state = state.copyWith(selectedGameIds: newSelection);
  }

  void toggleGameSelection(int id) =>
      state.selectedGameIds.contains(id) ? deselectGame(id) : selectGame(id);

  void selectAll() => state = state.copyWith(
    selectedGameIds: state.filteredGames.map((g) => g.id).toSet(),
  );

  void clearSelection() {
    if (state.selectedGameIds.isEmpty) return;
    state = state.copyWith(selectedGameIds: {});
  }

  void setSelection(Iterable<int> ids) {
    final next = ids.toSet();
    if (const SetEquality<int>().equals(state.selectedGameIds, next)) return;
    state = state.copyWith(selectedGameIds: next);
  }

  void selectRange(int startId, int endId) {
    final filtered = state.filteredGames;
    final startIndex = filtered.indexWhere((g) => g.id == startId);
    final endIndex = filtered.indexWhere((g) => g.id == endId);

    if (startIndex == -1 || endIndex == -1) return;

    final (first, last) = startIndex < endIndex
        ? (startIndex, endIndex)
        : (endIndex, startIndex);
    state = state.copyWith(
      selectedGameIds: {
        ...state.selectedGameIds,
        for (var i = first; i <= last; i++) filtered[i].id,
      },
    );
  }
}

/// Games provider
final gamesProvider = NotifierProvider<GamesNotifier, GamesState>(
  GamesNotifier.new,
);

typedef ActiveFiltersState = ({
  String searchQuery,
  List<int> tagFilters,
  bool showDeadlineOnly,
  bool showDlcOnly,
  bool showUsedOnly,
  bool showNoPicturesOnly,
  bool showNoTagsOnly,
});

final activeFiltersProvider = Provider<ActiveFiltersState>(
  (ref) => ref.watch(
    gamesProvider.select(
      (s) => (
        searchQuery: s.searchQuery,
        tagFilters: s.tagFilters,
        showDeadlineOnly: s.showDeadlineOnly,
        showDlcOnly: s.showDlcOnly,
        showUsedOnly: s.showUsedOnly,
        showNoPicturesOnly: s.showNoPicturesOnly,
        showNoTagsOnly: s.showNoTagsOnly,
      ),
    ),
  ),
);

final selectedGamesProvider = Provider<List<Game>>((ref) {
  final (games, selectedIds) = ref.watch(
    gamesProvider.select((s) => (s.filteredGames, s.selectedGameIds)),
  );
  if (selectedIds.isEmpty) return const [];
  return games.where((game) => selectedIds.contains(game.id)).toList();
});

/// Metadata edits only update the affected cards. The scrollable view needs
/// rebuilding only when the filtered membership or display order changes.
final filteredGameIdsProvider =
    NotifierProvider<_FilteredGameIdsNotifier, List<int>>(
      _FilteredGameIdsNotifier.new,
    );

class _FilteredGameIdsNotifier extends Notifier<List<int>> {
  List<int> _ids = const [];

  @override
  List<int> build() {
    final games = ref.watch(gamesProvider.select((s) => s.filteredGames));
    if (games.length == _ids.length) {
      var unchanged = true;
      for (var i = 0; i < games.length; i++) {
        if (games[i].id != _ids[i]) {
          unchanged = false;
          break;
        }
      }
      if (unchanged) return _ids;
    }
    return _ids = List.unmodifiable(games.map((game) => game.id));
  }
}

final selectedSteamGamesProvider = Provider<List<Game>>(
  (ref) => ref
      .watch(selectedGamesProvider)
      .where((g) => g.platform == 'Steam')
      .toList(),
);

final selectedGamesAllUsedProvider = Provider<bool>((ref) {
  final selectedGames = ref.watch(selectedGamesProvider);
  return selectedGames.isNotEmpty && selectedGames.every((g) => g.isUsed);
});

final allGamesProvider = Provider<List<Game>>(
  (ref) => ref.watch(gamesProvider.select((s) => s.games)),
);

final gamesByIdProvider = Provider<Map<int, Game>>(
  (ref) => {for (final game in ref.watch(allGamesProvider)) game.id: game},
);

final gameByIdProvider = Provider.autoDispose.family<Game?, int>(
  (ref, gameId) =>
      ref.watch(gamesByIdProvider.select((games) => games[gameId])),
);
