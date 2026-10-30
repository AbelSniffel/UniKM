/// Update status, downloads and release notes, opened from the Updates
/// navigation button.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/application/update_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/update_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../providers/app_providers.dart';
import '../widgets/app_combo_box.dart';
import '../widgets/app_progress_indicator.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/segmented_bar.dart';
import '../widgets/update_status_icons.dart';

Future<void> showUpdateDialog(BuildContext context) =>
    showAppDialog<void>(context: context, builder: (_) => const UpdateDialog());

class UpdateDialog extends ConsumerWidget {
  const UpdateDialog({super.key});

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
    final theme = ref.watch(themeProvider);
    final state = ref.watch(updateProvider);
    final notifier = ref.read(updateProvider.notifier);
    final customRepo = ref.watch(
      updatesSettingsProvider.select((s) => s.updateRepo),
    );
    final repo = customRepo.isNotEmpty ? customRepo : kGitHubRepo;
    final skipped = ref.watch(
      updatesSettingsProvider.select((s) => s.skippedVersions.length),
    );
    final stage = state.stage;

    return ThemedAlertDialog(
      theme: theme,
      maxWidth: 560,
      title: DialogHeader(
        icon: Icons.system_update_alt,
        title: 'Updates',
        theme: theme,
      ),
      titleActions: [
        // A check would replace the release being downloaded or installed.
        if (!state.isDownloading && state.downloadedFilePath == null)
          IconButton(
            key: const ValueKey('update-check-button'),
            tooltip: state.isChecking
                ? 'Checking for updates'
                : state.hasChecked
                ? 'Recheck Updates'
                : 'Check for Updates',
            onPressed: state.isChecking ? null : notifier.checkForUpdates,
            icon: const Icon(Icons.refresh),
          ),
        if (skipped > 0)
          IconButton(
            tooltip: 'Skipped Versions',
            onPressed: () => showAppDialog<void>(
              context: context,
              builder: (_) => SkippedVersionsDialog(theme: theme),
            ),
            icon: Badge.count(
              count: skipped,
              backgroundColor: theme.accent,
              textColor: theme.accent.computeLuminance() > 0.3
                  ? Colors.black
                  : Colors.white,
              child: const Icon(Icons.block),
            ),
          ),
        IconButton(
          tooltip: 'GitHub Releases',
          icon: const Icon(Icons.open_in_new),
          onPressed: () => launchUrl(
            Uri.parse('https://github.com/$repo/releases'),
            mode: LaunchMode.externalApplication,
          ),
        ),
      ],
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          // Sets the notes apart from the title bar, as far as below it.
          _ReleaseNotes(
            theme: theme,
            releases: state.allReleases,
            updateRelease: state.hasUpdate ? state.release : null,
          ),
          // Next to the buttons that act on it.
          _StatusCard(theme: theme, state: state),
        ],
      ),
      // The next step for the update, like any dialog's buttons.
      actions: switch (stage) {
        UpdatePreviewState.updateAvailable => [
          OutlinedButton.icon(
            onPressed: notifier.skipVersion,
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
                  : notifier.downloadUpdate,
              icon: const Icon(Icons.download),
              label: const Text('Download'),
            ),
          ),
        ],
        UpdatePreviewState.downloading => [
          OutlinedButton.icon(
            onPressed: notifier.cancelDownload,
            icon: const Icon(Icons.close),
            label: const Text('Cancel download'),
          ),
        ],
        UpdatePreviewState.downloaded => [
          if (!Platform.isAndroid && !Platform.isIOS)
            OutlinedButton.icon(
              onPressed: () => _showInFolder(state.downloadedFilePath!),
              icon: const Icon(Icons.folder_open),
              label: const Text('Show in Folder'),
            ),
          ElevatedButton.icon(
            onPressed: notifier.launchInstaller,
            icon: const Icon(Icons.install_desktop),
            label: const Text('Install & Restart'),
          ),
        ],
        _ => null,
      },
    );
  }
}

