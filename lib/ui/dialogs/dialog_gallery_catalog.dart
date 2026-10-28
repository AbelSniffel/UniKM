import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/application/update_controller.dart';
import '../../core/models/device_sync_models.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/database_file_info.dart';
import '../../core/services/device_sync_service.dart';
import '../../core/services/legacy_db_converter.dart';
import '../../core/services/steam_service.dart';
import '../../core/services/update_service.dart';
import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import '../../providers/app_providers.dart';
import '../pages/add_games_page.dart';
import '../pages/settings_sections/database_section.dart';
import '../pages/settings_sections/settings_theme_editor.dart';
import '../widgets/cover_image_card.dart';
import '../widgets/dialog_helpers.dart';
import 'add_tags_dialog.dart';
import 'backup_dialogs.dart';
import 'copy_actions_dialog.dart';
import 'library_stats_dialog.dart';
import 'database_unlock_dialog.dart';
import 'deadline_picker_dialog.dart';
import 'delete_games_dialog.dart';
import 'device_sync_dialog.dart';
import 'encryption_dialogs.dart';
import 'game_editor_dialog.dart';
import 'import_export_dialog.dart';
import 'incoming_pair_dialog.dart';
import 'legacy_conversion_dialog.dart';
import 'steam_lookup_dialog.dart';
import 'update_dialog.dart';

/// Add new dialog families here using their real opener or widget. Closures are
/// recreated after hot reload, including dialogs implemented with inline builders.
class DialogGalleryEntry {
  const DialogGalleryEntry(
    this.id,
    this.label,
    this.open, {
    this.viewport = const Size(680, 820),
    this.cachedSteam = false,
  });

  final String id;
  final String label;
  final FutureOr<Object?> Function(BuildContext context) open;
  final Size viewport;
  final bool cachedSteam;
}

final galleryDate = DateTime(2026, 10, 17, 14, 30);
final galleryTags = [
  Tag(id: 1, name: 'Favorites', colorHex: '#e4ac43'),
  Tag(id: 2, name: 'Puzzle', colorHex: '#507eb5', isSteamTag: true),
  Tag(id: 3, name: 'Co-op', colorHex: '#63a582', isSteamTag: true),
];
final galleryGame = Game(
  id: 1,
  title: 'Portal 2',
  gameKey: 'ABCDE-FGHIJ-KLMNO',
  platform: 'Steam',
  dateAdded: galleryDate,
  notes:
      'A sample game for checking dialog layouts.\nPlay together this weekend.',
  hasDeadline: true,
  deadlineDate: galleryDate.add(const Duration(days: 14)),
  steamAppId: '620',
  developer: 'Valve',
  reviewScore: 98,
  reviewCount: 350000,
  tags: galleryTags,
);
const gallerySteamResult = SteamSearchResult(
  appId: '620',
  name: 'Portal 2',
  developer: 'Valve',
  tags: ['Puzzle', 'Co-op'],
  reviewScore: 98,
  reviewCount: 350000,
  searchSource: SteamSearchSource.community,
  searchSourcesTried: [SteamSearchSource.store, SteamSearchSource.community],
  dataSources: [
    SteamDataSource.steamSpy,
    SteamDataSource.storeDetails,
    SteamDataSource.reviews,
  ],
);
const galleryPeer = DiscoveredSyncPeer(
  id: 'preview-laptop',
  name: 'Living room laptop',
  host: '192.0.2.10',
  port: 45871,
  deviceType: SyncDeviceType.desktop,
);
final galleryBackup = BackupInfo(
  filePath: '/preview/UniKM/backups/library.db',
  fileName: 'library.db',
  createdAt: galleryDate,
  isEncrypted: false,
  sizeBytes: 524288,
  databaseName: 'library.db',
);
const galleryDatabaseFiles = <String, DatabaseFileInfo>{
  '/preview/UniKM/library.db': (
    path: '/preview/UniKM/library.db',
    exists: true,
    isEncrypted: false,
    sizeBytes: 524288,
  ),
  '/preview/UniKM/collection.db': (
    path: '/preview/UniKM/collection.db.enc',
    exists: true,
    isEncrypted: true,
    sizeBytes: 1048576,
  ),
};

