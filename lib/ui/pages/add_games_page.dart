/// Add Games page - add single or batch games
/// Matches the original Python AddGamesPage
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/platform_patterns.dart';
import '../../core/utils/batch_parser.dart';
import '../../core/utils/duplicate_key_checker.dart';
import '../../core/utils/steam_result_mapper.dart';
import '../../core/utils/steam_tag_utils.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../pages/settings_sections/settings_common.dart';
import '../widgets/app_tag_chip.dart';
import '../widgets/tag_list.dart';
import '../widgets/notification_system.dart';
import '../widgets/section_groupbox.dart';
import '../widgets/platform_icon.dart';
import '../widgets/page_header_title.dart';
import '../widgets/app_date_field.dart';
import '../widgets/game_cover_image.dart';
import '../../core/services/steam_service.dart';
import '../dialogs/deadline_picker_dialog.dart';
import '../dialogs/steam_lookup_dialog.dart';
import '../widgets/dialog_helpers.dart';
import '../../models/game.dart';
import '../widgets/app_progress_indicator.dart';
import '../../core/constants/app_constants.dart';

/// Action to take when a duplicate key is found
enum _DuplicateAction { cancel, addAnyway, overwrite }

/// Add games page
class AddGamesPage extends ConsumerStatefulWidget {
  const AddGamesPage({super.key});

  @override
  ConsumerState<AddGamesPage> createState() => _AddGamesPageState();
}

class _AddGamesPageState extends ConsumerState<AddGamesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: ref.read(addGamesSelectedTabProvider),
    );
    _tabController.addListener(_handleTabChanged);
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) {
      return;
    }

    final selectedTab = ref.read(addGamesSelectedTabProvider);
    if (selectedTab != _tabController.index) {
      ref.read(addGamesSelectedTabProvider.notifier).setIndex(
        _tabController.index,
      );
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          decoration: BoxDecoration(
            color: theme.background,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeaderTitle(
                title: 'Add New Games',
                icon: Icons.add_circle,
                theme: theme,
              ),
              const SizedBox(height: 6),
              TabBar(
                controller: _tabController,
                labelColor: theme.accent,
                unselectedLabelColor: theme.textSecondary,
                indicator: theme.tabIndicator,
                indicatorSize: TabBarIndicatorSize.tab,
                tabs: const [
                  Tab(text: 'Single Entry'),
                  Tab(text: 'Multiple Entries'),
                ],
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _SingleEntryTab(theme: theme),
              _BatchAddTab(theme: theme),
            ],
          ),
        ),
      ],
    );
  }
}

/// Single entry tab
class _SingleEntryTab extends ConsumerStatefulWidget {
  const _SingleEntryTab({required this.theme});

  final AppThemeData theme;

  @override
  ConsumerState<_SingleEntryTab> createState() => _SingleEntryTabState();
}

