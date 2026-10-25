/// Update page - check for and install app updates
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../widgets/app_combo_box.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/format_utils.dart';
import '../../core/services/update_service.dart';
import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/surface_depth.dart';
import '../../providers/app_providers.dart';
import '../widgets/notification_system.dart';
import '../widgets/app_progress_indicator.dart';
import '../widgets/update_status_icons.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/section_groupbox.dart';
import '../widgets/footer_wrap.dart';
import '../widgets/navigation_panel.dart' show isVeryNarrowAppLayout;

/// Update state
class UpdateState {
  const UpdateState({
    this.isChecking = false,
    this.hasChecked = false,
    this.isDownloading = false,
    this.hasUpdate = false,
    this.release,
    this.downloadProgress = 0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.error,
    this.downloadedFilePath,
    this.allReleases = const [],
    this.switchingToVersion,
  });

  final bool isChecking;
  final bool hasChecked;
  final bool isDownloading;
  final bool hasUpdate;
  final GitHubRelease? release;
  final double downloadProgress;
  final int downloadedBytes;
  final int totalBytes;
  final String? error;
  final String? downloadedFilePath;

  /// All available releases (for changelog / version switcher).
  final List<GitHubRelease> allReleases;

  /// Version being installed via the version switcher (null = none in progress).
  final String? switchingToVersion;

  String? get latestVersion => release?.version;
  String? get downloadUrl => release?.downloadUrl;
  String? get downloadSize => release?.formattedSize;
  bool get isPrerelease => release?.isPrerelease ?? false;

  UpdateState copyWith({
    bool? isChecking,
    bool? hasChecked,
    bool? isDownloading,
    bool? hasUpdate,
    Object? release = _unset,
    double? downloadProgress,
    int? downloadedBytes,
    int? totalBytes,
    String? error,
    Object? downloadedFilePath = _unset,
    List<GitHubRelease>? allReleases,
    Object? switchingToVersion = _unset,
  }) {
    return UpdateState(
      isChecking: isChecking ?? this.isChecking,
      hasChecked: hasChecked ?? this.hasChecked,
      isDownloading: isDownloading ?? this.isDownloading,
      hasUpdate: hasUpdate ?? this.hasUpdate,
      release: release == _unset ? this.release : release as GitHubRelease?,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      error: error,
      downloadedFilePath: downloadedFilePath == _unset
          ? this.downloadedFilePath
          : downloadedFilePath as String?,
      allReleases: allReleases ?? this.allReleases,
      switchingToVersion: switchingToVersion == _unset
          ? this.switchingToVersion
          : switchingToVersion as String?,
    );
  }
}

// Sentinel used inside UpdateState.copyWith for nullable fields that need a
// "no change" value distinct from an explicit null.
const Object _unset = Object();

enum UpdatePreviewState {
  idle,
  checking,
  upToDate,
  updateAvailable,
  downloading,
  downloaded,
  error,
}

