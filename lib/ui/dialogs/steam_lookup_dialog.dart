/// Steam lookup dialog - search and apply Steam data to games
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/steam_service.dart';
import '../../core/theme/app_theme.dart';
import 'package:intl/intl.dart';
import '../../models/game.dart';
import '../../providers/app_providers.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/notification_system.dart';
import '../widgets/section_groupbox.dart';
import '../../core/services/logging.dart';

/// Show Steam lookup dialog for a game
Future<bool?> showSteamLookupDialog(
  BuildContext context,
  Game game, {
  bool forceRefresh = false,
  SteamSearchResult? initialResult,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => SteamLookupDialog(
      game: game,
      forceRefresh: forceRefresh,
      initialResult: initialResult,
    ),
  );
}

class SteamApplyOptions {
  const SteamApplyOptions({
    required this.applyAppId,
    required this.applyTags,
    required this.applyImage,
    required this.applyReviews,
  });

  final bool applyAppId;
  final bool applyTags;
  final bool applyImage;
  final bool applyReviews;

  static const defaults = SteamApplyOptions(
    applyAppId: true,
    applyTags: true,
    applyImage: true,
    applyReviews: true,
  );

  SteamApplyOptions copyWith({
    bool? applyAppId,
    bool? applyTags,
    bool? applyImage,
    bool? applyReviews,
  }) {
    return SteamApplyOptions(
      applyAppId: applyAppId ?? this.applyAppId,
      applyTags: applyTags ?? this.applyTags,
      applyImage: applyImage ?? this.applyImage,
      applyReviews: applyReviews ?? this.applyReviews,
    );
  }
}

/// Apply a SteamSearchResult to a game with the given options.
/// Returns null on success or an error message on failure.
Future<String?> applySteamResultToGame(
  WidgetRef ref,
  Game game,
  SteamSearchResult result,
  SteamApplyOptions options,
) async {
  return _applySteamResultToGameWithRead(
    ref.read,
    ref,
    game,
    result,
    options,
  );
}

/// Apply a SteamSearchResult using a ProviderContainer reader.
Future<String?> applySteamResultToGameWithContainer(
  ProviderContainer container,
  Game game,
  SteamSearchResult result,
  SteamApplyOptions options,
) async {
  return _applySteamResultToGameWithRead(
    container.read,
    container,
    game,
    result,
    options,
  );
}