class _SingleEntryTabState extends ConsumerState<_SingleEntryTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _keyController = TextEditingController();
  final _notesController = TextEditingController();
  final _coverImageController = TextEditingController();

  String _platform = kAutoDetectPlatformValue;
  bool _hasDeadline = false;
  DateTime? _deadlineDate;
  bool _isDlc = false;
  Set<int> _selectedTagIds = {};
  bool _isSubmitting = false;

  // Steam fetch state (tags, image and reviews)
  List<Tag> _fetchedSteamTags = [];
  bool _isFetchingSteamData = false;

  // Fetched preview data
  String? _fetchedSteamTitle;
  String? _fetchedAppId;
  String? _fetchedCoverImagePath;
  int? _fetchedReviewScore;
  int? _fetchedReviewCount;
  DateTime? _singleSteamCacheAt;

  @override
  void initState() {
    super.initState();
    _loadDraftFromProvider();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _keyController.dispose();
    _notesController.dispose();
    _coverImageController.dispose();
    super.dispose();
  }

  void _loadDraftFromProvider() {
    final draft = ref.read(addGamesSingleEntryDraftProvider);
    _titleController.text = draft.title;
    _keyController.text = draft.gameKey;
    _notesController.text = draft.notes;
    _coverImageController.text = draft.coverImage;
    _platform = draft.platform;
    _hasDeadline = draft.hasDeadline;
    _deadlineDate = draft.deadlineDate;
    _isDlc = draft.isDlc;
    _selectedTagIds = Set<int>.from(draft.selectedTagIds);
    _fetchedSteamTags = List<Tag>.from(draft.fetchedSteamTags);
    _fetchedSteamTitle = draft.fetchedSteamTitle;
    _fetchedAppId = draft.fetchedAppId;
    _fetchedCoverImagePath = draft.fetchedCoverImagePath;
    _fetchedReviewScore = draft.fetchedReviewScore;
    _fetchedReviewCount = draft.fetchedReviewCount;
    _singleSteamCacheAt = draft.singleSteamCacheAt;
  }

  void _saveDraft() {
    ref.read(addGamesSingleEntryDraftProvider.notifier).replace(
      AddGamesSingleEntryDraft(
        title: _titleController.text,
        gameKey: _keyController.text,
        notes: _notesController.text,
        coverImage: _coverImageController.text,
        platform: _platform,
        hasDeadline: _hasDeadline,
        deadlineDate: _deadlineDate,
        isDlc: _isDlc,
        selectedTagIds: Set<int>.from(_selectedTagIds),
        fetchedSteamTags: List<Tag>.from(_fetchedSteamTags),
        fetchedSteamTitle: _fetchedSteamTitle,
        fetchedAppId: _fetchedAppId,
        fetchedCoverImagePath: _fetchedCoverImagePath,
        fetchedReviewScore: _fetchedReviewScore,
        fetchedReviewCount: _fetchedReviewCount,
        singleSteamCacheAt: _singleSteamCacheAt,
      ),
    );
  }

  bool get _usesAutoDetectPlatform => _platform == kAutoDetectPlatformValue;

  GamePlatform get _resolvedGamePlatform {
    if (_usesAutoDetectPlatform) {
      return PlatformDetector.detectPlatform(_keyController.text);
    }

    return GamePlatform.fromDisplayName(_platform);
  }

  String get _resolvedPlatform {
    return _resolvedGamePlatform.displayName;
  }

  bool get _isSteamPlatform =>
      _resolvedGamePlatform == GamePlatform.steam;

  bool get _hasFetchedSteamPreview =>
      _fetchedSteamTitle != null ||
      _fetchedAppId != null ||
      _fetchedReviewScore != null ||
      _fetchedReviewCount != null ||
      _fetchedCoverImagePath != null;

  String get _gameKeyPlatformTooltip {
    final prefix = _usesAutoDetectPlatform
        ? 'Detected platform'
        : 'Selected platform';
    return '$prefix: $_resolvedPlatform';
  }

  void _handleKeyChanged(String _) {
    if (_usesAutoDetectPlatform) {
      setState(() {});
    }
    _saveDraft();
  }

  /// Check if any existing game has the given key
  Game? _findExistingGameByKey(String key) {
    final games = ref.read(allGamesProvider);
    return DuplicateKeyChecker.findExistingByKey(key, games);
  }

  /// Show dialog when duplicate key is detected
  Future<_DuplicateAction?> _showDuplicateDialog(Game existing) async {
    final theme = widget.theme;
    return showDialog<_DuplicateAction>(
      context: context,
      builder: (ctx) => ThemedAlertDialog(
        theme: theme,
        maxWidth: 400,
        title: DialogHeader(
          icon: Icons.warning_amber_rounded,
          iconColor: theme.warning,
          iconSize: 28,
          title: 'Duplicate Key Found',
          theme: theme,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A game with this key already exists:',
              style: TextStyle(color: theme.textSecondary),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.background,
                borderRadius: BorderRadius.circular(theme.cornerRadius),
                border: Border.all(color: theme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existing.title,
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    existing.gameKey,
                    style: TextStyle(
                      color: theme.textSecondary,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: kDialogSpacing),
            Text(
              'What would you like to do?',
              style: TextStyle(color: theme.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _DuplicateAction.addAnyway),
            child: Text('Add Anyway', style: TextStyle(color: theme.accent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: theme.accent),
            onPressed: () => Navigator.pop(ctx, _DuplicateAction.overwrite),
            child: Text(
              'Overwrite',
              style: TextStyle(color: theme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (ref.read(deviceSyncServiceProvider).isReceiverSyncInFlight) {
      NotificationManager.instance.warning(
        'Cannot add games while device sync is in progress',
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final gameKey = _keyController.text.trim();
    final resolvedPlatform = _resolvedPlatform;

    // Check for duplicate key
    final existingGame = _findExistingGameByKey(gameKey);
    if (existingGame != null) {
      final action = await _showDuplicateDialog(existingGame);
      if (action == null || action == _DuplicateAction.cancel) {
        return; // User cancelled
      }
      if (action == _DuplicateAction.overwrite) {
        // Delete the existing game first
        await ref.read(gamesProvider.notifier).deleteGame(existingGame.id);
      }
      // For addAnyway, we just continue to add the new game
    }

    setState(() => _isSubmitting = true);

    try {
      final result = await ref
          .read(gamesProvider.notifier)
          .addGame(
            title: _titleController.text.trim(),
            gameKey: gameKey,
            platform: resolvedPlatform,
            notes: _notesController.text.trim(),
            coverImage: _coverImageController.text.trim(),
            hasDeadline: _hasDeadline,
            deadlineDate: _hasDeadline ? _deadlineDate : null,
            isDlc: _isDlc,
            tagIds: _selectedTagIds.toList(),
          );

      if (result != null) {
        var shouldRefreshCreatedGame = false;

        // Attach any fetched Steam tags to the newly created game. Steam tags
        // are managed separately from the custom tag selector.
        if (resolvedPlatform == GamePlatform.steam.displayName &&
            _fetchedSteamTags.isNotEmpty) {
          final db = ref.read(requireDatabaseProvider);
          for (final tag in _fetchedSteamTags) {
            await db.addTagToGame(result.id, tag.id);
          }
          await persistEncryptedDbIfNeeded(ref);
          // Refresh tag state once new Steam tags are attached.
          await ref.read(tagsProvider.notifier).refresh();
          shouldRefreshCreatedGame = true;
        }

        // Persist any fetched steam metadata (AppID, image, reviews)
        if (resolvedPlatform == GamePlatform.steam.displayName &&
            (_fetchedAppId != null ||
                _fetchedCoverImagePath != null ||
                _fetchedReviewScore != null)) {
          final updated = result.copyWith(
            steamAppId: _fetchedAppId ?? result.steamAppId,
            coverImage: _fetchedCoverImagePath ?? result.coverImage,
            reviewScore: _fetchedReviewScore ?? result.reviewScore,
            reviewCount: _fetchedReviewCount ?? result.reviewCount,
            isDlc: _isDlc,
          );
          await ref.read(gamesProvider.notifier).updateGame(updated);
          shouldRefreshCreatedGame = true;
        }

        if (shouldRefreshCreatedGame) {
          await ref.read(gamesProvider.notifier).refreshGame(result.id);
        }

        NotificationManager.instance.success('Game added: ${result.title}');
        _clearForm();
      }
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  void _clearForm() {
    _titleController.clear();
    _keyController.clear();
    _notesController.clear();
    _coverImageController.clear();
    setState(() {
      _platform = kAutoDetectPlatformValue;
      _hasDeadline = false;
      _deadlineDate = null;
      _isDlc = false;
      _selectedTagIds = {};
      _fetchedSteamTags = [];
      _fetchedSteamTitle = null;
      _isFetchingSteamData = false;
      _fetchedAppId = null;
      _fetchedCoverImagePath = null;
      _fetchedReviewScore = null;
      _fetchedReviewCount = null;
      _singleSteamCacheAt = null;
    });
    ref.read(addGamesSingleEntryDraftProvider.notifier).clear();
  }

  Future<void> _loadSingleEntryCacheAt() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    _singleSteamCacheAt = await getCachedAtForTitle(title);
    if (mounted) {
      setState(() {});
      _saveDraft();
    }
  }

  void _resetSteamPreview() {
    setState(() {
      _fetchedSteamTags = [];
      _fetchedSteamTitle = null;
      _fetchedAppId = null;
      _fetchedCoverImagePath = null;
      _fetchedReviewScore = null;
      _fetchedReviewCount = null;
    });
    _saveDraft();
  }

  void _applySteamPreview({
    required String steamTitle,
    required List<Tag> steamTags,
    required SteamPreviewData preview,
    DateTime? cacheAt,
  }) {
    setState(() {
      _fetchedSteamTags = steamTags;
      _fetchedSteamTitle = steamTitle;
      _fetchedAppId = preview.appId;
      _fetchedCoverImagePath = preview.coverImagePath;
      _fetchedReviewScore = preview.reviewScore;
      _fetchedReviewCount = preview.reviewCount;
      _isDlc = preview.isDlc;
      if (_fetchedCoverImagePath != null) {
        _coverImageController.text = _fetchedCoverImagePath!;
      }
      if (cacheAt != null) {
        _singleSteamCacheAt = cacheAt;
      }
    });
    _saveDraft();
  }

  /// Fetch full Steam data (tags, image, reviews) for the current title and prepare a preview
  Future<void> _fetchSteamData() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      NotificationManager.instance.info('Enter a title to fetch Steam data');
      return;
    }

    if (!_isSteamPlatform) {
      NotificationManager.instance.info(
        'Steam data is only available when platform is set to Steam',
      );
      return;
    }

    setState(() => _isFetchingSteamData = true);
    try {
      final steamService = ref.read(steamServiceProvider);
      final db = ref.read(requireDatabaseProvider);

      final resolution = await resolveSteamResultForTitle(
        context,
        title: title,
        steamService: steamService,
      );
      if (!mounted) return;
      if (resolution.cancelled) {
        return;
      }

      final result = resolution.result;
      if (result == null) {
        NotificationManager.instance.info('No Steam data found for "$title"');
        _resetSteamPreview();
        return;
      }

      String? imagePath;
      if (!resolution.usedCache) {
        // Use the wide Steam header image first (better fit for the UI preview).
        // Fallback to library image is handled by SteamService.downloadImage.
        imagePath = await steamService.downloadImage(
          result.appId,
          useLibraryImage: false,
        );
      }
      final preview = SteamResultMapper.toPreviewData(
        result,
        downloadedImagePath: imagePath,
      );

      // Create/get steam tags for preview
      final created = await SteamTagUtils.ensureSteamTags(
        db: db,
        tagNames: result.tags,
      );

      await ref.read(tagsProvider.notifier).refresh();
      await persistEncryptedDbIfNeeded(ref);

      if (!mounted) return;
      _applySteamPreview(
        steamTitle: result.name,
        steamTags: created,
        preview: preview,
        cacheAt: resolution.usedCache ? resolution.cachedAt : null,
      );

      NotificationManager.instance.success(
        resolution.usedCache
            ? 'Loaded cached Steam data for "${result.name}"'
            : 'Fetched Steam data for "${result.name}"',
      );
    } catch (e) {
      NotificationManager.instance.error('Failed to fetch Steam data: $e');
    } finally {
      if (mounted) setState(() => _isFetchingSteamData = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final customTags = ref.watch(customTagsProvider);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Basic info section
                  SectionGroupBox(
                    title: 'Game Information',
                    theme: widget.theme,
                    titleIcon: Icons.videogame_asset,
                    groupPosition: SectionGroupPosition.first,
                    alternateBackground: false,
                    child: Column(
                      children: [
                        // Title
                        TextFormField(
                          controller: _titleController,
                          style: TextStyle(color: widget.theme.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'Game Title *',
                            hintText: 'Enter game title',
                          ),
                          onChanged: (_) {
                            _loadSingleEntryCacheAt();
                            _saveDraft();
                          },
                          validator: (value) => value?.isEmpty == true
                              ? 'Title is required'
                              : null,
                        ),
                        const SizedBox(height: 16),

                        // Key
                        TextFormField(
                          controller: _keyController,
                          style: TextStyle(color: widget.theme.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Game Key *',
                            hintText: 'Enter activation key',
                            suffixIcon: Tooltip(
                              message: _gameKeyPlatformTooltip,
                              child: IgnorePointer(
                                child: SizedBox(
                                  width: 42,
                                  child: Center(
                                    child: PlatformIcon(
                                      platform: _resolvedGamePlatform,
                                      color: widget.theme.accent,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          onChanged: _handleKeyChanged,
                          validator: (value) =>
                              value?.isEmpty == true ? 'Key is required' : null,
                        ),
                        const SizedBox(height: 16),

                        // Platform
                        DropdownButtonFormField<String>(
                          key: ValueKey(_platform),
                          initialValue: _platform,
                          isExpanded: true,
                          menuMaxHeight: 320,
                          borderRadius: BorderRadius.circular(
                            widget.theme.cornerRadius,
                          ),
                          style: TextStyle(color: widget.theme.textPrimary),
                          dropdownColor: widget.theme.surface,
                          decoration: const InputDecoration(
                            labelText: 'Platform',
                          ),
                          items: [
                            DropdownMenuItem(
                              value: kAutoDetectPlatformValue,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.auto_fix_high,
                                    color: widget.theme.textPrimary,
                                    size: 18,
                                  ),
                                  const SizedBox(width: kElementHSpacing),
                                  const Text('Auto-detect'),
                                ],
                              ),
                            ),
                            ...GamePlatform.values.map((p) {
                              return DropdownMenuItem(
                                value: p.displayName,
                                child: Row(
                                  children: [
                                    PlatformIcon(
                                      platform: p,
                                      color: widget.theme.textPrimary,
                                      size: 18,
                                    ),
                                    const SizedBox(width: kElementHSpacing),
                                    Text(p.displayName),
                                  ],
                                ),
                              );
                            }),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _platform = value);
                              _saveDraft();
                            }
                          },
                        ),
                        const SizedBox(height: 16),

                        // Cover image URL
                        TextFormField(
                          controller: _coverImageController,
                          style: TextStyle(color: widget.theme.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Cover Image URL',
                            hintText: 'https://...',
                            suffixIcon: IconButton(
                              icon: Icon(
                                Icons.image,
                                color: widget.theme.textHint,
                              ),
                              tooltip: 'Pick image',
                              onPressed: () async {
                                try {
                                    final result = await FilePicker
                                      .pickFiles(
                                        dialogTitle: 'Pick cover image',
                                        type: FileType.image,
                                        allowMultiple: false,
                                      );
                                  final selectedPath =
                                      result?.files.single.path;
                                  if (selectedPath != null &&
                                      selectedPath.isNotEmpty) {
                                    setState(() {
                                      _coverImageController.text = selectedPath;
                                    });
                                    _saveDraft();
                                  }
                                } catch (e) {
                                  NotificationManager.instance.error(
                                    'Failed to pick image: $e',
                                  );
                                }
                              },
                            ),
                          ),
                          onChanged: (_) => _saveDraft(),
                        ),
                      ],
                    ),
                  ),

                  // Options section
                  SectionGroupBox(
                    title: 'Options',
                    theme: widget.theme,
                    titleIcon: Icons.settings,
                    groupPosition: SectionGroupPosition.middle,
                    alternateBackground: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            AppOptionChip(
                              theme: widget.theme,
                              label: 'DLC',
                              isSelected: _isDlc,
                              onTap: () {
                                setState(() => _isDlc = !_isDlc);
                                _saveDraft();
                              },
                            ),
                            AppOptionChip(
                              theme: widget.theme,
                              label: 'Deadline',
                              isSelected: _hasDeadline,
                              onTap: () {
                                setState(() => _hasDeadline = !_hasDeadline);
                                _saveDraft();
                              },
                            ),
                            if (_hasDeadline)
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: kDeadlineSelectorWidth,
                                ),
                                child: AppDateField(
                                  theme: widget.theme,
                                  date: _deadlineDate,
                                  placeholder: 'Select date',
                                  onTap: () async {
                                    final date =
                                        await showDeadlinePickerDialog(
                                      context: context,
                                      theme: widget.theme,
                                      initialDate:
                                          _deadlineDate ?? DateTime.now(),
                                      firstDate: DateTime.now(),
                                    );
                                    if (date != null) {
                                      setState(() => _deadlineDate = date);
                                      _saveDraft();
                                    }
                                  },
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Tags section (custom tags only)
                  SectionGroupBox(
                    title: 'Custom Tags',
                    theme: widget.theme,
                    titleIcon: Icons.label,
                    groupPosition: SectionGroupPosition.middle,
                    alternateBackground: false,
                    child: customTags.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'No custom tags created yet',
                              style: TextStyle(color: widget.theme.textHint),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : SizedBox(
                            height: 200,
                            child: TagList(
                              tags: customTags,
                              theme: widget.theme,
                              selectedTagIds: _selectedTagIds,
                              onTagToggled: (tagId) {
                                setState(() {
                                  if (_selectedTagIds.contains(tagId)) {
                                    _selectedTagIds.remove(tagId);
                                  } else {
                                    _selectedTagIds.add(tagId);
                                  }
                                });
                                _saveDraft();
                              },
                              showSearch: true,
                            ),
                          ),
                  ),

                  if (_isSteamPlatform)
                    SectionGroupBox(
                      title: 'Fetched Steam Data',
                      description: 'Image, reviews and tags',
                      theme: widget.theme,
                      titleIcon: Icons.cloud,
                      groupPosition: SectionGroupPosition.middle,
                      alternateBackground: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_hasFetchedSteamPreview)
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    widget.theme.cornerRadius,
                                  ),
                                  child: SizedBox(
                                    width: 120,
                                    height: 56,
                                    child: GameCoverImage(
                                      theme: widget.theme,
                                      coverImage: _fetchedCoverImagePath,
                                      placeholderIcon: Icons.gamepad,
                                      onError: () {
                                        if (!mounted ||
                                            _fetchedCoverImagePath == null) {
                                          return;
                                        }
                                        setState(
                                          () => _fetchedCoverImagePath = null,
                                        );
                                        _saveDraft();
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (_fetchedSteamTitle != null)
                                        Text(
                                          _fetchedSteamTitle!,
                                          style: TextStyle(
                                            color: widget.theme.textPrimary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      if (_fetchedReviewScore != null)
                                        Text(
                                          'Reviews: $_fetchedReviewScore% · ${_fetchedReviewCount ?? 0} reviews',
                                          style: TextStyle(
                                            color: widget.theme.textPrimary,
                                          ),
                                        ),
                                      if (_fetchedAppId != null) ...[
                                        Text(
                                          'AppID: ${_fetchedAppId!}',
                                          style: TextStyle(
                                            color: widget.theme.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                        if (_singleSteamCacheAt != null)
                                          Text(
                                            'Cached: ${DateFormat('dd/MM/yyyy HH:mm').format(_singleSteamCacheAt!)}',
                                            style: TextStyle(
                                              color:
                                                  widget.theme.textSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          if (_fetchedSteamTags.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'Fetched Steam data will appear here',
                                style: TextStyle(color: widget.theme.textHint),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          if (_fetchedSteamTags.isNotEmpty)
                            const SizedBox(height: 12),
                          TagList(
                            tags: _fetchedSteamTags,
                            theme: widget.theme,
                            allSelected: true,
                          ),
                        ],
                      ),
                    ),

                  // Notes section
                  SectionGroupBox(
                    title: 'Notes',
                    theme: widget.theme,
                    titleIcon: Icons.notes,
                    groupPosition: SectionGroupPosition.last,
                    alternateBackground: !_isSteamPlatform,
                    child: TextFormField(
                      controller: _notesController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Add any notes about this game...',
                        border: widget.theme.resolveInputBorder(showTopBorder: true),
                        constraints: const BoxConstraints(minHeight: 0),
                      ),
                      onChanged: (_) => _saveDraft(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Pinned Submit buttons at bottom
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: BoxDecoration(
            color: widget.theme.surface,
            border: Border(top: BorderSide(color: widget.theme.border)),
          ),
          child: Row(
            mainAxisAlignment: _isSteamPlatform
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.end,
            children: [
              if (_isSteamPlatform)
                OutlinedButton.icon(
                  onPressed: _isFetchingSteamData ? null : _fetchSteamData,
                  icon: _isFetchingSteamData
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: AppCircularProgressIndicator(),
                        )
                      : const Icon(Icons.cloud_download),
                  label: const Text('Fetch Steam Data'),
                ),
              Row(
                children: [
                  TextButton(
                    onPressed: _clearForm,
                    child: const Text('Clear'),
                  ),
                  const SizedBox(width: kElementHSpacing),
                  ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: AppCircularProgressIndicator(),
                          )
                        : const Icon(Icons.save),
                    label: const Text('Save Game'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Batch add tab
class _BatchAddTab extends ConsumerStatefulWidget {
  const _BatchAddTab({required this.theme});

  final AppThemeData theme;

  @override
  ConsumerState<_BatchAddTab> createState() => _BatchAddTabState();
}

class _BatchAddTabState extends ConsumerState<_BatchAddTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _textController = TextEditingController();
  String _platform = kAutoDetectPlatformValue;
  bool _hasDeadline = false;
  DateTime? _deadlineDate;
  List<ParsedBatchEntry> _parsedGames = [];
  bool _isImporting = false;

  // Steam fetch state for batch entries
  Map<String, SteamSearchResult?> _steamResults = {};
  Map<String, String?> _steamErrors = {};
  bool _isFetchingSteam = false;

  @override
  void initState() {
    super.initState();
    _loadDraftFromProvider();
  }

  bool get _hasSteamGames =>
      _parsedGames.any((g) => g.platform == GamePlatform.steam.displayName);

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _loadDraftFromProvider() {
    final draft = ref.read(addGamesBatchDraftProvider);
    _textController.text = draft.text;
    _platform = draft.platform;
    _hasDeadline = draft.hasDeadline;
    _deadlineDate = draft.deadlineDate;
    _parsedGames = List<ParsedBatchEntry>.from(draft.parsedGames);
    _steamResults = Map<String, SteamSearchResult?>.from(draft.steamResults);
    _steamErrors = Map<String, String?>.from(draft.steamErrors);
  }

  void _saveDraft() {
    ref.read(addGamesBatchDraftProvider.notifier).replace(
      AddGamesBatchDraft(
        text: _textController.text,
        platform: _platform,
        hasDeadline: _hasDeadline,
        deadlineDate: _deadlineDate,
        parsedGames: List<ParsedBatchEntry>.from(_parsedGames),
        steamResults: Map<String, SteamSearchResult?>.from(_steamResults),
        steamErrors: Map<String, String?>.from(_steamErrors),
      ),
    );
  }

  void _clearBatchInput() {
    _textController.clear();
    setState(() {
      _parsedGames = [];
      _steamResults = {};
      _steamErrors = {};
      _hasDeadline = false;
      _deadlineDate = null;
    });
    _saveDraft();
  }

  void _parseInput() {
    final parsed = parseBatchText(
      _textController.text,
      defaultPlatform: _platform == kAutoDetectPlatformValue
          ? GamePlatform.other.displayName
          : _platform,
    );
    // When a specific platform is selected, override auto-detected platforms
    final games = _platform == kAutoDetectPlatformValue
        ? parsed
        : parsed
              .map(
                (g) => ParsedBatchEntry(
                  title: g.title,
                  key: g.key,
                  platform: _platform,
                ),
              )
              .toList();
    setState(() {
      _parsedGames = games;
      _steamResults = {};
      _steamErrors = {};
    });
    _saveDraft();
  }

  /// Fetch Steam data for all Steam-platform games in the parsed list
  Future<void> _fetchSteamBatch() async {
    if (_isFetchingSteam) return;
    setState(() => _isFetchingSteam = true);
    try {
      final steamService = ref.read(steamServiceProvider);
      for (final game in List<ParsedBatchEntry>.from(_parsedGames)) {
        if (game.platform != GamePlatform.steam.displayName) continue;
        try {
          final result = await steamService.searchGame(game.title);
          if (!mounted) return;
          setState(() {
            _steamResults[game.key] = result;
            if (result == null) {
              _steamErrors[game.key] =
                  'No Steam data found for "${game.title}"';
            }
          });
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _steamResults[game.key] = null;
            _steamErrors[game.key] = e.toString();
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingSteam = false);
        _saveDraft();
      }
    }
  }

  /// Find all duplicate keys in the batch
  Map<String, Game> _findDuplicateKeys(List<ParsedBatchEntry> games) {
    final existingGames = ref.read(allGamesProvider);
    return DuplicateKeyChecker.findDuplicatesByInputKeys(
      games.map((g) => g.key),
      existingGames,
    );
  }

  /// Show dialog when duplicate keys are detected in batch
  Future<_DuplicateAction?> _showBatchDuplicateDialog(
    Map<String, Game> duplicates,
  ) async {
    final theme = widget.theme;
    return showDialog<_DuplicateAction>(
      context: context,
      builder: (ctx) => ThemedAlertDialog(
        theme: theme,
        title: DialogHeader(
          icon: Icons.warning_amber_rounded,
          iconColor: theme.warning,
          iconSize: 28,
          title: 'Duplicate Keys Found',
          theme: theme,
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${duplicates.length} game(s) with matching keys already exist:',
                style: TextStyle(color: theme.textSecondary),
              ),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: duplicates.length,
                  itemBuilder: (context, index) {
                    final entry = duplicates.entries.elementAt(index);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.background,
                        borderRadius: BorderRadius.circular(theme.cornerRadius),
                        border: Border.all(color: theme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.value.title,
                            style: TextStyle(
                              color: theme.textPrimary,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            entry.key,
                            style: TextStyle(
                              color: theme.textHint,
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: kDialogSpacing),
              Text(
                'What would you like to do with duplicates?',
                style: TextStyle(color: theme.textSecondary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _DuplicateAction.addAnyway),
            child: Text(
              'Skip Duplicates',
              style: TextStyle(color: theme.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: theme.accent),
            onPressed: () => Navigator.pop(ctx, _DuplicateAction.overwrite),
            child: Text(
              'Overwrite All',
              style: TextStyle(color: theme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    if (ref.read(deviceSyncServiceProvider).isReceiverSyncInFlight) {
      NotificationManager.instance.warning(
        'Cannot add games while device sync is in progress',
      );
      return;
    }
    if (_parsedGames.isEmpty) return;

    // Check for duplicates
    final duplicates = _findDuplicateKeys(_parsedGames);
    _DuplicateAction? action;

    if (duplicates.isNotEmpty) {
      action = await _showBatchDuplicateDialog(duplicates);
      if (action == null || action == _DuplicateAction.cancel) {
        return; // User cancelled
      }

      if (action == _DuplicateAction.overwrite) {
        // Delete all existing duplicates first
        for (final existing in duplicates.values) {
          await ref.read(gamesProvider.notifier).deleteGame(existing.id);
        }
      }
    }

    setState(() => _isImporting = true);

    try {
      int imported = 0;
      int skipped = 0;
      final steamService = ref.read(steamServiceProvider);
      final db = ref.read(requireDatabaseProvider);

      for (final game in _parsedGames) {
        // Skip duplicates if user chose to skip
        if (action == _DuplicateAction.addAnyway &&
            duplicates.containsKey(game.key)) {
          skipped++;
          continue;
        }

        final result = await ref
            .read(gamesProvider.notifier)
            .addGame(
              title: game.title,
              gameKey: game.key,
              platform: game.platform,
              hasDeadline: _hasDeadline,
              deadlineDate: _hasDeadline ? _deadlineDate : null,
            );
        if (result != null) {
          imported++;

          // Apply fetched Steam data if available
          final steamResult = _steamResults[game.key];
          if (steamResult != null) {
            String? imagePath;
            try {
              imagePath = await steamService.downloadImage(
                steamResult.appId,
                useLibraryImage: false,
              );
            } catch (_) {}

            final createdTags = await SteamTagUtils.ensureSteamTags(
              db: db,
              tagNames: steamResult.tags,
            );
            for (final tag in createdTags) {
              await db.addTagToGame(result.id, tag.id);
            }

            final updated = result.copyWith(
              steamAppId: steamResult.appId,
              coverImage: imagePath ?? result.coverImage,
              reviewScore: steamResult.reviewScore ?? result.reviewScore,
              reviewCount: steamResult.reviewCount ?? result.reviewCount,
              isDlc: steamResult.isDlc,
            );
            await ref.read(gamesProvider.notifier).updateGame(updated);
          }
        }
      }

      if (_steamResults.isNotEmpty) {
        await ref.read(tagsProvider.notifier).refresh();
        await persistEncryptedDbIfNeeded(ref);
      }

      if (skipped > 0) {
        NotificationManager.instance.success(
          'Imported $imported games ($skipped skipped)',
        );
      } else {
        NotificationManager.instance.success('Imported $imported games');
      }
      _clearBatchInput();
    } finally {
      setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Paste input
                SectionGroupBox(
                  title: 'Paste Games',
                  theme: widget.theme,
                  titleIcon: Icons.content_paste,
                  groupPosition: SectionGroupPosition.first,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _textController,
                        maxLines: 10,
                        onChanged: (_) => _parseInput(),
                        decoration: InputDecoration(
                          constraints: const BoxConstraints(minHeight: 0),
                          hintText:
                              'Game Title | XXXXX-XXXXX-XXXXX\nAnother Game | YYYYY-YYYYY-YYYYY\nOr just paste keys on their own',
                          hintStyle: TextStyle(color: widget.theme.textHint),
                          border: widget.theme.resolveInputBorder(
                            showTopBorder: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey(_platform),
                        initialValue: _platform,
                        isExpanded: true,
                        menuMaxHeight: 320,
                        borderRadius: BorderRadius.circular(
                          widget.theme.cornerRadius,
                        ),
                        style: TextStyle(color: widget.theme.textPrimary),
                        dropdownColor: widget.theme.surface,
                        decoration: const InputDecoration(
                          labelText: 'Platform',
                        ),
                        items: [
                          DropdownMenuItem(
                            value: kAutoDetectPlatformValue,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.auto_fix_high,
                                  color: widget.theme.textPrimary,
                                  size: 16,
                                ),
                                const SizedBox(width: kElementHSpacing),
                                const Text('Auto-detect'),
                              ],
                            ),
                          ),
                          ...GamePlatform.values.map((p) {
                            return DropdownMenuItem(
                              value: p.displayName,
                              child: Row(
                                children: [
                                  PlatformIcon(
                                    platform: p,
                                    color: widget.theme.textPrimary,
                                    size: 16,
                                  ),
                                  const SizedBox(width: kElementHSpacing),
                                  Text(p.displayName),
                                ],
                              ),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _platform = value);
                            _parseInput();
                          }
                        },
                      ),
                    ],
                  ),
                ),
                SectionGroupBox(
                  title: '',
                  showTitle: false,
                  theme: widget.theme,
                  groupPosition: _parsedGames.isNotEmpty
                      ? SectionGroupPosition.middle
                      : SectionGroupPosition.last,
                  alternateBackground: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ToggleSettingRow(
                        theme: widget.theme,
                        label: 'Deadline',
                        value: _hasDeadline,
                        onChanged: (value) {
                          setState(() => _hasDeadline = value);
                          _saveDraft();
                        },
                        trailing: _hasDeadline
                            ? AppDateField(
                                theme: widget.theme,
                                date: _deadlineDate,
                                maxWidth: kDeadlineSelectorWidth,
                                placeholder: 'Select date',
                                onTap: () async {
                                  final date = await showDeadlinePickerDialog(
                                    context: context,
                                    theme: widget.theme,
                                    initialDate:
                                        _deadlineDate ?? DateTime.now(),
                                    firstDate: DateTime.now(),
                                  );
                                  if (date != null) {
                                    setState(() => _deadlineDate = date);
                                    _saveDraft();
                                  }
                                },
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
                if (_parsedGames.isNotEmpty) ...[
                  SectionGroupBox(
                    title: 'Preview (${_parsedGames.length} games)',
                    theme: widget.theme,
                    titleIcon: Icons.preview,
                    groupPosition: SectionGroupPosition.last,
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _parsedGames.length,
                        itemBuilder: (context, index) {
                          final game = _parsedGames[index];
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.videogame_asset,
                              color: widget.theme.accent,
                            ),
                            title: Text(
                              game.title,
                              style: TextStyle(color: widget.theme.textPrimary),
                            ),
                            subtitle: Text(
                              '${game.platform} • ${game.key}',
                              style: TextStyle(
                                color: widget.theme.textSecondary,
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_steamResults.containsKey(game.key) ||
                                    _steamErrors.containsKey(game.key)) ...[
                                  if (_steamResults[game.key] != null)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 4),
                                      child: Icon(
                                        Icons.check_circle,
                                        color: widget.theme.accent,
                                        size: 18,
                                      ),
                                    )
                                  else
                                    Padding(
                                      padding: const EdgeInsets.only(right: 4),
                                      child: Tooltip(
                                        message:
                                            _steamErrors[game.key] ??
                                            'Fetch failed',
                                        child: const Icon(
                                          Icons.error,
                                          color: Colors.red,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                ],
                                IconButton(
                                  icon: Icon(
                                    Icons.close,
                                    color: widget.theme.textHint,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _parsedGames.removeAt(index);
                                      _steamResults.remove(game.key);
                                      _steamErrors.remove(game.key);
                                    });
                                    _saveDraft();
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        // Pinned Import buttons at bottom
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.theme.surface,
            border: Border(top: BorderSide(color: widget.theme.border)),
          ),
          child: Row(
            mainAxisAlignment: (_parsedGames.isNotEmpty && _hasSteamGames)
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.end,
            children: [
              if (_parsedGames.isNotEmpty && _hasSteamGames)
                OutlinedButton.icon(
                  onPressed: _isFetchingSteam ? null : _fetchSteamBatch,
                  icon: _isFetchingSteam
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: AppCircularProgressIndicator(),
                        )
                      : const Icon(Icons.cloud_download),
                  label: const Text('Fetch Steam Data'),
                ),
              Row(
                children: [
                  if (_parsedGames.isNotEmpty) ...[
                    TextButton(
                      onPressed: _clearBatchInput,
                      child: const Text('Clear'),
                    ),
                    const SizedBox(width: kElementHSpacing),
                  ],
                  ElevatedButton.icon(
                    onPressed: _parsedGames.isEmpty || _isImporting
                        ? null
                        : _import,
                    icon: _isImporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: AppCircularProgressIndicator(),
                          )
                        : const Icon(Icons.save),
                    label: Text('Save ${_parsedGames.length} Games'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
