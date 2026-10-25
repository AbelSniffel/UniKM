/// Steam lookup dialog - search and apply Steam data to games
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../features/steam/application/apply_steam_metadata.dart';
export '../../features/steam/application/apply_steam_metadata.dart'
    show SteamApplyOptions;
import '../../core/services/deadline_notification_service.dart';
import '../../core/services/steam_service.dart';
import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import 'package:intl/intl.dart';
import '../../models/game.dart';
import '../../providers/app_providers.dart';
import '../pages/settings_sections/settings_control_cards.dart';
import '../../core/constants/app_constants.dart';
import '../widgets/app_progress_indicator.dart';
import '../widgets/tag_list.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/notification_system.dart';
import '../widgets/section_groupbox.dart';
import '../widgets/game_cover_image.dart';
import '../widgets/steam_lookup_info_menu.dart';
import '../../core/services/logging.dart';

/// Show Steam lookup dialog for a game
Future<bool?> showSteamLookupDialog(
  BuildContext context,
  Game game, {
  bool forceRefresh = false,
  SteamSearchResult? initialResult,
}) {
  return showAppDialog<bool>(
    context: context,
    builder: (ctx) => SteamLookupDialog(
      game: game,
      forceRefresh: forceRefresh,
      initialResult: initialResult,
    ),
  );
}

/// Both fetch choices and result previews edit the same immutable options.
class _SteamOptionsGrid extends StatelessWidget {
  const _SteamOptionsGrid({
    required this.theme,
    required this.options,
    required this.onChanged,
    this.result,
  });

  final AppThemeData theme;
  final SteamApplyOptions options;
  final ValueChanged<SteamApplyOptions> onChanged;
  final SteamSearchResult? result;

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    final reviews = [
      if (result?.reviewScore != null) '${result!.reviewScore}% positive',
      if (result?.reviewCount != null)
        '${NumberFormat.compact().format(result!.reviewCount)} reviews',
    ].join(' · ');
    Widget option(
      String label,
      String description,
      bool value,
      SteamApplyOptions Function(bool) update,
    ) => SettingsToggleCard(
      theme: theme,
      label: label,
      description: description,
      value: value,
      onChanged: (value) => onChanged(update(value)),
    );
    return SettingsControlWrap(
      minimumCardWidth:
          kInteractionCardMinWidth *
          MediaQuery.textScalerOf(context).scale(14) /
          14,
      children: [
        option(
          'AppID',
          result == null ? 'Save Steam AppID' : 'Save AppID ${result.appId}',
          options.applyAppId,
          (v) => options.copyWith(applyAppId: v),
        ),
        if (result == null || result.tags.isNotEmpty)
          option(
            'Tags',
            result == null
                ? 'Add Steam tags'
                : 'Add ${result.tags.length} Steam tags',
            options.applyTags,
            (v) => options.copyWith(applyTags: v),
          ),
        option(
          'Cover Image',
          result == null
              ? 'Download Steam header image'
              : 'Steam header artwork',
          options.applyImage,
          (v) => options.copyWith(applyImage: v),
        ),
        option(
          'Developer',
          result == null
              ? 'Add game developer name'
              : result.developer?.trim().isNotEmpty == true
              ? result.developer!
              : 'No developer supplied',
          options.applyDeveloper,
          (v) => options.copyWith(applyDeveloper: v),
        ),
        if (result == null || reviews.isNotEmpty)
          option(
            'Reviews',
            result == null ? 'Score and review count' : reviews,
            options.applyReviews,
            (v) => options.copyWith(applyReviews: v),
          ),
      ],
    );
  }
}

List<Tag> _steamPreviewTags(List<String> names) => List.generate(
  names.length,
  (index) => Tag(
    id: -(index + 1),
    name: names[index],
    colorHex: '#000000',
    isSteamTag: true,
  ),
);

/// Apply a SteamSearchResult to a game with the given options.
/// Returns null on success or an error message on failure.
Future<String?> applySteamResultToGame(
  ProviderContainer container,
  Game game,
  SteamSearchResult result,
  SteamApplyOptions options, {
  int? expectedRevision,
  bool Function()? isCancelled,
}) async {
  try {
    final session = container.read(databaseNotifierProvider);
    final db = session.database;
    if (db == null ||
        (expectedRevision != null && expectedRevision != session.revision)) {
      throw StateError('Database session changed during the operation');
    }
    final steamService = container.read(steamServiceProvider);
    await ApplySteamMetadata(
      database: db,
      isCurrent: () =>
          container.read(databaseNotifierProvider).revision ==
              session.revision &&
          !(isCancelled?.call() ?? false),
      downloadImage: (appId) =>
          steamService.downloadImage(appId, imageUrl: result.imageUrl),
    ).apply(game.id, result, options);
    await persistEncryptedDbIfNeeded(container, database: db);
    return null;
  } catch (e) {
    return e.toString();
  }
}

