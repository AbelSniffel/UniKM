/// Steam lookup dialog - search and apply Steam data to games
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/steam/application/apply_steam_metadata.dart';
import '../../core/services/deadline_notification_service.dart';
import '../../core/services/steam_service.dart';
import '../../core/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/game.dart';
import '../../providers/app_providers.dart';
import '../../core/constants/app_constants.dart';
import '../widgets/app_progress_indicator.dart';
import '../widgets/tag_list.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/game_editor_layout.dart'
    show GameBannerBackdrop, GameBannerHero, GameStat;
import '../widgets/notification_system.dart';
import '../widgets/segmented_bar.dart';
import '../widgets/game_cover_image.dart';
import '../widgets/steam_lookup_info_menu.dart';
import '../../core/services/logging.dart';

/// What Save confirmed in a Steam lookup: the match shown, and whether it
/// was the cached match (cached at [cachedAt], if known) rather than one
/// fetched fresh.
typedef SteamLookupChoice = ({
  SteamSearchResult result,
  bool usedCache,
  DateTime? cachedAt,
});

/// Shows the Steam match for [title]: the cached one when there is one,
/// which Fetch Fresh replaces from Steam, else a fresh search. Returns null
/// when closed without saving.
Future<SteamLookupChoice?> showSteamLookupDialog(
  BuildContext context, {
  required String title,
}) => _showLookup<SteamLookupChoice>(context, title: title);

/// Asks whether a batch of [gameCount] games, shown by the first, [title],
/// uses cached data where a game has some, without searching Steam. Returns
/// true to use the cache, false to fetch fresh, or null when closed.
Future<bool?> showSteamBatchLookupDialog(
  BuildContext context, {
  required String title,
  required int gameCount,
}) => _showLookup<bool>(context, title: title, gameCount: gameCount);

Future<T?> _showLookup<T>(
  BuildContext context, {
  required String title,
  int gameCount = 1,
}) async {
  final preview = AppDialogPreviewScope.maybeOf(context);
  final cached = preview != null
      ? preview.steamResult
      : await getCachedResultForTitle(title);
  final cachedAt = cached == null
      ? null
      : preview != null
      ? preview.steamCachedAt
      : await getCachedAtForTitle(title);
  if (!context.mounted) return null;
  return showAppDialog<T>(
    context: context,
    builder: (ctx) => SteamLookupDialog(
      title: title,
      gameCount: gameCount,
      result: cached,
      fromCache: cached != null,
      cachedAt: cachedAt,
    ),
  );
}

/// Apply everything in a SteamSearchResult to a game.
/// Returns null on success or an error message on failure.
///
/// The cover is the match's artwork even when one is saved under the
/// game's title, unless [refreshCover] is off (a batch): then only a game
/// matched to a different app gets new artwork.
Future<String?> applySteamResultToGame(
  ProviderContainer container,
  Game game,
  SteamSearchResult result, {
  int? expectedRevision,
  bool Function()? isCancelled,
  bool refreshCover = true,
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
      downloadImage: (appId, title) => steamService.downloadImage(
        appId,
        title: title,
        imageUrl: result.imageUrl,
        replace:
            refreshCover ||
            (game.steamAppId.isNotEmpty && game.steamAppId != appId),
      ),
    ).apply(game.id, result);
    await persistEncryptedDbIfNeeded(container, database: db);
    return null;
  } catch (e) {
    return e.toString();
  }
}

/// Looks [game] up on Steam and applies what the lookup saves.
Future<void> performSingleSteamLookup(
  BuildContext context,
  WidgetRef ref,
  Game game,
) async {
  final sessionRevision = ref.read(databaseNotifierProvider).revision;
  final batchNotifier = ref.read(batchFetchProvider.notifier);
  batchNotifier.startBatch([game.id]);
  batchNotifier.setProcessing(game.id);
  try {
    final choice = await showSteamLookupDialog(context, title: game.title);
    if (!context.mounted ||
        choice == null ||
        ref.read(databaseNotifierProvider).revision != sessionRevision) {
      return;
    }
    final error = await applySteamResultToGame(
      ProviderScope.containerOf(context, listen: false),
      game,
      choice.result,
      expectedRevision: sessionRevision,
    );
    if (error == null) {
      NotificationManager.instance.success(
        'Updated "${game.title}" with Steam data',
      );
    } else {
      NotificationManager.instance.error('Failed to apply Steam data: $error');
    }
  } finally {
    batchNotifier.endBatch();
  }
}