Future<String?> _applySteamResultToGameWithRead(
  dynamic read,
  dynamic refLike,
  Game game,
  SteamSearchResult result,
  SteamApplyOptions options,
) async {
  try {
    AppLog.d('[applySteamResultToGame] Starting for game: "${game.title}" (ID: ${game.id})');
    AppLog.d('[applySteamResultToGame]   Steam result: AppID=${result.appId}, Tags=[${result.tags.join(", ")}]');
    AppLog.d('[applySteamResultToGame]   Options: applyTags=${options.applyTags}');
    
    final db = read(requireDatabaseProvider);
    final steamService = read(steamServiceProvider);

    // Download image if needed
    String? imagePath;
    if (options.applyImage) {
      try {
        imagePath = await steamService.downloadImage(result.appId);
      } catch (_) {
        imagePath = null;
      }
    }

    // Build tag IDs: keep custom tags, replace Steam tags with fetched ones
    final existingTagEntries = await db.getTagsForGame(game.id);
    AppLog.d('[applySteamResultToGame]   Existing tags from DB: ${existingTagEntries.map((t) => '${t.name}(${t.isSteamTag ? "steam" : "custom"})').join(", ")}');
    
    // Keep only custom (non-Steam) tags
    final customTagIds = existingTagEntries
        .where((t) => !t.isSteamTag)
        .map((t) => t.id)
        .toList();
    AppLog.d('[applySteamResultToGame]   Custom tag IDs to keep: $customTagIds');
    final newTagIds = <int>{...customTagIds};

    if (options.applyTags && result.tags.isNotEmpty) {
      // Add the newly fetched Steam tags (replacing old Steam tags)
      AppLog.d('[applySteamResultToGame]   Applying NEW Steam tags: ${result.tags.join(", ")}');
      for (final tagName in result.tags) {
        final tag = await db.getOrCreateTag(tagName, isSteamTag: true);
        AppLog.d('[applySteamResultToGame]     Created/got tag: ${tag.name} (ID: ${tag.id})');
        newTagIds.add(tag.id);
      }
    } else {
      // If not applying tags, keep existing Steam tags too
      final existingSteamTagIds = existingTagEntries
          .where((t) => t.isSteamTag)
          .map((t) => t.id);
      AppLog.d('[applySteamResultToGame]   NOT applying tags, keeping existing Steam tag IDs: $existingSteamTagIds');
      newTagIds.addAll(existingSteamTagIds);
    }
    
    AppLog.d('[applySteamResultToGame]   Final tag IDs to save: ${newTagIds.toList()}');

    final updatedGame = game.copyWith(
      isDlc: result.isDlc,
      steamAppId: options.applyAppId ? result.appId : game.steamAppId,
      reviewScore: options.applyReviews
          ? (result.reviewScore ?? game.reviewScore)
          : game.reviewScore,
      reviewCount: options.applyReviews
          ? (result.reviewCount ?? game.reviewCount)
          : game.reviewCount,
      coverImage: options.applyImage
          ? (imagePath ?? result.imageUrl ?? game.coverImage)
          : game.coverImage,
    );

    final success = await read(gamesProvider.notifier)
      .updateGame(updatedGame, tagIds: newTagIds.toList());

    if (!success) {
      AppLog.w('[applySteamResultToGame]   FAILED to update game');
      return 'Failed to update game with Steam data';
    }

    await read(tagsProvider.notifier).refresh();
    await read(gamesProvider.notifier).refreshGame(game.id);
    
    // Verify what was actually saved
    final verifyTags = await db.getTagsForGame(game.id);
    AppLog.i('[applySteamResultToGame]   VERIFIED tags after save: ${verifyTags.map((t) => '${t.name}(ID:${t.id},${t.isSteamTag ? "steam" : "custom"})').join(", ")}');
    
    await persistEncryptedDbIfNeeded(refLike);

    return null;
  } catch (e) {
    return e.toString();
  }
}

