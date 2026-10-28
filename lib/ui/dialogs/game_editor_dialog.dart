/// Game Editor dialog - view and edit game information
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import '../controllers/game_editor_fields.dart';
import '../../providers/app_providers.dart';
import 'delete_games_dialog.dart';
import '../pages/settings_sections/settings_control_cards.dart';
import '../widgets/app_progress_indicator.dart';
import '../widgets/cover_image_card.dart';
import '../widgets/deadline_chip.dart';
import '../widgets/game_options_row.dart';
import '../widgets/game_editor_layout.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/notification_system.dart';
import '../widgets/platform_menu_button.dart';
import '../widgets/tinted_tiles.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/key_privacy.dart';
import '../../core/services/steam_service.dart';
import '../dialogs/steam_lookup_dialog.dart';

/// Show the Game Editor dialog
Future<bool?> showGameEditorDialog(
  BuildContext context,
  Game game, {
  List<int>? gameIds,
  Future<void> Function(int gameId)? onViewedGame,
}) => showAppDialog<bool>(
  context: context,
  barrierDismissible: true,
  builder: (ctx) => GameEditorDialog(
    game: game,
    gameIds: gameIds,
    initialGameId: game.id,
    onViewedGame: onViewedGame,
  ),
);

/// Game Editor dialog
class GameEditorDialog extends ConsumerStatefulWidget {
  const GameEditorDialog({
    super.key,
    // Allow passing just a game (legacy) or list+id
    this.game,
    this.gameIds,
    this.initialGameId,
    this.onViewedGame,
  });

  final Game? game;
  final List<int>? gameIds;
  final int? initialGameId;
  final Future<void> Function(int gameId)? onViewedGame;

  @override
  ConsumerState<GameEditorDialog> createState() => _GameEditorDialogState();
}

class _GameEditorDialogState extends ConsumerState<GameEditorDialog> {
  final _editorLayoutKey = GlobalKey<GameEditorLayoutState>();
  final _fields = GameEditorFields();

  late Game _currentGame;
  late List<int> _gameIds;
  int _currentIndex = 0;

  late String _platform;
  late bool _hasDeadline;
  late DateTime? _deadlineDate;
  late bool _isDlc;
  late bool _isUsed;
  late Set<int> _selectedTagIds;

  late final int _sessionRevision;
  bool _isKeyVisible = false; // Will be set from settings in initState
  bool _isSaving = false;
  bool _hasChanges = false;
  int? _lastViewedNotifiedId;
  bool _viewedNotificationScheduled = false;

  // Steam-specific state
  late String _steamAppId;
  bool _isFetching = false;
  DateTime? _steamCacheAt;
  DateTime? _lastUpdatedAt;

  // Local fetched review preview values (null == not available)
  int? _fetchedReviewScore;
  int? _fetchedReviewCount;

  // Locally tracked Steam developer info (from fetched metadata)
  String? _steamDeveloper;

  @override
  void initState() {
    super.initState();
    _sessionRevision = ref.read(databaseNotifierProvider).revision;

    // Masked keys start hidden.
    _isKeyVisible = !ref.read(securitySettingsProvider).maskKeys;

    // Navigation list; a lone game is a list of one.
    _gameIds = [...?widget.gameIds];
    if (_gameIds.isEmpty && widget.game != null) _gameIds = [widget.game!.id];
    final startId = widget.initialGameId ?? widget.game?.id;
    _currentIndex = startId == null
        ? 0
        : math.max(0, _gameIds.indexOf(startId));

    // Prefer the provider's copy over a possibly stale widget.game.
    final currentId = _gameIds[_currentIndex];
    _currentGame =
        ref.read(gameByIdProvider(currentId)) ??
        widget.game ??
        ref.read(allGamesProvider).firstWhere((g) => g.id == currentId);

    _initializeFromGame();
    _fields.title.addListener(() {
      if (mounted) setState(() {});
    });
    _scheduleViewedGameNotification();
  }

