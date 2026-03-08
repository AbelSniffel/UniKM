/// Update page - check for and install app updates
library;

import 'dart:async';
import 'dart:io';

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
import '../../core/utils/app_version_resolver.dart';
import '../../providers/app_providers.dart';
import '../widgets/notification_system.dart';
import '../widgets/section_groupbox.dart';

/// Update state
class UpdateState {
  const UpdateState({
    this.isChecking = false,
    this.hasChecked = false,
    this.isDownloading = false,
    this.hasUpdate = false,
    this.latestVersion,
    this.releaseNotes,
    this.downloadUrl,
    this.releaseHtmlUrl,
    this.downloadProgress = 0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.downloadSize,
    this.error,
    this.downloadedFilePath,
    this.allReleases = const [],
    this.switchingToVersion,
    this.isPrerelease = false,
  });

  final bool isChecking;
  final bool hasChecked;
  final bool isDownloading;
  final bool hasUpdate;
  final String? latestVersion;
  final String? releaseNotes;
  final String? downloadUrl;
  final String? releaseHtmlUrl;
  final double downloadProgress;
  final int downloadedBytes;
  final int totalBytes;
  final String? downloadSize;
  final String? error;
  final String? downloadedFilePath;

  /// All available releases (for changelog / version switcher).
  final List<GitHubRelease> allReleases;

  /// Version being installed via the version switcher (null = none in progress).
  final String? switchingToVersion;

  /// Whether the available update is a pre-release version.
  final bool isPrerelease;