/// What the update is doing, tinted by its outcome: an icon, the versions
/// involved, the download size and, while downloading, its progress.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.theme, required this.state});

  final AppThemeData theme;
  final UpdateState state;

  @override
  Widget build(BuildContext context) {
    final stage = state.stage;
    final failed = stage == UpdatePreviewState.error;
    final downloading = stage == UpdatePreviewState.downloading;
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
        'Downloading',
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
    final target =
        {
          UpdatePreviewState.updateAvailable,
          UpdatePreviewState.downloading,
          UpdatePreviewState.downloaded,
        }.contains(stage)
        ? state.switchingToVersion ?? state.latestVersion
        : null;
    final detail = TextStyle(
      color: theme.textSecondary,
      fontWeight: FontWeight.w400,
    );
    final progress = state.downloadProgress.clamp(0.0, 1.0);
    // The bar's bubbles give the sizes while downloading.
    final size = stage == UpdatePreviewState.updateAvailable
        ? state.downloadSize
        : null;

    return Container(
      key: const ValueKey('update-status-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(theme.cornerRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          Row(
            spacing: 14,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(theme.cornerRadius),
                ),
                child: Center(
                  child: downloading || stage == UpdatePreviewState.checking
                      ? AppCircularProgressIndicator(size: 24, color: color)
                      : Icon(icon, color: color, size: 28),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Semantics(
                      liveRegion: true,
                      header: true,
                      child: Text(
                        title,
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (failed)
                      SelectableText(
                        state.error!,
                        style: TextStyle(color: color, fontSize: 12),
                      )
                    else if (target != null)
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: 'v$kAppVersion'),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  color: color,
                                  size: 16,
                                ),
                              ),
                            ),
                            TextSpan(text: 'v$target'),
                            if (size != null)
                              TextSpan(text: '  ·  $size', style: detail),
                            if (state.isPrerelease)
                              TextSpan(
                                text: '  ·  Pre-release',
                                style: detail.copyWith(color: theme.secondary),
                              ),
                          ],
                        ),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Text('Installed v$kAppVersion', style: detail),
                  ],
                ),
              ),
              // As large as the stats tiles' numbers.
              if (downloading)
                Text(
                  '${(progress * 100).round()}%',
                  style: TextStyle(
                    color: color,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          if (downloading)
            SegmentedBar(
              theme: theme,
              formatCount: formatFileSize,
              // One fill growing over its track, like a progress bar.
              gap: 0,
              // Unknown sizes show an empty track.
              segments: [
                if (state.totalBytes > 0) ...[
                  (
                    label: 'Downloaded',
                    count: state.downloadedBytes,
                    color: theme.accent,
                  ),
                  (
                    label: 'Remaining',
                    count: math.max(
                      0,
                      state.totalBytes - state.downloadedBytes,
                    ),
                    color: theme.accent.withValues(alpha: 0.25),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

MarkdownStyleSheet _releaseMarkdownStyleSheet(AppThemeData theme) {
  TextStyle heading(double fontSize) => TextStyle(
    color: theme.textPrimary,
    fontSize: fontSize,
    fontWeight: FontWeight.bold,
  );
  return MarkdownStyleSheet(
    p: TextStyle(color: theme.textPrimary, fontSize: 13),
    h1: heading(16),
    h2: heading(14),
    h3: heading(13),
    code: TextStyle(color: theme.accent, fontFamily: 'monospace', fontSize: 12),
    blockquote: TextStyle(color: theme.textSecondary, fontSize: 13),
    listBullet: TextStyle(color: theme.textPrimary, fontSize: 13),
  );
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
                        onPressed: () async =>
                            await notifier.unskipVersion(version),
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

/// One release's notes at a time, picked from every known release, with
/// the installer for each.
class _ReleaseNotes extends ConsumerStatefulWidget {
  const _ReleaseNotes({
    required this.theme,
    required this.releases,
    this.updateRelease,
  });

  final AppThemeData theme;
  final List<GitHubRelease> releases;
  final GitHubRelease? updateRelease;

  @override
  ConsumerState<_ReleaseNotes> createState() => _ReleaseNotesState();
}

class _ReleaseNotesState extends ConsumerState<_ReleaseNotes> {
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
  void didUpdateWidget(covariant _ReleaseNotes oldWidget) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        if (release == null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(theme.cornerRadius),
            ),
            child: Text(
              'Release notes will appear after checking for updates.',
              style: TextStyle(color: theme.textSecondary),
            ),
          )
        else ...[
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: AppComboBox<String>(
                  key: const ValueKey('changelog-version-selector'),
                  menuMaxHeight: kDropdownMenuMaxHeight * 2,
                  initialValue: release.tagName,
                  decoration: const InputDecoration(labelText: 'Version'),
                  theme: theme,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium!.copyWith(color: theme.textPrimary),
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
                    ? const AppCircularProgressIndicator(size: 20)
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
          Container(
            key: const ValueKey('changelog-info-panel'),
            // The notes scroll inside a share of the window, below the
            // status and picker.
            constraints: BoxConstraints(
              maxHeight: math.max(
                160,
                MediaQuery.sizeOf(context).height * 0.35,
              ),
            ),
            decoration: BoxDecoration(
              color: theme.surface,
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
                  spacing: 6,
                  children: [
                    Text(
                      release.name.trim().isEmpty
                          ? 'UniKM v${release.version}'
                          : release.name,
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    // The date, then how this release relates to the app.
                    Text.rich(
                      TextSpan(
                        text: DateFormat.yMMMd().format(release.publishedAt),
                        children: [
                          for (final (label, color) in [
                            if (isCurrent) ('Installed', theme.accent),
                            if (release.isPrerelease)
                              ('Pre-release', theme.secondary),
                            if (isSkipped) ('Skipped', theme.textSecondary),
                          ]) ...[
                            const TextSpan(text: '  ·  '),
                            TextSpan(
                              text: label,
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                      style: TextStyle(
                        color: theme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    Divider(height: 8, color: theme.border),
                    MarkdownBody(
                      data: release.body.trim().isEmpty
                          ? 'No release notes were provided for this version.'
                          : release.body,
                      styleSheet: _releaseMarkdownStyleSheet(theme),
                      onTapLink: (_, href, _) async {
                        final uri = Uri.tryParse(href ?? '');
                        if (uri != null &&
                            (uri.scheme == 'https' || uri.scheme == 'http')) {
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
        ],
      ],
    );
  }
}