/// Show a two-button options dialog when cached Steam data exists.
/// Returns a map with keys: 'choice' -> 'cache'|'fresh', 'cached' -> SteamSearchResult?, 'applyToAll' -> bool, 'options' -> SteamApplyOptions.
Future<Map<String, dynamic>> showSteamFetchOptionsDialog(
  BuildContext context, {
  required String title,
  bool showApplyToAll = false,
  bool showApplyOptions = true,
}) async {
  final container = ProviderScope.containerOf(context);

  // Use top-level cache helpers to avoid depending on a service instance
  SteamSearchResult? cached;
  DateTime? cachedAt;

  // Only use title-based cache/lookups. AppID-based lookups are removed for consistency.
  cached = await getCachedResultForTitle(title);
  cachedAt = await getCachedAtForTitle(title);

  // If no cache and no options/applyToAll needed, return immediately
  if (cached == null && !showApplyOptions && !showApplyToAll) {
    return {
      'choice': 'fresh',
      'cached': null,
      'applyToAll': false,
      'options': SteamApplyOptions.defaults,
    };
  }

  if (!context.mounted) {
    return {
      'choice': 'fresh',
      'cached': null,
      'applyToAll': false,
      'options': SteamApplyOptions.defaults,
    };
  }

  final theme = container.read(themeProvider);

  // Use a stateful builder to capture the 'apply to all' checkbox state when requested
  bool applyToAll = false;
  bool applyAppId = true;
  bool applyTags = true;
  bool applyImage = true;
  bool applyReviews = true;
  final choice = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx2, setState2) {
          return AlertDialog(
            backgroundColor: theme.background,
            title: Row(
              children: [
                Icon(Icons.cloud_download, color: theme.accent),
                const SizedBox(width: 12),
                Text(
                  cached != null ? 'Steam Data Cache' : 'Steam Data Options',
                  style: TextStyle(color: theme.textPrimary),
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (cached != null) ...[
                    Text('Cached data found for "$title"'),
                    const SizedBox(height: 8),
                    Text(
                      'Cached at: ${cachedAt != null ? DateFormat('dd/MM/yyyy HH:mm').format(cachedAt) : 'Unknown'}',
                      style: TextStyle(color: theme.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Choose whether to use cached data or fetch fresh data from Steam.',
                    ),
                  ] else ...[
                    Text('No cached data found for "$title"'),
                    const SizedBox(height: 12),
                    Text(
                      'Configure options for fetching fresh data from Steam.',
                    ),
                  ],
                  if (showApplyOptions) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Apply Options',
                      style: TextStyle(
                        color: theme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: applyAppId,
                      onChanged: (v) => setState2(() => applyAppId = v),
                      title: const Text('AppID'),
                      subtitle: const Text('Save Steam AppID'),
                      activeThumbColor: theme.accent,
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      value: applyTags,
                      onChanged: (v) => setState2(() => applyTags = v),
                      title: const Text('Tags'),
                      subtitle: const Text('Add Steam tags'),
                      activeThumbColor: theme.accent,
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      value: applyImage,
                      onChanged: (v) => setState2(() => applyImage = v),
                      title: const Text('Cover Image'),
                      subtitle: const Text('Download Steam header image'),
                      activeThumbColor: theme.accent,
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      value: applyReviews,
                      onChanged: (v) => setState2(() => applyReviews = v),
                      title: const Text('Reviews'),
                      subtitle: const Text('Score and review count'),
                      activeThumbColor: theme.accent,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                  if (showApplyToAll) ...[
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: applyToAll,
                      onChanged: (v) =>
                          setState2(() => applyToAll = v ?? false),
                      title: const Text(
                        'Do this for all remaining selected games',
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('Cancel'),
              ),
              if (cached != null)
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cache'),
                  child: Text('Use Cache'),
                ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, 'fresh'),
                child: Text(cached != null ? 'Fetch Fresh' : 'OK'),
              ),
            ],
          );
        },
      );
    },
  );

  if (choice == null || choice == 'cancel') {
    return {
      'choice': 'cancel',
      'cached': null,
      'applyToAll': false,
      'options': SteamApplyOptions.defaults,
    };
  }

  final options = SteamApplyOptions(
    applyAppId: applyAppId,
    applyTags: applyTags,
    applyImage: applyImage,
    applyReviews: applyReviews,
  );

  if (choice == 'cache') {
    return {
      'choice': 'cache',
      'cached': cached,
      'applyToAll': applyToAll,
      'options': options,
    };
  }
  return {
    'choice': 'fresh',
    'cached': null,
    'applyToAll': applyToAll,
    'options': options,
  };
}

class SteamFetchResolution {
  const SteamFetchResolution({
    required this.cancelled,
    required this.result,
    required this.usedCache,
    this.cachedAt,
  });

  final bool cancelled;
  final SteamSearchResult? result;
  final bool usedCache;
  final DateTime? cachedAt;
}

Future<SteamFetchResolution> resolveSteamResultForTitle(
  BuildContext context, {
  required String title,
  required SteamService steamService,
  bool promptForCacheChoice = true,
}) async {
  DateTime? cachedAt;

  if (promptForCacheChoice) {
    cachedAt = await getCachedAtForTitle(title);
    if (!context.mounted) {
      return const SteamFetchResolution(
        cancelled: true,
        result: null,
        usedCache: false,
      );
    }
    final choice = await showSteamFetchOptionsDialog(
      context,
      title: title,
      showApplyToAll: false,
      showApplyOptions: false,
    );

    if (choice['choice'] == 'cancel') {
      return const SteamFetchResolution(
        cancelled: true,
        result: null,
        usedCache: false,
      );
    }

    if (choice['choice'] == 'cache' && choice['cached'] != null) {
      return SteamFetchResolution(
        cancelled: false,
        result: choice['cached'] as SteamSearchResult,
        usedCache: true,
        cachedAt: cachedAt,
      );
    }
  }

  final result = await steamService.searchGame(title, forceRefresh: true);
  return SteamFetchResolution(
    cancelled: false,
    result: result,
    usedCache: false,
    cachedAt: cachedAt,
  );
}

