/// Game details dialog - view and edit game information
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/platform_patterns.dart';
import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import '../../providers/app_providers.dart';
import '../widgets/app_progress_indicator.dart';
import '../widgets/app_tag_chip.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/tag_list.dart';
import '../widgets/notification_system.dart';
import '../widgets/section_groupbox.dart';
import '../widgets/platform_icon.dart';
import '../widgets/app_date_field.dart';
import 'deadline_picker_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/steam_service.dart';
import '../dialogs/steam_lookup_dialog.dart';

/// Show the game details dialog
Future<bool?> showGameDetailsDialog(
  BuildContext context,
  Game game, {
  List<int>? gameIds,
  Future<void> Function(int gameId)? onViewedGame,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => GameDetailsDialog(
      game: game,
      gameIds: gameIds,
      initialGameId: game.id,
      onViewedGame: onViewedGame,
    ),
  );
}

/// Game details dialog
class GameDetailsDialog extends ConsumerStatefulWidget {
  const GameDetailsDialog({
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
  ConsumerState<GameDetailsDialog> createState() => _GameDetailsDialogState();
}

class _GameDetailsDialogState extends ConsumerState<GameDetailsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _titleController;
  late TextEditingController _keyController;
  late TextEditingController _notesController;
  late TextEditingController _coverImageController;

  late Game _currentGame;
  late List<int> _gameIds;
  int _currentIndex = 0;

  late String _platform;
  late bool _hasDeadline;
  late DateTime? _deadlineDate;
  late bool _isDlc;
  late bool _isUsed;
  late Set<int> _selectedTagIds;

  bool _isKeyVisible = false; // Will be set from settings in initState
  final bool _isEditing = true;
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
    _tabController = TabController(length: 3, vsync: this);

    // Read the maskKeys setting - if maskKeys is true, keys should be hidden by default
    final maskKeys = ref.read(securitySettingsProvider).maskKeys;
    _isKeyVisible =
        !maskKeys; // Invert: maskKeys=true means key should be hidden (not visible)

    // Initialize navigation list
    if (widget.gameIds != null && widget.gameIds!.isNotEmpty) {
      _gameIds = List.from(widget.gameIds!);
    } else if (widget.game != null) {
      _gameIds = [widget.game!.id];
    } else {
      // Should not happen based on logic but handled safe
      _gameIds = [];
    }

    // Determine initial game
    final startId = widget.initialGameId ?? widget.game?.id;
    if (startId != null && _gameIds.contains(startId)) {
      _currentIndex = _gameIds.indexOf(startId);
    } else {
      _currentIndex = 0;
    }

    // Set current game - try to get fresh from provider if possible, else use widget.game
    _currentGame =
        widget.game ??
        ref.read(gameByIdProvider(_gameIds[_currentIndex])) ??
        ref
            .read(allGamesProvider)
            .firstWhere((g) => g.id == _gameIds[_currentIndex]);

    // If we have an ID but widget.game is null or stale, ensure we have the latest
    if (_gameIds.isNotEmpty) {
      try {
        final fresh = ref.read(gameByIdProvider(_gameIds[_currentIndex]));
        if (fresh != null) {
          _currentGame = fresh;
        }
      } catch (e) {
        // keep default
      }
    }

    _initializeFromGame();
    _scheduleViewedGameNotification();
  }