AppThemeData _theme(BuildContext context) =>
    ProviderScope.containerOf(context, listen: false).read(themeProvider);
ProviderContainer _container(BuildContext context) =>
    ProviderScope.containerOf(context, listen: false);
Future<Object?> _widget(BuildContext context, WidgetBuilder builder) =>
    showAppDialog<Object>(context: context, builder: builder);

List<DialogGalleryEntry> buildDialogGalleryCatalog() => [
  DialogGalleryEntry('import', 'Import games', showImportDialog),
  DialogGalleryEntry('export', 'Export games', showExportDialog),
  DialogGalleryEntry(
    'game-editor',
    'Game editor',
    (c) => showGameEditorDialog(c, galleryGame),
    viewport: const Size(1180, 900),
  ),
  DialogGalleryEntry(
    'cover-path',
    'Cover image path',
    (c) => _widget(
      c,
      (_) => CoverPathDialog(
        theme: _theme(c),
        initialPath: '/preview/UniKM/images/portal-2.png',
      ),
    ),
  ),
  DialogGalleryEntry(
    'deadline',
    'Deadline picker',
    (c) => showDeadlinePickerDialog(
      context: c,
      theme: _theme(c),
      currentDate: galleryDate,
      initialDate: galleryGame.deadlineDate,
    ),
  ),
  DialogGalleryEntry(
    'add-tags',
    'Add tags',
    (c) => _widget(c, (_) => AddTagsDialog(theme: _theme(c))),
  ),
  DialogGalleryEntry(
    'duplicate-keys',
    'Duplicate keys',
    (c) => showDuplicateKeyDialog(c, _theme(c), [
      MapEntry(galleryGame.gameKey, galleryGame),
      MapEntry('PQRST-UVWXY-Z1234', galleryGame.copyWith(title: 'Half-Life 2')),
    ]),
  ),
  DialogGalleryEntry(
    'unsaved-game',
    'Unsaved game changes',
    (c) => showUnsavedGameChangesDialog(c, _theme(c), galleryGame.title),
  ),
  DialogGalleryEntry(
    'delete-games',
    'Delete games',
    (c) => showDeleteGamesDialog(c, _theme(c), 3),
  ),
  DialogGalleryEntry(
    'copy-actions',
    'Copy options',
    (c) => showCopyActionsDialog(c, [galleryGame]),
  ),
  DialogGalleryEntry(
    'library-stats',
    'Library stats',
    (c) => showLibraryStatsDialog(c, [
      galleryGame,
      galleryGame.copyWith(id: 2, platform: 'GOG', isUsed: true),
    ]),
  ),
  DialogGalleryEntry(
    'steam-lookup',
    'Steam lookup result',
    (c) => _widget(
      c,
      (_) => SteamLookupDialog(
        game: galleryGame,
        initialResult: gallerySteamResult,
      ),
    ),
  ),
  DialogGalleryEntry(
    'steam-options',
    'Steam fetch options',
    (c) => showSteamFetchOptionsDialog(c, title: galleryGame.title),
  ),
  DialogGalleryEntry(
    'steam-cache-choice',
    'Steam cache choice',
    (c) => showSteamFetchOptionsDialog(
      c,
      title: galleryGame.title,
      showApplyOptions: false,
    ),
    cachedSteam: true,
  ),
  DialogGalleryEntry(
    'steam-cache',
    'Steam cached data',
    (c) => showSteamFetchOptionsDialog(c, title: galleryGame.title),
    cachedSteam: true,
  ),
  DialogGalleryEntry(
    'create-database',
    'Create database',
    (c) => showCreateDatabaseChoiceDialog(c, _theme(c)),
  ),
  DialogGalleryEntry(
    'create-database-mobile',
    'Create database • mobile',
    (c) =>
        showCreateDatabaseChoiceDialog(c, _theme(c), forceMobileLayout: true),
  ),
  DialogGalleryEntry(
    'change-database',
    'Change database',
    (c) => showChangeDatabaseDialog(c, _theme(c)),
  ),
  DialogGalleryEntry(
    'unlock-database',
    'Unlock database / backup',
    (c) => DatabaseUnlockDialog.show(c, _theme(c)),
  ),
  DialogGalleryEntry(
    'unlock-startup',
    'Unlock database • startup',
    (c) => DatabaseUnlockDialog.showForStartup(
      c,
      _theme(c),
      currentDatabasePath: '/preview/UniKM/collection.db.enc',
    ),
  ),
  DialogGalleryEntry(
    'enable-encryption',
    'Enable encryption',
    (c) => _widget(c, (_) => EnableEncryptionDialog(theme: _theme(c))),
  ),
  DialogGalleryEntry(
    'create-password',
    'Create password',
    (c) => EnableEncryptionDialog.showForNewDatabase(c, _theme(c)),
  ),
  for (final tab in [0, 1])
    DialogGalleryEntry(
      tab == 0 ? 'disable-encryption' : 'change-password',
      tab == 0 ? 'Encryption • disable' : 'Encryption • change password',
      (c) => _widget(
        c,
        (_) => EncryptionManagementDialog(
          theme: _theme(c),
          initialTab: tab,
          onDisable: (_) async {},
          onChangePassword: (_, _) async {},
        ),
      ),
    ),
  DialogGalleryEntry('backups', 'Backup manager • backups', showBackupDialog),
  DialogGalleryEntry(
    'restore',
    'Backup manager • restore',
    (c) => showBackupDialog(c, initialTab: 1),
  ),
  DialogGalleryEntry(
    'restore-confirm',
    'Restore backup confirmation',
    (c) => showRestoreConfirmDialog(c, _container(c), galleryBackup),
  ),
  DialogGalleryEntry(
    'legacy-conversion',
    'Legacy database conversion',
    (c) => showLegacyConversionDialog(
      c,
      theme: _theme(c),
      dbPath: '/preview/UniKM/legacy.db',
      conversion: const LegacyDbConversionResult(
        converted: true,
        actions: [
          'Adapted games to the current schema',
          'Preserved custom tags and game creation dates',
        ],
      ),
    ),
  ),
  DialogGalleryEntry('device-sync', 'Device sync', showDeviceSyncDialog),
  DialogGalleryEntry(
    'sync-direction',
    'Sync direction',
    (c) => showChooseSyncDirectionDialog(
      context: c,
      theme: _theme(c),
      hasMismatch: false,
      peerName: galleryPeer.name,
      peerId: galleryPeer.id,
    ),
  ),
  DialogGalleryEntry(
    'sync-mismatch',
    'Sync direction • different database',
    (c) => showChooseSyncDirectionDialog(
      context: c,
      theme: _theme(c),
      hasMismatch: true,
      peerName: galleryPeer.name,
      peerId: galleryPeer.id,
    ),
  ),
  DialogGalleryEntry('pair-code', 'Outgoing pairing code', (c) {
    showOutgoingPairCodeDialog(
      context: c,
      theme: _theme(c),
      peerName: galleryPeer.name,
      verificationCode: '123456',
      onCancel: () {},
      pairingResult: Completer<void>().future,
    );
    return null;
  }),
  DialogGalleryEntry(
    'pair-request',
    'Incoming pairing request',
    (c) => _widget(
      c,
      (_) => IncomingPairDialog(
        request: PendingPairRequest(
          requestId: 'preview-request',
          peer: galleryPeer,
          requestedAt: galleryDate,
        ),
      ),
    ),
  ),
  DialogGalleryEntry(
    'create-theme',
    'Create theme',
    (c) => _widget(c, (_) => ThemeEditorDialog(theme: _theme(c))),
    viewport: const Size(780, 950),
  ),
  DialogGalleryEntry(
    'edit-theme',
    'Edit theme',
    (c) => _widget(
      c,
      (_) => ThemeEditorDialog(
        theme: _theme(c),
        existingTheme: _theme(c).copyWith(name: 'Sample theme'),
      ),
    ),
    viewport: const Size(780, 950),
  ),
  DialogGalleryEntry(
    'updates',
    'Updates',
    showUpdateDialog,
    viewport: const Size(780, 950),
  ),
  DialogGalleryEntry(
    'skipped-versions',
    'Skipped versions',
    (c) => _widget(c, (_) => SkippedVersionsDialog(theme: _theme(c))),
  ),
  for (final confirmation in _confirmations)
    DialogGalleryEntry(
      confirmation.id,
      confirmation.title,
      (c) => showConfirmDialog(
        context: c,
        theme: _theme(c),
        title: confirmation.title,
        message: confirmation.message,
        confirmLabel: confirmation.action,
        destructive: confirmation.destructive,
        showCancel: confirmation.id == 'unpair',
        titleIcon:
            const {
              'delete-backup',
              'delete-tag',
              'delete-all-tags',
              'cleanup-tags',
              'unused-tags',
              'delete-theme',
              'replace-data',
              'reset-settings',
              'unpair',
            }.contains(confirmation.id)
            ? confirmation.icon
            : null,
        confirmIcon: confirmation.id == 'unpair' ? Icons.link_off : null,
      ),
    ),
];

