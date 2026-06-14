/// Update page - check for and install app updates
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/update_service.dart';
import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../widgets/notification_system.dart';
import '../widgets/app_progress_indicator.dart';
import '../widgets/page_header_title.dart';
import '../widgets/dialog_helpers.dart';

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
  String? get releaseNotes => release?.body;
  String? get downloadUrl => release?.downloadUrl;
  String? get releaseHtmlUrl => release?.htmlUrl;
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

String _formatBytesHuman(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
    final updatesSettings = ref.read(updatesSettingsProvider);
    final customRepo = updatesSettings.updateRepo;
    final githubToken = updatesSettings.githubApiToken;

    _updateService = UpdateService(
      customRepo: customRepo.isNotEmpty ? customRepo : null,
      githubToken: githubToken.isNotEmpty ? githubToken : null,
    );

    // Load cached releases immediately so the changelog shows without a network hit.
    Future.microtask(_loadCachedReleases);

    // React to navigation to manage off-page notifications.
    ref.listen(currentNavProvider, (prev, next) {
      if (next == NavItem.updates) {
        // User arrived on the updates page — dismiss off-page notifications.
        _updateNotificationHandle?.dismiss();
        _updateNotificationHandle = null;
        _downloadNotificationHandle?.dismiss();
        _downloadNotificationHandle = null;
        ref.read(pageNotificationsProvider.notifier).remove(NavItem.updates);
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

  /// Get the releases page URL
  String get releasesPageUrl => _updateService.releasesPageUrl;

  void previewState(UpdatePreviewState preview) {
    if (!kDebugMode) return;

    _updateNotificationHandle?.dismiss();
    _updateNotificationHandle = null;
    _downloadNotificationHandle?.dismiss();
    _downloadNotificationHandle = null;
    ref.read(pageNotificationsProvider.notifier).remove(NavItem.updates);

    final cachedReleases = state.allReleases;
    _currentRelease = null;

    switch (preview) {
      case UpdatePreviewState.idle:
        state = UpdateState(allReleases: cachedReleases);
        break;
      case UpdatePreviewState.checking:
        state = UpdateState(
          isChecking: true,
          hasChecked: false,
          allReleases: cachedReleases,
        );
        break;
      case UpdatePreviewState.upToDate:
        state = UpdateState(hasChecked: true, allReleases: cachedReleases);
        break;
      case UpdatePreviewState.updateAvailable:
        _currentRelease = _devPreviewRelease;
        state = UpdateState(
          hasChecked: true,
          hasUpdate: true,
          release: _devPreviewRelease,
          allReleases: cachedReleases,
        );
        break;
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
        break;
      case UpdatePreviewState.downloaded:
        state = UpdateState(
          hasChecked: true,
          downloadedFilePath: r'C:\Temp\UniKM-Preview-9.9.9.exe',
          allReleases: cachedReleases,
        );
        break;
      case UpdatePreviewState.error:
        state = UpdateState(
          hasChecked: true,
          error: 'Preview error: unable to reach the update service.',
          allReleases: cachedReleases,
        );
        break;
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
      _updateService = UpdateService(
        customRepo: updatesSettings.updateRepo.isNotEmpty
            ? updatesSettings.updateRepo
            : null,
        githubToken: updatesSettings.githubApiToken.isNotEmpty
            ? updatesSettings.githubApiToken
            : null,
      );
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
              ref.read(currentNavProvider.notifier).setNav(NavItem.updates);
            },
            actionLabel: 'View',
            onAction: () {
              ref.read(currentNavProvider.notifier).setNav(NavItem.updates);
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
      _downloadNotificationHandle?.dismiss();
      _downloadNotificationHandle = null;
      ref.read(pageNotificationsProvider.notifier).remove(NavItem.updates);
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
        _downloadNotificationHandle?.dismiss();
        _downloadNotificationHandle = null;
        ref.read(pageNotificationsProvider.notifier).remove(NavItem.updates);
        state = state.copyWith(
          isDownloading: false,
          switchingToVersion: null,
        );
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
        _downloadNotificationHandle?.dismiss();
        _downloadNotificationHandle = null;
        ref.read(pageNotificationsProvider.notifier).remove(NavItem.updates);
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
      _updateNotificationHandle?.dismiss();
      _updateNotificationHandle = null;
      ref.read(pageNotificationsProvider.notifier).remove(NavItem.updates);
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
    _downloadNotificationHandle?.dismiss();
    _downloadNotificationHandle = null;
    ref.read(pageNotificationsProvider.notifier).remove(NavItem.updates);
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
    _updateNotificationHandle?.dismiss();
    _updateNotificationHandle = null;
    _downloadNotificationHandle?.dismiss();
    _downloadNotificationHandle = null;
    _currentRelease = null;
    ref.read(pageNotificationsProvider.notifier).remove(NavItem.updates);
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
    final updateNotifier = ref.read(updateProvider.notifier);
    final showInlineStatus =
        !updateState.isChecking &&
        updateState.error == null &&
        updateState.downloadedFilePath == null &&
        !updateState.hasUpdate &&
        updateState.switchingToVersion == null;

    void openReleasePage() async {
      final htmlUrl = updateState.releaseHtmlUrl;
      final releasesUrl = updateNotifier.releasesPageUrl;
      final url = htmlUrl ?? releasesUrl;
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    Widget? buildStatusCard() {
      if (updateState.error != null) {
        return _ErrorCard(
          theme: theme,
          error: updateState.error!,
          onRecheck: () => updateNotifier.checkForUpdates(),
        );
      }

      if (updateState.downloadedFilePath != null) {
        return _DownloadCompleteCard(
          theme: theme,
          filePath: updateState.downloadedFilePath!,
          onInstall: () => updateNotifier.launchInstaller(),
        );
      }

      if (updateState.isChecking) {
        return _UpdateStatusCard(
          theme: theme,
          isChecking: true,
          hasChecked: updateState.hasChecked,
        );
      }

      if (updateState.switchingToVersion != null || updateState.hasUpdate) {
        return _UpdateAvailableCard(
          theme: theme,
          updateState: updateState,
          onDownload: () => updateNotifier.downloadUpdate(),
          onSkip: () => updateNotifier.skipVersion(),
          onViewOnGithub: openReleasePage,
        );
      }

      if (!showInlineStatus && !updateState.isChecking && !updateState.hasUpdate) {
        return _UpdateStatusCard(
          theme: theme,
          isChecking: false,
          hasChecked: updateState.hasChecked,
        );
      }

      return null;
    }

    final statusCard = buildStatusCard();

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
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      PageHeaderTitle(
                        title: 'Software Updates',
                        icon: Icons.download_rounded,
                        theme: theme,
                      ),
                      const Spacer(),
                      _SkippedVersionsButton(theme: theme),
                    ],
                  ),

                  const SizedBox(height: 16),

                  if (showInlineStatus)
                    _UpdateStatusCard(
                      theme: theme,
                      isChecking: updateState.isChecking,
                      hasChecked: updateState.hasChecked,
                    ),

                  // Update status
                  ...<Widget?>[statusCard].whereType<Widget>(),

                  const SizedBox(height: 28),

                  // Changelog (always visible when releases are available)
                  if (updateState.allReleases.isNotEmpty)
                    _ChangelogSection(
                      key: ValueKey<String>(
                        'changelog-${updateState.isChecking}-${updateState.hasChecked}-${updateState.release?.tagName ?? 'none'}-${updateState.allReleases.length}',
                      ),
                      theme: theme,
                      releases: updateState.allReleases,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UpdateStateCardShell extends StatelessWidget {
  const _UpdateStateCardShell({
    required this.theme,
    required this.color,
    required this.leading,
    required this.child,
  });

  final AppThemeData theme;
  final Color color;
  final Widget leading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _UpdateStateCardFrame(
      theme: theme,
      color: color,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(theme.cornerRadius),
            ),
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(child: leading),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _UpdateStateCardFrame extends StatelessWidget {
  const _UpdateStateCardFrame({
    required this.theme,
    required this.color,
    required this.child,
  });

  final AppThemeData theme;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(theme.cornerRadius * 1.5),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: child,
    );
  }
}

/// Update status card
class _UpdateStatusCard extends ConsumerWidget {
  const _UpdateStatusCard({
    required this.theme,
    required this.isChecking,
    required this.hasChecked,
  });

  final AppThemeData theme;
  final bool isChecking;
  final bool hasChecked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = theme.accent;

    final leadingIcon = isChecking
        ? const Padding(
            padding: EdgeInsets.all(4),
            child: AppCircularProgressIndicator(),
          )
        : Icon(
            hasChecked ? Icons.check_circle : Icons.pending_outlined,
            color: theme.accent,
            size: 32,
          );

    return _UpdateStateCardShell(
      theme: theme,
      color: statusColor,
      leading: leadingIcon,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isChecking
                      ? 'Checking for updates...'
                      : !hasChecked
                      ? 'UniKM'
                      : 'You\'re up to date!',
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Current version $kAppVersion',
                  style: TextStyle(color: theme.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Check for Updates',
            onPressed: isChecking
                ? null
                : () => ref.read(updateProvider.notifier).checkForUpdates(),
            icon: Icon(
              Icons.refresh,
              color: isChecking ? theme.textHint : theme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Update available card
class _UpdateAvailableCard extends ConsumerWidget {
  const _UpdateAvailableCard({
    required this.theme,
    required this.updateState,
    required this.onDownload,
    required this.onSkip,
    required this.onViewOnGithub,
  });

  final AppThemeData theme;
  final UpdateState updateState;
  final VoidCallback onDownload;
  final VoidCallback onSkip;
  final VoidCallback onViewOnGithub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final release = updateState.release;
    final releaseNotes = updateState.releaseNotes?.trim() ?? '';

    return _UpdateStateCardFrame(
      theme: theme,
      color: theme.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: icon + info + Recheck
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(theme.cornerRadius),
                ),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: Icon(
                      Icons.new_releases,
                      color: theme.accent,
                      size: 32,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: kElementHSpacing,
                      runSpacing: 4,
                      children: [
                        Text(
                          updateState.isDownloading
                              ? 'Downloading Update'
                              : 'Update Available!',
                          style: TextStyle(
                            color: theme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (updateState.isPrerelease)
                          Tooltip(
                            message: 'Pre-release',
                            child: const Icon(
                              Icons.science,
                              color: Colors.orange,
                              size: 22,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          kAppVersion,
                          style: TextStyle(color: theme.textSecondary),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Icon(
                            Icons.arrow_forward,
                            size: 16,
                            color: theme.accent,
                          ),
                        ),
                        Text(
                          release?.version ?? '',
                          style: TextStyle(
                            color: theme.accent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!updateState.isDownloading) ...[
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'Skip Update',
                  onPressed: onSkip,
                  icon: Icon(Icons.block, color: theme.textPrimary),
                ),
                const SizedBox(width: kElementHSpacing),
                IconButton(
                  tooltip: 'Recheck Updates',
                  onPressed: () =>
                      ref.read(updateProvider.notifier).checkForUpdates(),
                  icon: Icon(Icons.refresh, color: theme.textPrimary),
                ),
              ],
              if (updateState.isDownloading &&
                  (updateState.totalBytes > 0 ||
                      updateState.downloadProgress > 0)) ...[
                const SizedBox(width: 12),
                Text(
                  updateState.totalBytes > 0
                      ? '${_formatBytesHuman(updateState.downloadedBytes)} / ${_formatBytesHuman(updateState.totalBytes)}'
                      : '${(updateState.downloadProgress * 100).toInt()}%',
                  style: TextStyle(color: theme.textSecondary, fontSize: 12),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          // Full-width button / progress row
          if (!updateState.isDownloading)
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: updateState.downloadUrl == null
                        ? 'Installer file not found'
                        : '',
                    child: ElevatedButton.icon(
                      onPressed: updateState.downloadUrl == null
                          ? null
                          : onDownload,
                      icon: const Icon(Icons.download),
                      label: const Text('Download'),
                    ),
                  ),
                ),
                const SizedBox(width: kElementHSpacing),
                TextButton.icon(
                  onPressed: onViewOnGithub,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('GitHub'),
                ),
              ],
            ),
          if (updateState.isDownloading) ...[
            Row(
              children: [
                Expanded(
                  child: AppLinearProgressBar(
                    theme: theme,
                    value: updateState.downloadProgress,
                    minHeight: kElementHeight,
                    label:
                        '${(updateState.downloadProgress.clamp(0.0, 1.0) * 100).round()}%',
                    labelStyle: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: kElementHSpacing),
                TextButton(
                  onPressed: () =>
                      ref.read(updateProvider.notifier).cancelDownload(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
          if (release != null && releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ReleaseNotesPanel(
              theme: theme,
              data: releaseNotes,
              scrollable: true,
              maxHeight: 220,
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
    code: TextStyle(
      color: theme.accent,
      fontFamily: 'monospace',
      fontSize: 12,
    ),
    blockquote: TextStyle(color: theme.textSecondary, fontSize: 13),
    listBullet: TextStyle(color: theme.textPrimary, fontSize: 13),
  );
}

class _ReleaseNotesPanel extends StatelessWidget {
  const _ReleaseNotesPanel({
    required this.theme,
    required this.data,
    this.scrollable = false,
    this.maxHeight = 220,
  });

  final AppThemeData theme;
  final String data;
  final bool scrollable;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final markdown = MarkdownBody(
      data: data,
      styleSheet: _releaseMarkdownStyleSheet(theme),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        border: Border.all(color: theme.border),
      ),
      child: scrollable
          ? ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(child: markdown),
            )
          : markdown,
    );
  }
}

/// Download complete card
class _DownloadCompleteCard extends StatelessWidget {
  const _DownloadCompleteCard({
    required this.theme,
    required this.filePath,
    required this.onInstall,
  });

  final AppThemeData theme;
  final String filePath;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final fileName = filePath.split(Platform.pathSeparator).last;

    return _UpdateStateCardFrame(
      theme: theme,
      color: theme.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(theme.cornerRadius),
                ),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: Icon(
                      Icons.download_done,
                      color: theme.accent,
                      size: 32,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Download Complete!',
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fileName,
                      style: TextStyle(color: theme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onInstall,
                  icon: const Icon(Icons.install_desktop),
                  label: const Text('Install & Restart'),
                ),
              ),
              if (!Platform.isAndroid && !Platform.isIOS) ...[
                const SizedBox(width: kElementHSpacing),
                OutlinedButton.icon(
                  onPressed: () async {
                    if (Platform.isWindows) {
                      await Process.run('explorer', ['/select,', filePath]);
                    } else if (Platform.isMacOS) {
                      await Process.run('open', ['-R', filePath]);
                    } else if (Platform.isLinux) {
                      final dir = filePath.substring(
                        0,
                        filePath.lastIndexOf('/'),
                      );
                      await Process.run('xdg-open', [dir]);
                    }
                  },
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Show in Folder'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Small releases button shown next to the page title.
class _ReleasesLinkButton extends ConsumerWidget {
  const _ReleasesLinkButton({required this.theme, required this.compact});

  final AppThemeData theme;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updatesSettings = ref.watch(updatesSettingsProvider);
    final customRepo = updatesSettings.updateRepo;
    final repo = customRepo.isNotEmpty ? customRepo : kGitHubRepo;
    final releasesUrl = 'https://github.com/$repo/releases';
    const label = 'GitHub Releases';

    return Tooltip(
      message: releasesUrl,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18),
          visualDensity: VisualDensity.standard,
        ),
        onPressed: () async {
          final uri = Uri.parse(releasesUrl);
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        icon: const Icon(Icons.open_in_new),
        label: const Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
        ),
      ),
    );
  }
}

/// Error card
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.theme,
    required this.error,
    required this.onRecheck,
  });

  final AppThemeData theme;
  final String error;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    return _UpdateStateCardShell(
      theme: theme,
      color: Colors.red,
      leading: const Icon(Icons.error, color: Colors.red, size: 32),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Update Check Failed',
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(error, style: TextStyle(color: theme.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: onRecheck,
            icon: const Icon(Icons.refresh),
            tooltip: 'Recheck',
          ),
        ],
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
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => _SkippedVersionsDialog(theme: theme),
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
class _SkippedVersionsDialog extends ConsumerWidget {
  const _SkippedVersionsDialog({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skipped = ref.watch(
      updatesSettingsProvider.select((s) => s.skippedVersions),
    );
    final notifier = ref.read(updateProvider.notifier);

    return ThemedAlertDialog(
      theme: theme,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        side: BorderSide(color: theme.border),
      ),
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
                      trailing: TextButton(
                        onPressed: () async {
                          await notifier.unskipVersion(version);
                        },
                        child: Text(
                          'Unskip',
                          style: TextStyle(color: theme.accent),
                        ),
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
            child: Text(
              'Clear All',
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Changelog / Version Switcher
// =============================================================================

/// Always-visible changelog section listing all GitHub releases.
class _ChangelogSection extends ConsumerWidget {
  const _ChangelogSection({
    super.key,
    required this.theme,
    required this.releases,
  });

  final AppThemeData theme;
  final List<GitHubRelease> releases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sortedReleases = [...releases]
      ..sort(
        (a, b) => ref
            .read(updateProvider.notifier)
            .compareVersions(b.version, a.version),
      );

    return LayoutBuilder(
      builder: (context, constraints) {
        final useCompactReleasesLink = constraints.maxWidth < 780;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.article, color: theme.accent),
                const SizedBox(width: 6),
                Text(
                  'Changelog',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _ReleasesLinkButton(
                      theme: theme,
                      compact: useCompactReleasesLink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: kElementVSpacing),
            Container(
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(theme.cornerRadius * 1.5),
                border: Border.all(color: theme.border),
              ),
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(theme.cornerRadius),
                child: Column(
                  children: [
                    for (int i = 0; i < sortedReleases.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: theme.border),
                      _ReleaseEntryCard(theme: theme, release: sortedReleases[i]),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A single release entry inside the changelog with expandable notes and
/// an install / downgrade / current action button.
class _ReleaseEntryCard extends ConsumerStatefulWidget {
  const _ReleaseEntryCard({
    required this.theme,
    required this.release,
  });

  final AppThemeData theme;
  final GitHubRelease release;

  @override
  ConsumerState<_ReleaseEntryCard> createState() => _ReleaseEntryCardState();
}

class _ReleaseEntryCardState extends ConsumerState<_ReleaseEntryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    final theme = widget.theme;
    final updateState = ref.watch(updateProvider);
    final skippedVersions = ref.watch(
      updatesSettingsProvider.select((settings) => settings.skippedVersions),
    );
    final notifier = ref.read(updateProvider.notifier);

    // Determine the current running version from the single source of truth.
    const currentVersion = kAppVersion;
    final cmp = notifier.compareVersions(release.version, currentVersion);
    final isCurrent = cmp == 0;
    final isNewer = cmp > 0;

    final isDownloading =
        updateState.isDownloading &&
        updateState.switchingToVersion == release.version;
    final isOtherDownloading =
        updateState.isDownloading &&
        updateState.switchingToVersion != release.version;
    final isSkipped = skippedVersions.contains(release.version);
    final canInstallRelease =
        !isOtherDownloading && release.downloadUrl != null;

    final dateFormatted = DateFormat('yyyy-MM-dd').format(release.publishedAt);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(theme.cornerRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              child: Row(
                children: [
                  // Version label
                  Text(
                    'UniKM V${release.version}',
                    style: TextStyle(
                      color: isCurrent
                          ? theme.accent
                          : isNewer
                          ? theme.textPrimary
                          : theme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: kElementHSpacing),

                  // Pre-release indicator
                  if (release.isPrerelease) ...[
                    Tooltip(
                      message: 'Pre-release',
                      child: Icon(
                        Icons.science,
                        color: Colors.orange,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: kElementHSpacing),
                  ],

                  const Spacer(),

                  // Action button
                  if (isCurrent)
                    IconButton(
                      icon: Icon(Icons.check_circle, color: theme.accent),
                      onPressed: null,
                      tooltip: 'Current version',
                    )
                  else if (isSkipped)
                    IconButton(
                      icon: Icon(Icons.block, color: theme.textSecondary),
                      onPressed: null,
                      tooltip: 'Skipped version',
                    )
                  else if (isDownloading)
                    IconButton(
                      icon: const SizedBox(
                        width: 20,
                        height: 20,
                        child: AppCircularProgressIndicator(),
                      ),
                      onPressed: null,
                      tooltip: 'Downloading...',
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.download),
                      onPressed: canInstallRelease
                          ? () => notifier.switchToVersion(release)
                          : null,
                      tooltip: release.downloadUrl == null
                          ? 'Installer file not found'
                          : 'Download',
                    ),

                  const SizedBox(width: 12),

                  // Date
                  Text(
                    dateFormatted,
                    style: TextStyle(color: theme.textSecondary, fontSize: 11),
                  ),

                  const SizedBox(width: kElementHSpacing),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.textSecondary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),

          // Expanded release notes
          if (_expanded && release.body.trim().isNotEmpty)
            _ReleaseNotesPanel(
              theme: theme,
              data: release.body,
            ),
        ],
      ),
    );
  }
}
