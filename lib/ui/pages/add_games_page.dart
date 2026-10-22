/// Add Games page - add single or batch games
/// Matches the original Python AddGamesPage
library;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../widgets/app_tab_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/platform_patterns.dart';
import '../../core/settings/settings_model.dart';
import '../../core/utils/batch_parser.dart';
import '../../core/utils/duplicate_key_checker.dart';
import '../../core/utils/steam_tag_utils.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../widgets/notification_system.dart';
import '../widgets/section_groupbox.dart';
import '../widgets/platform_menu_button.dart';
import '../widgets/batch_games_editor.dart';
import '../widgets/deadline_chip.dart';
import '../widgets/footer_wrap.dart';
import '../widgets/game_editor_layout.dart';
import '../widgets/cover_image_card.dart';
import '../widgets/game_options_row.dart';
import '../../core/services/steam_service.dart';
import '../dialogs/steam_lookup_dialog.dart';
import '../widgets/dialog_helpers.dart';
import '../../models/game.dart';
import '../controllers/game_editor_fields.dart';
import '../widgets/app_progress_indicator.dart';
import '../../core/constants/app_constants.dart';

/// Action to take when a duplicate key is found
enum DuplicateAction { addAnyway, skip }

/// Shared duplicate-key warning with a compact, scrollable list.
Future<DuplicateAction?> showDuplicateKeyDialog(
  BuildContext context,
  AppThemeData theme,
  List<MapEntry<String, Game>> duplicates,
) => showAppDialog<DuplicateAction>(
  context: context,
  builder: (ctx) => ThemedAlertDialog(
    theme: theme,
    maxWidth: kCompactDialogWidth,
    title: DialogHeader(
      icon: Icons.warning_amber_rounded,
      iconColor: theme.error,
      iconSize: 28,
      title: 'Duplicate Keys Found',
      theme: theme,
    ),
    content: SectionGroupBox(
      title: duplicates.length == 1 ? 'Existing Key' : 'Existing Keys',
      titleIcon: Icons.key,
      titleLocation: SectionTitleLocation.top,
      theme: theme,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: (MediaQuery.sizeOf(ctx).height * 0.45).clamp(100, 320),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: duplicates.length,
          separatorBuilder: (_, _) => Divider(height: 1, color: theme.border),
          itemBuilder: (_, index) {
            final entry = duplicates[index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.value.title,
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      height: 1.15,
                    ),
                  ),
                  Text(
                    entry.key,
                    style: TextStyle(
                      color: theme.textSecondary,
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.pop(ctx, DuplicateAction.addAnyway),
        child: const Text('Add Anyway'),
      ),
      ElevatedButton(
        onPressed: () => Navigator.pop(ctx, DuplicateAction.skip),
        child: const Text('Skip'),
      ),
    ],
  ),
);

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
      animationDuration: kTabTransition,
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
      ref
          .read(addGamesSelectedTabProvider.notifier)
          .setIndex(_tabController.index);
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: AppTabBar(
            theme: theme,
            controller: _tabController,
            tabs: const [AppTab('Single Game'), AppTab('Multiple Games')],
          ),
        ),
        Expanded(
          child: AppTabView(
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

class _SingleEntryTabState extends ConsumerState<_SingleEntryTab> {
  final _formKey = GlobalKey<FormState>();
  final _fields = GameEditorFields();
  final _coverCardKey = GlobalKey();
  final _editorLayoutKey = GlobalKey<GameEditorLayoutState>();

  String _platform = kAutoDetectPlatformValue;
  bool _hasDeadline = false;
  DateTime? _deadlineDate;
  bool _isDlc = false;
  bool _isUsed = false;
  Set<int> _selectedTagIds = {};
  bool _isSubmitting = false;

  // Steam fetch state (tags, image and reviews)
  List<Tag> _fetchedSteamTags = [];
  bool _isFetchingSteamData = false;

  SteamSearchResult? _steamPreview;
  DateTime? _singleSteamCacheAt;

  @override
  void initState() {
    super.initState();
    _loadDraftFromProvider();
  }

  @override
  void dispose() {
    _fields.dispose();
    super.dispose();
  }

  void _loadDraftFromProvider() {
    final draft = ref.read(addGamesSingleEntryDraftProvider);
    _fields.load(
      title: draft.title,
      gameKey: draft.gameKey,
      notes: draft.notes,
      coverImage: draft.coverImage,
    );
    _platform = draft.platform;
    _hasDeadline = draft.hasDeadline;
    _deadlineDate = draft.deadlineDate;
    _isDlc = draft.isDlc;
    _isUsed = draft.isUsed;
    _selectedTagIds = Set<int>.from(draft.selectedTagIds);
    _fetchedSteamTags = List<Tag>.from(draft.fetchedSteamTags);
    _steamPreview = draft.steamPreview;
    _singleSteamCacheAt = draft.singleSteamCacheAt;
  }

  void _saveDraft() {
    ref
        .read(addGamesSingleEntryDraftProvider.notifier)
        .set(
          AddGamesSingleEntryDraft(
            title: _fields.title.text,
            gameKey: _fields.gameKey.text,
            notes: _fields.notes.text,
            coverImage: _fields.coverImage.text,
            platform: _platform,
            hasDeadline: _hasDeadline,
            deadlineDate: _deadlineDate,
            isDlc: _isDlc,
            isUsed: _isUsed,
            selectedTagIds: Set<int>.from(_selectedTagIds),
            fetchedSteamTags: List<Tag>.from(_fetchedSteamTags),
            steamPreview: _steamPreview,
            singleSteamCacheAt: _singleSteamCacheAt,
          ),
        );
  }

  bool get _usesAutoDetectPlatform => _platform == kAutoDetectPlatformValue;

  GamePlatform get _resolvedGamePlatform {
    if (_usesAutoDetectPlatform) {
      return PlatformDetector.detectPlatform(_fields.gameKey.text);
    }

    return GamePlatform.fromDisplayName(_platform);
  }

  String get _resolvedPlatform {
    return _resolvedGamePlatform.displayName;
  }

  bool get _isSteamPlatform => _resolvedGamePlatform == GamePlatform.steam;

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

  Future<void> _submit() async {
    if (ref.read(deviceSyncServiceProvider).isReceiverSyncInFlight) {
      NotificationManager.instance.warning(
        'Cannot add games while device sync is in progress',
      );
      return;
    }
    if (!_formKey.currentState!.validate()) {
      _editorLayoutKey.currentState?.showDetails();
      return;
    }

    final gameKey = _fields.gameKey.text.trim();
    final resolvedPlatform = _resolvedPlatform;

    final database = ref.read(databaseProvider);
    final isSteam = resolvedPlatform == GamePlatform.steam.displayName;

    // Check for duplicate key
    final existingGame = _findExistingGameByKey(gameKey);
    if (existingGame != null) {
      final action = await showDuplicateKeyDialog(context, widget.theme, [
        MapEntry(existingGame.gameKey, existingGame),
      ]);
      if (action != DuplicateAction.addAnyway) return;
    }

    if (!mounted || !identical(ref.read(databaseProvider), database)) return;
    setState(() => _isSubmitting = true);

    try {
      final result = await ref
          .read(gamesProvider.notifier)
          .addGame(
            title: _fields.title.text.trim(),
            gameKey: gameKey,
            platform: resolvedPlatform,
            notes: _fields.notes.text.trim(),
            coverImage: _fields.coverImage.text.trim(),
            steamAppId: isSteam ? (_steamPreview?.appId ?? '') : '',
            reviewScore: isSteam ? (_steamPreview?.reviewScore ?? 0) : 0,
            reviewCount: isSteam ? (_steamPreview?.reviewCount ?? 0) : 0,
            hasDeadline: _hasDeadline,
            deadlineDate: _hasDeadline ? _deadlineDate : null,
            isDlc: _isDlc,
            isUsed: _isUsed,
            tagIds: {
              ..._selectedTagIds,
              if (isSteam) ..._fetchedSteamTags.map((tag) => tag.id),
            }.toList(),
          );

      if (!mounted || !identical(ref.read(databaseProvider), database)) return;
      if (result != null) {
        NotificationManager.instance.success('Game added: ${result.title}');
        _clearForm();
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _clearForm() {
    _editorLayoutKey.currentState?.showDetails();
    _fields.clear();
    setState(() {
      _platform = kAutoDetectPlatformValue;
      _hasDeadline = false;
      _deadlineDate = null;
      _isDlc = false;
      _isUsed = false;
      _selectedTagIds = {};
      _fetchedSteamTags = [];
      _isFetchingSteamData = false;
      _steamPreview = null;
      _singleSteamCacheAt = null;
    });
    ref.read(addGamesSingleEntryDraftProvider.notifier).reset();
  }

  Future<void> _loadSingleEntryCacheAt() async {
    final title = _fields.title.text.trim();
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
      _steamPreview = null;
    });
    _saveDraft();
  }

  void _applySteamPreview({
    required SteamSearchResult result,
    required List<Tag> steamTags,
    String? coverImage,
    DateTime? cacheAt,
  }) {
    setState(() {
      _fetchedSteamTags = steamTags;
      _steamPreview = result;
      _isDlc = result.isDlc;
      if (coverImage != null) _fields.coverImage.text = coverImage;
      if (cacheAt != null) _singleSteamCacheAt = cacheAt;
    });
    _saveDraft();
  }

  /// Fetch full Steam data (tags, image, reviews) for the current title and prepare a preview
  Future<void> _fetchSteamData() async {
    final title = _fields.title.text.trim();
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

      final imagePath = await steamService.downloadImage(
        result.appId,
        imageUrl: result.imageUrl,
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
        result: result,
        steamTags: created,
        coverImage: imagePath,
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
    final theme = widget.theme;
    final customTags = ref.watch(customTagsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: GameEditorLayout(
                key: _editorLayoutKey,
                theme: theme,
                titleController: _fields.title,
                notesController: _fields.notes,
                onNotesChanged: _saveDraft,
                cover: CoverImageCard(
                  key: _coverCardKey,
                  theme: theme,
                  isDlc: _isDlc,
                  isUsed: _isUsed,
                  hasDeadline: _hasDeadline,
                  deadlineDate: _deadlineDate,
                  controller: _fields.coverImage,
                  onChanged: _saveDraft,
                ),
                informationBuilder: (position) => GameEditorInformation(
                  theme: theme,
                  groupPosition: position,
                  platformSelector: PlatformMenuButton(
                    theme: theme,
                    value: _platform,
                    detectedPlatform: _resolvedGamePlatform,
                    tooltip: '$_gameKeyPlatformTooltip. Choose platform',
                    onSelected: (value) {
                      setState(() => _platform = value);
                      _saveDraft();
                    },
                  ),
                  titleController: _fields.title,
                  keyController: _fields.gameKey,
                  titleLabel: 'Title *',
                  keyLabel: 'Game Key *',
                  titleValidator: (value) =>
                      value == null || value.trim().isEmpty
                      ? 'Title is required'
                      : null,
                  keyValidator: (value) => value == null || value.trim().isEmpty
                      ? 'Key is required'
                      : null,
                  onTitleChanged: (_) {
                    _loadSingleEntryCacheAt();
                    _saveDraft();
                  },
                  onKeyChanged: _handleKeyChanged,
                ),
                optionsBuilder: (position) => _buildOptions(theme, position),
                wideDetails: _isSteamPlatform
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 16),
                        child: _buildSteamMetadata(
                          theme,
                          groupPosition: SectionGroupPosition.only,
                        ),
                      )
                    : null,
                detailsBuilder: (information) => SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ?information,
                      _buildOptions(
                        theme,
                        information == null
                            ? (_isSteamPlatform
                                  ? SectionGroupPosition.first
                                  : SectionGroupPosition.only)
                            : (_isSteamPlatform
                                  ? SectionGroupPosition.middle
                                  : SectionGroupPosition.last),
                      ),
                      if (_isSteamPlatform) _buildSteamMetadata(theme),
                    ],
                  ),
                ),
                tags: GameEditorTags(
                  theme: theme,
                  customTags: customTags,
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
                  steamTags: _isSteamPlatform ? _fetchedSteamTags : const [],
                ),
              ),
            ),
          ),
        ),
        Container(
          key: const ValueKey('single-entry-footer'),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: BoxDecoration(
            color: theme.surface,
            border: Border(top: BorderSide(color: theme.border)),
          ),
          child: Wrap(
            alignment: _isSteamPlatform
                ? WrapAlignment.spaceBetween
                : WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: kElementHSpacing,
            runSpacing: kElementVSpacing,
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
                      : const FaIcon(FontAwesomeIcons.steam, size: 18),
                  label: const Text('Fetch'),
                ),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: kElementHSpacing,
                runSpacing: kElementVSpacing,
                children: [
                  TextButton(onPressed: _clearForm, child: const Text('Clear')),
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

  Widget _buildOptions(AppThemeData theme, SectionGroupPosition position) =>
      SectionGroupBox(
        title: 'Options',
        theme: theme,
        titleIcon: Icons.tune,
        groupPosition: position,
        alternateBackground: true,
        child: SingleChildScrollView(
          child: GameOptionsRow(
            theme: theme,
            isDlc: _isDlc,
            onDlcChanged: (value) {
              setState(() => _isDlc = value);
              _saveDraft();
            },
            deadline: DeadlineChip(
              theme: theme,
              hasDeadline: _hasDeadline,
              date: _deadlineDate,
              onEnabledChanged: (value) {
                setState(() => _hasDeadline = value);
                _saveDraft();
              },
              onDateChanged: (value) {
                setState(() => _deadlineDate = value);
                _saveDraft();
              },
            ),
            isUsed: _isUsed,
            onUsedChanged: (value) {
              setState(() => _isUsed = value);
              _saveDraft();
            },
          ),
        ),
      );

  Widget _buildSteamMetadata(
    AppThemeData theme, {
    SectionGroupPosition groupPosition = SectionGroupPosition.last,
  }) => SectionGroupBox(
    title: 'Metadata',
    theme: theme,
    titleIcon: Icons.schedule,
    groupPosition: groupPosition,
    child: Column(
      children: [
        if (_steamPreview != null)
          _steamMetadataRow(theme, 'Steam Title', _steamPreview!.name),
        _steamMetadataRow(
          theme,
          'Steam AppID',
          _steamPreview?.appId ?? 'Not set',
        ),
        _steamMetadataRow(
          theme,
          'Reviews',
          _steamPreview?.reviewScore == null
              ? 'No reviews'
              : '${_steamPreview?.reviewScore}% · ${NumberFormat.compact().format(_steamPreview?.reviewCount ?? 0)} reviews',
        ),
        _steamMetadataRow(
          theme,
          'Cache',
          _singleSteamCacheAt == null
              ? 'No cached data'
              : DateFormat('dd/MM/yyyy HH:mm').format(_singleSteamCacheAt!),
        ),
      ],
    ),
  );

  Widget _steamMetadataRow(AppThemeData theme, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 95,
              child: Text(label, style: TextStyle(color: theme.textSecondary)),
            ),
            Expanded(
              child: Text(value, style: TextStyle(color: theme.textPrimary)),
            ),
          ],
        ),
      );
}