// Content variants of the shared confirmation window.
const _confirmations =
    <
      ({
        String id,
        String title,
        String message,
        String action,
        bool destructive,
        IconData? icon,
      })
    >[
      (
        id: 'delete-backup',
        title: 'Delete Backup',
        message: 'Are you sure you want to delete "library.db"?',
        action: 'Delete',
        destructive: true,
        icon: Icons.delete_forever,
      ),
      (
        id: 'delete-tag',
        title: 'Delete Tag',
        message:
            'Delete "Favorites"? This tag will also be removed from games.',
        action: 'Delete',
        destructive: true,
        icon: Icons.delete_forever,
      ),
      (
        id: 'delete-all-tags',
        title: 'Delete All Custom Tags',
        message:
            'Delete all custom tags? They will also be removed from games.',
        action: 'Delete',
        destructive: true,
        icon: Icons.delete_forever,
      ),
      (
        id: 'cleanup-tags',
        title: 'One-time Cleanup',
        message:
            'Remove 4 old default tags (non-Steam)?\n\nThey will also be removed from any games.\nThis button disappears after running once.',
        action: 'Remove',
        destructive: true,
        icon: Icons.delete_forever,
      ),
      (
        id: 'unused-tags',
        title: 'Clear Unused Tags',
        message:
            'Delete Steam and old default tags not used by any game? Other custom tags stay.',
        action: 'Delete',
        destructive: true,
        icon: Icons.delete_forever,
      ),
      (
        id: 'delete-theme',
        title: 'Delete Theme',
        message: 'Delete "Sample theme"? This action cannot be undone.',
        action: 'Delete',
        destructive: true,
        icon: Icons.delete,
      ),
      (
        id: 'replace-data',
        title: 'Replace all data?',
        message:
            'This will delete all existing games, tags, and backups before importing.',
        action: 'Replace',
        destructive: true,
        icon: Icons.warning_amber_rounded,
      ),
      (
        id: 'reset-settings',
        title: 'Reset Settings?',
        message:
            'This will reset all settings, library filters, and sorting to their default values. Your database choice, games, and data will be kept.',
        action: 'Reset',
        destructive: true,
        icon: Icons.warning_amber_rounded,
      ),
      (
        id: 'unpair',
        title: 'Unpair Device',
        message: 'Are you sure you want to unpair "Living room laptop"?',
        action: 'Unpair',
        destructive: true,
        icon: Icons.link_off,
      ),
    ];