/// Perform a batch Steam lookup for the given games.
///
/// This central helper is used by individual game cards and by the
/// selection action bar so both paths share the exact same behaviour,
/// notifications and cancellation handling.
Future<void> performSteamBatchLookup(
  BuildContext context,
  List<Game> targets, {
  bool promptForOptions = true,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final batchNotifier = container.read(batchFetchProvider.notifier);

  final steamTargets = targets.where((g) => g.platform == 'Steam').toList();
  if (steamTargets.isEmpty) {
    NotificationManager.instance.info('No Steam games selected');
    return;
  }

  final gameSnapshots = steamTargets.map((g) => {'id': g.id, 'title': g.title}).toList();
  final total = gameSnapshots.length;

  // Start batch fetch tracking
  batchNotifier.startBatch(gameSnapshots.map((g) => g['id'] as int).toList());

  late NotificationHandle handle;
  handle = NotificationManager.instance.beginTask(
    'Fetching Steam data',
    type: NotificationType.steam,
    title: 'Starting...',
    progress: 0,
    actionLabel: 'Cancel',
    onAction: () {
      batchNotifier.cancelBatch();
      handle.update(message: 'Cancelling...', clearAction: true);
    },
  );

  int updated = 0;
  int notFound = 0;
  int failed = 0;

  bool applyToAll = false;
  String? choiceForAll;
  SteamApplyOptions optionsForAll = SteamApplyOptions.defaults;

  for (var i = 0; i < gameSnapshots.length; i++) {
    final gameSnapshot = gameSnapshots[i];
    final gameId = gameSnapshot['id'] as int;
    final gameTitle = gameSnapshot['title'] as String;

    // Check for cancellation (user-initiated via notification button)
    if (batchNotifier.isCancelled) break;

    // Mark this game as processing
    batchNotifier.setProcessing(gameId);

    // Auto-deselect the game being fetched so the selection UI reflects
    // in-progress items and the user can continue selecting other games.
    // This mirrors the UX of the context-menu path and keeps behavior
    // deterministic for batch operations.
    try {
      container.read(gamesProvider.notifier).deselectGame(gameId);
    } catch (_) {
      // Non-fatal: provider may not be available in some test harnesses.
    }

    handle.update(
      message: 'Fetching Steam data (${i + 1}/$total)',
      title: gameTitle,
      progress: total == 0 ? 0 : (i / total).clamp(0.0, 1.0),
    );

    String choice;
    SteamSearchResult? cached;
    SteamApplyOptions options;

    if (!promptForOptions) {
      choice = 'fresh';
      cached = null;
      options = SteamApplyOptions.defaults;
    } else if (!applyToAll) {
      if (!context.mounted) {
        // Continue processing without dialog - use fresh fetch
        choice = 'fresh';
        cached = null;
        options = SteamApplyOptions.defaults;
      } else {
        final selection = await showSteamFetchOptionsDialog(
          context,
          title: gameTitle,
          showApplyToAll: true,
        );

        // Check cancellation after dialog
        if (batchNotifier.isCancelled) break;

        choice = selection['choice'] as String;
        if (choice == 'cancel') {
          batchNotifier.cancelBatch();
          handle.update(message: 'Cancelled', clearAction: true);
          break;
        }
        cached = selection['cached'] as SteamSearchResult?;
        options = (selection['options'] as SteamApplyOptions?) ?? SteamApplyOptions.defaults;

        final pickedApplyToAll = selection['applyToAll'] == true;
        if (pickedApplyToAll) {
          applyToAll = true;
          choiceForAll = choice;
          optionsForAll = options;
        }
      }
    } else {
      choice = choiceForAll ?? 'fresh';
      options = optionsForAll;
      if (choice == 'cache') {
        cached = await getCachedResultForTitle(gameTitle);
        // Check cancellation after cache lookup
        if (batchNotifier.isCancelled) break;
      } else {
        cached = null;
      }
    }

    // Fetch the current game state from provider just before applying
    final games = container.read(gamesProvider).games;
    final game = games.firstWhere((g) => g.id == gameId, orElse: () => steamTargets.firstWhere((g) => g.id == gameId));

    AppLog.d('[SteamBatchFetch] Processing game ${i + 1}/$total: "${game.title}" (ID: ${game.id})');
    AppLog.d('[SteamBatchFetch]   Current tags: ${game.tags.map((t) => '${t.name}(${t.isSteamTag ? "steam" : "custom"})').join(", ")}');

    // Resolve result for the chosen option
    SteamSearchResult? result;
    if (choice == 'cache' && cached != null) {
      result = cached;
    } else {
      final steamService = container.read(steamServiceProvider);
      result = await steamService.searchGame(game.title, forceRefresh: true);
    }

    // Check cancellation after fetch
    if (batchNotifier.isCancelled) break;

    if (result == null) {
      AppLog.d('[SteamBatchFetch]   Result: NOT FOUND');
      batchNotifier.setError(gameId);
      notFound++;
      continue;
    }

    // Apply the fetched result via the container-friendly API
    try {
      final applyError = await applySteamResultToGameWithContainer(
        container,
        game,
        result,
        options,
      );

      if (applyError != null) {
        AppLog.w('[SteamBatchFetch]   ERROR APPLYING: $applyError');
        batchNotifier.setError(gameId);
        failed++;
      } else {
        AppLog.i('[SteamBatchFetch]   SUCCESS: Updated game');
        batchNotifier.setDone(gameId);
        updated++;
      }
    } catch (e, st) {
      AppLog.w('[SteamBatchFetch]   ERROR: $e\n$st');
      batchNotifier.setError(gameId);
      failed++;
    }

    // Check cancellation after applying
    if (batchNotifier.isCancelled) break;
  }

  AppLog.i('[SteamBatchFetch] Batch complete: updated=$updated, notFound=$notFound, failed=$failed');

  handle.setProgress(1);
  // End batch fetch after a short delay to show completion status
  Future.delayed(const Duration(seconds: 2), () {
    batchNotifier.endBatch();
  });

  if (failed > 0) {
    handle.completeError('Updated $updated, failed $failed, not found $notFound');
  } else {
    handle.completeSuccess('Updated $updated, not found $notFound');
  }
}

/// Steam lookup dialog
class SteamLookupDialog extends ConsumerStatefulWidget {
  const SteamLookupDialog({
    super.key,
    required this.game,
    this.forceRefresh = false,
    this.initialResult,
  });

  final Game game;
  final bool forceRefresh;
  final SteamSearchResult? initialResult;

  @override
  ConsumerState<SteamLookupDialog> createState() => _SteamLookupDialogState();
}

class _SteamLookupDialogState extends ConsumerState<SteamLookupDialog> {
  bool _isSearching = false;
  bool _isApplying = false;
  SteamSearchResult? _result;
  String? _error;

  // Options for what to apply
  bool _applyAppId = true;
  bool _applyTags = true;
  bool _applyImage = true;
  bool _applyReviews = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialResult != null) {
      _result = widget.initialResult;
      _isSearching = false;
    } else {
      _searchSteam(forceRefresh: widget.forceRefresh);
    }
  }

  Future<void> _searchSteam({bool forceRefresh = false}) async {
    setState(() {
      _isSearching = true;
      _error = null;
      _result = null;
    });

    try {
      final steamService = ref.read(steamServiceProvider);

      // Always search by title (no AppID-based lookup)
      final result = await steamService.searchGame(
        widget.game.title,
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;
      setState(() {
        _result = result;
        _isSearching = false;
        if (result == null) {
          _error = 'No matching game found on Steam';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isSearching = false;
      });
    }
  }

  Future<void> _applyData() async {
    if (_result == null) return;

    setState(() => _isApplying = true);

    try {
      final options = SteamApplyOptions(
        applyAppId: _applyAppId,
        applyTags: _applyTags,
        applyImage: _applyImage,
        applyReviews: _applyReviews,
      );

      final error = await applySteamResultToGame(
        ref,
        widget.game,
        _result!,
        options,
      );

      if (error != null) {
        NotificationManager.instance.error('Failed to apply Steam data: $error');
        if (mounted) setState(() => _isApplying = false);
        return;
      }

      NotificationManager.instance.success(
        'Updated "${widget.game.title}" with Steam data',
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      NotificationManager.instance.error('Failed to apply Steam data: $e');
      if (mounted) setState(() => _isApplying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);

    return AlertDialog(
      backgroundColor: theme.background,
      title: DialogHeader(
        icon: Icons.cloud_download,
        title: 'Steam Lookup',
        theme: theme,
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Game being looked up
              SectionGroupBox(
                title: 'Looking up',
                theme: theme,
                child: Text(
                  widget.game.title,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Search status / results
              if (_isSearching)
                _buildSearchingState(theme)
              else if (_error != null)
                _buildErrorState(theme)
              else if (_result != null)
                _buildResultState(theme),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isApplying ? null : () => Navigator.pop(context, false),
          child: Text('Cancel', style: TextStyle(color: theme.textSecondary)),
        ),
        if (_result != null && !_isSearching)
          ElevatedButton(
            onPressed: _isApplying ? null : _applyData,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.accent,
              foregroundColor: Colors.white,
            ),
            child: _isApplying
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Apply'),
          ),
      ],
    );
  }

  Widget _buildSearchingState(AppThemeData theme) {
    return SectionGroupBox(
      title: 'Searching Steam...',
      theme: theme,
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _buildErrorState(AppThemeData theme) {
    return SectionGroupBox(
      title: 'Search Failed',
      theme: theme,
      child: Column(
        children: [
          Icon(Icons.error_outline, color: theme.error, size: 48),
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: theme.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _searchSteam,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildResultState(AppThemeData theme) {
    final imageUrl = _result?.imageUrl?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Found game info
        SectionGroupBox(
          title: 'Found on Steam',
          theme: theme,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Game image
              ClipRRect(
                borderRadius: BorderRadius.circular(theme.cornerRadius),
                child: (imageUrl.isNotEmpty && imageUrl.startsWith('http'))
                    ? Image.network(
                        imageUrl,
                        width: 120,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 120,
                          height: 56,
                          color: theme.surface,
                          child: Icon(
                            Icons.image_not_supported,
                            color: theme.textHint,
                          ),
                        ),
                      )
                    : Container(
                        width: 120,
                        height: 56,
                        color: theme.surface,
                        child: Icon(
                          Icons.image_not_supported,
                          color: theme.textHint,
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              // Game details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _result!.name,
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'AppID: ${_result!.appId}',
                      style: TextStyle(
                        color: theme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if (_result!.isDlc) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'DLC',
                          style: TextStyle(
                            color: theme.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Tags preview
        if (_result!.tags.isNotEmpty) ...[
          SectionGroupBox(
            title: 'Tags (${_result!.tags.length})',
            theme: theme,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _result!.tags.map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.accent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(color: theme.textPrimary, fontSize: 12),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Apply options
        SectionGroupBox(
          title: 'Apply Options',
          theme: theme,
          child: Column(
            children: [
              _buildOption(
                theme,
                'AppID',
                'Save Steam AppID: ${_result!.appId}',
                _applyAppId,
                (v) => setState(() => _applyAppId = v),
              ),
              if (_result!.tags.isNotEmpty)
                _buildOption(
                  theme,
                  'Tags',
                  'Add ${_result!.tags.length} Steam tags',
                  _applyTags,
                  (v) => setState(() => _applyTags = v),
                ),
              _buildOption(
                theme,
                'Cover Image',
                'Download Steam header image',
                _applyImage,
                (v) => setState(() => _applyImage = v),
              ),
              if (_result!.reviewScore != null)
                _buildOption(
                  theme,
                  'Reviews',
                  'Score: ${_result!.reviewScore}%',
                  _applyReviews,
                  (v) => setState(() => _applyReviews = v),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOption(
    AppThemeData theme,
    String label,
    String description,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(color: theme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: theme.accent,
          ),
        ],
      ),
    );
  }
}