  void _scheduleViewedGameNotification() {
    if (_viewedNotificationScheduled) return;
    _viewedNotificationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _viewedNotificationScheduled = false;
      final gameId = _currentGame.id;
      if (_lastViewedNotifiedId == gameId) return;
      _lastViewedNotifiedId = gameId;
      widget.onViewedGame?.call(gameId);
    });
  }

  void _initializeFromGame() {
    _fields.load(
      title: _currentGame.title,
      gameKey: _currentGame.gameKey,
      notes: _currentGame.notes,
      coverImage: _currentGame.coverImage,
    );

    _platform = _currentGame.platform;
    _hasDeadline = _currentGame.hasDeadline;
    _deadlineDate = _currentGame.deadlineDate;
    _isUsed = _currentGame.isUsed;
    _steamDeveloper = _currentGame.developer;
    _loadSteamState(_currentGame);
    _hasChanges = false;

    // Load cache timestamp if present
    _loadSteamCacheAt();
  }

  @override
  void dispose() {
    _fields.dispose();
    super.dispose();
  }

  /// The fields a Steam fetch can change, as stored on [game].
  void _loadSteamState(Game game) {
    final hasReviews = game.reviewCount != 0;
    _steamAppId = game.steamAppId;
    _isDlc = game.isDlc;
    _selectedTagIds = game.tagIds.toSet();
    _fetchedReviewScore = hasReviews ? game.reviewScore : null;
    _fetchedReviewCount = hasReviews ? game.reviewCount : null;
    _lastUpdatedAt = game.updatedAt;
  }

  void _markChanged() => setState(() => _hasChanges = true);

  /// Applies [change] as an unsaved edit.
  void _edit(VoidCallback change) => setState(() {
    change();
    _hasChanges = true;
  });

  Future<void> _save({bool close = true}) async {
    if (!_hasChanges) {
      if (close) Navigator.pop(context, false);
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Ensure Steam-specific metadata and Steam tags are removed when platform is not Steam
      final steamTags = ref.read(steamTagsProvider);
      final steamTagIds = steamTags.map((t) => t.id).toSet();
      final selectedTagIds = _selectedTagIds
          .where((id) => _platform == 'Steam' || !steamTagIds.contains(id))
          .toList();

      // Ensure we have logic to merge with current state properly
      final currentGameState =
          ref.read(gameByIdProvider(_currentGame.id)) ?? _currentGame;

      final updatedGame = _currentGame.copyWith(
        title: _fields.title.text.trim(),
        gameKey: _fields.gameKey.text.trim(),
        platform: _platform,
        notes: _fields.notes.text.trim(),
        coverImage: _fields.coverImage.text.trim(),
        hasDeadline: _hasDeadline,
        deadlineDate: _hasDeadline ? _deadlineDate : null,
        isDlc: _isDlc,
        isUsed: _isUsed,
        steamAppId: _platform == 'Steam' ? _steamAppId : '',
        // Preserve any fetched review info (from provider) when platform is Steam; otherwise clear
        reviewScore: _platform == 'Steam' ? currentGameState.reviewScore : 0,
        reviewCount: _platform == 'Steam' ? currentGameState.reviewCount : 0,
      );

      final ok = await ref
          .read(gamesProvider.notifier)
          .updateGame(updatedGame, tagIds: selectedTagIds);

      if (!ok) throw Exception('Update failed');

      // Update local state to match saved
      _currentGame = updatedGame;
      _hasChanges = false;

      NotificationManager.instance.success(
        'Game updated: ${updatedGame.title}',
      );
      if (mounted && close) Navigator.pop(context, true);
    } catch (e) {
      NotificationManager.instance.error('Failed to save: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final theme = ref.read(themeProvider);
    final confirmed = await showDeleteGamesDialog(
      context,
      theme,
      1,
      gameTitle: _currentGame.title,
    );

    if (confirmed) {
      await ref.read(gamesProvider.notifier).deleteGame(_currentGame.id);
      NotificationManager.instance.success('Game deleted');
      if (mounted) Navigator.pop(context, true);
    }
  }

  void _copyKey() {
    KeyPrivacy.copy(_currentGame.gameKey);
    NotificationManager.instance.success('Key copied to clipboard');
  }

  /// Fetch Steam AppID, tags and DLC status and apply them to this game
  Future<void> _fetchSteamData() async {
    if (_platform != 'Steam') {
      NotificationManager.instance.info(
        'Fetch is only available when Platform is set to Steam',
      );
      return;
    }

    // Otherwise fetch fresh data
    setState(() => _isFetching = true);
    try {
      final steamService = ref.read(steamServiceProvider);

      final resolution = await resolveSteamResultForTitle(
        context,
        title: _fields.title.text.trim(),
        steamService: steamService,
      );
      if (!mounted || resolution == null) return;

      final result = resolution.result;
      if (result == null) {
        NotificationManager.instance.info('No Steam data found for this game');
        return;
      }

      await _applySteamResult(result);
    } catch (e) {
      NotificationManager.instance.error('Failed to fetch Steam data: $e');
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  /// Apply a SteamSearchResult to this game (tags, image, appId, reviews)
  Future<void> _applySteamResult(SteamSearchResult result) async {
    try {
      final applyError = await applySteamResultToGame(
        ProviderScope.containerOf(context, listen: false),
        _currentGame,
        result,
        SteamApplyOptions.defaults,
        expectedRevision: _sessionRevision,
      );

      if (applyError != null) {
        NotificationManager.instance.error(
          'Failed to update game with Steam data: $applyError',
        );
        return;
      }

      await ref.read(gamesProvider.notifier).refreshGame(_currentGame.id);

      if (!mounted ||
          ref.read(databaseNotifierProvider).revision != _sessionRevision) {
        return;
      }
      final updated =
          ref.read(gameByIdProvider(_currentGame.id)) ?? _currentGame;

      // Update local tracking
      _currentGame = updated;

      setState(() {
        _loadSteamState(updated);
        _steamDeveloper = result.developer;
        _fields.coverImage.text = updated.coverImage;
      });

      // reload cache timestamp
      _loadSteamCacheAt();

      NotificationManager.instance.success('Applied Steam data');
    } catch (e) {
      NotificationManager.instance.error('Failed to apply Steam data: $e');
    }
  }

  Future<void> _loadSteamCacheAt() async {
    // Use title-only cache lookup
    final preview = AppDialogPreviewScope.maybeOf(context);
    final cached = preview != null
        ? preview.steamCachedAt
        : await getCachedAtForTitle(_fields.title.text.trim());
    if (mounted) setState(() => _steamCacheAt = cached);
  }

  Future<void> _navigate(int delta) async {
    if (_hasChanges) {
      final theme = ref.read(themeProvider);
      final shouldSave = await showUnsavedGameChangesDialog(
        context,
        theme,
        _currentGame.title,
      );

      if (shouldSave == null || shouldSave == 'cancel') return;
      if (shouldSave == 'save') {
        await _save(close: false);
        if (_hasChanges) return; // Save failed
      }
    }

    // Move to next
    final newIndex = _currentIndex + delta;
    if (newIndex >= 0 && newIndex < _gameIds.length) {
      setState(() {
        _currentIndex = newIndex;
        _currentGame =
            ref.read(gameByIdProvider(_gameIds[newIndex])) ?? _currentGame;
        _initializeFromGame();
      });
      _scheduleViewedGameNotification();
    }
  }

  void _dismissDialog() => Navigator.pop(context, false);

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final tags = ref.watch(tagsProvider);
    final showGameDetailsSkmId = ref.watch(
      settingsProvider.select(
        (settings) =>
            (settings[SettingsKeys.showGameDetailsSkmId] as bool?) ??
            DefaultSettings.showGameDetailsSkmId,
      ),
    );
    return DialogInteractionScope(
      onPrimaryAction: _hasChanges && !_isSaving ? _save : null,
      onDismiss: _dismissDialog,
      child: ThemedAlertDialog(
        maxWidth: 1200,
        showCloseButton: false,
        body: GameEditorLayout(
          key: _editorLayoutKey,
          theme: theme,
          titleController: _fields.title,
          cover: _buildCover(theme),
          trailing: _buildHeaderActions(theme),
          notesController: _fields.notes,
          onNotesChanged: _markChanged,
          information: GameEditorInformation(
            theme: theme,
            platformSelector: PlatformMenuButton(
              theme: theme,
              value: _platform,
              tooltip: 'Selected platform: $_platform. Choose platform',
              includeAutoDetect: false,
              onSelected: _changePlatform,
            ),
            titleController: _fields.title,
            keyController: _fields.gameKey,
            isKeyVisible: _isKeyVisible,
            onKeyVisibilityChanged: (value) =>
                setState(() => _isKeyVisible = value),
            onCopyKey: _copyKey,
            onTitleChanged: (_) => _markChanged(),
            onKeyChanged: (_) => _markChanged(),
          ),
          detailsBuilder: (information) => _DetailsTab(
            information: information,
            theme: theme,
            game: _currentGame,
            showGameDetailsSkmId: showGameDetailsSkmId,
            platform: _platform,
            steamAppId: _steamAppId,
            steamDeveloper: _steamDeveloper,
            steamCacheAt: _steamCacheAt,
            lastUpdatedAt: _lastUpdatedAt,
            steamReviewScore: _fetchedReviewScore,
            steamReviewCount: _fetchedReviewCount,
            status: _buildStatus(theme),
          ),
          tags: GameEditorTags(
            theme: theme,
            customTags: tags.where((tag) => !tag.isSteamTag).toList(),
            selectedTagIds: _selectedTagIds,
            steamTags: tags
                .where(
                  (tag) => tag.isSteamTag && _selectedTagIds.contains(tag.id),
                )
                .toList(),
            onTagToggled: (tagId) => _edit(() {
              if (!_selectedTagIds.remove(tagId)) _selectedTagIds.add(tagId);
            }),
          ),
        ),
        actions: [_buildFooter(theme)],
        below: _gameIds.length > 1 ? _buildNavigationBar(theme) : null,
      ),
    );
  }

  Widget _buildCover(AppThemeData theme) => CoverImageCard(
    theme: theme,
    isDlc: _isDlc,
    isUsed: _isUsed,
    hasDeadline: _hasDeadline,
    deadlineDate: _deadlineDate,
    controller: _fields.coverImage,
    onChanged: _markChanged,
  );

  void _changePlatform(String platform) => _edit(() {
    final wasSteam = _platform == 'Steam';
    _platform = platform;
    if (wasSteam && platform != 'Steam') {
      _steamAppId = '';
      final steamTagIds = ref
          .read(steamTagsProvider)
          .map((tag) => tag.id)
          .toSet();
      _selectedTagIds.removeWhere(steamTagIds.contains);
    }
  });

  Widget _buildStatus(AppThemeData theme) => GameOptionsRow(
    theme: theme,
    isDlc: _isDlc,
    onDlcChanged: (value) => _edit(() => _isDlc = value),
    deadline: DeadlineChip(
      theme: theme,
      hasDeadline: _hasDeadline,
      date: _deadlineDate,
      firstDate: DateTime(2020),
      onEnabledChanged: (value) => _edit(() => _hasDeadline = value),
      onDateChanged: (value) => _edit(() => _deadlineDate = value),
    ),
    isUsed: _isUsed,
    onUsedChanged: (value) => _edit(() => _isUsed = value),
  );

  Future<void> _openSteamPage() async {
    final title = _fields.title.text.trim();
    final Uri url = _steamAppId.isNotEmpty
        ? Uri.parse(steamAppPageUrl(_steamAppId))
        : Uri.parse(steamSearchPageUrl(title));
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      NotificationManager.instance.error('Failed to open Steam page: $e');
    }
  }

  /// The Steam actions beside the close button.
  Widget _buildHeaderActions(AppThemeData theme) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: kElementHSpacing,
    children: [
      if (_platform == 'Steam') ...[
        IconButton(
          tooltip: 'Fetch Steam data',
          onPressed: _isFetching ? null : _fetchSteamData,
          color: theme.accent,
          icon: _isFetching
              ? const AppCircularProgressIndicator(size: 18)
              : const Icon(Icons.cloud_download_outlined),
        ),
        IconButton(
          tooltip: 'Steam Page',
          onPressed: _openSteamPage,
          color: theme.accent,
          icon: const Icon(Icons.open_in_new),
        ),
      ],
      IconButton(
        tooltip: 'Close Game Editor',
        icon: Icon(Icons.close, color: theme.textSecondary),
        onPressed: _dismissDialog,
      ),
    ],
  );

  /// Two filled arrow buttons around a darker tinted label, on a raised
  /// strip, so it is hard to miss.
  Widget _buildNavigationBar(AppThemeData theme) {
    final radius = BorderRadius.circular(theme.cornerRadius);
    final arrowStyle = IconButton.styleFrom(
      backgroundColor: theme.primaryButton,
      foregroundColor: theme.primaryButtonText,
      disabledBackgroundColor: theme.primaryButtonDisabled,
      disabledForegroundColor: theme.primaryButtonDisabledText,
      shape: RoundedRectangleBorder(borderRadius: radius),
    );
    return Center(
      child: Material(
        color: theme.surface,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: theme.accent.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              IconButton(
                style: arrowStyle,
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous Game',
                onPressed: _currentIndex > 0 ? () => _navigate(-1) : null,
              ),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.accent.withValues(alpha: 0.12),
                    borderRadius: radius,
                  ),
                  child: Text(
                    'Game ${_currentIndex + 1} of ${_gameIds.length}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              IconButton(
                style: arrowStyle,
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next Game',
                onPressed: _currentIndex < _gameIds.length - 1
                    ? () => _navigate(1)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(AppThemeData theme) => Row(
    children: [
      IconButton(
        tooltip: 'Delete',
        onPressed: _confirmDelete,
        icon: const Icon(Icons.delete),
        color: theme.secondary,
      ),
      const Spacer(),
      ElevatedButton.icon(
        onPressed: _hasChanges && !_isSaving ? _save : null,
        icon: _isSaving
            ? const AppCircularProgressIndicator(size: 18)
            : const Icon(Icons.save),
        label: const Text('Save'),
      ),
    ],
  );
}

/// Details tab: Information on narrow screens, then status and metadata.
class _DetailsTab extends StatelessWidget {
  const _DetailsTab({
    required this.theme,
    required this.information,
    required this.game,
    required this.showGameDetailsSkmId,
    required this.platform,
    required this.steamAppId,
    this.steamCacheAt,
    this.lastUpdatedAt,
    this.steamReviewScore,
    this.steamReviewCount,
    required this.status,
    this.steamDeveloper,
  });

  final AppThemeData theme;
  final Widget? information;
  final Game game;
  final bool showGameDetailsSkmId;
  final String platform;
  final Widget status;

  // Steam fetch props
  final String steamAppId;
  final String? steamDeveloper;

  // Fetched review preview (may be null)
  final DateTime? steamCacheAt;
  final DateTime? lastUpdatedAt;
  final int? steamReviewScore;
  final int? steamReviewCount;

  Widget _tile(IconData icon, String label, String value, [Widget? trailing]) =>
      TintedOptionTile(
        theme: theme,
        icon: icon,
        title: value,
        subtitle: label,
        trailing: trailing,
      );

  @override
  Widget build(BuildContext context) {
    final steam = platform == 'Steam';
    final score = steamReviewScore ?? game.reviewScore;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          if (information != null) ...[information!, const SizedBox(height: 8)],
          TintedHeading(theme: theme, title: 'Status'),
          status,
          const SizedBox(height: 8),
          TintedHeading(
            theme: theme,
            title: 'Metadata',
            trailing: showGameDetailsSkmId ? 'SKM-ID ${game.id}' : null,
          ),
          _DatesTile(
            theme: theme,
            added: game.createdAt,
            updated: lastUpdatedAt ?? game.updatedAt,
            steam: steam,
            cachedAt: steamCacheAt,
          ),
          SettingsControlWrap(
            minimumCardWidth: 220,
            children: [
              if (steamDeveloper?.isNotEmpty == true)
                _tile(Icons.business_outlined, 'Developer', steamDeveloper!),
              if (steam)
                steamReviewCount == null || steamReviewCount == 0
                    ? _tile(Icons.thumb_up_outlined, 'Reviews', 'No reviews')
                    : _tile(
                        Icons.thumb_up_outlined,
                        '${NumberFormat.compact().format(steamReviewCount)} reviews',
                        '$score% · ${Game.reviewRatingFor(score)}',
                      ),
              if (steam)
                _tile(
                  Icons.pin_outlined,
                  'Steam AppID',
                  steamAppId.isEmpty ? 'Not set' : steamAppId,
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    color: theme.textSecondary,
                    tooltip: 'Copy AppID',
                    onPressed: steamAppId.isEmpty
                        ? null
                        : () {
                            Clipboard.setData(ClipboardData(text: steamAppId));
                            NotificationManager.instance.success(
                              'Steam AppID copied to clipboard',
                            );
                          },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The game's dates side by side, each as how long ago it was over the
/// date itself; hovering one shows its exact time. An update no later than
/// the add says Unchanged, and a game without Steam data says Not cached.
class _DatesTile extends StatelessWidget {
  const _DatesTile({
    required this.theme,
    required this.added,
    required this.updated,
    required this.steam,
    this.cachedAt,
  });

  final AppThemeData theme;
  final DateTime added;
  final DateTime updated;
  final bool steam;
  final DateTime? cachedAt;

  static final _day = DateFormat('d MMM yyyy');
  static final _exact = DateFormat('dd/MM/yyyy HH:mm');

  static String _ago(DateTime date) {
    final days = DateUtils.dateOnly(
      DateTime.now(),
    ).difference(DateUtils.dateOnly(date)).inDays;
    String plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'} ago';
    return switch (days) {
      <= 0 => 'Today',
      1 => 'Yesterday',
      < 30 => plural(days, 'day'),
      < 365 => plural(days ~/ 30, 'month'),
      _ => plural(days ~/ 365, 'year'),
    };
  }

  Widget _entry(IconData icon, String label, DateTime? date, String fallback) {
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Row(
          spacing: 6,
          children: [
            Icon(icon, color: theme.accent, size: 16),
            Flexible(
              child: Text(
                label,
                style: TextStyle(color: theme.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
        Text(
          date == null ? fallback : _ago(date),
          style: TextStyle(
            color: date == null ? theme.textSecondary : theme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (date != null)
          Text(
            _day.format(date),
            style: TextStyle(color: theme.textHint, fontSize: 12),
          ),
      ],
    );
    return Expanded(
      child: date == null
          ? column
          : Tooltip(message: _exact.format(date), child: column),
    );
  }

  @override
  Widget build(BuildContext context) {
    final divider = VerticalDivider(
      width: 20,
      color: theme.accent.withValues(alpha: 0.2),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(theme.cornerRadius),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _entry(Icons.add_circle_outline, 'Added', added, ''),
            divider,
            _entry(
              Icons.edit_outlined,
              'Updated',
              updated.isAfter(added.add(const Duration(minutes: 1)))
                  ? updated
                  : null,
              'Unchanged',
            ),
            if (steam) ...[
              divider,
              _entry(Icons.history, 'Cached', cachedAt, 'Not cached'),
            ],
          ],
        ),
      ),
    );
  }
}

Future<String?> showUnsavedGameChangesDialog(
  BuildContext context,
  AppThemeData theme,
  String gameTitle,
) => showAppDialog<String>(
  context: context,
  builder: (ctx) => ThemedAlertDialog(
    theme: theme,
    maxWidth: kCompactDialogWidth,
    title: DialogHeader(
      icon: Icons.edit_note,
      title: 'Unsaved Changes',
      theme: theme,
    ),
    content: Text(
      'Save changes to "$gameTitle"?',
      style: TextStyle(color: theme.textSecondary),
    ),
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.pop(ctx, 'discard'),
        child: const Text('Discard'),
      ),
      ElevatedButton(
        onPressed: () => Navigator.pop(ctx, 'save'),
        child: const Text('Save'),
      ),
    ],
  ),
);