/// Standalone containers prevent preview lifecycle code from reaching the app's
/// database, preferences, network discovery, backup files, or update service.
ProviderContainer createDialogGalleryContainer(
  AppThemeData theme, {
  Map<String, dynamic> appearanceSettings = const {},
}) => ProviderContainer(
  overrides: [
    settingsProvider.overrideWith(() => _GallerySettings(appearanceSettings)),
    themeProvider.overrideWith(() => _GalleryTheme(theme)),
    gamesProvider.overrideWith(_GalleryGames.new),
    tagsProvider.overrideWith(_GalleryTags.new),
    deviceSyncProvider.overrideWith(_GallerySync.new),
    deviceSyncServiceProvider.overrideWith(
      (ref) => _GallerySyncService(ref: ref),
    ),
    backupServiceProvider.overrideWith((ref) => _GalleryBackups(ref: ref)),
    updateProvider.overrideWith(_GalleryUpdates.new),
  ],
);

class _GallerySettings extends SettingsNotifier {
  _GallerySettings(this.appearanceSettings);

  final Map<String, dynamic> appearanceSettings;

  @override
  Map<String, dynamic> build() => {
    ...appearanceSettings,
    SettingsKeys.databasePath: galleryDatabaseFiles.keys.first,
    SettingsKeys.recentDatabasePaths: galleryDatabaseFiles.keys.toList(),
    SettingsKeys.skippedVersions: ['v1.3.0', 'v1.2.0'],
  };
  @override
  Future<void> setMany(Map<String, dynamic> updates) async =>
      state = {...state, ...updates};

