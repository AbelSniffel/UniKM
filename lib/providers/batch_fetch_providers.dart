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
  
  /// Check if a specific game is in the batch
  bool containsGame(int gameId) => gameStatuses.containsKey(gameId);

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
    final statuses = <int, GameFetchStatus>{};
    for (final id in gameIds) {
      statuses[id] = GameFetchStatus.waiting;
    }
    state = BatchFetchState(
      isActive: true,
      gameStatuses: statuses,
      totalGames: gameIds.length,
      completedGames: 0,
    );
  }
  
  /// Cancel the batch fetch (user-initiated)
  void cancelBatch() {
    _cancelled = true;
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

  /// Mark a game as done
  void setDone(int gameId) {
    if (!state.gameStatuses.containsKey(gameId)) return;
    final newStatuses = Map<int, GameFetchStatus>.from(state.gameStatuses);
    newStatuses[gameId] = GameFetchStatus.done;
    state = state.copyWith(
      gameStatuses: newStatuses,
      completedGames: state.completedGames + 1,
      clearCurrentGame: state.currentGameId == gameId,
    );
  }

  /// Mark a game as error
  void setError(int gameId) {
    if (!state.gameStatuses.containsKey(gameId)) return;
    final newStatuses = Map<int, GameFetchStatus>.from(state.gameStatuses);
    newStatuses[gameId] = GameFetchStatus.error;
    state = state.copyWith(
      gameStatuses: newStatuses,
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