String _formatMegabytes(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

String _downloadNotificationMessage({
  required int downloadedBytes,
  required int totalBytes,
}) {
  if (totalBytes > 0) {
    return 'Downloaded ${_formatMegabytes(downloadedBytes)} / ${_formatMegabytes(totalBytes)}';
  }
  return 'Downloaded ${_formatMegabytes(downloadedBytes)}';
}

bool canRunAutomaticUpdateCheck(UpdateState state) {
  return !state.isChecking &&
      !state.isDownloading &&
      state.downloadedFilePath == null;
}

bool canShowUpdateAvailableNotification(UpdateState state) {
  return !state.isDownloading && state.downloadedFilePath == null;
}

/// Update notifier using real GitHub API
class UpdateNotifier extends Notifier<UpdateState> {
  late UpdateService _updateService;
  GitHubRelease? _currentRelease;
  NotificationHandle? _updateNotificationHandle;
  NotificationHandle? _downloadNotificationHandle;

  static final GitHubRelease _devPreviewRelease = GitHubRelease(
    tagName: 'v9.9.9',
    version: '9.9.9',
    name: 'UniKM 9.9.9',
    body:
        '## Preview build\n\nThis is a dev-only preview release used to style the update UI.',
    htmlUrl: 'https://github.com/example/unikm/releases/tag/v9.9.9',
    publishedAt: DateTime(2026, 3, 6),
    isPrerelease: false,
    downloadUrl: 'https://example.invalid/unikm-preview-installer.exe',
    downloadSize: 48234496,
  );

  @override
  UpdateState build() {
    // Use ref.read so that writing to settings (e.g. skippedVersions) does not
    // retrigger build() and reset all accumulated state back to UpdateState().
    _updateService = _serviceFor(ref.read(updatesSettingsProvider));

    // Load cached releases immediately so the changelog shows without a network hit.
    Future.microtask(_loadCachedReleases);

    // React to navigation to manage off-page notifications.
    ref.listen(currentNavProvider, (prev, next) {
      if (next == NavItem.updates) {
        // User arrived on the updates page — dismiss off-page notifications.
        _clearOffPageNotifications();
      } else if (prev == NavItem.updates) {
        // User navigated away from the updates page.
        if (state.isDownloading) {
          _showOrUpdateDownloadNotification(
            downloadedBytes: state.downloadedBytes,
            totalBytes: state.totalBytes,
            progress: state.downloadProgress,
          );
        } else if (state.downloadedFilePath != null) {
          _showDownloadReadyNotification();
        }
      }
    });

    return const UpdateState();
  }

  static UpdateService _serviceFor(UpdatesSettings settings) => UpdateService(
    customRepo: settings.updateRepo.isNotEmpty ? settings.updateRepo : null,
    githubToken: settings.githubApiToken.isNotEmpty
        ? settings.githubApiToken
        : null,
  );

  /// Dismisses the off-page notifications and clears the Updates badge.
  void _clearOffPageNotifications({bool update = true, bool download = true}) {
    if (update) {
      _updateNotificationHandle?.dismiss();
      _updateNotificationHandle = null;
    }
    if (download) {
      _downloadNotificationHandle?.dismiss();
      _downloadNotificationHandle = null;
    }
    ref.read(pageNotificationsProvider.notifier).remove(NavItem.updates);
  }

  Future<void> _loadCachedReleases() async {
    final cached = await _updateService.loadCachedReleases();
    if (cached.isNotEmpty) {
      state = state.copyWith(allReleases: cached);
    }
  }

  NotificationHandle _showOrUpdateDownloadNotification({
    required int downloadedBytes,
    required int totalBytes,
    required double progress,
  }) {
    final message = _downloadNotificationMessage(
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
    );
    final handle = _downloadNotificationHandle;

    if (handle == null) {
      _downloadNotificationHandle = NotificationManager.instance.showHandle(
        message: message,
        type: NotificationType.download,
        title: 'Update Download',
        progress: progress,
        actionLabel: 'Cancel',
        onAction: cancelDownload,
        persistent: true,
        dedupe: false,
      );
    } else {
      handle.update(
        message: message,
        type: NotificationType.download,
        title: 'Update Download',
        progress: progress,
        actionLabel: 'Cancel',
        onAction: cancelDownload,
      );
    }

    ref.read(pageNotificationsProvider.notifier).add(NavItem.updates);
    return _downloadNotificationHandle!;
  }

  void _showDownloadReadyNotification() {
    final handle = _downloadNotificationHandle;

    if (handle == null) {
      _downloadNotificationHandle = NotificationManager.instance.showHandle(
        message: 'Update ready to install.',
        type: NotificationType.success,
        title: 'Download Complete',
        actionLabel: 'Install',
        onAction: () => launchInstaller(),
        persistent: true,
        dedupe: false,
      );
    } else {
      handle.update(
        message: 'Update ready to install.',
        type: NotificationType.success,
        title: 'Download Complete',
        clearProgress: true,
        actionLabel: 'Install',
        onAction: () => launchInstaller(),
      );
    }

    ref.read(pageNotificationsProvider.notifier).add(NavItem.updates);
  }

  void previewState(UpdatePreviewState preview) {
    if (!kDebugMode) return;

    _clearOffPageNotifications();

    final cachedReleases = state.allReleases;
    _currentRelease = null;

    switch (preview) {
      case UpdatePreviewState.idle:
        state = UpdateState(allReleases: cachedReleases);
      case UpdatePreviewState.checking:
        state = UpdateState(
          isChecking: true,
          hasChecked: false,
          allReleases: cachedReleases,
        );
      case UpdatePreviewState.upToDate:
        state = UpdateState(hasChecked: true, allReleases: cachedReleases);
      case UpdatePreviewState.updateAvailable:
        _currentRelease = _devPreviewRelease;
        state = UpdateState(
          hasChecked: true,
          hasUpdate: true,
          release: _devPreviewRelease,
          allReleases: cachedReleases,
        );
      case UpdatePreviewState.downloading:
        _currentRelease = _devPreviewRelease;
        state = UpdateState(
          hasChecked: true,
          hasUpdate: true,
          isDownloading: true,
          release: _devPreviewRelease,
          downloadProgress: 0.64,
          downloadedBytes: 30870077,
          totalBytes: _devPreviewRelease.downloadSize ?? 48234496,
          allReleases: cachedReleases,
        );
      case UpdatePreviewState.downloaded:
        state = UpdateState(
          hasChecked: true,
          downloadedFilePath: r'C:\Temp\UniKM-Preview-9.9.9.exe',
          allReleases: cachedReleases,
        );
      case UpdatePreviewState.error:
        state = UpdateState(
          hasChecked: true,
          error: 'Preview error: unable to reach the update service.',
          allReleases: cachedReleases,
        );
    }

    if ((state.hasUpdate || state.downloadedFilePath != null) &&
        ref.read(currentNavProvider) != NavItem.updates) {
      ref.read(pageNotificationsProvider.notifier).add(NavItem.updates);
    }

    NotificationManager.instance.info('Update preview set to ${preview.name}.');
  }

  Future<void> checkForUpdates() async {
    final notificationState = state;
    _currentRelease = null;
    state = state.copyWith(
      isChecking: true,
      hasUpdate: false,
      release: null,
      error: null,
    );

    try {
      final updatesSettings = ref.read(updatesSettingsProvider);
      _updateService = _serviceFor(updatesSettings);
      final currentVersion = kAppVersion;

      // Run update check and full release list fetch in parallel.
      final results = await Future.wait([
        _updateService.checkForUpdates(
          currentVersion: currentVersion,
          includePrerelease: updatesSettings.includePrerelease,
          skippedVersions: updatesSettings.skippedVersions,
        ),
        _updateService.fetchAllReleases(),
      ]);

      final result = results[0] as UpdateCheckResult;
      final allReleases = results[1] as List<GitHubRelease>;

      // Persist updated release list to cache.
      if (allReleases.isNotEmpty) {
        unawaited(_updateService.saveReleasesCache(allReleases));
      }

      if (result.isError) {
        state = state.copyWith(
          isChecking: false,
          hasChecked: true,
          error: result.error,
          allReleases: allReleases.isNotEmpty ? allReleases : state.allReleases,
        );
        return;
      }

      _currentRelease = result.release;

      state = state.copyWith(
        isChecking: false,
        hasChecked: true,
        hasUpdate: result.hasUpdate,
        release: result.release,
        allReleases: allReleases.isNotEmpty ? allReleases : state.allReleases,
      );

      if (!result.hasUpdate || result.release == null) {
        _updateNotificationHandle?.dismiss();
        _updateNotificationHandle = null;
        if (!state.isDownloading && state.downloadedFilePath == null) {
          ref.read(pageNotificationsProvider.notifier).remove(NavItem.updates);
        }
      }

      // Fire "update available" notification when allowed by settings.
      if (result.hasUpdate &&
          result.release != null &&
          canShowUpdateAvailableNotification(notificationState)) {
        final notifSettings = ref.read(notificationsSettingsProvider);
        if (notifSettings.updateNotifications) {
          final version = result.release!.version;
          _updateNotificationHandle?.dismiss();
          _updateNotificationHandle = NotificationManager.instance.showHandle(
            message: 'Version $version is available.',
            type: NotificationType.update,
            title: 'Update Available',
            onTap: () {
              ref.read(currentNavProvider.notifier).set(NavItem.updates);
            },
            actionLabel: 'View',
            onAction: () {
              ref.read(currentNavProvider.notifier).set(NavItem.updates);
            },
            secondaryActionLabel: 'Skip',
            onSecondaryAction: () {
              skipVersion();
            },
            persistent: true,
            dedupe: false,
          );
          // Mark the Updates destination when the user is not already there.
          if (ref.read(currentNavProvider) != NavItem.updates) {
            ref.read(pageNotificationsProvider.notifier).add(NavItem.updates);
          }
        }
      }
    } catch (e) {
      state = state.copyWith(
        isChecking: false,
        hasChecked: true,
        error: e.toString(),
      );
    }
  }

  Future<void> downloadUpdate() async {
    if (_currentRelease == null) return;

    await _downloadRelease(
      release: _currentRelease!,
      completionMessage: 'Update downloaded — ready to install.',
    );
  }

  Future<void> _downloadRelease({
    required GitHubRelease release,
    required String completionMessage,
    String? switchingToVersion,
  }) async {
    final isOnUpdatesPage = ref.read(currentNavProvider) == NavItem.updates;

    state = state.copyWith(
      switchingToVersion: switchingToVersion,
      release: release,
      isDownloading: true,
      downloadProgress: 0,
      downloadedBytes: 0,
      totalBytes: 0,
      downloadedFilePath: null,
      error: null,
    );
    _currentRelease = release;

    if (isOnUpdatesPage) {
      _clearOffPageNotifications(update: false);
    } else {
      _showOrUpdateDownloadNotification(
        downloadedBytes: 0,
        totalBytes: 0,
        progress: 0,
      );
    }

    try {
      final downloadResult = await _updateService.downloadUpdate(
        release,
        onProgress: (received, total) {
          final progress = total > 0 ? received / total : 0.0;
          state = state.copyWith(
            downloadProgress: progress,
            downloadedBytes: received,
            totalBytes: total,
          );
          if (ref.read(currentNavProvider) != NavItem.updates) {
            _showOrUpdateDownloadNotification(
              downloadedBytes: received,
              totalBytes: total,
              progress: progress,
            );
          }
        },
      );

      if (downloadResult.openedExternally) {
        _clearOffPageNotifications(update: false);
        state = state.copyWith(isDownloading: false, switchingToVersion: null);
        NotificationManager.instance.info(
          switchingToVersion == null
              ? 'Update download opened in your device downloader.'
              : 'Version ${release.version} was handed off to your device downloader.',
        );
        return;
      }

      final filePath = downloadResult.filePath;
      if (filePath == null || filePath.isEmpty) {
        throw StateError('Download completed without a local installer file');
      }

      state = state.copyWith(
        isDownloading: false,
        downloadedFilePath: filePath,
        switchingToVersion: null,
      );

      if (ref.read(currentNavProvider) != NavItem.updates) {
        _showDownloadReadyNotification();
      } else {
        _clearOffPageNotifications(update: false);
        NotificationManager.instance.success(completionMessage);
      }
    } on DownloadCancelledException {
      // User cancelled — notification already dismissed in cancelDownload().
    } catch (e) {
      _downloadNotificationHandle?.completeError('Download failed.');
      _downloadNotificationHandle = null;
      ref.read(pageNotificationsProvider.notifier).remove(NavItem.updates);
      state = state.copyWith(
        isDownloading: false,
        error: 'Download failed: $e',
        switchingToVersion: null,
      );
    }
  }

  Future<void> launchInstaller() async {
    if (state.downloadedFilePath == null) return;

    try {
      final shouldCloseApp = await _updateService.launchInstaller(
        state.downloadedFilePath!,
      );

      if (!shouldCloseApp) {
        NotificationManager.instance.info(
          'Update package opened. Finish the install manually if needed.',
        );
        return;
      }

      NotificationManager.instance.info(
        'Installer launched. The app will close shortly.',
      );

      // Give time for the installer to start, then exit
      await Future.delayed(const Duration(seconds: 2));
      exit(0);
    } catch (e) {
      NotificationManager.instance.error('Failed to launch installer: $e');
    }
  }

  Future<void> skipVersion() async {
    // Capture the version BEFORE any await so state resets cannot clear it.
    final version = state.latestVersion;
    if (version != null) {
      final updatesSettings = ref.read(updatesSettingsProvider);
      final currentSkipped = updatesSettings.skippedVersions;

      if (!currentSkipped.contains(version)) {
        final updatedSkipped = [...currentSkipped, version];
        await ref
            .read(settingsProvider.notifier)
            .setSetting(SettingsKeys.skippedVersions, updatedSkipped);
      }

      _currentRelease = null;
      state = state.copyWith(
        hasUpdate: false,
        hasChecked: false,
        release: null,
      );
      _clearOffPageNotifications(download: false);
      NotificationManager.instance.info('Version $version skipped');
    }
  }

  /// Remove a single version from the skipped list.
  Future<void> unskipVersion(String version) async {
    final updatesSettings = ref.read(updatesSettingsProvider);
    final updated = updatesSettings.skippedVersions
        .where((v) => v != version)
        .toList();
    await ref
        .read(settingsProvider.notifier)
        .setSetting(SettingsKeys.skippedVersions, updated);
    NotificationManager.instance.success('Version $version unskipped');
  }

  /// Clear all entries from the skipped versions list.
  Future<void> clearAllSkippedVersions() async {
    await ref
        .read(settingsProvider.notifier)
        .setSetting(SettingsKeys.skippedVersions, <String>[]);
    NotificationManager.instance.success('All skipped versions cleared');
  }

  /// Download and install a specific release (update or downgrade).
  Future<void> switchToVersion(GitHubRelease release) async {
    // If downgrading to 1.1.0 or below, reset the toggle style to regular
    if (compareVersions(release.version, '1.1.0') <= 0) {
      ref
          .read(settingsProvider.notifier)
          .setSetting(SettingsKeys.toggleStyle, ToggleStyle.regular);
    }

    await _downloadRelease(
      release: release,
      switchingToVersion: release.version,
      completionMessage:
          'Version ${release.version} downloaded. Click Install to apply.',
    );
  }

  /// Cancel any in-progress download and reset download state.
  void cancelDownload() {
    _updateService.cancelActiveDownload();
    _clearOffPageNotifications(update: false);
    state = state.copyWith(
      isDownloading: false,
      downloadProgress: 0,
      downloadedBytes: 0,
      totalBytes: 0,
      switchingToVersion: null,
    );
    NotificationManager.instance.info('Download cancelled');
  }

  /// Clear any update state.
  void clearUpdate() {
    _clearOffPageNotifications();
    _currentRelease = null;
    state = UpdateState(allReleases: state.allReleases);
    NotificationManager.instance.info('Update cleared');
  }

  /// Delegate to [UpdateService.compareVersions].
  int compareVersions(String a, String b) =>
      _updateService.compareVersions(a, b);
}

final updateProvider = NotifierProvider<UpdateNotifier, UpdateState>(
  UpdateNotifier.new,
);

/// Update page
class UpdatePage extends ConsumerStatefulWidget {
  const UpdatePage({super.key});

  @override
  ConsumerState<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends ConsumerState<UpdatePage> {
  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final updateState = ref.watch(updateProvider);
    final shellSettings = ref.watch(appShellSettingsProvider);
    final isVeryNarrowMode = isVeryNarrowAppLayout(
      MediaQuery.sizeOf(context).width,
      position: shellSettings.navBarPosition,
      appearance: shellSettings.navBarAppearance,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.hasBoundedHeight
            ? math.max(0.0, constraints.maxHeight - 40)
            : 0.0;

        return RefreshIndicator(
          onRefresh: () async {
            if (!canRunAutomaticUpdateCheck(updateState)) {
              return;
            }
            await ref.read(updateProvider.notifier).checkForUpdates();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: _UpdatePageLayout(
              viewportHeight: minHeight,
              minimumChangelogHeight: MediaQuery.textScalerOf(
                context,
              ).scale(240),
              children: [
                _UpdateStatusPanel(
                  theme: theme,
                  state: updateState,
                  isVeryNarrowMode: isVeryNarrowMode,
                ),
                _ChangelogSection(
                  key: const ValueKey('update-changelog'),
                  theme: theme,
                  releases: updateState.allReleases,
                  updateRelease: updateState.hasUpdate
                      ? updateState.release
                      : null,
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    'v$kAppVersion',
                    key: const ValueKey('update-installed-version'),
                    style: TextStyle(
                      color: theme.textSecondary.withValues(alpha: 0.15),
                      fontSize: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Measures the status and footer before giving the changelog its remaining
/// window space. Small windows can scroll while keeping a usable reading area.
class _UpdatePageLayout extends MultiChildRenderObjectWidget {
  const _UpdatePageLayout({
    required this.viewportHeight,
    required this.minimumChangelogHeight,
    required super.children,
  });

  final double viewportHeight;
  final double minimumChangelogHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderUpdatePageLayout(viewportHeight, minimumChangelogHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderUpdatePageLayout renderObject,
  ) {
    renderObject
      ..viewportHeight = viewportHeight
      ..minimumChangelogHeight = minimumChangelogHeight
      ..markNeedsLayout();
  }
}

class _UpdatePageParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderUpdatePageLayout extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _RenderUpdatePageLayout(this.viewportHeight, this.minimumChangelogHeight);

  double viewportHeight;
  double minimumChangelogHeight;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _UpdatePageParentData();
    }
  }

  @override
  void performLayout() {
    final status = firstChild!;
    final changelog = childAfter(status)!;
    final footer = lastChild!;
    final childConstraints = BoxConstraints.tightFor(
      width: constraints.maxWidth,
    );
    status.layout(childConstraints, parentUsesSize: true);
    footer.layout(childConstraints, parentUsesSize: true);
    const gap = 24.0;
    final remaining =
        viewportHeight - status.size.height - footer.size.height - gap * 2;
    changelog.layout(
      childConstraints.copyWith(
        maxHeight: math.max(minimumChangelogHeight, remaining),
      ),
      parentUsesSize: true,
    );
    final contentHeight =
        status.size.height +
        changelog.size.height +
        footer.size.height +
        gap * 2;
    size = constraints.constrain(
      Size(constraints.maxWidth, math.max(viewportHeight, contentHeight)),
    );
    (status.parentData! as ContainerBoxParentData<RenderBox>).offset =
        Offset.zero;
    (changelog.parentData! as ContainerBoxParentData<RenderBox>).offset =
        Offset(0, status.size.height + gap);
    (footer.parentData! as ContainerBoxParentData<RenderBox>).offset = Offset(
      0,
      size.height - footer.size.height,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// A single responsive surface keeps every stage of an update in one place.
class _UpdateStatusPanel extends ConsumerWidget {
  const _UpdateStatusPanel({
    required this.theme,
    required this.state,
    required this.isVeryNarrowMode,
  });

  final AppThemeData theme;
  final UpdateState state;
  final bool isVeryNarrowMode;

  Future<void> _showInFolder(String filePath) async {
    if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', filePath]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', filePath]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [File(filePath).parent.path]);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(updateProvider.notifier);
    final stage = state.error != null
        ? UpdatePreviewState.error
        : state.downloadedFilePath != null
        ? UpdatePreviewState.downloaded
        : state.isChecking
        ? UpdatePreviewState.checking
        : state.isDownloading
        ? UpdatePreviewState.downloading
        : state.hasUpdate || state.switchingToVersion != null
        ? UpdatePreviewState.updateAvailable
        : state.hasChecked
        ? UpdatePreviewState.upToDate
        : UpdatePreviewState.idle;
    final busy =
        stage == UpdatePreviewState.checking ||
        stage == UpdatePreviewState.downloading;
    final available = stage == UpdatePreviewState.updateAvailable;
    final downloading = stage == UpdatePreviewState.downloading;
    final ready = stage == UpdatePreviewState.downloaded;
    final failed = stage == UpdatePreviewState.error;
    final color = failed ? theme.secondary : theme.accent;
    final (title, icon) = switch (stage) {
      UpdatePreviewState.idle => ('UniKM updates', UpdateStatusIcons.idle),
      UpdatePreviewState.checking => (
        'Looking for updates',
        UpdateStatusIcons.idle,
      ),
      UpdatePreviewState.upToDate => (
        "You're up to date",
        UpdateStatusIcons.upToDate,
      ),
      UpdatePreviewState.updateAvailable => (
        state.switchingToVersion != null
            ? 'Switch version'
            : 'Update available',
        UpdateStatusIcons.available,
      ),
      UpdatePreviewState.downloading => (
        'Downloading update',
        UpdateStatusIcons.available,
      ),
      UpdatePreviewState.downloaded => (
        'Ready to install',
        UpdateStatusIcons.downloaded,
      ),
      UpdatePreviewState.error => (
        "Couldn't complete the update",
        UpdateStatusIcons.error,
      ),
    };
    final targetVersion = state.switchingToVersion ?? state.latestVersion;
    final showTarget = available || downloading || ready;

    final headline = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: SurfaceDepth.gradient(
              Color.alphaBlend(color.withValues(alpha: 0.12), theme.surface),
              highlight: 0.08,
            ),
            borderRadius: BorderRadius.circular(theme.cornerRadius),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Center(
            child: busy
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: AppCircularProgressIndicator(color: color),
                  )
                : Icon(icon, color: color, size: 28),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                liveRegion: true,
                header: true,
                child: Text(
                  title,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (showTarget && targetVersion != null) ...[
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'v$targetVersion',
                      style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (state.release != null)
                      Text(
                        state.isPrerelease ? 'Pre-release' : 'Stable release',
                        style: TextStyle(
                          color: theme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    if (state.downloadSize != null)
                      Text(
                        state.downloadSize!,
                        style: TextStyle(
                          color: theme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ],
              if (failed || ready) ...[
                SelectableText(
                  failed
                      ? state.error!
                      : state.downloadedFilePath!.split(RegExp(r'[/\\]')).last,
                  style: TextStyle(
                    color: failed ? color : theme.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    final actions = Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (ready) ...[
          if (!Platform.isAndroid && !Platform.isIOS)
            OutlinedButton.icon(
              onPressed: () => _showInFolder(state.downloadedFilePath!),
              icon: const Icon(Icons.folder_open),
              label: const Text('Show in Folder'),
            ),
          ElevatedButton.icon(
            onPressed: () => notifier.launchInstaller(),
            icon: const Icon(Icons.install_desktop),
            label: const Text('Install & Restart'),
          ),
        ] else if (available) ...[
          OutlinedButton.icon(
            onPressed: () => notifier.skipVersion(),
            icon: const Icon(Icons.block),
            label: const Text('Skip version'),
          ),
          Tooltip(
            message: state.downloadUrl == null
                ? 'Installer file not found'
                : 'Download this release',
            child: ElevatedButton.icon(
              onPressed: state.downloadUrl == null
                  ? null
                  : () => notifier.downloadUpdate(),
              icon: const Icon(Icons.download),
              label: const Text('Download'),
            ),
          ),
        ],
        _SkippedVersionsButton(theme: theme),
      ],
    );
    final hasSkippedVersions = ref.watch(
      updatesSettingsProvider.select(
        (settings) => settings.skippedVersions.isNotEmpty,
      ),
    );
    final showActions = available || ready || hasSkippedVersions;
    final showCheck = !downloading && !ready;
    final checkButton = IconButton(
      key: const ValueKey('update-check-button'),
      tooltip: busy
          ? 'Checking for updates'
          : state.hasChecked || failed || available
          ? 'Recheck Updates'
          : 'Check for Updates',
      style: theme.compactIconButtonStyle,
      color: theme.accent,
      onPressed: busy ? null : () => notifier.checkForUpdates(),
      icon: const Icon(Icons.refresh, size: 22),
    );
    final trailingControls = showActions || showCheck
        ? Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showActions) Flexible(child: actions),
              if (showActions && showCheck) const SizedBox(width: 8),
              if (showCheck) checkButton,
            ],
          )
        : null;

    return SectionGroupBox(
      key: const ValueKey('update-status-panel'),
      title: '',
      showTitle: false,
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: headline),
              if (!isVeryNarrowMode && trailingControls != null)
                Flexible(
                  fit: FlexFit.loose,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: trailingControls,
                  ),
                ),
            ],
          ),
          if (isVeryNarrowMode && trailingControls != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: Align(
                alignment: Alignment.centerRight,
                child: trailingControls,
              ),
            ),
          ],
          if (downloading) ...[
            const SizedBox(height: 18),
            AppLinearProgressBar(
              theme: theme,
              value: state.downloadProgress.clamp(0.0, 1.0),
              label:
                  '${(state.downloadProgress.clamp(0.0, 1.0) * 100).round()}%',
            ),
            const SizedBox(height: 8),
            FooterWrap(
              leading: Text(
                state.totalBytes > 0
                    ? '${formatFileSize(state.downloadedBytes)} / ${formatFileSize(state.totalBytes)}'
                    : 'Preparing download…',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.textSecondary, fontSize: 12),
              ),
              trailing: ElevatedButton.icon(
                onPressed: notifier.cancelDownload,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Cancel download'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

MarkdownStyleSheet _releaseMarkdownStyleSheet(AppThemeData theme) {
  return MarkdownStyleSheet(
    p: TextStyle(color: theme.textPrimary, fontSize: 13),
    h1: TextStyle(
      color: theme.textPrimary,
      fontSize: 16,
      fontWeight: FontWeight.bold,
    ),
    h2: TextStyle(
      color: theme.textPrimary,
      fontSize: 14,
      fontWeight: FontWeight.bold,
    ),
    h3: TextStyle(
      color: theme.textPrimary,
      fontSize: 13,
      fontWeight: FontWeight.bold,
    ),
    code: TextStyle(color: theme.accent, fontFamily: 'monospace', fontSize: 12),
    blockquote: TextStyle(color: theme.textSecondary, fontSize: 13),
    listBullet: TextStyle(color: theme.textPrimary, fontSize: 13),
  );
}

/// Opens the release archive from the changelog title bar.
class _ReleasesLinkButton extends ConsumerWidget {
  const _ReleasesLinkButton({required this.theme});
  final AppThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customRepo = ref.watch(updatesSettingsProvider).updateRepo;
    final repo = customRepo.isNotEmpty ? customRepo : kGitHubRepo;
    return IconButton(
      tooltip: 'GitHub Releases',
      style: theme.compactIconButtonStyle,
      color: theme.accent,
      icon: const Icon(Icons.open_in_new, size: 22),
      onPressed: () => launchUrl(
        Uri.parse('https://github.com/$repo/releases'),
        mode: LaunchMode.externalApplication,
      ),
    );
  }
}

// =============================================================================
// Skipped Versions
// =============================================================================

/// Small button shown in the page header when there are skipped versions.
class _SkippedVersionsButton extends ConsumerWidget {
  const _SkippedVersionsButton({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skipped = ref.watch(
      updatesSettingsProvider.select((s) => s.skippedVersions),
    );
    if (skipped.isEmpty) return const SizedBox.shrink();

    return TextButton.icon(
      onPressed: () => showAppDialog<void>(
        context: context,
        builder: (_) => SkippedVersionsDialog(theme: theme),
      ),
      icon: Icon(Icons.block, color: theme.textSecondary),
      label: Text(
        'Skipped (${skipped.length})',
        style: TextStyle(color: theme.textSecondary),
      ),
    );
  }
}

/// Dialog that lists all skipped versions with unskip controls.
class SkippedVersionsDialog extends ConsumerWidget {
  const SkippedVersionsDialog({super.key, required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skipped = ref.watch(
      updatesSettingsProvider.select((s) => s.skippedVersions),
    );
    final notifier = ref.read(updateProvider.notifier);

    return ThemedAlertDialog(
      theme: theme,
      maxWidth: kCompactDialogWidth,
      title: DialogHeader(
        icon: Icons.block,
        title: 'Skipped Versions',
        theme: theme,
      ),
      content: SizedBox(
        width: 380,
        child: skipped.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No skipped versions.',
                  style: TextStyle(color: theme.textSecondary),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final version in skipped)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.commit,
                        color: theme.textSecondary,
                        size: 18,
                      ),
                      title: Text(
                        'v$version',
                        style: TextStyle(color: theme.textPrimary),
                      ),
                      trailing: OutlinedButton(
                        onPressed: () async {
                          await notifier.unskipVersion(version);
                        },
                        child: const Text('Unskip'),
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        if (skipped.isNotEmpty)
          ElevatedButton(
            onPressed: () async {
              await notifier.clearAllSkippedVersions();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text('Clear All'),
          ),
      ],
    );
  }
}

// =============================================================================
// Changelog / Version Switcher
// =============================================================================

/// One release at a time, with a persistent selector and bounded reading area.
class _ChangelogSection extends ConsumerStatefulWidget {
  const _ChangelogSection({
    super.key,
    required this.theme,
    required this.releases,
    this.updateRelease,
  });
  final AppThemeData theme;
  final List<GitHubRelease> releases;
  final GitHubRelease? updateRelease;

  @override
  ConsumerState<_ChangelogSection> createState() => _ChangelogSectionState();
}

class _ChangelogSectionState extends ConsumerState<_ChangelogSection> {
  String? _selectedTag;
  final _scrollController = ScrollController();

  List<GitHubRelease> get _releases => [
    ...widget.releases,
    if (widget.updateRelease != null &&
        !widget.releases.any(
          (release) => release.tagName == widget.updateRelease!.tagName,
        ))
      widget.updateRelease!,
  ];

  @override
  void initState() {
    super.initState();
    _selectedTag = widget.updateRelease?.tagName;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ChangelogSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final detectedTag = widget.updateRelease?.tagName;
    if (detectedTag != null &&
        detectedTag != oldWidget.updateRelease?.tagName) {
      _selectedTag = detectedTag;
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    } else if (_selectedTag != null &&
        !_releases.any((release) => release.tagName == _selectedTag)) {
      _selectedTag = null;
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final notifier = ref.read(updateProvider.notifier);
    final releases = _releases
      ..sort((a, b) => notifier.compareVersions(b.version, a.version));
    final release = releases.isEmpty
        ? null
        : releases.firstWhere(
            (release) => release.tagName == _selectedTag,
            orElse: () => releases.first,
          );
    final updateState = ref.watch(updateProvider);
    final skipped = ref.watch(updatesSettingsProvider).skippedVersions;
    final isCurrent =
        release != null &&
        notifier.compareVersions(release.version, kAppVersion) == 0;
    final isSkipped = release != null && skipped.contains(release.version);
    final isDownloading =
        release != null &&
        updateState.isDownloading &&
        updateState.switchingToVersion == release.version;
    final canDownload =
        release != null &&
        !isCurrent &&
        !isSkipped &&
        !updateState.isDownloading &&
        release.downloadUrl != null;

    return SectionGroupBox(
      title: 'Changelog',
      contentFit: FlexFit.loose,
      titleIcon: Icons.article_outlined,
      titleLocation: SectionTitleLocation.top,
      headerCrossAxisAlignment: CrossAxisAlignment.center,
      theme: theme,
      trailing: _ReleasesLinkButton(theme: theme),
      child: release == null
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Release notes will appear after checking for updates.',
                style: TextStyle(color: theme.textSecondary),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: AppComboBox<String>(
                        key: const ValueKey('changelog-version-selector'),
                        menuMaxHeight: kDropdownMenuMaxHeight * 2,
                        initialValue: release.tagName,
                        decoration: const InputDecoration(labelText: 'Version'),
                        theme: theme,
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          color: theme.textPrimary,
                        ),
                        items: [
                          for (final item in releases)
                            DropdownMenuItem(
                              value: item.tagName,
                              child: Text(
                                'v${item.version}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (tag) {
                          if (tag == null || tag == release.tagName) return;
                          setState(() => _selectedTag = tag);
                          if (_scrollController.hasClients) {
                            _scrollController.jumpTo(0);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: isCurrent
                          ? 'Current version'
                          : isSkipped
                          ? 'Skipped version'
                          : isDownloading
                          ? 'Downloading...'
                          : release.downloadUrl == null
                          ? 'Installer file not found'
                          : 'Download',
                      style: theme.compactIconButtonStyle,
                      onPressed: canDownload
                          ? () => notifier.switchToVersion(release)
                          : null,
                      icon: isDownloading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: AppCircularProgressIndicator(),
                            )
                          : Icon(
                              isCurrent
                                  ? Icons.check_circle
                                  : isSkipped
                                  ? Icons.block
                                  : Icons.download,
                              color: theme.accent,
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  fit: FlexFit.loose,
                  child: Container(
                    key: const ValueKey('changelog-info-panel'),
                    constraints: const BoxConstraints(maxHeight: 840),
                    decoration: BoxDecoration(
                      color: theme.background.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(theme.cornerRadius),
                      border: Border.all(color: theme.border),
                    ),
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        key: const ValueKey('changelog-info-scroll'),
                        controller: _scrollController,
                        primary: false,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              release.name.trim().isEmpty
                                  ? 'UniKM v${release.version}'
                                  : release.name,
                              style: TextStyle(
                                color: theme.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                Text(
                                  DateFormat(
                                    'yyyy-MM-dd',
                                  ).format(release.publishedAt),
                                  style: TextStyle(
                                    color: theme.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                                if (isCurrent)
                                  Text(
                                    'Current version',
                                    style: TextStyle(
                                      color: theme.accent,
                                      fontSize: 12,
                                    ),
                                  ),
                                if (release.isPrerelease)
                                  Text(
                                    'Pre-release',
                                    style: TextStyle(
                                      color: theme.secondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                if (isSkipped)
                                  Text(
                                    'Skipped version',
                                    style: TextStyle(
                                      color: theme.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                            Divider(height: 24, color: theme.border),
                            MarkdownBody(
                              data: release.body.trim().isEmpty
                                  ? 'No release notes were provided for this version.'
                                  : release.body,
                              styleSheet: _releaseMarkdownStyleSheet(theme),
                              onTapLink: (_, href, _) async {
                                final uri = Uri.tryParse(href ?? '');
                                if (uri != null &&
                                    (uri.scheme == 'https' ||
                                        uri.scheme == 'http')) {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