  UpdateState copyWith({
    bool? isChecking,
    bool? hasChecked,
    bool? isDownloading,
    bool? hasUpdate,
    String? latestVersion,
    String? releaseNotes,
    String? downloadUrl,
    String? releaseHtmlUrl,
    double? downloadProgress,
    int? downloadedBytes,
    int? totalBytes,
    String? downloadSize,
    String? error,
    String? downloadedFilePath,
    List<GitHubRelease>? allReleases,
    Object? switchingToVersion = _unset,
    bool? isPrerelease,
  }) {
    return UpdateState(
      isChecking: isChecking ?? this.isChecking,
      hasChecked: hasChecked ?? this.hasChecked,
      isDownloading: isDownloading ?? this.isDownloading,
      hasUpdate: hasUpdate ?? this.hasUpdate,
      latestVersion: latestVersion ?? this.latestVersion,
      releaseNotes: releaseNotes ?? this.releaseNotes,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      releaseHtmlUrl: releaseHtmlUrl ?? this.releaseHtmlUrl,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadSize: downloadSize ?? this.downloadSize,
      error: error,
      downloadedFilePath: downloadedFilePath ?? this.downloadedFilePath,
      allReleases: allReleases ?? this.allReleases,
      switchingToVersion: switchingToVersion == _unset
          ? this.switchingToVersion
          : switchingToVersion as String?,
      isPrerelease: isPrerelease ?? this.isPrerelease,
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
          // Re-show download progress notification off-page.
          _downloadNotificationHandle?.dismiss();
          _downloadNotificationHandle = NotificationManager.instance.showHandle(
            message: 'Downloading update\u2026',
            type: NotificationType.download,
            title: 'Update Download',
            progress: state.downloadProgress,
            persistent: true,
            dedupe: false,
          );
          ref.read(pageNotificationsProvider.notifier).add(NavItem.updates);
        } else if (state.downloadedFilePath != null) {
          // Download complete but not yet installed — show install notification.
          _downloadNotificationHandle?.dismiss();
          _downloadNotificationHandle = NotificationManager.instance.showHandle(
            message: 'Update ready to install.',
            type: NotificationType.success,
            title: 'Download Complete',
            actionLabel: 'Install',
            onAction: () => launchInstaller(),
            persistent: true,
            dedupe: false,
          );
          ref.read(pageNotificationsProvider.notifier).add(NavItem.updates);
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
          latestVersion: _devPreviewRelease.version,
          releaseNotes: _devPreviewRelease.body,
          downloadUrl: _devPreviewRelease.downloadUrl,
          releaseHtmlUrl: _devPreviewRelease.htmlUrl,
          downloadSize: _devPreviewRelease.formattedSize,
          isPrerelease: _devPreviewRelease.isPrerelease,
          allReleases: cachedReleases,
        );
        break;
      case UpdatePreviewState.downloading:
        _currentRelease = _devPreviewRelease;
        state = UpdateState(
          hasChecked: true,
          hasUpdate: true,
          isDownloading: true,
          latestVersion: _devPreviewRelease.version,
          releaseNotes: _devPreviewRelease.body,
          downloadUrl: _devPreviewRelease.downloadUrl,
          releaseHtmlUrl: _devPreviewRelease.htmlUrl,
          downloadSize: _devPreviewRelease.formattedSize,
          downloadProgress: 0.64,
          downloadedBytes: 30870077,
          totalBytes: _devPreviewRelease.downloadSize ?? 48234496,
          isPrerelease: _devPreviewRelease.isPrerelease,
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
    state = state.copyWith(isChecking: true, error: null);

    try {
      final updatesSettings = ref.read(updatesSettingsProvider);
      final currentVersion = await AppVersionResolver.currentVersion();

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
        latestVersion: result.release?.version,
        releaseNotes: result.release?.body,
        downloadUrl: result.release?.downloadUrl,
        releaseHtmlUrl: result.release?.htmlUrl,
        downloadSize: result.release?.formattedSize,
        isPrerelease: result.release?.isPrerelease ?? false,
        allReleases: allReleases.isNotEmpty ? allReleases : state.allReleases,
      );

      // Fire "update available" notification when allowed by settings.
      if (result.hasUpdate && result.release != null) {
        final notifSettings = ref.read(notificationsSettingsProvider);
        if (notifSettings.updateNotifications) {
          final version = result.release!.version;
          _updateNotificationHandle?.dismiss();
          _updateNotificationHandle = NotificationManager.instance.showHandle(
            message: 'Version $version is available.',
            type: NotificationType.update,
            title: 'Update Available',
            actionLabel: 'View Update',
            onAction: () {
              ref.read(currentNavProvider.notifier).setNav(NavItem.updates);
            },
            persistent: true,
            dedupe: false,
          );
          // Pulsate only when Updates page is not currently selected.
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

    state = state.copyWith(
      isDownloading: true,
      downloadProgress: 0,
      error: null,
    );

    // Show a progress notification when the user is not already on the updates page.
    final isOnUpdatesPage = ref.read(currentNavProvider) == NavItem.updates;
    if (!isOnUpdatesPage) {
      _downloadNotificationHandle?.dismiss();
      _downloadNotificationHandle = NotificationManager.instance.showHandle(
        message: 'Downloading update\u2026',
        type: NotificationType.download,
        title: 'Update Download',
        progress: 0.0,
        persistent: true,
        dedupe: false,
      );
      ref.read(pageNotificationsProvider.notifier).add(NavItem.updates);
    }

    try {
      final filePath = await _updateService.downloadUpdate(
        _currentRelease!,
        onProgress: (received, total) {
          final progress = total > 0 ? received / total : 0.0;
          state = state.copyWith(
            downloadProgress: progress,
            downloadedBytes: received,
            totalBytes: total,
          );
          // Update off-page notification progress.
          _downloadNotificationHandle?.setProgress(progress);
        },
      );

      state = state.copyWith(
        isDownloading: false,
        downloadedFilePath: filePath,
      );

      // Convert the progress notification into an Install action notification.
      _downloadNotificationHandle?.update(
        message: 'Update ready to install.',
        type: NotificationType.success,
        title: 'Download Complete',
        clearProgress: true,
        actionLabel: 'Install',
        onAction: () => launchInstaller(),
      );
      // If no off-page notification was shown, fire a plain success toast.
      if (isOnUpdatesPage) {
        NotificationManager.instance.success('Update downloaded — ready to install.');
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
      );
    }
  }

  Future<void> launchInstaller() async {
    if (state.downloadedFilePath == null) return;

    try {
      await _updateService.launchInstaller(state.downloadedFilePath!);
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

      state = state.copyWith(hasUpdate: false, hasChecked: false);
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
    state = state.copyWith(
      switchingToVersion: release.version,
      isDownloading: true,
      downloadProgress: 0,
      error: null,
    );
    _currentRelease = release;

    try {
      final filePath = await _updateService.downloadUpdate(
        release,
        onProgress: (received, total) {
          final progress = total > 0 ? received / total : 0.0;
          state = state.copyWith(
            downloadProgress: progress,
            downloadedBytes: received,
            totalBytes: total,
          );
        },
      );

      state = state.copyWith(
        isDownloading: false,
        downloadedFilePath: filePath,
        switchingToVersion: null,
      );

      NotificationManager.instance.success(
        'Version ${release.version} downloaded. Click Install to apply.',
      );
    } on DownloadCancelledException {
      // User cancelled — state was already reset by cancelDownload().
    } catch (e) {
      state = state.copyWith(
        isDownloading: false,
        error: 'Download failed: $e',
        switchingToVersion: null,
      );
    }
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
  void initState() {
    super.initState();
    // Startup auto-check: only run if the setting is enabled, and delay 3s so
    // the app has time to fully initialise (DB load, providers, etc.) before
    // hitting the network.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = ref.read(updatesSettingsProvider);
      if (!settings.autoCheckEnabled) return;
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) ref.read(updateProvider.notifier).checkForUpdates();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final updateState = ref.watch(updateProvider);
    final showInlineStatus =
        !updateState.isChecking &&
        updateState.error == null &&
        updateState.downloadedFilePath == null &&
        !updateState.hasUpdate;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.update, size: 32, color: theme.accent),
              const SizedBox(width: 16),
              Text(
                'Software Updates',
                style: TextStyle(
                  color: theme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
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
          if (updateState.error != null)
            _ErrorCard(
              theme: theme,
              error: updateState.error!,
              onRecheck: () =>
                  ref.read(updateProvider.notifier).checkForUpdates(),
            )
          else if (updateState.downloadedFilePath != null)
            _DownloadCompleteCard(
              theme: theme,
              filePath: updateState.downloadedFilePath!,
              onInstall: () =>
                  ref.read(updateProvider.notifier).launchInstaller(),
            )
          else if (updateState.isChecking)
            _UpdateStatusCard(
              theme: theme,
              isChecking: true,
              hasChecked: updateState.hasChecked,
            )
          else if (updateState.hasUpdate)
            _UpdateAvailableCard(
              theme: theme,
              updateState: updateState,
              onDownload: () =>
                  ref.read(updateProvider.notifier).downloadUpdate(),
              onSkip: () => ref.read(updateProvider.notifier).skipVersion(),
              onViewOnGithub: () async {
                final htmlUrl = updateState.releaseHtmlUrl;
                final releasesUrl = ref
                    .read(updateProvider.notifier)
                    .releasesPageUrl;
                final url = htmlUrl ?? releasesUrl;
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            )
          else if (!showInlineStatus && !updateState.isChecking && !updateState.hasUpdate)
            _UpdateStatusCard(
              theme: theme,
              isChecking: false,
              hasChecked: updateState.hasChecked,
            ),

          // Release notes (only shown when there's an active update to display notes for,
          // and no full changelog is loaded yet)
          if (updateState.releaseNotes != null &&
              updateState.hasUpdate &&
              updateState.allReleases.isEmpty)
            SectionGroupBox(
              title: 'Release Notes',
              theme: theme,
              titleIcon: Icons.description,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: MarkdownBody(
                    data: updateState.releaseNotes!,
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(color: theme.textPrimary, fontSize: 13),
                      h1: TextStyle(color: theme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                      h2: TextStyle(color: theme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                      h3: TextStyle(color: theme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                      code: TextStyle(color: theme.accent, fontFamily: 'monospace', fontSize: 12),
                      blockquote: TextStyle(color: theme.textSecondary, fontSize: 13),
                      listBullet: TextStyle(color: theme.textPrimary, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 28),

          // Changelog (always visible when releases are available)
          if (updateState.allReleases.isNotEmpty)
            _ChangelogSection(theme: theme, releases: updateState.allReleases),


        ],
      ),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
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
        ? Padding(
            padding: const EdgeInsets.all(4),
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: theme.accent,
            ),
          )
        : Icon(
            hasChecked ? Icons.check_circle : Icons.pending_outlined,
            color: theme.accent,
            size: 32,
          );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(theme.cornerRadius * 2),
            ),
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(child: leadingIcon),
            ),
          ),
          const SizedBox(width: 16),
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
                FutureBuilder<String>(
                  future: AppVersionResolver.currentVersion(),
                  builder: (context, snapshot) {
                    final version = snapshot.data ?? AppConstants.appVersion;
                    return Text(
                      'Current version $version',
                      style: TextStyle(color: theme.textSecondary),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: isChecking
                ? null
                : () => ref.read(updateProvider.notifier).checkForUpdates(),
            icon: const Icon(Icons.refresh),
            label: const Text('Check'),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        border: Border.all(color: theme.accent.withValues(alpha: 0.3)),
      ),
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
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: Icon(Icons.new_releases, color: theme.accent, size: 32),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      updateState.isDownloading ? 'Downloading Update' : 'Update Available!',
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        FutureBuilder<String>(
                          future: AppVersionResolver.currentVersion(),
                          builder: (context, snapshot) {
                            final version =
                                snapshot.data ?? AppConstants.appVersion;
                            return Text(
                              version,
                              style: TextStyle(color: theme.textSecondary),
                            );
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(
                            Icons.arrow_forward,
                            size: 16,
                            color: theme.accent,
                          ),
                        ),
                        Text(
                          updateState.latestVersion ?? '',
                          style: TextStyle(
                            color: theme.accent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (updateState.isPrerelease) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.2),
                              borderRadius:
                                  BorderRadius.circular(theme.cornerRadius),
                              border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.5)),
                            ),
                            child: const Text(
                              'PRE-RELEASE',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (!updateState.isDownloading) ...[
                const SizedBox(width: 12),
                // moved skip button up here (previously below)
                OutlinedButton(
                  onPressed: onSkip,
                  child: const Text('Skip'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(updateProvider.notifier).checkForUpdates(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Recheck'),
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
                  style: TextStyle(
                    color: theme.textSecondary,
                    fontSize: 12,
                  ),
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
                      onPressed:
                          updateState.downloadUrl == null ? null : onDownload,
                      icon: const Icon(Icons.download),
                      label: const Text('Download'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // GitHub link moved here instead of skip
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
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(theme.cornerRadius),
                        child: LinearProgressIndicator(
                          value: updateState.downloadProgress,
                          backgroundColor: theme.surface,
                          valueColor: AlwaysStoppedAnimation(theme.primary),
                          minHeight: 32,
                        ),
                      ),
                      Text(
                        'Downloading...',
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () =>
                      ref.read(updateProvider.notifier).cancelDownload(),
                  icon: Icon(
                    Icons.cancel_outlined,
                    color: Colors.red.shade400,
                    size: 16,
                  ),
                  label: Text(
                    'Cancel',
                    style: TextStyle(color: Colors.red.shade400),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
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

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        border: Border.all(color: theme.accent.withValues(alpha: 0.3)),
      ),
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
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: Icon(Icons.download_done, color: theme.accent, size: 32),
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
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  if (Platform.isWindows) {
                    await Process.run('explorer', ['/select,', filePath]);
                  } else if (Platform.isMacOS) {
                    await Process.run('open', ['-R', filePath]);
                  } else if (Platform.isLinux) {
                    final dir = filePath.substring(0, filePath.lastIndexOf('/'));
                    await Process.run('xdg-open', [dir]);
                  }
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('Show in Folder'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small releases button shown next to the page title.
class _ReleasesLinkButton extends ConsumerWidget {
  const _ReleasesLinkButton({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updatesSettings = ref.watch(updatesSettingsProvider);
    final customRepo = updatesSettings.updateRepo;
    final repo = customRepo.isNotEmpty ? customRepo : kGitHubRepo;
    final releasesUrl = 'https://github.com/$repo/releases';

    return TextButton.icon(
      onPressed: () async {
        final uri = Uri.parse(releasesUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      },
      icon: Icon(Icons.open_in_new),
      label: Text('https://github.com/$repo/releases'),
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
          OutlinedButton.icon(
            onPressed: onRecheck,
            icon: const Icon(Icons.refresh),
            label: const Text('Recheck'),
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

    return AlertDialog(
      backgroundColor: theme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        side: BorderSide(color: theme.border),
      ),
      title: Row(
        children: [
          Icon(Icons.block, color: theme.accent),
          const SizedBox(width: 12),
          Text('Skipped Versions', style: TextStyle(color: theme.textPrimary)),
        ],
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
                      leading: Icon(Icons.commit, color: theme.textSecondary, size: 18),
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
          TextButton(
            onPressed: () async {
              await notifier.clearAllSkippedVersions();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text(
              'Clear All',
              style: TextStyle(color: Colors.red.shade400),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close', style: TextStyle(color: theme.textSecondary)),
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
  const _ChangelogSection({required this.theme, required this.releases});

  final AppThemeData theme;
  final List<GitHubRelease> releases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.article, size: 20, color:theme.accent),
            const SizedBox(width: 6),
            Text(
              'Changelog',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            _ReleasesLinkButton(theme: theme),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(theme.cornerRadius),
            border: Border.all(color: theme.border),
          ),
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(theme.cornerRadius),
            child: Column(
              children: [
                for (int i = 0; i < releases.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: theme.border),
                  _ReleaseEntryCard(
                    theme: theme,
                    release: releases[i],
                    isFirst: i == 0,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A single release entry inside the changelog with expandable notes and
/// an install / downgrade / current action button.
class _ReleaseEntryCard extends ConsumerStatefulWidget {
  const _ReleaseEntryCard({
    required this.theme,
    required this.release,
    required this.isFirst,
  });

  final AppThemeData theme;
  final GitHubRelease release;
  final bool isFirst;

  @override
  ConsumerState<_ReleaseEntryCard> createState() => _ReleaseEntryCardState();
}

class _ReleaseEntryCardState extends ConsumerState<_ReleaseEntryCard> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // Auto-expand is deferred to didChangeDependencies so it only fires once
    // the UpdatePage is actually visible (TickerMode enabled).  Building
    // MarkdownBody while the page is hidden in the IndexedStack causes a
    // noticeable main-thread freeze on boot.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Auto-expand the first (most recent) entry only when the page is visible.
    // TickerMode is false for pages hidden by IndexedStack, so this defers the
    // expensive MarkdownBody render until the user actually opens Updates.
    if (widget.isFirst && TickerMode.valuesOf(context).enabled && !_expanded) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    final theme = widget.theme;
    final updateState = ref.watch(updateProvider);
    final notifier = ref.read(updateProvider.notifier);

    // Determine the current running version asynchronously — we compare eagerly
    // to kAppVersion as a heuristic since AppVersionResolver just returns the constant.
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
                    'v${release.version}',
                    style: TextStyle(
                      color: isCurrent
                          ? Colors.green
                          : isNewer
                          ? theme.accent
                          : theme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Pre-release badge
                  if (release.isPrerelease) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(theme.cornerRadius),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Text(
                        'PRE-RELEASE',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Release name
                  Expanded(
                    child: Text(
                      release.name.isNotEmpty ? release.name : 'v${release.version}',
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Date
                  Text(
                    dateFormatted,
                    style: TextStyle(color: theme.textSecondary, fontSize: 11),
                  ),

                  const SizedBox(width: 12),

                  // Action button
                  if (isCurrent)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Current',
                        style: TextStyle(color: Colors.green, fontSize: 12),
                      ),
                    )
                  else if (isDownloading)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.accent,
                      ),
                    )
                  else
                    SizedBox(
                      height: 28,
                      child: Tooltip(
                        message: release.downloadUrl == null
                            ? 'Installer file not found'
                            : '',
                        child: OutlinedButton(
                          onPressed: isOtherDownloading ||
                                  release.downloadUrl == null ? null : () => notifier.switchToVersion(release),
                          child: Text(isNewer ? 'Install' : 'Downgrade'),
                        ),
                      ),
                    ),

                  const SizedBox(width: 8),
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
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.background.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(theme.cornerRadius/1.5),
                border: Border.all(color: theme.border),
              ),
              child: MarkdownBody(
                data: release.body,
                styleSheet: MarkdownStyleSheet(
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
                  blockquote: TextStyle(
                    color: theme.textSecondary,
                    fontSize: 13,
                  ),
                  listBullet: TextStyle(color: theme.textPrimary, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