  void _scheduleViewedGameNotification() {
    if (_viewedNotificationScheduled) {
      return;
    }

    _viewedNotificationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _viewedNotificationScheduled = false;
      _notifyViewedGame();
    });
  }

  void _notifyViewedGame() {
    final gameId = _currentGame.id;
    if (_lastViewedNotifiedId == gameId) {
      return;
    }
    _lastViewedNotifiedId = gameId;
    widget.onViewedGame?.call(gameId);
  }

  void _initializeFromGame() {
    // Title controller listens for changes so the header updates immediately
    _titleController = TextEditingController(text: _currentGame.title)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _keyController = TextEditingController(text: _currentGame.gameKey);
    _notesController = TextEditingController(text: _currentGame.notes);
    _coverImageController = TextEditingController(
      text: _currentGame.coverImage,
    );

    _platform = _currentGame.platform;
    _hasDeadline = _currentGame.hasDeadline;
    _deadlineDate = _currentGame.deadlineDate;
    _isDlc = _currentGame.isDlc;
    _isUsed = _currentGame.isUsed;
    _selectedTagIds = _currentGame.tagIds.toSet();
    _steamAppId = _currentGame.steamAppId; // initialize local AppID state
    _steamDeveloper = _currentGame.developer;
    _fetchedReviewScore = _currentGame.reviewCount == 0
        ? null
        : _currentGame.reviewScore;
    _fetchedReviewCount = _currentGame.reviewCount == 0
        ? null
        : _currentGame.reviewCount;
    _lastUpdatedAt = _currentGame.updatedAt;

    _hasChanges = false;

    // Load cache timestamp if present
    _loadSteamCacheAt();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _keyController.dispose();
    _notesController.dispose();
    _coverImageController.dispose();
    super.dispose();
  }

  void _markChanged() {
    setState(() {
      _hasChanges = true;
    });
  }

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
        title: _titleController.text.trim(),
        gameKey: _keyController.text.trim(),
        platform: _platform,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        coverImage: _coverImageController.text.trim().isEmpty
            ? null
            : _coverImageController.text.trim(),
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
    final confirmed = await showConfirmDialog(
      context: context,
      theme: theme,
      title: 'Delete Game "${_currentGame.title}"?',
      message: 'This action cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );

    if (confirmed) {
      await ref.read(gamesProvider.notifier).deleteGame(_currentGame.id);
      NotificationManager.instance.success('Game deleted');
      if (mounted) Navigator.pop(context, true);
    }
  }

  void _copyKey() {
    Clipboard.setData(ClipboardData(text: _currentGame.gameKey));
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
        title: _titleController.text.trim(),
        steamService: steamService,
      );
      if (!mounted) return;
      if (resolution.cancelled) {
        return;
      }

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
        ref,
        _currentGame,
        result,
        SteamApplyOptions.defaults,
      );

      if (applyError != null) {
        NotificationManager.instance.error(
          'Failed to update game with Steam data: $applyError',
        );
        return;
      }

      await ref.read(gamesProvider.notifier).refreshGame(_currentGame.id);

      final updated =
          ref.read(gameByIdProvider(_currentGame.id)) ?? _currentGame;

      // Update local tracking
      _currentGame = updated;

      setState(() {
        _steamAppId = updated.steamAppId;
        _steamDeveloper = result.developer;
        _isDlc = updated.isDlc;
        _selectedTagIds = updated.tagIds.toSet();
        _coverImageController.text = updated.coverImage;
        _fetchedReviewScore = updated.reviewCount == 0
            ? null
            : updated.reviewScore;
        _fetchedReviewCount = updated.reviewCount == 0
            ? null
            : updated.reviewCount;
        _lastUpdatedAt = updated.updatedAt;
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
    final cached = await getCachedAtForTitle(_titleController.text.trim());
    if (mounted) setState(() => _steamCacheAt = cached);
  }

  Future<void> _navigate(int delta) async {
    if (_hasChanges) {
      final theme = ref.read(themeProvider);
      final shouldSave = await showDialog<String>(
        context: context,
        builder: (ctx) => ThemedAlertDialog(
          theme: theme,

          title: DialogHeader(
            icon: Icons.edit_note,
            title: 'Unsaved Changes',
            theme: theme,
          ),
          content: Text(
            'Save changes to "${_currentGame.title}"?',
            style: TextStyle(color: theme.textSecondary),
          ),
          actions: [
            TextButton(
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
        // Fetch fresh
        try {
          final fresh = ref.read(gameByIdProvider(_gameIds[_currentIndex]));
          if (fresh != null) {
            _currentGame = fresh;
          }
        } catch (_) {
          // If not found in provider (maybe filtered out?), assume broken state or fallback
        }
        _initializeFromGame();
      });
      _scheduleViewedGameNotification();
    }
  }

  void _dismissDialog() {
    Navigator.pop(context, false);
  }

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
        theme: theme,
        showCloseButton: false,
        title: _buildHeader(theme),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Chips
            _buildChips(theme),
            const SizedBox(height: kDialogSpacing),

            // Tabs
              TabBar(
                controller: _tabController,
                labelColor: theme.accent,
                unselectedLabelColor: theme.textSecondary,
                indicator: theme.tabIndicator,
                indicatorSize: TabBarIndicatorSize.tab,
                tabs: const [
                  Tab(text: 'Details'),
                  Tab(text: 'Tags'),
                  Tab(text: 'Notes'),
                ],
              ),

              // Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _DetailsTab(
                      theme: theme,
                      game: _currentGame,
                      showGameDetailsSkmId: showGameDetailsSkmId,
                      titleController: _titleController,
                      keyController: _keyController,
                      coverImageController: _coverImageController,
                      platform: _platform,
                      hasDeadline: _hasDeadline,
                      deadlineDate: _deadlineDate,
                      isDlc: _isDlc,
                      isUsed: _isUsed,
                      isKeyVisible: _isKeyVisible,
                      isEditing: _isEditing,
                      steamAppId: _steamAppId,
                      steamDeveloper: _steamDeveloper,
                      steamCacheAt: _steamCacheAt,
                      lastUpdatedAt: _lastUpdatedAt,
                      steamReviewScore: _fetchedReviewScore,
                      steamReviewCount: _fetchedReviewCount,
                      onPlatformChanged: (v) => setState(() {
                        final wasSteam = _platform == 'Steam';
                        _platform = v;

                        // If switching away from Steam, clear Steam-specific state and remove any Steam tags
                        if (wasSteam && v != 'Steam') {
                          _steamAppId = '';
                          final steamTags = ref.read(steamTagsProvider);
                          final steamTagIds = steamTags
                              .map((t) => t.id)
                              .toSet();
                          _selectedTagIds.removeWhere(
                            (id) => steamTagIds.contains(id),
                          );
                        }

                        _markChanged();
                      }),
                      onHasDeadlineChanged: (v) => setState(() {
                        _hasDeadline = v;
                        _markChanged();
                      }),
                      onDeadlineDateChanged: (v) => setState(() {
                        _deadlineDate = v;
                        _markChanged();
                      }),
                      onIsDlcChanged: (v) => setState(() {
                        _isDlc = v;
                        _markChanged();
                      }),
                      onIsUsedChanged: (v) => setState(() {
                        _isUsed = v;
                        _markChanged();
                      }),
                      onKeyVisibilityChanged: (v) =>
                          setState(() => _isKeyVisible = v),
                      onCopyKey: _copyKey,
                      onFieldChanged: _markChanged,
                    ),
                    _TagsTab(
                      theme: theme,
                      tags: tags,
                      selectedTagIds: _selectedTagIds,
                      onTagToggled: (tagId) {
                        setState(() {
                          if (_selectedTagIds.contains(tagId)) {
                            _selectedTagIds.remove(tagId);
                          } else {
                            _selectedTagIds.add(tagId);
                          }
                          _markChanged();
                        });
                      },
                      game: _currentGame,
                    ),
                    _NotesTab(
                      theme: theme,
                      controller: _notesController,
                      isEditing: _isEditing,
                      onChanged: _markChanged,
                    ),
                  ],
                ),
              ),

          ],
        ),
        actions: [_buildFooter(theme)],
        below: _gameIds.length > 1 ? _buildNavigationBar(theme) : null,
      ),
    );
  }

  Widget _buildHeader(AppThemeData theme) {
    // Use edited cover image if present so UI updates immediately after fetch
    final coverImage = _coverImageController.text.trim();
    final isWindowsPath = RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(coverImage);
    final ImageProvider? coverProvider = coverImage.isEmpty
        ? null
        : coverImage.startsWith('http')
        ? NetworkImage(coverImage)
        : coverImage.startsWith('assets/')
        ? AssetImage(coverImage)
        : FileImage(
            coverImage.startsWith('file://') && !isWindowsPath
                ? File.fromUri(Uri.parse(coverImage))
                : File(coverImage),
          );

    return Row(
      children: [
        // Cover image thumbnail
        Container(
          width: 140,
          height: 70,
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(theme.cornerRadius),
            image: coverProvider == null
                ? null
                : DecorationImage(image: coverProvider, fit: BoxFit.cover),
          ),
          child: coverProvider != null
              ? null
              : Icon(
                  Icons.videogame_asset_outlined,
                  color: theme.textHint,
                  size: 28,
                ),
        ),
        const SizedBox(width: 16),

        // Title — use live editing state so header updates immediately
        Expanded(
          child: Text(
            _titleController.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        // Close button
        IconButton(
          icon: Icon(Icons.close, color: theme.textSecondary),
          onPressed: _dismissDialog,
        ),
      ],
    );
  }

  Widget _buildChips(AppThemeData theme) {
    final platformEnum = GamePlatform.fromDisplayName(_platform);
    final deadlineColor = Color.lerp(theme.accent, theme.secondary, 0.35) ??
        theme.accent;

    Widget buildQuickChip({
      required String label,
      required Color color,
      Widget? leading,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(theme.cornerRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              leading,
              const SizedBox(width: 4),
            ],
            Text(label, style: TextStyle(color: color, fontSize: 13)),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        buildQuickChip(
          label: _platform,
          color: theme.accent,
          leading: PlatformIcon(
            platform: platformEnum,
            color: theme.accent,
            size: 16,
          ),
        ),

        if (_isUsed)
          buildQuickChip(
            label: 'USED',
            color: theme.textSecondary,
          ),

        if (_isDlc)
          buildQuickChip(
            label: 'DLC',
            color: theme.secondary,
          ),

        // Deadline chip (shows when deadline toggle is enabled)
        if (_hasDeadline)
          buildQuickChip(
            label: _deadlineDate != null
                ? 'Deadline: ${DateFormat('dd/MM/yyyy').format(_deadlineDate!)}'
                : 'Deadline: -',
            color: deadlineColor,
          ),
      ],
    );
  }

  Future<void> _openSteamPage() async {
    final title = _titleController.text.trim();
    final Uri url = _steamAppId.isNotEmpty
        ? Uri.parse(steamAppPageUrl(_steamAppId))
        : Uri.parse(steamSearchPageUrl(title));
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      NotificationManager.instance.error('Failed to open Steam page: $e');
    }
  }

  Widget _buildNavigationBar(AppThemeData theme) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: theme.background,
            borderRadius: BorderRadius.circular(theme.cornerRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  Icons.chevron_left,
                  color: _currentIndex > 0 ? theme.textPrimary : theme.textHint,
                ),
                tooltip: 'Previous Game',
                onPressed: _currentIndex > 0 ? () => _navigate(-1) : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '${_currentIndex + 1}/${_gameIds.length}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.chevron_right,
                  color: _currentIndex < _gameIds.length - 1
                      ? theme.textPrimary
                      : theme.textHint,
                ),
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

  Widget _buildFooter(AppThemeData theme) {
    return Row(
      children: [
        // Delete icon button
        IconButton(
          tooltip: 'Delete',
          onPressed: _confirmDelete,
          icon: const Icon(Icons.delete),
          color: Colors.red,
        ),

        if (_platform == 'Steam') ...[
          Tooltip(
            message: 'Fetch Steam Data',
            child: IconButton(
              onPressed: _isFetching ? null : _fetchSteamData,
              icon: _isFetching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: AppCircularProgressIndicator(),
                    )
                  : const Icon(Icons.cloud_download),
            ),
          ),
          IconButton(
            tooltip: 'Steam Page',
            onPressed: _openSteamPage,
            icon: const Icon(Icons.open_in_new),
          ),
        ],

        const Spacer(),

        // Save button
        ElevatedButton.icon(
          onPressed: _hasChanges && !_isSaving ? _save : null,
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: AppCircularProgressIndicator(),
                )
              : const Icon(Icons.save),
          label: const Text('Save'),
        ),
      ],
    );
  }
}

