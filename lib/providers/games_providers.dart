/// Riverpod providers for game list state, filtering, sorting, and selection.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/database.dart';
import '../core/settings/settings_model.dart';
import '../models/game.dart';
import 'database_providers.dart';
import 'settings_providers.dart';
import 'tags_providers.dart';

// =============================================================================
// GAMES STATE
// =============================================================================

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
    this.sortMode = GameSortMode.deadlineFirst,
    this.selectedGameIds = const {},
    this.filteredGames = const [],
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
  final GameSortMode sortMode;
  final Set<int> selectedGameIds;
  final List<Game> filteredGames;

  /// Get selected games in display order (matching filteredGames order)
  List<Game> get selectedGames {
    // Use filteredGames to maintain display order for operations like Steam batch fetch
    return filteredGames.where((g) => selectedGameIds.contains(g.id)).toList();
  }

  static List<Game> _computeFilteredGames({
    required List<Game> games,
    required String searchQuery,
    required String? platformFilter,
    required List<int> tagFilters,
    required bool showDeadlineOnly,
    required bool showDlcOnly,
    required bool showUsedOnly,
    required bool showNoPicturesOnly,
    required GameSortMode sortMode,
  }) {
    var result = List<Game>.from(games);
    
    // Search filter
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      result = result.where((g) => 
        g.title.toLowerCase().contains(query) ||
        g.gameKey.toLowerCase().contains(query)
      ).toList();
    }
    
    // Platform filter
    if (platformFilter != null && platformFilter.isNotEmpty) {
      result = result.where((g) => g.platform == platformFilter).toList();
    }
    
    // Tag filters (AND logic - must have all selected tags)
    if (tagFilters.isNotEmpty) {
      result = result.where((g) {
        final gameTagIds = g.tags.map((t) => t.id).toSet();
        return tagFilters.every((tagId) => gameTagIds.contains(tagId));
      }).toList();
    }
    
    // Toggle filters
    if (showDeadlineOnly) {
      result = result.where((g) => g.hasDeadline).toList();
    }
    if (showDlcOnly) {
      result = result.where((g) => g.isDlc).toList();
    }
    if (showUsedOnly) {
      result = result.where((g) => g.isUsed).toList();
    }
    if (showNoPicturesOnly) {
      result = result.where((g) => !g.hasCoverImage).toList();
    }
    
    // Sort
    result = _sortGames(result, sortMode);
    
    return result;
  }

  static List<Game> _sortGames(List<Game> games, GameSortMode mode) {
    final sorted = List<Game>.from(games);
    
    switch (mode) {
      case GameSortMode.deadlineFirst:
        sorted.sort((a, b) {
          // Games with deadlines come before games without deadlines
          if (a.hasDeadline && !b.hasDeadline) return -1;
          if (!a.hasDeadline && b.hasDeadline) return 1;

          // If both have deadlines, prefer non-expired items first so
          // "about to expire" games are pushed to the top. Expired
          // games should appear after active deadlines but still before
          // games without any deadline.
          if (a.hasDeadline && b.hasDeadline) {
            final aExpired = a.isExpired;
            final bExpired = b.isExpired;
            if (aExpired && !bExpired) return 1; // expired -> later
            if (!aExpired && bExpired) return -1; // active -> earlier

            // Both active or both expired: fall back to chronological order
            return (a.deadlineDate ?? DateTime.now())
                .compareTo(b.deadlineDate ?? DateTime.now());
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
    
    return sorted;
  }

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
    final nextShowNoPicturesOnly = showNoPicturesOnly ?? this.showNoPicturesOnly;
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
        sortMode != null;

    final nextFilteredGames = needsRefilter 
        ? _computeFilteredGames(
            games: nextGames,
            searchQuery: nextSearchQuery,
            platformFilter: nextPlatformFilter,
            tagFilters: nextTagFilters,
            showDeadlineOnly: nextShowDeadlineOnly,
            showDlcOnly: nextShowDlcOnly,
            showUsedOnly: nextShowUsedOnly,
            showNoPicturesOnly: nextShowNoPicturesOnly,
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
      sortMode: nextSortMode,
      selectedGameIds: selectedGameIds ?? this.selectedGameIds,
      filteredGames: nextFilteredGames,
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
  
  /// Tracks the last database revision to detect actual changes
  int _lastLoadedRevision = -1;

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

      if (i != 0 && i % _loadChunkSize == 0) {
        await _yieldToUi();
      }
    }

    return games;
  }

  Future<List<Game>> _computeFilteredGamesAsync({
    required List<Game> games,
    required String searchQuery,
    required String? platformFilter,
    required List<int> tagFilters,
    required bool showDeadlineOnly,
    required bool showDlcOnly,
    required bool showUsedOnly,
    required bool showNoPicturesOnly,
    required GameSortMode sortMode,
  }) async {
    if (games.isEmpty) return const [];

    final filtered = <Game>[];
    final normalizedQuery = searchQuery.trim().toLowerCase();
    final hasQuery = normalizedQuery.isNotEmpty;
    final hasPlatformFilter = platformFilter != null && platformFilter.isNotEmpty;
    final hasTagFilters = tagFilters.isNotEmpty;

    for (var i = 0; i < games.length; i++) {
      final game = games[i];

      if (hasQuery) {
        final title = game.title.toLowerCase();
        final key = game.gameKey.toLowerCase();
        if (!title.contains(normalizedQuery) && !key.contains(normalizedQuery)) {
          if (i != 0 && i % _loadChunkSize == 0) {
            await _yieldToUi();
          }
          continue;
        }
      }

      if (hasPlatformFilter && game.platform != platformFilter) {
        if (i != 0 && i % _loadChunkSize == 0) {
          await _yieldToUi();
        }
        continue;
      }

      if (hasTagFilters) {
        final gameTagIds = game.tags.map((t) => t.id).toSet();
        if (!tagFilters.every((tagId) => gameTagIds.contains(tagId))) {
          if (i != 0 && i % _loadChunkSize == 0) {
            await _yieldToUi();
          }
          continue;
        }
      }

      if (showDeadlineOnly && !game.hasDeadline) {
        if (i != 0 && i % _loadChunkSize == 0) {
          await _yieldToUi();
        }
        continue;
      }
      if (showDlcOnly && !game.isDlc) {
        if (i != 0 && i % _loadChunkSize == 0) {
          await _yieldToUi();
        }
        continue;
      }
      if (showUsedOnly && !game.isUsed) {
        if (i != 0 && i % _loadChunkSize == 0) {
          await _yieldToUi();
        }
        continue;
      }
      if (showNoPicturesOnly && game.hasCoverImage) {
        if (i != 0 && i % _loadChunkSize == 0) {
          await _yieldToUi();
        }
        continue;
      }

      filtered.add(game);

      if (i != 0 && i % _loadChunkSize == 0) {
        await _yieldToUi();
      }
    }

    await _yieldToUi();
    return GamesState._sortGames(filtered, sortMode);
  }

  Future<void> _setLoadedState(List<Game> games) async {
    final previous = state;
    final filteredGames = await _computeFilteredGamesAsync(
      games: games,
      searchQuery: previous.searchQuery,
      platformFilter: previous.platformFilter,
      tagFilters: previous.tagFilters,
      showDeadlineOnly: previous.showDeadlineOnly,
      showDlcOnly: previous.showDlcOnly,
      showUsedOnly: previous.showUsedOnly,
      showNoPicturesOnly: previous.showNoPicturesOnly,
      sortMode: previous.sortMode,
    );

    final validIds = games.map((g) => g.id).toSet();
    final selectedIds = previous.selectedGameIds
        .where(validIds.contains)
        .toSet();

    state = GamesState(
      games: games,
      isLoading: false,
      error: null,
      searchQuery: previous.searchQuery,
      platformFilter: previous.platformFilter,
      tagFilters: previous.tagFilters,
      showDeadlineOnly: previous.showDeadlineOnly,
      showDlcOnly: previous.showDlcOnly,
      showUsedOnly: previous.showUsedOnly,
      showNoPicturesOnly: previous.showNoPicturesOnly,
      sortMode: previous.sortMode,
      selectedGameIds: selectedIds,
      filteredGames: filteredGames,
    );
  }

  @override
  GamesState build() {
    // Watch the database state so we reload when the database changes
    final dbState = ref.watch(databaseNotifierProvider);
    
    // Read initial sort mode from settings.
    final sortMode = ref.read(gameSortModeSettingProvider);

    // If database isn't ready yet, return loading state
    if (dbState.database == null) {
      final next = _cachedState.copyWith(sortMode: sortMode, isLoading: true);
      _cachedState = next;
      return next;
    }

    // Only trigger load if database revision changed (prevents duplicate loads)
    if (_lastLoadedRevision != dbState.revision) {
      _lastLoadedRevision = dbState.revision;
      // IMPORTANT: don't touch `state` before it is initialized (i.e., before build returns).
      Future.microtask(_loadGames);
    }

    // Preserve existing loaded data across rebuilds to avoid loading flicker.
    if (_cachedState.games.isEmpty && !_isLoadingInProgress) {
      final next = _cachedState.copyWith(sortMode: sortMode, isLoading: true);
      _cachedState = next;
      return next;
    }

    final next = _cachedState.copyWith(sortMode: sortMode);
    _cachedState = next;
    return next;
  }

  /// Load all games from database
  Future<void> _loadGames() async {
    // Prevent duplicate concurrent loads
    if (_isLoadingInProgress) return;
    _isLoadingInProgress = true;
    
    try {
      state = state.copyWith(isLoading: true, error: null);
      
      final db = ref.read(requireDatabaseProvider);
      final entries = await db.getAllGames();
      
      // Batch fetch all tags in a single query (eliminates N+1)
      final gameIds = entries.map((e) => e.id).toList();
      final tagsByGame = await db.getTagsForGames(gameIds);

      final games = await _buildGamesInChunks(entries, tagsByGame);
      await _setLoadedState(games);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    } finally {
      _isLoadingInProgress = false;
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
    String steamAppId = '',
    List<int> tagIds = const [],
  }) async {
    try {
      final db = ref.read(requireDatabaseProvider);
      
      final id = await db.insertGame(GamesCompanion.insert(
        title: title,
        gameKey: gameKey,
        platform: Value(platform),
        notes: Value(notes),
        coverImage: Value(coverImage),
        hasDeadline: Value(hasDeadline),
        deadlineDate: Value(deadlineDate),
        isDlc: Value(isDlc),
        steamAppId: Value(steamAppId),
        updatedAt: Value(DateTime.now()),
      ));
      
      // Add tags
      if (tagIds.isNotEmpty) {
        await db.setTagsForGame(id, tagIds);
      }
      
      final entry = await db.getGameById(id);
      if (entry == null) return null;

      final tagEntries = await db.getTagsForGame(id);
      final tags = tagEntries.map((t) => Tag.fromEntry(t)).toList();
      final newGame = Game.fromEntry(entry, tags: tags);

      state = state.copyWith(
        games: [...state.games, newGame],
        isLoading: false,
      );
      await persistEncryptedDbIfNeeded(ref);
      return newGame;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Update a game
  Future<bool> updateGame(Game game, {List<int>? tagIds}) async {
    try {
      final db = ref.read(requireDatabaseProvider);
      final updatedAt = DateTime.now();
      
      await db.updateGame(GameEntry(
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
        reviewScore: game.reviewScore,
        reviewCount: game.reviewCount,
      ));
      
      // Update tags if provided, otherwise use existing tags
      final tagsToSet = tagIds ?? game.tags.map((t) => t.id).toList();
      await db.setTagsForGame(game.id, tagsToSet);

      final updatedEntry = await db.getGameById(game.id);
      if (updatedEntry == null) return false;
      final tagEntries = await db.getTagsForGame(game.id);
      final tags = tagEntries.map((t) => Tag.fromEntry(t)).toList();
      final updatedGame = Game.fromEntry(updatedEntry, tags: tags);

      final updatedGames = [...state.games];
      final index = updatedGames.indexWhere((g) => g.id == game.id);
      if (index != -1) {
        updatedGames[index] = updatedGame;
      } else {
        updatedGames.add(updatedGame);
      }

      state = state.copyWith(games: updatedGames);
      await persistEncryptedDbIfNeeded(ref);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Delete a single game
  Future<bool> deleteGame(int id) => deleteGames([id]);

  /// Delete games
  Future<bool> deleteGames(List<int> ids) async {
    try {
      final db = ref.read(requireDatabaseProvider);
      await db.deleteGames(ids);
      // Clean up steam/auto tags no longer associated with any game.
      await ref.read(tagsProvider.notifier).deleteUnusedNonUserTags();
      final remaining = state.games.where((g) => !ids.contains(g.id)).toList();
      final remainingSelection = Set<int>.from(state.selectedGameIds)
        ..removeAll(ids);
      state = state.copyWith(games: remaining, selectedGameIds: remainingSelection);
      await persistEncryptedDbIfNeeded(ref);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Mark games as used/unused
  Future<bool> setGamesUsed(List<int> ids, bool isUsed) async {
    try {
      final db = ref.read(requireDatabaseProvider);
      await db.setGamesUsed(ids, isUsed);
      final updatedGames = state.games.map((g) {
        if (ids.contains(g.id)) {
          return g.copyWith(isUsed: isUsed);
        }
        return g;
      }).toList();
      state = state.copyWith(games: updatedGames);
      await persistEncryptedDbIfNeeded(ref);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Refresh a single game entry (for partial updates)
  Future<void> refreshGame(int id) async {
    final db = ref.read(requireDatabaseProvider);
    final entry = await db.getGameById(id);
    if (entry == null) return;
    final tagEntries = await db.getTagsForGame(id);
    final tags = tagEntries.map((t) => Tag.fromEntry(t)).toList();
    final refreshed = Game.fromEntry(entry, tags: tags);

    final updatedGames = [...state.games];
    final index = updatedGames.indexWhere((g) => g.id == id);
    if (index != -1) {
      updatedGames[index] = refreshed;
    } else {
      updatedGames.add(refreshed);
    }

    state = state.copyWith(games: updatedGames);
  }

  /// Refresh all games from database
  Future<void> refreshAllGames() async {
    final db = ref.read(requireDatabaseProvider);
    final entries = await db.getAllGames();
    
    // Batch fetch all tags in a single query (eliminates N+1)
    final gameIds = entries.map((e) => e.id).toList();
    final tagsByGame = await db.getTagsForGames(gameIds);

    final games = await _buildGamesInChunks(entries, tagsByGame);
    await _setLoadedState(games);
  }

  // ===========================================================================
  // FILTERING
  // ===========================================================================

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setPlatformFilter(String? platform) {
    // Normalize empty strings to null so the filter is never stored as '' and
    // "All Platforms" reliably clears the filter.
    final normalized = (platform != null && platform.isEmpty) ? null : platform;
    state = state.copyWith(platformFilter: normalized);
  }

  void setTagFilters(List<int> tagIds) {
    state = state.copyWith(tagFilters: tagIds);
  }

  void toggleTagFilter(int tagId) {
    final current = List<int>.from(state.tagFilters);
    if (current.contains(tagId)) {
      current.remove(tagId);
    } else {
      current.add(tagId);
    }
    state = state.copyWith(tagFilters: current);
  }

  void setShowDeadlineOnly(bool value) {
    state = state.copyWith(showDeadlineOnly: value);
  }

  void setShowDlcOnly(bool value) {
    state = state.copyWith(showDlcOnly: value);
  }

  void setShowUsedOnly(bool value) {
    state = state.copyWith(showUsedOnly: value);
  }

  void setShowNoPicturesOnly(bool value) {
    state = state.copyWith(showNoPicturesOnly: value);
  }

  void clearAllFilters() {
    state = state.copyWith(
      searchQuery: '',
      platformFilter: null,
      tagFilters: [],
      showDeadlineOnly: false,
      showDlcOnly: false,
      showUsedOnly: false,
      showNoPicturesOnly: false,
    );
  }

  // ===========================================================================
  // SORTING
  // ===========================================================================

  Future<void> setSortMode(GameSortMode mode) async {
    state = state.copyWith(sortMode: mode);
    await ref.read(settingsProvider.notifier).set(SettingsKeys.gameSortMode, mode);
  }

  // ===========================================================================
  // SELECTION
  // ===========================================================================

  void selectGame(int id) {
    state = state.copyWith(selectedGameIds: {...state.selectedGameIds, id});
  }

  void deselectGame(int id) {
    final newSelection = Set<int>.from(state.selectedGameIds)..remove(id);
    state = state.copyWith(selectedGameIds: newSelection);
  }

  void toggleGameSelection(int id) {
    if (state.selectedGameIds.contains(id)) {
      deselectGame(id);
    } else {
      selectGame(id);
    }
  }

  void selectAll() {
    state = state.copyWith(
      selectedGameIds: state.filteredGames.map((g) => g.id).toSet(),
    );
  }

  void clearSelection() {
    state = state.copyWith(selectedGameIds: {});
  }

  void selectRange(int startId, int endId) {
    final filtered = state.filteredGames;
    final startIndex = filtered.indexWhere((g) => g.id == startId);
    final endIndex = filtered.indexWhere((g) => g.id == endId);
    
    if (startIndex == -1 || endIndex == -1) return;
    
    final minIndex = startIndex < endIndex ? startIndex : endIndex;
    final maxIndex = startIndex > endIndex ? startIndex : endIndex;
    
    final newSelection = <int>{};
    for (var i = minIndex; i <= maxIndex; i++) {
      newSelection.add(filtered[i].id);
    }
    
    state = state.copyWith(selectedGameIds: {...state.selectedGameIds, ...newSelection});
  }
}

/// Games provider
final gamesProvider = NotifierProvider<GamesNotifier, GamesState>(() {
  return GamesNotifier();
});

typedef ActiveFiltersState = ({
  String searchQuery,
  List<int> tagFilters,
  bool showDeadlineOnly,
  bool showDlcOnly,
  bool showUsedOnly,
  bool showNoPicturesOnly,
});

final activeFiltersProvider = Provider<ActiveFiltersState>((ref) {
  return ref.watch(
    gamesProvider.select(
      (s) => (
        searchQuery: s.searchQuery,
        tagFilters: s.tagFilters,
        showDeadlineOnly: s.showDeadlineOnly,
        showDlcOnly: s.showDlcOnly,
        showUsedOnly: s.showUsedOnly,
        showNoPicturesOnly: s.showNoPicturesOnly,
      ),
    ),
  );
});

final selectedGamesProvider = Provider<List<Game>>((ref) {
  return ref.watch(gamesProvider.select((s) => s.selectedGames));
});

final selectedSteamGamesProvider = Provider<List<Game>>((ref) {
  final selectedGames = ref.watch(selectedGamesProvider);
  return selectedGames.where((g) => g.platform == 'Steam').toList();
});

final selectedGamesAllUsedProvider = Provider<bool>((ref) {
  final selectedGames = ref.watch(selectedGamesProvider);
  return selectedGames.isNotEmpty && selectedGames.every((g) => g.isUsed);
});

final allGamesProvider = Provider<List<Game>>((ref) {
  return ref.watch(gamesProvider.select((s) => s.games));
});

final gamesByIdProvider = Provider<Map<int, Game>>((ref) {
  final games = ref.watch(allGamesProvider);
  return {for (final game in games) game.id: game};
});

final gameByIdProvider = Provider.family<Game?, int>((ref, gameId) {
  final gamesById = ref.watch(gamesByIdProvider);
  return gamesById[gameId];
});