/// Batch add tab
class _BatchAddTab extends ConsumerStatefulWidget {
  const _BatchAddTab({required this.theme});

  final AppThemeData theme;

  @override
  ConsumerState<_BatchAddTab> createState() => _BatchAddTabState();
}

class _BatchAddTabState extends ConsumerState<_BatchAddTab> {
  final _textController = BatchGamesEditingController();
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
    ref
        .read(addGamesBatchDraftProvider.notifier)
        .set(
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
          if (!_parsedGames.any(
            (entry) =>
                entry.key == game.key &&
                entry.platform == GamePlatform.steam.displayName,
          )) {
            continue;
          }
          setState(() {
            _steamResults[game.key] = result;
            if (result == null) {
              _steamErrors[game.key] =
                  'No Steam data found for "${game.title}"';
            }
          });
        } catch (e) {
          if (!mounted) return;
          if (!_parsedGames.any(
            (entry) =>
                entry.key == game.key &&
                entry.platform == GamePlatform.steam.displayName,
          )) {
            continue;
          }
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
    DuplicateAction? action;

    if (duplicates.isNotEmpty) {
      action = await showDuplicateKeyDialog(
        context,
        widget.theme,
        duplicates.entries.toList(),
      );
      if (action == null) {
        return; // User cancelled
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
        if (action == DuplicateAction.skip &&
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
          if (steamResult != null &&
              game.platform == GamePlatform.steam.displayName) {
            String? imagePath;
            try {
              imagePath = await steamService.downloadImage(
                steamResult.appId,
                useLibraryImage: false,
                imageUrl: steamResult.imageUrl,
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
                  titleLocation: SectionTitleLocation.top,
                  headerCrossAxisAlignment: CrossAxisAlignment.center,
                  trailing: PlatformMenuButton(
                    theme: widget.theme,
                    value: _platform,
                    tooltip: _platform == kAutoDetectPlatformValue
                        ? 'Platform Override: Disabled'
                        : 'Platform Override: $_platform',
                    onSelected: (value) {
                      setState(() => _platform = value);
                      _parseInput();
                    },
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BatchGamesEditor(
                        controller: _textController,
                        theme: widget.theme,
                        platformOverride: _platform == kAutoDetectPlatformValue
                            ? null
                            : GamePlatform.fromDisplayName(_platform),
                        onChanged: (_) => _parseInput(),
                      ),
                      if (_steamResults.isNotEmpty || _steamErrors.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Tooltip(
                            message: _steamErrors.values
                                .whereType<String>()
                                .join('\n'),
                            child: Text(
                              'Steam data: ${_steamResults.values.where((result) => result != null).length} loaded'
                              '${_steamErrors.isEmpty ? "" : ", ${_steamErrors.length} failed"}',
                              style: TextStyle(
                                color: widget.theme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SectionGroupBox(
                  title: 'Options',
                  theme: widget.theme,
                  titleIcon: Icons.tune,
                  groupPosition: SectionGroupPosition.last,
                  alternateBackground: true,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DeadlineChip(
                        theme: widget.theme,
                        hasDeadline: _hasDeadline,
                        date: _deadlineDate,
                        firstDate: DateTime.now(),
                        onEnabledChanged: (value) {
                          setState(() => _hasDeadline = value);
                          _saveDraft();
                        },
                        onDateChanged: (value) {
                          setState(() => _deadlineDate = value);
                          _saveDraft();
                        },
                      ),
                    ],
                  ),
                ),
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
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final actions = Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: kElementHSpacing,
                runSpacing: kElementVSpacing,
                children: [
                  if (_parsedGames.isNotEmpty)
                    TextButton(
                      onPressed: _clearBatchInput,
                      child: const Text('Clear'),
                    ),
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
              );
              return FooterWrap(
                leading: _parsedGames.isNotEmpty && _hasSteamGames
                    ? OutlinedButton.icon(
                        onPressed: _isFetchingSteam ? null : _fetchSteamBatch,
                        icon: _isFetchingSteam
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: AppCircularProgressIndicator(),
                              )
                            : const FaIcon(FontAwesomeIcons.steam, size: 18),
                        label: const Text('Fetch'),
                      )
                    : const SizedBox.shrink(),
                trailing: actions,
              );
            },
          ),
        ),
      ],
    );
  }
}