  @override
  Future<void> resetToDefaults() async => state = build();
}

class _GalleryTheme extends ThemeNotifier {
  _GalleryTheme(this.initialTheme);
  final AppThemeData initialTheme;
  @override
  AppThemeData build() => initialTheme;
}

class _GalleryGames extends GamesNotifier {
  @override
  GamesState build() =>
      GamesState(games: [galleryGame], filteredGames: [galleryGame]);
}

class _GalleryTags extends TagsNotifier {
  @override
  List<Tag> build() => galleryTags;
}

class _GallerySync extends DeviceSyncNotifier {
  @override
  Future<DeviceSyncSnapshot> build() async => DeviceSyncSnapshot(
    enabled: true,
    autoOnStartup: false,
    deviceId: 'preview-desktop',
    status: DeviceSyncStatus.idle,
    trustedPeers: [galleryPeer.toTrustedPeer()],
    discoveredPeers: [galleryPeer],
    pendingPairRequests: const [],
    lastSyncAt: galleryDate,
    lastTrustedPeerId: galleryPeer.id,
  );
  @override
  Future<void> discoverPeers() async {}
}

class _GalleryBackups extends BackupService {
  _GalleryBackups({required super.ref});
  @override
  Future<List<BackupInfo>> listBackups() async => [
    galleryBackup,
    BackupInfo(
      filePath: '/preview/UniKM/backups/collection.db.enc',
      fileName: 'collection.db.enc',
      createdAt: galleryDate.subtract(const Duration(days: 1)),
      isEncrypted: true,
      sizeBytes: 1048576,
      kind: BackupKind.preSync,
      databaseName: 'collection.db',
      peerName: galleryPeer.name,
    ),
  ];
}

class _GalleryUpdates extends UpdateNotifier {
  @override
  UpdateState build() {
    final release = GitHubRelease(
      tagName: 'v9.9.9',
      version: '9.9.9',
      name: 'UniKM 9.9.9',
      body:
          '## Highlights\n\n- Sample release notes for the gallery\n'
          '- Downloads and installs stay in this dialog',
      htmlUrl: 'https://example.invalid/releases/v9.9.9',
      publishedAt: DateTime(2026, 10, 1),
      isPrerelease: false,
      downloadUrl: 'https://example.invalid/unikm-9.9.9.exe',
      downloadSize: 48234496,
    );
    return UpdateState(
      hasChecked: true,
      hasUpdate: true,
      release: release,
      allReleases: [release],
    );
  }

  @override
  int compareVersions(String a, String b) =>
      UpdateService().compareVersions(a, b);
}

class _GallerySyncService extends DeviceSyncService {
  _GallerySyncService({required super.ref});
  @override
  Stream<SyncEvent> get syncEvents => const Stream.empty();
  @override
  Future<void> dispose() async {}
}