/// A confirmed fetch choice. [cached] is set when the user chose cached data.
typedef SteamFetchChoice = ({
  SteamSearchResult? cached,
  DateTime? cachedAt,
  SteamApplyOptions options,
});

/// Show Steam fetch options, including a cache choice when cached data exists.
/// Returns null when cancelled.
Future<SteamFetchChoice?> showSteamFetchOptionsDialog(
  BuildContext context, {
  required String title,
  bool showApplyOptions = true,
}) async {
  final container = ProviderScope.containerOf(context);

  // Only use title-based cache/lookups. AppID-based lookups are removed for consistency.
  final preview = AppDialogPreviewScope.maybeOf(context);
  final cached = preview != null
      ? preview.steamResult
      : await getCachedResultForTitle(title);
  final cachedAt = preview != null
      ? preview.steamCachedAt
      : await getCachedAtForTitle(title);

  // Without a cache or apply options there is nothing to ask.
  if ((cached == null && !showApplyOptions) || !context.mounted) {
    return (
      cached: null,
      cachedAt: cachedAt,
      options: SteamApplyOptions.defaults,
    );
  }

  final theme = container.read(themeProvider);

  var options = SteamApplyOptions.defaults;
  final useCache = await showAppDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx2, setState2) {
          return ThemedAlertDialog(
            theme: theme,

            title: DialogHeader(
              icon: Icons.cloud_download,
              title: cached != null ? 'Steam Data Cache' : 'Steam Data Options',
              theme: theme,
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (cached != null) ...[
                    Text('Cached data found for "$title"'),
                    const SizedBox(height: kElementVSpacing),
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
                    const SizedBox(height: kDialogSpacing),
                    SectionGroupBox(
                      title: 'Apply Options',
                      theme: theme,
                      titleIcon: Icons.tune,
                      child: _SteamOptionsGrid(
                        theme: theme,
                        options: options,
                        onChanged: (value) => setState2(() => options = value),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (cached != null)
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('Use Cache'),
                ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(cached != null ? 'Fetch Fresh' : 'Fetch'),
              ),
            ],
          );
        },
      );
    },
  );

  if (useCache == null) return null;
  return (
    cached: useCache ? cached : null,
    cachedAt: cachedAt,
    options: options,
  );
}

/// The data a single fetch resolved to; [cachedAt] is when the cache entry
/// was written, whether or not it was used.
typedef SteamFetchResolution = ({
  SteamSearchResult? result,
  bool usedCache,
  DateTime? cachedAt,
});

/// Asks whether to use cached data, then resolves the result.
/// Returns null when cancelled.
Future<SteamFetchResolution?> resolveSteamResultForTitle(
  BuildContext context, {
  required String title,
  required SteamService steamService,
}) async {
  final choice = await showSteamFetchOptionsDialog(
    context,
    title: title,
    showApplyOptions: false,
  );
  if (choice == null) return null;
  final cached = choice.cached;
  return (
    result: cached ?? await steamService.searchGame(title, forceRefresh: true),
    usedCache: cached != null,
    cachedAt: choice.cachedAt,
  );
}

Future<void> performSingleSteamLookup(
  BuildContext context,
  WidgetRef ref,
  Game game,
) async {
  final sessionRevision = ref.read(databaseNotifierProvider).revision;
  final batchNotifier = ref.read(batchFetchProvider.notifier);
  batchNotifier.startBatch([game.id]);
  batchNotifier.setProcessing(game.id);

  final steamService = ref.read(steamServiceProvider);
  try {
    final resolution = await resolveSteamResultForTitle(
      context,
      title: game.title,
      steamService: steamService,
    );
    if (!context.mounted ||
        resolution == null ||
        ref.read(databaseNotifierProvider).revision != sessionRevision) {
      return;
    }

    final result = resolution.result;
    if (result == null) {
      NotificationManager.instance.info(
        'No Steam data found for "${game.title}"',
      );
      return;
    }

    await showSteamLookupDialog(context, game, initialResult: result);
  } finally {
    batchNotifier.endBatch();
  }
}