/// Details tab
class _DetailsTab extends StatelessWidget {
  const _DetailsTab({
    required this.theme,
    required this.game,
    required this.showGameDetailsSkmId,
    required this.titleController,
    required this.keyController,
    required this.coverImageController,
    required this.platform,
    required this.hasDeadline,
    required this.deadlineDate,
    required this.isDlc,
    required this.isUsed,
    required this.isKeyVisible,
    required this.isEditing,
    required this.steamAppId,
    this.steamCacheAt,
    this.lastUpdatedAt,
    this.steamReviewScore,
    this.steamReviewCount,
    required this.onPlatformChanged,
    required this.onHasDeadlineChanged,
    required this.onDeadlineDateChanged,
    required this.onIsDlcChanged,
    required this.onIsUsedChanged,
    required this.onKeyVisibilityChanged,
    required this.onCopyKey,
    required this.onFieldChanged,
    this.steamDeveloper,
  });

  final AppThemeData theme;
  final Game game;
  final bool showGameDetailsSkmId;
  final TextEditingController titleController;
  final TextEditingController keyController;
  final TextEditingController coverImageController;
  final String platform;
  final bool hasDeadline;
  final DateTime? deadlineDate;
  final bool isDlc;
  final bool isUsed;
  final bool isKeyVisible;
  final bool isEditing;
  final void Function(String) onPlatformChanged;
  final void Function(bool) onHasDeadlineChanged;
  final void Function(DateTime?) onDeadlineDateChanged;
  final void Function(bool) onIsDlcChanged;
  final void Function(bool) onIsUsedChanged;
  final void Function(bool) onKeyVisibilityChanged;
  final VoidCallback onCopyKey;
  final VoidCallback onFieldChanged;

