/// Update checks, downloads and installs, shared by the update dialog, the
/// navigation badge and the automatic check.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/update_service.dart';
import '../../core/settings/settings_model.dart';
import '../../providers/app_providers.dart';
import '../../ui/widgets/notification_system.dart';

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

  /// The stage the update dialog shows.
  UpdatePreviewState get stage => error != null
      ? UpdatePreviewState.error
      : downloadedFilePath != null
      ? UpdatePreviewState.downloaded
      : isChecking
      ? UpdatePreviewState.checking
      : isDownloading
      ? UpdatePreviewState.downloading
      : hasUpdate || switchingToVersion != null
      ? UpdatePreviewState.updateAvailable
      : hasChecked
      ? UpdatePreviewState.upToDate
      : UpdatePreviewState.idle;

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
  }) => UpdateState(
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

String _downloadNotificationMessage(int downloadedBytes, int totalBytes) =>
    totalBytes > 0
    ? 'Downloaded ${_formatMegabytes(downloadedBytes)} / ${_formatMegabytes(totalBytes)}'
    : 'Downloaded ${_formatMegabytes(downloadedBytes)}';

bool canRunAutomaticUpdateCheck(UpdateState state) =>
    !state.isChecking &&
    !state.isDownloading &&
    state.downloadedFilePath == null;

bool canShowUpdateAvailableNotification(UpdateState state) =>
    !state.isDownloading && state.downloadedFilePath == null;

/// Update notifier using real GitHub API
class UpdateNotifier extends Notifier<UpdateState> {
  late UpdateService _updateService;
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

    // Progress moves between the dialog and notifications as it opens and
    // closes.
    ref.listen(updateDialogOpenProvider, (_, open) {
      if (open) {
        _clearOffPageNotifications();
      } else {
        if (state.isDownloading) {
          _showDownloadNotification(
            _downloadNotificationMessage(
              state.downloadedBytes,
              state.totalBytes,
            ),
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

  bool get _dialogOpen => ref.read(updateDialogOpenProvider);

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
    if (cached.isNotEmpty) state = state.copyWith(allReleases: cached);
  }

  /// Shows or updates the persistent download notification. Without a
  /// [progress] the download is complete and the bar is cleared.
  void _showDownloadNotification(String message, {double? progress}) {
    final done = progress == null;
    final type = done ? NotificationType.success : NotificationType.download;
    final title = done ? 'Download Complete' : 'Update Download';
    final actionLabel = done ? 'Install' : 'Cancel';
    final VoidCallback onAction = done
        ? () => launchInstaller()
        : cancelDownload;
    final handle = _downloadNotificationHandle;
    if (handle == null) {
      _downloadNotificationHandle = NotificationManager.instance.showHandle(
        message: message,
        type: type,
        title: title,
        progress: progress,
        actionLabel: actionLabel,
        onAction: onAction,
        persistent: true,
        dedupe: false,
      );
    } else {
      handle.update(
        message: message,
        type: type,
        title: title,
        progress: progress,
        clearProgress: done,
        actionLabel: actionLabel,
        onAction: onAction,
      );
    }
    ref.read(pageNotificationsProvider.notifier).add(NavItem.updates);
  }

  void _showDownloadProgressNotification(int received, int total) =>
      _showDownloadNotification(
        _downloadNotificationMessage(received, total),
        progress: total > 0 ? received / total : 0.0,
      );

  void _showDownloadReadyNotification() =>
      _showDownloadNotification('Update ready to install.');

  void previewState(UpdatePreviewState preview) {
    if (!kDebugMode) return;

    _clearOffPageNotifications();

    final cachedReleases = state.allReleases;

    state = switch (preview) {
      UpdatePreviewState.idle => UpdateState(allReleases: cachedReleases),
      UpdatePreviewState.checking => UpdateState(
        isChecking: true,
        allReleases: cachedReleases,
      ),
      UpdatePreviewState.upToDate => UpdateState(
        hasChecked: true,
        allReleases: cachedReleases,
      ),
      UpdatePreviewState.updateAvailable => UpdateState(
        hasChecked: true,
        hasUpdate: true,
        release: _devPreviewRelease,
        allReleases: cachedReleases,
      ),
      UpdatePreviewState.downloading => UpdateState(
        hasChecked: true,
        hasUpdate: true,
        isDownloading: true,
        release: _devPreviewRelease,
        downloadProgress: 0.64,
        downloadedBytes: 30870077,
        totalBytes: _devPreviewRelease.downloadSize ?? 48234496,
        allReleases: cachedReleases,
      ),
      UpdatePreviewState.downloaded => UpdateState(
        hasChecked: true,
        downloadedFilePath: r'C:\Temp\UniKM-Preview-9.9.9.exe',
        allReleases: cachedReleases,
      ),
      UpdatePreviewState.error => UpdateState(
        hasChecked: true,
        error: 'Preview error: unable to reach the update service.',
        allReleases: cachedReleases,
      ),
    };

    if ((state.hasUpdate || state.downloadedFilePath != null) && !_dialogOpen) {
      ref.read(pageNotificationsProvider.notifier).add(NavItem.updates);
    }

    NotificationManager.instance.info('Update preview set to ${preview.name}.');
  }

  Future<void> checkForUpdates() async {
    final notificationState = state;
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
          void openUpdates() =>
              ref.read(updateDialogOpenProvider.notifier).set(true);
          _updateNotificationHandle?.dismiss();
          _updateNotificationHandle = NotificationManager.instance.showHandle(
            message: 'Version $version is available.',
            type: NotificationType.update,
            title: 'Update Available',
            onTap: openUpdates,
            actionLabel: 'View',
            onAction: openUpdates,
            secondaryActionLabel: 'Skip',
            onSecondaryAction: skipVersion,
            persistent: true,
            dedupe: false,
          );
          // Mark the Updates button while the dialog is closed.
          if (!_dialogOpen) {
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
    final release = state.release;
    if (release == null) return;

    await _downloadRelease(
      release: release,
      completionMessage: 'Update downloaded — ready to install.',
    );
  }

  Future<void> _downloadRelease({
    required GitHubRelease release,
    required String completionMessage,
    String? switchingToVersion,
  }) async {
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

    if (_dialogOpen) {
      _clearOffPageNotifications(update: false);
    } else {
      _showDownloadProgressNotification(0, 0);
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
          if (!_dialogOpen) {
            _showDownloadProgressNotification(received, total);
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

      if (!_dialogOpen) {
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
