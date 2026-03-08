/// Game details dialog - view and edit game information
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/platform_patterns.dart';
import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import '../../providers/app_providers.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/flow_tag_selector.dart';
import '../widgets/notification_system.dart';
import '../widgets/section_groupbox.dart';
import '../widgets/toggle_switch.dart';
import '../../core/services/steam_service.dart';
import '../dialogs/steam_lookup_dialog.dart';

/// Show the game details dialog
Future<bool?> showGameDetailsDialog(
  BuildContext context,
  Game game, {
  List<int>? gameIds,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => GameDetailsDialog(
        game: game,
        gameIds: gameIds,
        initialGameId: game.id,
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
      this.initialGameId
  });

  final Game? game;
  final List<int>? gameIds;
  final int? initialGameId;

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

  // Steam-specific state
  late String _steamAppId;
  bool _isFetching = false;
  DateTime? _steamCacheAt;
  DateTime? _lastUpdatedAt;

  // Local fetched review preview values (null == not available)
  int? _fetchedReviewScore;
  int? _fetchedReviewCount;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // Read the maskKeys setting - if maskKeys is true, keys should be hidden by default
    final maskKeys = ref.read(securitySettingsProvider).maskKeys;
    _isKeyVisible = !maskKeys; // Invert: maskKeys=true means key should be hidden (not visible)
    
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
      ref.read(allGamesProvider).firstWhere((g) => g.id == _gameIds[_currentIndex]);
    
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
  }

  void _initializeFromGame() {
    // Title controller listens for changes so the header updates immediately
    _titleController = TextEditingController(text: _currentGame.title)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _keyController = TextEditingController(text: _currentGame.gameKey);
    _notesController = TextEditingController(text: _currentGame.notes);
    _coverImageController =
        TextEditingController(text: _currentGame.coverImage);

    _platform = _currentGame.platform;
    _hasDeadline = _currentGame.hasDeadline;
    _deadlineDate = _currentGame.deadlineDate;
    _isDlc = _currentGame.isDlc;
    _isUsed = _currentGame.isUsed;
    _selectedTagIds = _currentGame.tagIds.toSet();
    _steamAppId = _currentGame.steamAppId; // initialize local AppID state
    _fetchedReviewScore = _currentGame.reviewCount == 0 ? null : _currentGame.reviewScore;
    _fetchedReviewCount = _currentGame.reviewCount == 0 ? null : _currentGame.reviewCount;
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
      final selectedTagIds = _selectedTagIds.where((id) => _platform == 'Steam' || !steamTagIds.contains(id)).toList();

      // Ensure we have logic to merge with current state properly
        final currentGameState =
          ref.read(gameByIdProvider(_currentGame.id)) ?? _currentGame;

      final updatedGame = _currentGame.copyWith(
        title: _titleController.text.trim(),
        gameKey: _keyController.text.trim(),
        platform: _platform,
        notes:
            _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
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

      final ok = await ref.read(gamesProvider.notifier).updateGame(
        updatedGame,
        tagIds: selectedTagIds,
      );
      
      if (!ok) throw Exception('Update failed');
      
      // Update local state to match saved
      _currentGame = updatedGame;
      _hasChanges = false;

      NotificationManager.instance.success('Game updated: ${updatedGame.title}');
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
      title: 'Delete Game?',
      message: 'Are you sure you want to delete "${_currentGame.title}"?\n'
          'This action cannot be undone.',
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
      NotificationManager.instance.info('Fetch is only available when Platform is set to Steam');
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
        NotificationManager.instance.error('Failed to update game with Steam data: $applyError');
        return;
      }

      await ref.read(gamesProvider.notifier).refreshGame(_currentGame.id);

      final updated = ref.read(gameByIdProvider(_currentGame.id)) ?? _currentGame;
      
      // Update local tracking
      _currentGame = updated;
      
      setState(() {
        _steamAppId = updated.steamAppId;
        _isDlc = updated.isDlc;
        _selectedTagIds = updated.tagIds.toSet();
        _coverImageController.text = updated.coverImage;
        _fetchedReviewScore = updated.reviewCount == 0 ? null : updated.reviewScore;
        _fetchedReviewCount = updated.reviewCount == 0 ? null : updated.reviewCount;
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
       final shouldSave = await showDialog<String>(
         context: context,
         builder: (ctx) => AlertDialog(
            title: const Text('Unsaved Changes'),
            content: Text('Save changes to "${_currentGame.title}"?'),
            actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Discard')),
                ElevatedButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
            ]
         )
       );
       
       if (shouldSave == 'cancel') return;
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final tags = ref.watch(tagsProvider);
    final screenSize = MediaQuery.of(context).size;

    final dialogWidth = (screenSize.width * 0.7).clamp(600.0, 900.0);
    final dialogHeight = (screenSize.height * 0.8).clamp(500.0, 700.0);

    return Dialog(
      backgroundColor: theme.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cornerRadius * 2),
      ),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            _buildHeader(theme),
            const SizedBox(height: 16),

            // Tabs
            TabBar(
              controller: _tabController,
              labelColor: theme.accent,
              unselectedLabelColor: theme.textSecondary,
              indicatorColor: theme.accent,
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
                        final steamTagIds = steamTags.map((t) => t.id).toSet();
                        _selectedTagIds.removeWhere((id) => steamTagIds.contains(id));
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

            const SizedBox(height: 16),

            // Footer
            _buildFooter(theme),
          ],
        ),
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
                : DecorationImage(
                    image: coverProvider,
                    fit: BoxFit.cover,
                  ),
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

        // Title and platform — use live editing state so header updates immediately
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _titleController.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _platform,
                      style: TextStyle(
                        color: theme.accent,
                        fontSize: 12,
                      ),
                    ),
                  ),

                  // Deadline chip (shows when deadline toggle is enabled)
                  if (_hasDeadline) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _deadlineDate != null
                            ? 'Deadline: ${DateFormat('dd/MM/yyyy').format(_deadlineDate!)}'
                            : 'Deadline: -',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],

                  if (_isDlc) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                       child: const Text(
                        'DLC',
                        style: TextStyle(
                          color: Colors.purple,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  if (_isUsed) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                       child: const Text(
                        'USED',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        // Navigation controls
        if (_gameIds.isNotEmpty && _gameIds.length > 1) ...[
             IconButton(
                icon: Icon(Icons.chevron_left, color: _currentIndex > 0 ? theme.textPrimary : theme.textHint),
                tooltip: 'Previous Game',
                onPressed: _currentIndex > 0 ? () => _navigate(-1) : null,
            ),
             Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                    '${_currentIndex + 1}/${_gameIds.length}',
                    style: TextStyle(color: theme.textSecondary, fontSize: 13)
                ),
            ),
             IconButton(
                icon: Icon(Icons.chevron_right, color: _currentIndex < _gameIds.length - 1 ? theme.textPrimary : theme.textHint),
                tooltip: 'Next Game',
                onPressed: _currentIndex < _gameIds.length - 1 ? () => _navigate(1) : null,
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 24, color: theme.border),
            const SizedBox(width: 16),
        ],

        // Close button
        IconButton(
          icon: Icon(Icons.close, color: theme.textSecondary),
          onPressed: () { 
             if (_hasChanges) {
               // If close is clicked but changes exist, ask to save? 
               // For now just allow close (discard) per standard dialog generic behavior 
               // or maybe I should trigger the same check as navigate? 
               // User specifically asked for "easily switch", manual save is in footer.
               // Let's rely on user clicking Save or discarding via Close.
             }
             Navigator.pop(context, false);
          },
        ),
      ],
    );
  }

  Widget _buildFooter(AppThemeData theme) {
    return Row(
      children: [
        // Delete button
        OutlinedButton.icon(
          onPressed: _confirmDelete,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
          ),
          icon: const Icon(Icons.delete),
          label: const Text('Delete'),
        ),

        if (_platform == 'Steam') ...[
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _isFetching ? null : _fetchSteamData,
            icon: _isFetching
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.primaryButtonText,
                    ),
                  )
                : const Icon(Icons.cloud_download),
            label: const Text('Fetch Steam Data'),
          ),
        ],

        const Spacer(),

        // Cancel button
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 12),

        // Save button
        ElevatedButton.icon(
          onPressed: _hasChanges && !_isSaving ? _save : null,
          icon: _isSaving
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.primaryButtonText,
                  ),
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
  });

  final AppThemeData theme;
  final Game game;
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
                  decoration: const InputDecoration(
                    labelText: 'Title',
                  ),
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
                const SizedBox(height: 16),

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
                          border: const OutlineInputBorder(),
                          // Use suffixIcon (like image picker) so layout/padding matches
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  isKeyVisible ? Icons.visibility_off : Icons.visibility,
                                  color: theme.textSecondary,
                                ),
                                tooltip: isKeyVisible ? 'Hide key' : 'Show key',
                                onPressed: () => onKeyVisibilityChanged(!isKeyVisible),
                                padding: const EdgeInsets.all(8),
                                constraints: const BoxConstraints(),
                              ),
                              IconButton(
                                icon: Icon(Icons.copy, color: theme.accent),
                                tooltip: 'Copy key',
                                onPressed: onCopyKey,
                                padding: const EdgeInsets.all(8),
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ),
                        onChanged: (_) => onFieldChanged(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Platform
                DropdownButtonFormField<String>(
                  initialValue: platform,
                  isExpanded: true,
                  style: TextStyle(color: theme.textPrimary),
                  dropdownColor: theme.surface,
                  decoration: const InputDecoration(
                    labelText: 'Platform',
                  ),
                  items: GamePlatform.values.map((p) {
                    return DropdownMenuItem(
                      value: p.displayName,
                      child: Text(p.displayName),
                    );
                  }).toList(),
                  onChanged: isEditing
                      ? (v) {
                          if (v != null) onPlatformChanged(v);
                        }
                      : null,
                ),
                const SizedBox(height: 16),

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
                                final result = await FilePicker.platform.pickFiles(
                                  dialogTitle: 'Pick cover image',
                                  type: FileType.image,
                                  allowMultiple: false,
                                );
                                final selectedPath = result?.files.single.path;
                                if (selectedPath != null && selectedPath.isNotEmpty) {
                                  coverImageController.text = selectedPath;
                                  onFieldChanged();
                                }
                              } catch (e) {
                                NotificationManager.instance.error('Failed to pick image: $e');
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
            child: Column(
              children: [
                // Used toggle
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Key Used',
                        style: TextStyle(color: theme.textPrimary),
                      ),
                    ),
                    AppToggleSwitch(
                      value: isUsed,
                      onChanged: isEditing ? onIsUsedChanged : null,
                      theme: theme,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // DLC toggle
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'DLC',
                        style: TextStyle(color: theme.textPrimary),
                      ),
                    ),
                    AppToggleSwitch(
                      value: isDlc,
                      onChanged: isEditing ? onIsDlcChanged : null,
                      theme: theme,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Deadline toggle + inline date field
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Redemption deadline',
                        style: TextStyle(color: theme.textPrimary),
                      ),
                    ),

                    if (hasDeadline)
                      InkWell(
                        onTap: isEditing
                            ? () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: deadlineDate ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                                  useRootNavigator: false,
                                );
                                onDeadlineDateChanged(date);
                              }
                            : null,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 160),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: theme.inputBackground,
                            borderRadius: BorderRadius.circular(theme.cornerRadius),
                            border: Border.all(color: theme.border),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today, color: theme.textSecondary, size: 18),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  deadlineDate != null
                                      ? DateFormat('dd/MM/yyyy').format(deadlineDate!)
                                      : 'No date set',
                                  style: TextStyle(color: theme.textPrimary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(width: 12),

                    AppToggleSwitch(
                      value: hasDeadline,
                      onChanged: isEditing ? onHasDeadlineChanged : null,
                      theme: theme,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

              ],
            ),
          ),

          // Metadata
          SectionGroupBox(
            title: 'Metadata',
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
                  value: DateFormat('dd/MM/yyyy HH:mm').format(lastUpdatedAt ?? game.updatedAt),
                  theme: theme,
                ),
                _MetadataRow(
                  label: 'SKM-ID',
                  value: game.id.toString(),
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
                if (platform == 'Steam')
                  _MetadataRow(
                    label: 'Reviews',
                    value: (steamReviewCount == null || steamReviewCount == 0)
                        ? 'No reviews'
                        : '${steamReviewScore ?? game.reviewScore}% · ${NumberFormat.compact().format(steamReviewCount)} reviews',
                    theme: theme,
                  ),
                // Steam AppID (only shown for Steam platform)
                if (platform == 'Steam') Padding(
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
                        icon: Icon(Icons.copy, color: theme.textSecondary),
                        tooltip: 'Copy AppID',
                        onPressed: steamAppId.isEmpty
                            ? null
                            : () {
                                Clipboard.setData(ClipboardData(text: steamAppId));
                                NotificationManager.instance.success('Steam AppID copied to clipboard');
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
            child: Text(
              label,
              style: TextStyle(color: theme.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: theme.textPrimary),
            ),
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
    if (oldWidget.tags != widget.tags || oldWidget.selectedTagIds != widget.selectedTagIds) {
      _computeSteamTagsFromProps();
    }
  }

  void _computeSteamTagsFromProps() {
    _steamTagsForGame = widget.tags.where((t) => t.isSteamTag && widget.selectedTagIds.contains(t.id)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final customTags = widget.tags.where((t) => !t.isSteamTag).toList();
    final selectedCustomIds = widget.selectedTagIds.where((id) => customTags.any((t) => t.id == id)).toSet();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Custom Tags (click to add/remove)',
            style: TextStyle(color: theme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: FlowTagSelector(
              tags: customTags,
              selectedTagIds: selectedCustomIds,
              onTagToggled: (tagId) => widget.onTagToggled(tagId),
              theme: theme,
            ),
          ),

          const SizedBox(height: 12),

          Text(
            'Steam Tags (auto-managed)',
            style: TextStyle(color: theme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: _steamTagsForGame.isEmpty
                ? Text('No Steam tags for this game', style: TextStyle(color: theme.textHint))
                : SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _steamTagsForGame.map((t) => TagChip(tag: t, theme: theme, isSelected: true)).toList(),
                    ),
                  ),
          ),
        ],
      ),
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
      child: TextField(
        controller: controller,
        enabled: isEditing,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(color: theme.textPrimary),
        decoration: InputDecoration(
          hintText: 'Add notes about this game...',
          hintStyle: TextStyle(color: theme.textHint),
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: theme.inputBackground,
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}