  // Steam fetch props
  final String steamAppId;
  final String? steamDeveloper;

  // Fetched review preview (may be null)
  final DateTime? steamCacheAt;
  final DateTime? lastUpdatedAt;
  final int? steamReviewScore;
  final int? steamReviewCount;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Info section
          SectionGroupBox(
            title: 'Information',
            theme: theme,
            titleIcon: Icons.info,
            groupPosition: SectionGroupPosition.first,
            alternateBackground: false,
            child: Column(
              children: [
                // Title
                TextField(
                  controller: titleController,
                  enabled: isEditing,
                  style: TextStyle(color: theme.textPrimary),
                  decoration: const InputDecoration(labelText: 'Title'),
                  onChanged: (_) {
                    // mark changed and allow caller to react
                    onFieldChanged();
                  },
                  onSubmitted: (v) {
                    // Ensure Enter commits/normalises the value and triggers UI update
                    final trimmed = v.trim();
                    if (trimmed != v) titleController.text = trimmed;
                    onFieldChanged();
                  },
                ),
                const SizedBox(height: kDialogSpacing),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: keyController,
                        enabled: isEditing,
                        obscureText: !isKeyVisible,
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontFamily: 'monospace',
                          letterSpacing: 1.5,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Game Key',
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  isKeyVisible
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: theme.textSecondary,
                                ),
                                tooltip: isKeyVisible ? 'Hide key' : 'Show key',
                                onPressed: () =>
                                    onKeyVisibilityChanged(!isKeyVisible),
                              ),
                              IconButton(
                                icon: Icon(Icons.copy, color: theme.accent),
                                tooltip: 'Copy key',
                                onPressed: onCopyKey,
                              ),
                            ],
                          ),
                        ),
                        onChanged: (_) => onFieldChanged(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: kDialogSpacing),

                // Platform
                DropdownButtonFormField<String>(
                  initialValue: platform,
                  isExpanded: true,
                  menuMaxHeight: 320,
                  borderRadius: BorderRadius.circular(theme.cornerRadius),
                  style: TextStyle(color: theme.textPrimary),
                  dropdownColor: theme.surface,
                  decoration: const InputDecoration(labelText: 'Platform'),
                  items: GamePlatform.values.map((p) {
                    return DropdownMenuItem(
                      value: p.displayName,
                      child: Row(
                        children: [
                          PlatformIcon(
                            platform: p,
                            color: theme.textPrimary,
                            size: 16,
                          ),
                          const SizedBox(width: kElementHSpacing),
                          Text(p.displayName),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: isEditing
                      ? (v) {
                          if (v != null) onPlatformChanged(v);
                        }
                      : null,
                ),
                const SizedBox(height: kDialogSpacing),

                // Cover image URL
                TextField(
                  controller: coverImageController,
                  enabled: isEditing,
                  style: TextStyle(color: theme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Cover Image URL',
                    suffixIcon: IconButton(
                      icon: Icon(Icons.image, color: theme.textHint),
                      tooltip: 'Pick image',
                      onPressed: isEditing
                          ? () async {
                              try {
                                final result = await FilePicker
                                    .pickFiles(
                                      dialogTitle: 'Pick cover image',
                                      type: FileType.image,
                                      allowMultiple: false,
                                    );
                                final selectedPath = result?.files.single.path;
                                if (selectedPath != null &&
                                    selectedPath.isNotEmpty) {
                                  coverImageController.text = selectedPath;
                                  onFieldChanged();
                                }
                              } catch (e) {
                                NotificationManager.instance.error(
                                  'Failed to pick image: $e',
                                );
                              }
                            }
                          : null,
                    ),
                  ),
                  onChanged: (_) => onFieldChanged(),
                ),
              ],
            ),
          ),

          // Status section
          SectionGroupBox(
            title: 'Status',
            theme: theme,
            titleIcon: Icons.flag,
            groupPosition: SectionGroupPosition.middle,
            alternateBackground: true,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppOptionChip(
                  label: 'Key Used',
                  theme: theme,
                  isSelected: isUsed,
                  onTap: isEditing ? () => onIsUsedChanged(!isUsed) : null,
                ),
                AppOptionChip(
                  label: 'DLC',
                  theme: theme,
                  isSelected: isDlc,
                  onTap: isEditing ? () => onIsDlcChanged(!isDlc) : null,
                ),
                AppOptionChip(
                  label: 'Deadline',
                  theme: theme,
                  isSelected: hasDeadline,
                  onTap: isEditing
                      ? () => onHasDeadlineChanged(!hasDeadline)
                      : null,
                ),
                if (hasDeadline)
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: kDeadlineSelectorWidth,
                    ),
                    child: AppDateField(
                      theme: theme,
                      date: deadlineDate,
                      placeholder: 'No date set',
                      enabled: isEditing,
                      onTap: isEditing
                          ? () async {
                              final date = await showDeadlinePickerDialog(
                                context: context,
                                theme: theme,
                                initialDate: deadlineDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                useRootNavigator: false,
                              );
                              onDeadlineDateChanged(date);
                            }
                          : null,
                    ),
                  ),
              ],
            ),
          ),

          // Metadata
          SectionGroupBox(
            title: showGameDetailsSkmId
                ? 'Metadata / SKM-ID ${game.id}'
                : 'Metadata',
            theme: theme,
            titleIcon: Icons.schedule,
            groupPosition: SectionGroupPosition.last,
            alternateBackground: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MetadataRow(
                  label: 'Added',
                  value: DateFormat('dd/MM/yyyy HH:mm').format(game.createdAt),
                  theme: theme,
                ),
                _MetadataRow(
                  label: 'Updated',
                  value: DateFormat(
                    'dd/MM/yyyy HH:mm',
                  ).format(lastUpdatedAt ?? game.updatedAt),
                  theme: theme,
                ),
                if (platform == 'Steam')
                  _MetadataRow(
                    label: 'Cache',
                    value: steamCacheAt != null
                        ? DateFormat('dd/MM/yyyy HH:mm').format(steamCacheAt!)
                        : 'No cached data',
                    theme: theme,
                  ),
                if (steamDeveloper != null && steamDeveloper!.isNotEmpty)
                  _MetadataRow(
                    label: 'Developer',
                    value: steamDeveloper!,
                    theme: theme,
                  ),
                if (platform == 'Steam')
                  _MetadataRow(
                    label: 'Reviews',
                    value: (steamReviewCount == null || steamReviewCount == 0)
                        ? 'No reviews'
                        : '${steamReviewScore ?? game.reviewScore}% · ${Game.reviewRatingFor(steamReviewScore ?? game.reviewScore)} · ${NumberFormat.compact().format(steamReviewCount)} reviews',
                    theme: theme,
                  ),
                // Steam AppID (only shown for Steam platform)
                if (platform == 'Steam')
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 95,
                          child: Text(
                            'Steam AppID',
                            style: TextStyle(color: theme.textSecondary),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            steamAppId.isEmpty ? 'Not set' : steamAppId,
                            style: TextStyle(color: theme.textPrimary),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.copy,
                            color: theme.textSecondary,
                            size: 20,
                          ),
                          tooltip: 'Copy AppID',
                          iconSize: 20,
                          padding: const EdgeInsets.all(5),
                          constraints: const BoxConstraints(),
                          onPressed: steamAppId.isEmpty
                              ? null
                              : () {
                                  Clipboard.setData(
                                    ClipboardData(text: steamAppId),
                                  );
                                  NotificationManager.instance.success(
                                    'Steam AppID copied to clipboard',
                                  );
                                },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({
    required this.label,
    required this.value,
    required this.theme,
  });

  final String label;
  final String value;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(color: theme.textSecondary)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: theme.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// Tags tab
class _TagsTab extends ConsumerStatefulWidget {
  const _TagsTab({
    required this.theme,
    required this.tags,
    required this.selectedTagIds,
    required this.onTagToggled,
    required this.game,
  });

  final AppThemeData theme;
  final List<Tag> tags;
  final Set<int> selectedTagIds;
  final void Function(int) onTagToggled;
  final Game game;

  @override
  ConsumerState<_TagsTab> createState() => _TagsTabState();
}

class _TagsTabState extends ConsumerState<_TagsTab> {
  List<Tag> _steamTagsForGame = [];

  @override
  void initState() {
    super.initState();
    _computeSteamTagsFromProps();
  }

  @override
  void didUpdateWidget(covariant _TagsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tags != widget.tags ||
        oldWidget.selectedTagIds != widget.selectedTagIds) {
      _computeSteamTagsFromProps();
    }
  }

  void _computeSteamTagsFromProps() {
    _steamTagsForGame = widget.tags
        .where((t) => t.isSteamTag && widget.selectedTagIds.contains(t.id))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final customTags = widget.tags.where((t) => !t.isSteamTag).toList();
    final selectedCustomIds = widget.selectedTagIds
        .where((id) => customTags.any((t) => t.id == id))
        .toSet();

    return ListView(
      padding: const EdgeInsets.only(top: 16),
      children: [
        SectionGroupBox(
          title: 'Custom Tags',
          description: 'click to add/remove',
          theme: theme,
          titleIcon: Icons.label,
          groupPosition: SectionGroupPosition.first,
          child: customTags.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'No custom tags created yet',
                    style: TextStyle(color: theme.textHint),
                    textAlign: TextAlign.center,
                  ),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: TagList(
                    tags: customTags,
                    theme: theme,
                    selectedTagIds: selectedCustomIds,
                    onTagToggled: (tagId) => widget.onTagToggled(tagId),
                    showSearch: true,
                  ),
                ),
        ),
        SectionGroupBox(
          title: 'Steam Tags',
          description: 'auto-managed',
          theme: theme,
          titleIcon: FontAwesomeIcons.steam.data,
          groupPosition: SectionGroupPosition.last,
          alternateBackground: true,
          child: _steamTagsForGame.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'No Steam tags imported yet',
                    style: TextStyle(color: theme.textHint),
                    textAlign: TextAlign.center,
                  ),
                )
              : TagList(
                  tags: _steamTagsForGame,
                  theme: theme,
                  allSelected: true,
                ),
        ),
      ],
    );
  }
}

/// Notes tab
class _NotesTab extends StatelessWidget {
  const _NotesTab({
    required this.theme,
    required this.controller,
    required this.isEditing,
    required this.onChanged,
  });

  final AppThemeData theme;
  final TextEditingController controller;
  final bool isEditing;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SectionGroupBox(
        title: 'Notes',
        theme: theme,
        titleIcon: Icons.notes,
        child: TextField(
          controller: controller,
          enabled: isEditing,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: TextStyle(color: theme.textPrimary),
          decoration: InputDecoration(
            constraints: const BoxConstraints(minHeight: 0),
            filled: true,
            fillColor: theme.inputBackground,
            hintText: 'Add notes about this game...',
            hintStyle: TextStyle(color: theme.textHint),
            border: theme.resolveInputBorder(showTopBorder: true),
          ),
          onChanged: (_) => onChanged(),
        ),
      ),
    );
  }
}
