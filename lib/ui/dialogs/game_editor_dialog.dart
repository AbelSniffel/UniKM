/// Game Editor dialog - view and edit game information
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import '../controllers/game_editor_fields.dart';
import '../../providers/app_providers.dart';
import 'delete_games_dialog.dart';
import '../widgets/app_progress_indicator.dart';
import '../widgets/cover_image_card.dart';
import '../widgets/game_editor_layout.dart';
import '../widgets/deadline_chip.dart';
import '../widgets/game_options_row.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/notification_system.dart';
import '../widgets/platform_menu_button.dart';
import '../../core/utils/steam_page.dart';
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

  /// The tags as last loaded or saved, to tell real edits from undone ones.
  late Set<int> _savedTagIds;

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
    _steamStash = null;
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
    _loadSteamCacheAt();
  }

  bool get _isSteam => _platform == 'Steam';

  Set<int> _steamTagIds() =>
      ref.read(steamTagsProvider).map((tag) => tag.id).toSet();

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
    _savedTagIds = {..._selectedTagIds};
    _fetchedReviewScore = hasReviews ? game.reviewScore : null;
    _fetchedReviewCount = hasReviews ? game.reviewCount : null;
    _lastUpdatedAt = game.updatedAt;
  }

  void _markChanged() => setState(() => _hasChanges = true);

  VoidCallback? get _saveAction => _hasChanges && !_isSaving ? _save : null;

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
      // Off Steam, the Steam tags and figures are dropped.
      final steam = _isSteam;
      final steamTagIds = _steamTagIds();
      final selectedTagIds = _selectedTagIds
          .where((id) => steam || !steamTagIds.contains(id))
          .toList();
      // The provider's copy holds the latest fetched reviews.
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
        steamAppId: steam ? _steamAppId : '',
        reviewScore: steam ? currentGameState.reviewScore : 0,
        reviewCount: steam ? currentGameState.reviewCount : 0,
      );

      final ok = await ref
          .read(gamesProvider.notifier)
          .updateGame(updatedGame, tagIds: selectedTagIds);

      if (!ok) throw Exception('Update failed');

      // Update local state to match saved
      _currentGame = updatedGame;
      _hasChanges = false;
      _saved = true;
      _savedTagIds = selectedTagIds.toSet();

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
    if (!_isSteam) {
      NotificationManager.instance.info(
        'Fetch is only available when Platform is set to Steam',
      );
      return;
    }
    setState(() => _isFetching = true);
    try {
      final choice = await showSteamLookupDialog(
        context,
        title: _fields.title.text.trim(),
      );
      if (!mounted || choice == null) return;
      await _applySteamResult(choice.result);
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
      final updated = _currentGame =
          ref.read(gameByIdProvider(_currentGame.id)) ?? _currentGame;
      setState(() {
        _loadSteamState(updated);
        _steamDeveloper = result.developer;
        _fields.coverImage.text = updated.coverImage;
      });
      _loadSteamCacheAt();

      NotificationManager.instance.success('Applied Steam data');
    } catch (e) {
      NotificationManager.instance.error('Failed to apply Steam data: $e');
    }
  }

  Future<void> _loadSteamCacheAt() async {
    final preview = AppDialogPreviewScope.maybeOf(context);
    final cached = preview != null
        ? preview.steamCachedAt
        : await getCachedAtForTitle(_fields.title.text.trim());
    if (mounted) setState(() => _steamCacheAt = cached);
  }

  /// Whether the edits differ from the saved game. Edits undone by hand,
  /// such as switching the platform away and back, are no difference.
  bool get _isDirty {
    if (!_hasChanges) return false;
    final game = _currentGame;
    return _fields.title.text.trim() != game.title ||
        _fields.gameKey.text.trim() != game.gameKey ||
        _fields.notes.text.trim() != game.notes ||
        _fields.coverImage.text.trim() != game.coverImage ||
        _platform != game.platform ||
        _hasDeadline != game.hasDeadline ||
        (_hasDeadline && _deadlineDate != game.deadlineDate) ||
        _isDlc != game.isDlc ||
        _isUsed != game.isUsed ||
        (_isSteam ? _steamAppId : '') != game.steamAppId ||
        !setEquals(_selectedTagIds, _savedTagIds);
  }

  bool _confirmingDiscard = false;

  /// Whether any game was saved while the editor was open.
  bool _saved = false;

  /// Asks whether to save edits that differ from the saved game. True when
  /// the editor may move on: nothing differed, they were discarded, or saved.
  Future<bool> _resolveUnsavedChanges() async {
    if (!_isDirty) return true;
    if (_confirmingDiscard) return false;
    _confirmingDiscard = true;
    try {
      final choice = await showUnsavedGameChangesDialog(
        context,
        ref.read(themeProvider),
        _currentGame.title,
      );
      if (!mounted || choice == null) return false;
      if (choice == 'save') {
        await _save(close: false);
        return !_hasChanges; // False when the save failed.
      }
      return true;
    } finally {
      _confirmingDiscard = false;
    }
  }

  Future<void> _navigate(int delta) async {
    final newIndex = _currentIndex + delta;
    if (newIndex < 0 || newIndex >= _gameIds.length) return;
    if (!await _resolveUnsavedChanges()) return;
    setState(() {
      _currentIndex = newIndex;
      _currentGame =
          ref.read(gameByIdProvider(_gameIds[newIndex])) ?? _currentGame;
      _initializeFromGame();
    });
    _scheduleViewedGameNotification();
  }

  /// Every way out (the close button, Escape, a click outside, Back) asks
  /// first when the edits differ from the saved game.
  void _dismissDialog() => Navigator.maybePop(context, false);

  Future<void> _onPopBlocked() async {
    if (!await _resolveUnsavedChanges() || !mounted) return;
    // Saving reports a change to the library; discarding does not.
    Navigator.pop(context, _saved);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final showSkmId = ref.watch(
      settingsProvider.select(
        (settings) =>
            (settings[SettingsKeys.showGameDetailsSkmId] as bool?) ??
            DefaultSettings.showGameDetailsSkmId,
      ),
    );
    return PopScope<bool>(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onPopBlocked();
      },
      child: DialogInteractionScope(
        onPrimaryAction: _saveAction,
        onDismiss: _dismissDialog,
        child: ThemedAlertDialog(
          maxWidth: 1100,
          showCloseButton: false,
          // The banner reaches the edges; the buttons keep the dialog's padding.
          bleedContent: true,
          // Sized to its content, scrolling once it outgrows the window.
          content: _buildContent(theme, showSkmId),
          actions: [
            ElevatedButton(
              onPressed: _confirmDelete,
              style: themedFilledButtonStyle(theme, destructive: true),
              child: const Text('Delete'),
            ),
            ElevatedButton(
              onPressed: _saveAction,
              child: _isSaving
                  ? const AppCircularProgressIndicator(size: 18)
                  : const Text('Save'),
            ),
          ],
          below: _gameIds.length > 1 ? _buildNavigationBar(theme) : null,
        ),
      ),
    );
  }

  /// The game's Steam figures and dates, under the notes and tags.
  List<Widget> _buildStats(AppThemeData theme, bool showSkmId) {
    final game = _currentGame;
    final added = game.dateAdded;
    final updated = _lastUpdatedAt ?? game.updatedAt;
    final developer = _steamDeveloper;
    return [
      if (_isSteam)
        GameStat.reviews(
          theme: theme,
          score: _fetchedReviewScore ?? game.reviewScore,
          count: _fetchedReviewCount ?? 0,
        ),
      if (developer != null && developer.isNotEmpty)
        GameStat(theme: theme, label: 'Developer', value: developer),
      if (_isSteam) GameStat.steamAppId(theme: theme, appId: _steamAppId),
      GameStat.date(theme: theme, label: 'Added', date: added),
      GameStat.date(
        theme: theme,
        label: 'Updated',
        date: updated.isAfter(added.add(const Duration(minutes: 1)))
            ? updated
            : null,
        fallback: 'Unchanged',
      ),
      if (_isSteam)
        GameStat.date(
          theme: theme,
          label: 'Cached',
          date: _steamCacheAt,
          fallback: 'Not cached',
        ),
      if (showSkmId)
        GameStat(theme: theme, label: 'SKM-ID', value: '${game.id}'),
    ];
  }

  /// The Steam AppID and tags set aside by switching away from Steam, put
  /// back if Steam is chosen again before saving, so a slip of the platform
  /// menu needs no new fetch.
  ({String appId, Set<int> tagIds})? _steamStash;

  void _changePlatform(String platform) => _edit(() {
    final wasSteam = _isSteam;
    _platform = platform;
    if (wasSteam && !_isSteam) {
      final steamTagIds = _steamTagIds();
      _steamStash = (
        appId: _steamAppId,
        tagIds: _selectedTagIds.where(steamTagIds.contains).toSet(),
      );
      _steamAppId = '';
      _selectedTagIds.removeWhere(steamTagIds.contains);
    } else if (!wasSteam && _isSteam) {
      if (_steamStash case final stash?) {
        _steamAppId = stash.appId;
        _selectedTagIds.addAll(stash.tagIds);
      }
      _steamStash = null;
    }
  });

  Future<void> _openSteamPage() =>
      openSteamPage(appId: _steamAppId, title: _fields.title.text.trim());

  Widget _buildContent(AppThemeData theme, bool showSkmId) {
    final tags = ref.watch(tagsProvider);
    return GameEditorLayout(
      theme: theme,
      cornerRadius: theme.cornerRadius,
      heading: 'Game Editor',
      cover: CoverImageCard(
        theme: theme,
        isDlc: _isDlc,
        isUsed: _isUsed,
        hasDeadline: _hasDeadline,
        deadlineDate: _deadlineDate,
        controller: _fields.coverImage,
        onChanged: _markChanged,
        showPath: false,
      ),
      coverController: _fields.coverImage,
      actions: [
        if (_isSteam) ...[
          IconButton(
            tooltip: 'Fetch Steam data',
            onPressed: _isFetching ? null : _fetchSteamData,
            color: theme.accent,
            icon: _isFetching
                ? const AppCircularProgressIndicator.icon()
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
          icon: Icon(Icons.close, color: theme.textPrimary),
          onPressed: _dismissDialog,
        ),
      ],
      titleController: _fields.title,
      onTitleChanged: (_) => _markChanged(),
      keyField: GameKeyField(
        theme: theme,
        controller: _fields.gameKey,
        onChanged: (_) => _markChanged(),
        isVisible: _isKeyVisible,
        onVisibilityChanged: (value) => setState(() => _isKeyVisible = value),
        onCopy: _copyKey,
        playfulHints: true,
      ),
      platform: PlatformMenuButton(
        theme: theme,
        value: _platform,
        tooltip: 'Selected platform: $_platform. Choose platform',
        includeAutoDetect: false,
        onSelected: _changePlatform,
      ),
      options: GameOptionsRow(
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
      ),
      notesController: _fields.notes,
      onNotesChanged: _markChanged,
      customTags: tags.where((tag) => !tag.isSteamTag).toList(),
      selectedTagIds: _selectedTagIds,
      onTagToggled: (tagId) => _edit(() {
        if (!_selectedTagIds.remove(tagId)) _selectedTagIds.add(tagId);
      }),
      steamTags: tags
          .where((tag) => tag.isSteamTag && _selectedTagIds.contains(tag.id))
          .toList(),
      stats: _buildStats(theme, showSkmId),
    );
  }

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
    Widget arrow(IconData icon, String tooltip, int delta) {
      final target = _currentIndex + delta;
      return IconButton(
        style: arrowStyle,
        icon: Icon(icon),
        tooltip: tooltip,
        onPressed: target >= 0 && target < _gameIds.length
            ? () => _navigate(delta)
            : null,
      );
    }

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
              arrow(Icons.chevron_left, 'Previous Game', -1),
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
              arrow(Icons.chevron_right, 'Next Game', 1),
            ],
          ),
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