/// Perform a batch Steam lookup for the given games.
///
/// This central helper is used by individual game cards and by the
/// selection action bar so both paths share the exact same behaviour,
/// notifications and cancellation handling.
/// The first confirmed fetch choice and apply options are reused for the batch.
Future<void> performSteamBatchLookup(
  BuildContext context,
  List<Game> targets, {
  bool promptForOptions = true,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final sessionRevision = container.read(databaseNotifierProvider).revision;
  final batchNotifier = container.read(batchFetchProvider.notifier);
  bool stopped() =>
      batchNotifier.isCancelled ||
      container.read(databaseNotifierProvider).revision != sessionRevision;

  final steamTargets = targets.where((g) => g.platform == 'Steam').toList();
  if (steamTargets.isEmpty) {
    NotificationManager.instance.info('No Steam games selected');
    return;
  }
  final total = steamTargets.length;

  // Start batch fetch tracking
  batchNotifier.startBatch([for (final g in steamTargets) g.id]);

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
  final freshResultCache = <String, SteamSearchResult>{};

  // The first confirmed choice applies to the rest of the batch.
  SteamFetchChoice? choiceForAll;

  for (var i = 0; i < total; i++) {
    final target = steamTargets[i];
    final gameId = target.id;
    final gameTitle = target.title;

    // Check for cancellation (user-initiated via notification button)
    if (stopped()) break;

    // Mark this game as processing
    batchNotifier.setProcessing(gameId);

    // Auto-deselect the game being fetched so the selection UI reflects
    // in-progress items and the user can continue selecting other games.
    try {
      container.read(gamesProvider.notifier).deselectGame(gameId);
    } catch (_) {
      // Non-fatal: provider may not be available in some test harnesses.
    }

    handle.update(
      message: 'Fetching Steam data (${i + 1}/$total)',
      title: gameTitle,
      progress: (i / total).clamp(0.0, 1.0),
    );
    unawaited(
      DeadlineNotificationService.instance.showFetchProgressNotification(
        completed: i,
        total: total,
        currentTitle: gameTitle,
      ),
    );

    // Without a prompt (or a mounted context) the batch fetches fresh data.
    SteamSearchResult? cached;
    var options = SteamApplyOptions.defaults;
    final chosen = choiceForAll;
    if (chosen != null) {
      options = chosen.options;
      if (chosen.cached != null) {
        cached = await getCachedResultForTitle(gameTitle);
        if (stopped()) break;
      }
    } else if (promptForOptions && context.mounted) {
      final selection = await showSteamFetchOptionsDialog(
        context,
        title: gameTitle,
      );
      if (stopped()) break;
      if (selection == null) {
        batchNotifier.cancelBatch();
        handle.update(message: 'Cancelled', clearAction: true);
        break;
      }
      cached = selection.cached;
      options = selection.options;
      choiceForAll = selection;
    }

    // Fetch the current game state from provider just before applying
    final game = container
        .read(gamesProvider)
        .games
        .firstWhere((g) => g.id == gameId, orElse: () => target);

    AppLog.d(
      '[SteamBatchFetch] Processing game ${i + 1}/$total: "${game.title}" (ID: ${game.id})',
    );
    AppLog.d(
      '[SteamBatchFetch]   Current tags: ${game.tags.map((t) => '${t.name}(${t.isSteamTag ? "steam" : "custom"})').join(", ")}',
    );

    // A later game with the same title reuses this result instead of the
    // network.
    final batchCacheKey = cleanTitleForSearch(game.title);
    final result =
        cached ??
        freshResultCache[batchCacheKey] ??
        await container
            .read(steamServiceProvider)
            .searchGame(game.title, forceRefresh: true);
    if (result != null) freshResultCache[batchCacheKey] = result;

    // Check cancellation after fetch
    if (stopped()) break;

    if (result == null) {
      AppLog.d('[SteamBatchFetch]   Result: NOT FOUND');
      batchNotifier.setError(gameId);
      notFound++;
      continue;
    }

    final applyError = await applySteamResultToGame(
      container,
      game,
      result,
      options,
      expectedRevision: sessionRevision,
      isCancelled: () => batchNotifier.isCancelled,
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

    // Check cancellation after applying
    if (stopped()) break;
  }

  AppLog.i(
    '[SteamBatchFetch] Batch complete: updated=$updated, notFound=$notFound, failed=$failed',
  );

  handle.setProgress(1);
  unawaited(
    DeadlineNotificationService.instance.clearFetchProgressNotification(),
  );
  if (batchNotifier.isCancelled) {
    // Cancelled: clear state immediately so overlays disappear without delay.
    batchNotifier.endBatch();
  } else {
    // Normal completion: keep done/error status visible briefly then clear.
    Future.delayed(const Duration(seconds: 2), batchNotifier.endBatch);
  }

  final summary = [
    'Updated $updated',
    if (failed > 0) 'failed $failed',
    if (notFound > 0) 'not found $notFound',
  ].join(', ');
  if (failed > 0) {
    handle.completeError(summary);
  } else {
    handle.completeSuccess(summary);
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
  late final int _sessionRevision;
  bool _isSearching = false;
  bool _isApplying = false;
  SteamSearchResult? _result;
  final _coverDownloads = <String, Future<String?>>{};
  String? _error;

  var _options = SteamApplyOptions.defaults;

  @override
  void initState() {
    super.initState();
    _sessionRevision = ref.read(databaseNotifierProvider).revision;
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
        if (result == null) _error = 'No matching game found on Steam';
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
      final error = await applySteamResultToGame(
        ProviderScope.containerOf(context, listen: false),
        widget.game,
        _result!,
        _options,
        expectedRevision: _sessionRevision,
      );

      if (error != null) {
        NotificationManager.instance.error(
          'Failed to apply Steam data: $error',
        );
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

    return ThemedAlertDialog(
      theme: theme,

      title: DialogHeader(
        icon: Icons.cloud_download,
        title: 'Steam Lookup',
        theme: theme,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isSearching)
            _buildSearchingState(theme)
          else if (_error != null)
            _buildErrorState(theme)
          else if (_result != null)
            _buildResultState(theme),
        ],
      ),
      actions: [
        if (_result != null && !_isSearching)
          ElevatedButton(
            onPressed: _isApplying ? null : _applyData,
            child: _isApplying
                ? const AppCircularProgressIndicator(size: 20)
                : const Text('Save'),
          ),
      ],
    );
  }

  Widget _buildSearchingState(AppThemeData theme) => SectionGroupBox(
    title: 'Searching Steam...',
    theme: theme,
    titleIcon: FontAwesomeIcons.steam.data,
    titleLocation: SectionTitleLocation.top,
    alternateBackground: true,
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Center(child: AppCircularProgressIndicator()),
          const SizedBox(height: kDialogSpacing),
          Text(
            widget.game.title,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.textSecondary),
          ),
        ],
      ),
    ),
  );

  Widget _buildErrorState(AppThemeData theme) => SectionGroupBox(
    title: 'Search Failed',
    theme: theme,
    titleIcon: Icons.error,
    titleLocation: SectionTitleLocation.top,
    alternateBackground: true,
    child: Column(
      children: [
        Icon(Icons.error, color: theme.error, size: 48),
        const SizedBox(height: kDialogSpacing),
        Text(
          widget.game.title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: theme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: kDialogSpacing),
        Text(
          _error!,
          style: TextStyle(color: theme.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: kDialogSpacing),
        TextButton.icon(
          onPressed: _searchSteam,
          icon: const Icon(Icons.refresh),
          label: const Text('Try Again'),
        ),
      ],
    ),
  );

  Widget _buildResultState(AppThemeData theme) {
    final result = _result!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionGroupBox(
          title: 'Found on Steam',
          theme: theme,
          titleIcon: FontAwesomeIcons.steam.data,
          titleLocation: SectionTitleLocation.top,
          groupPosition: SectionGroupPosition.first,
          headerCrossAxisAlignment: CrossAxisAlignment.center,
          trailing: SteamLookupInfoMenu(
            theme: theme,
            searchedTitle: widget.game.title,
            result: result,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildGameSummary(theme, result),
              if (result.tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Steam tags (${result.tags.length})',
                  style: TextStyle(color: theme.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 6),
                TagList(
                  tags: _steamPreviewTags(result.tags),
                  theme: theme,
                  allSelected: true,
                  maxHeight: 96,
                ),
              ],
            ],
          ),
        ),
        SectionGroupBox(
          title: 'Apply Options',
          theme: theme,
          titleIcon: Icons.tune,
          titleLocation: SectionTitleLocation.top,
          groupPosition: SectionGroupPosition.last,
          alternateBackground: true,
          child: _SteamOptionsGrid(
            theme: theme,
            options: _options,
            result: result,
            onChanged: (value) => setState(() => _options = value),
          ),
        ),
      ],
    );
  }

  Widget _buildGameSummary(
    AppThemeData theme,
    SteamSearchResult result,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final imageWidth = (constraints.maxWidth * 0.3).clamp(64.0, 148.0);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(theme.cornerRadius),
            child: SizedBox(
              width: imageWidth,
              height: imageWidth * 215 / 460,
              child: AppDialogPreviewScope.maybeOf(context) != null
                  ? GameCoverImage(theme: theme, coverImage: result.imageUrl)
                  : FutureBuilder<String?>(
                      future: _coverDownloads.putIfAbsent(
                        result.appId,
                        () => ref
                            .read(steamServiceProvider)
                            .downloadImage(
                              result.appId,
                              imageUrl: result.imageUrl,
                            ),
                      ),
                      builder: (context, snapshot) => GameCoverImage(
                        theme: theme,
                        coverImage: snapshot.data,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.name,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (result.developer?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    result.developer!,
                    style: TextStyle(color: theme.textSecondary, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _detailBadge(theme, 'AppID ${result.appId}'),
                    if (result.isDlc) _detailBadge(theme, 'DLC'),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _detailBadge(AppThemeData theme, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: theme.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(theme.cornerRadius),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: theme.accent,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}
