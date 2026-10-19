/// Riverpod providers for batch Steam data fetch operations.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

// =============================================================================
// BATCH FETCH STATE
// =============================================================================

/// Status of a game in a batch fetch operation
enum GameFetchStatus {
  waiting,
  processing,
  done,
  error,
}

/// State for tracking batch Steam data fetch operations
class BatchFetchState {
  const BatchFetchState({
    this.isActive = false,
    this.gameStatuses = const {},
    this.currentGameId,
    this.totalGames = 0,
    this.completedGames = 0,
  });

  /// Whether a batch fetch is currently active
  final bool isActive;
  
  /// Map of game ID to its fetch status
  final Map<int, GameFetchStatus> gameStatuses;
  
  /// Currently processing game ID
  final int? currentGameId;
  
  /// Total games in the batch
  final int totalGames;
  
  /// Number of completed games (done or error)
  final int completedGames;

  /// Get status for a specific game
  GameFetchStatus? getStatus(int gameId) => gameStatuses[gameId];
  
  BatchFetchState copyWith({
    bool? isActive,
    Map<int, GameFetchStatus>? gameStatuses,
    int? currentGameId,
    int? totalGames,
    int? completedGames,
    bool clearCurrentGame = false,
  }) {
    return BatchFetchState(
      isActive: isActive ?? this.isActive,
      gameStatuses: gameStatuses ?? this.gameStatuses,
      currentGameId: clearCurrentGame ? null : (currentGameId ?? this.currentGameId),
      totalGames: totalGames ?? this.totalGames,
      completedGames: completedGames ?? this.completedGames,
    );
  }
}

/// Notifier for managing batch fetch state
class BatchFetchNotifier extends Notifier<BatchFetchState> {
  @override
  BatchFetchState build() => const BatchFetchState();
  
  bool _cancelled = false;
  
  /// Check if batch fetch has been cancelled
  bool get isCancelled => _cancelled;

  /// Start a batch fetch with the given game IDs
  void startBatch(List<int> gameIds) {
    _cancelled = false;
    state = BatchFetchState(
      isActive: true,
      gameStatuses: {for (final id in gameIds) id: GameFetchStatus.waiting},
      totalGames: gameIds.length,
      completedGames: 0,
    );
  }
  
  /// Cancel the batch fetch (user-initiated).
  ///
  /// If no game is currently being processed (i.e. the loop is idle between
  /// awaits), clear the state immediately so the UI updates without delay.
  void cancelBatch() {
    _cancelled = true;
    // If nothing is actively processing the loop will pick up the flag at the
    // next iteration, but if the loop is between items the overlay would linger
    // for that gap. Clearing state now gives an instant visual response while
    // the flag still prevents any further DB writes.
    if (state.currentGameId == null) {
      state = const BatchFetchState();
    }
  }

  /// Mark a game as currently processing
  void setProcessing(int gameId) {
    if (!state.gameStatuses.containsKey(gameId)) return;
    final newStatuses = Map<int, GameFetchStatus>.from(state.gameStatuses);
    newStatuses[gameId] = GameFetchStatus.processing;
    state = state.copyWith(
      gameStatuses: newStatuses,
      currentGameId: gameId,
    );
  }

  /// Mark a game as done.
  void setDone(int gameId) => _finishGame(gameId, GameFetchStatus.done);

  /// Mark a game as failed.
  void setError(int gameId) => _finishGame(gameId, GameFetchStatus.error);

  void _finishGame(int gameId, GameFetchStatus status) {
    if (!state.gameStatuses.containsKey(gameId)) return;
    state = state.copyWith(
      gameStatuses: {...state.gameStatuses, gameId: status},
      completedGames: state.completedGames + 1,
      clearCurrentGame: state.currentGameId == gameId,
    );
  }

  /// End the batch fetch
  void endBatch() {
    state = const BatchFetchState();
  }
}

/// Provider for batch fetch state
final batchFetchProvider = NotifierProvider<BatchFetchNotifier, BatchFetchState>(() {
  return BatchFetchNotifier();
});