/// Perform a batch Steam lookup for the given games.
///
/// This central helper is used by individual game cards and by the
/// selection action bar so both paths share the exact same behaviour,
/// notifications and cancellation handling.
/// The first game's lookup asks whether the batch uses cached data.
Future<void> performSteamBatchLookup(
  BuildContext context,
  List<Game> targets, {
  bool prompt = true,
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

  // Whether to use cached data, asked with the first game; without a prompt
  // every game is fetched fresh.
  var useCache = false;
  if (prompt && context.mounted) {
    final choice = await showSteamBatchLookupDialog(
      context,
      title: steamTargets.first.title,
      gameCount: total,
    );
    if (choice == null ||
        container.read(databaseNotifierProvider).revision != sessionRevision) {
      return;
    }
    useCache = choice;
  }

  // Start batch fetch tracking
  batchNotifier.startBatch([for (final g in steamTargets) g.id]);

  late NotificationHandle handle;
  handle = NotificationManager.instance.beginTask(
    'Fetching Steam data',
    type: NotificationType.steam,
    title: 'Starting...',
    progress: 0,
    progressLabel: '0/$total',
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
      message: 'Fetching Steam data',
      title: gameTitle,
      progress: (i / total).clamp(0.0, 1.0),
      progressLabel: '${i + 1}/$total',
    );
    unawaited(
      DeadlineNotificationService.instance.showFetchProgressNotification(
        completed: i,
        total: total,
        currentTitle: gameTitle,
      ),
    );

    // Cached data, where a game has some, when the lookup chose it.
    final cached = useCache ? await getCachedResultForTitle(gameTitle) : null;
    if (stopped()) break;

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
      expectedRevision: sessionRevision,
      isCancelled: () => batchNotifier.isCancelled,
      // Only re-matched games download artwork again.
      refreshCover: false,
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

/// A Steam match for a title, with what to save from it. It opens on a
/// cached match, which Fetch Fresh replaces from Steam, or searches Steam
/// when it is given none. Save closes it with a [SteamLookupChoice]; a
/// batch's never searches, closing with whether to use the cache.
class SteamLookupDialog extends ConsumerStatefulWidget {
  const SteamLookupDialog({
    super.key,
    required this.title,
    this.gameCount = 1,
    this.result,
    this.fromCache = false,
    this.cachedAt,
  });

  /// The title looked up.
  final String title;

  /// The games sharing these choices; more than one is a batch, shown by
  /// its first game.
  final int gameCount;

  /// The match shown at first; without one Steam is searched.
  final SteamSearchResult? result;

  /// Whether [result] is the cached match, cached at [cachedAt] if known.
  final bool fromCache;
  final DateTime? cachedAt;

  @override
  ConsumerState<SteamLookupDialog> createState() => _SteamLookupDialogState();
}

class _SteamLookupDialogState extends ConsumerState<SteamLookupDialog> {
  late SteamSearchResult? _result = widget.result;
  late bool _fromCache = widget.fromCache;
  // A batch never searches: it only chooses between cache and fresh data.
  late bool _isSearching = _result == null && !_isBatch;
  String? _error;

  /// One cover download per match, so rebuilds never restart it.
  final _coverDownloads = <String, Future<String?>>{};

  /// The shown match's downloaded cover, blurred in behind the banner.
  final _backdrop = TextEditingController();

  bool get _isBatch => widget.gameCount > 1;

  @override
  void initState() {
    super.initState();
    _isSearching ? _searchSteam() : _showBackdrop(_result);
  }

  @override
  void dispose() {
    _backdrop.dispose();
    super.dispose();
  }

  /// Replaces what is shown with a fresh match from Steam. A cached match
  /// comes back, with a notice, when the fresh search finds nothing.
  Future<void> _searchSteam() async {
    final cached = _fromCache ? _result : null;
    _showBackdrop(null);
    setState(() {
      _isSearching = true;
      _error = null;
      _result = null;
      _fromCache = false;
    });
    SteamSearchResult? result;
    String? failure;
    try {
      result = await ref
          .read(steamServiceProvider)
          .searchGame(widget.title, forceRefresh: true);
    } catch (e) {
      failure = e.toString();
    }
    if (!mounted) return;
    setState(() {
      _result = result ?? cached;
      _fromCache = result == null && cached != null;
      _error = switch (result) {
        _? => null,
        null when cached != null =>
          '${failure == null ? 'No match on Steam' : 'Search failed'}'
              ' · Using cached data',
        null => failure ?? 'No matching game found on Steam',
      };
      _isSearching = false;
    });
    _showBackdrop(_result);
  }

  /// [result]'s cover download; a dialog preview shows its URL.
  Future<String?> _coverFor(SteamSearchResult result) =>
      _coverDownloads.putIfAbsent(
        result.appId,
        () => AppDialogPreviewScope.maybeOf(context) != null
            ? Future.value(result.imageUrl)
            : ref
                  .read(steamServiceProvider)
                  .downloadImage(result.appId, imageUrl: result.imageUrl),
      );

  /// Blurs [result]'s cover in behind the banner once it has downloaded.
  void _showBackdrop(SteamSearchResult? result) {
    _backdrop.clear();
    if (result == null) return;
    _coverFor(result).then((path) {
      if (mounted && _result == result) _backdrop.text = path ?? '';
    }, onError: (_) {});
  }

  /// The match's store page, or a Steam search for the game until there is
  /// one, as in the Game Editor.
  Future<void> _openSteamPage() async {
    final appId = _result?.appId;
    final url = appId != null && appId.isNotEmpty
        ? steamAppPageUrl(appId)
        : steamSearchPageUrl(widget.title);
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      NotificationManager.instance.error('Failed to open Steam page: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final result = _isSearching ? null : _result;
    final divider = Divider(
      height: 40,
      indent: 16,
      endIndent: 16,
      color: theme.border,
    );
    return ThemedAlertDialog(
      theme: theme,
      showCloseButton: false,
      // The banner reaches the edges; the buttons keep the dialog's padding.
      bleedContent: true,
      // The banner's art runs on behind the buttons, so the dialog has no
      // edge where its content ends.
      backdrop: GameBannerBackdrop(theme: theme, coverController: _backdrop),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHero(theme, result),
          for (final section in _buildSections(theme, result)) ...[
            divider,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: section,
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
      actions: [
        // Fetch Fresh replaces a single game's cached match in place; a
        // batch closes with its choice, fetched for every game once it
        // starts.
        if (_fromCache)
          OutlinedButton(
            onPressed: _isBatch
                ? () => Navigator.pop<bool>(context, false)
                : _searchSteam,
            child: const Text('Fetch Fresh'),
          ),
        if (_isBatch)
          ElevatedButton(
            onPressed: () => Navigator.pop<bool>(context, _fromCache),
            child: Text(
              _fromCache ? 'Use Cache' : 'Fetch ${widget.gameCount} Games',
            ),
          )
        else if (result != null)
          ElevatedButton(
            onPressed: () => Navigator.pop<SteamLookupChoice>(context, (
              result: result,
              usedCache: _fromCache,
              cachedAt: _fromCache ? widget.cachedAt : null,
            )),
            child: const Text('Save'),
          ),
      ],
    );
  }

  /// The match's cover beside its name, or the search's progress or failure
  /// until there is one. A batch says what its buttons do there.
  Widget _buildHero(AppThemeData theme, SteamSearchResult? result) {
    final count = widget.gameCount;
    return LayoutBuilder(
      builder: (context, constraints) => GameBannerHero(
        theme: theme,
        // Cached data is named as such until Fetch Fresh replaces it.
        heading: _fromCache ? 'Steam Cache' : 'Steam Lookup',
        actions: [
          // Hidden while searching, until there is a match (or a failed
          // search, which opens a Steam search) to show.
          if (!_isSearching)
            IconButton(
              tooltip: 'Steam Page',
              onPressed: _openSteamPage,
              color: theme.accent,
              icon: const Icon(Icons.open_in_new),
            ),
          // The lookup's details describe a fresh search, so not the cache.
          if (result != null && !_fromCache)
            SteamLookupInfoMenu(
              theme: theme,
              searchedTitle: widget.title,
              result: result,
            ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
        wide: constraints.maxWidth >= 480,
        coverWidth: math.min(260, constraints.maxWidth * 0.45),
        cover: ClipRRect(
          borderRadius: BorderRadius.circular(theme.cornerRadius),
          // A Steam header's shape.
          child: AspectRatio(
            aspectRatio: 460 / 215,
            child: result != null
                ? _LoadingCover(theme: theme, cover: _coverFor(result))
                : ColoredBox(
                    color: theme.cardCoverPlaceholder,
                    child: Center(
                      child: _isSearching
                          ? const AppCircularProgressIndicator(size: 24)
                          : Icon(
                              // A batch's cache-less first game, or a failed
                              // search.
                              _isBatch
                                  ? Icons.cloud_download_outlined
                                  : Icons.search_off,
                              color: theme.textHint,
                              size: 32,
                            ),
                    ),
                  ),
          ),
        ),
        info: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            Text(
              result?.name ?? widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (result?.isDlc ?? false)
              TintedChip(theme: theme, color: theme.secondary, label: 'DLC'),
            if (_isBatch)
              Text(
                _fromCache
                    ? 'First of $count games · Cached data found'
                    : 'No cached data found',
                style: TextStyle(color: theme.textSecondary),
              ),
            if (_isSearching)
              Text(
                'Searching Steam...',
                style: TextStyle(color: theme.textSecondary),
              ),
            if (_error case final error?)
              Row(
                spacing: 4,
                children: [
                  Flexible(
                    child: Text(error, style: TextStyle(color: theme.error)),
                  ),
                  IconButton(
                    tooltip: 'Try Again',
                    onPressed: _searchSteam,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// The match's tags, then its figures as in the Game Editor, each under a
  /// divider; none until there is a match.
  List<Widget> _buildSections(AppThemeData theme, SteamSearchResult? result) {
    if (result == null) return const [];
    final cachedAt = widget.cachedAt;
    final developer = result.developer?.trim();
    return [
      if (result.tags.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Steam Tags',
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${result.tags.length}',
                  style: TextStyle(color: theme.textHint),
                ),
              ],
            ),
            TagList(
              tags: [
                for (final (index, name) in result.tags.indexed)
                  Tag(
                    id: -(index + 1),
                    name: name,
                    colorHex: '#000000',
                    isSteamTag: true,
                  ),
              ],
              theme: theme,
              allSelected: true,
              // Whole rows, so none is cut in half.
              maxRows: 3,
            ),
          ],
        ),
      Wrap(
        spacing: 36,
        runSpacing: 16,
        children: [
          // The review count is in the tooltip, so the AppID fits beside
          // the rating on a phone.
          GameStat.reviews(
            theme: theme,
            score: result.reviewScore ?? 0,
            count: result.reviewCount ?? 0,
            compact: true,
          ),
          GameStat.steamAppId(theme: theme, appId: result.appId),
          GameStat(
            theme: theme,
            label: 'Developer',
            value: developer == null || developer.isEmpty ? null : developer,
            fallback: 'Unknown',
            maxLines: 2,
          ),
          // Only a cached match has an age worth showing.
          if (_fromCache)
            GameStat.date(
              theme: theme,
              label: 'Cached',
              date: cachedAt,
              fallback: 'Unknown',
            ),
          // The title looked up, when the match goes by another.
          if (result.name.trim().toLowerCase() !=
              widget.title.trim().toLowerCase())
            GameStat(
              theme: theme,
              label: 'Searched',
              value: widget.title,
              maxLines: 2,
            ),
        ],
      ),
    ];
  }
}

/// A cover with a spinner on its placeholder while [cover] downloads and
/// while the image it names decodes.
class _LoadingCover extends StatefulWidget {
  const _LoadingCover({required this.theme, required this.cover});

  final AppThemeData theme;

  /// The cover's path once downloaded, or null for none.
  final Future<String?> cover;

  @override
  State<_LoadingCover> createState() => _LoadingCoverState();
}

class _LoadingCoverState extends State<_LoadingCover>
    implements CoverLoadListener {
  final _decoding = <Object>{};

  // Reports arrive while the cover builds or unmounts.
  void _rebuildNextFrame() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) setState(() {});
  });

  @override
  void coverLoading(Object cover) {
    if (_decoding.add(cover)) _rebuildNextFrame();
  }

  @override
  void coverSettled(Object cover) {
    if (_decoding.remove(cover)) _rebuildNextFrame();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: widget.cover,
    builder: (context, snapshot) {
      final downloaded = snapshot.connectionState == ConnectionState.done;
      return Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: widget.theme.cardCoverPlaceholder),
          if (downloaded)
            CoverLoadScope(
              listener: this,
              child: GameCoverImage(
                theme: widget.theme,
                coverImage: snapshot.data,
              ),
            ),
          if (!downloaded || _decoding.isNotEmpty)
            const Center(child: AppCircularProgressIndicator(size: 24)),
        ],
      );
    },
  );
}
