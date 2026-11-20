/// Update status, downloads and release notes, opened from the Updates
/// navigation button.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/application/update_controller.dart';
import '../../core/constants/app_constants.dart';
import '../widgets/app_scrollbar.dart';
import '../../core/services/update_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../providers/app_providers.dart';
import '../widgets/app_progress_indicator.dart';
import '../widgets/dialog_helpers.dart';
import '../pages/settings_sections/settings_control_cards.dart';
import '../widgets/segmented_bar.dart';
import '../widgets/tinted_card.dart';
import '../widgets/update_status_icons.dart';

Future<void> showUpdateDialog(BuildContext context) =>
    showAppDialog<void>(context: context, builder: (_) => const UpdateDialog());

Future<void> _openExternal(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

class const UpdateDialog({super.key}) extends ConsumerWidget {
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

    Widget titleAction(
      String tooltip,
      Widget icon,
      VoidCallback? onPressed, {
      Key? key,
    }) => IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      color: theme.accent,
      icon: icon,
    );
    Widget action(
      String label,
      IconData icon,
      VoidCallback? onPressed, {
      bool primary = false,
    }) => primary
        ? ElevatedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          );

    return ThemedAlertDialog(
      maxWidth: 560,
      title: DialogHeader(icon: Icons.system_update_alt, title: 'Updates'),
      titleActions: [
        // A check would replace the release being downloaded or installed.
        if (!state.isDownloading && state.downloadedFilePath == null)
          titleAction(
            key: const ValueKey('update-check-button'),
            state.isChecking
                ? 'Checking for updates'
                : state.hasChecked
                ? 'Recheck Updates'
                : 'Check for Updates',
            const Icon(Icons.refresh),
            state.isChecking ? null : notifier.checkForUpdates,
          ),
        if (skipped > 0)
          titleAction(
            'Skipped Versions',
            Badge.count(
              count: skipped,
              backgroundColor: theme.accent,
              textColor: theme.onAccentText,
              child: const Icon(Icons.block),
            ),
            () => showAppDialog<void>(
              context: context,
              builder: (_) => const SkippedVersionsDialog(),
            ),
          ),
        titleAction(
          'GitHub Releases',
          const Icon(Icons.open_in_new),
          () => _openExternal(Uri.parse('https://github.com/$repo/releases')),
        ),
      ],
      contentSpacing: 12,
      contentChildren: [
        // Sets the notes apart from the title bar, as far as below it.
        _ReleaseNotes(
          releases: state.allReleases,
          updateRelease: state.hasUpdate ? state.release : null,
        ),
        // Next to the buttons that act on it.
        _StatusCard(state: state),
      ],
      // The next step for the update, like any dialog's buttons.
      actions: switch (state.stage) {
        UpdatePreviewState.updateAvailable => [
          action('Skip version', Icons.block, notifier.skipVersion),
          Tooltip(
            message: state.downloadUrl == null
                ? 'Installer file not found'
                : 'Download this release',
            child: action(
              'Download',
              Icons.download,
              state.downloadUrl == null ? null : notifier.downloadUpdate,
              primary: true,
            ),
          ),
        ],
        UpdatePreviewState.downloading => [
          action('Cancel download', Icons.close, notifier.cancelDownload),
        ],
        UpdatePreviewState.downloaded => [
          if (!Platform.isAndroid && !Platform.isIOS)
            action(
              'Show in Folder',
              Icons.folder_open,
              () => _showInFolder(state.downloadedFilePath!),
            ),
          action(
            'Install & Restart',
            Icons.install_desktop,
            notifier.launchInstaller,
            primary: true,
          ),
        ],
        _ => null,
      },
    );
  }
}

/// What the update is doing, tinted by its outcome: an icon, the versions
/// involved, the download size and, while downloading, its progress.
class const _StatusCard({required final UpdateState state})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
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
    final target = switch (stage) {
      UpdatePreviewState.updateAvailable ||
      UpdatePreviewState.downloading ||
      UpdatePreviewState.downloaded =>
        state.switchingToVersion ?? state.latestVersion,
      _ => null,
    };
    final detail = TintedCard.detailStyle(theme, large: true);
    final progress = state.downloadProgress.clamp(0.0, 1.0);
    // The bar's bubbles give the sizes while downloading.
    final size = stage == UpdatePreviewState.updateAvailable
        ? state.downloadSize
        : null;

    return TintedCard(
      key: const ValueKey('update-status-card'),
      size: TintedCardSize.large,
      liveRegion: true,
      color: color,
      icon: icon,
      busy: downloading || stage == UpdatePreviewState.checking,
      title: title,
      details: failed
          ? SelectableText(
              state.error!,
              style: TextStyle(color: color, fontSize: 12),
            )
          : target != null
          ? Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'v$target'),
                  if (size != null) TextSpan(text: '  ·  $size', style: detail),
                  if (state.isPrerelease)
                    TextSpan(
                      text: '  ·  Pre-release',
                      style: detail.copyWith(color: theme.secondary),
                    ),
                ],
              ),
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            )
          : Text('Installed v$kAppVersion', style: detail),
      figure: downloading ? '${(progress * 100).round()}%' : null,
      children: [
        if (downloading)
          SegmentedBar(
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
                  count: math.max(0, state.totalBytes - state.downloadedBytes),
                  color: theme.accent.withValues(alpha: 0.25),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

/// Dialog that lists all skipped versions with unskip controls.
class const SkippedVersionsDialog({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.appTheme;
    final skipped = ref.watch(
      updatesSettingsProvider.select((s) => s.skippedVersions),
    );
    final notifier = ref.read(updateProvider.notifier);

    return ThemedAlertDialog(
      maxWidth: kCompactDialogWidth,
      title: DialogHeader(icon: Icons.block, title: 'Skipped Versions'),
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
                        onPressed: () => notifier.unskipVersion(version),
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
            child: const Text('Clear All'),
          ),
      ],
    );
  }
}

/// One release's notes at a time, picked from every known release, with
/// the installer for each.
class const _ReleaseNotes({
  required final List<GitHubRelease> releases,
  final GitHubRelease? updateRelease,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ReleaseNotes> createState() => _ReleaseNotesState();
}

class _ReleaseNotesState extends ConsumerState<_ReleaseNotes> {
  late String? _selectedTag = widget.updateRelease?.tagName;

  /// The selected release, while it is checked again.
  String? _checkingTag;

  List<GitHubRelease> get _releases => [
    ...widget.releases,
    if (widget.updateRelease case final update?
        when !widget.releases.any((r) => r.tagName == update.tagName))
      update,
  ];

  /// Checks [tag]'s release again, so the download button matches it.
  Future<void> _recheck(String tag) async {
    setState(() => _checkingTag = tag);
    await ref.read(updateProvider.notifier).refreshRelease(tag);
    if (mounted && _checkingTag == tag) setState(() => _checkingTag = null);
  }

  @override
  void didUpdateWidget(covariant _ReleaseNotes oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A newly detected update is shown; a release that has gone falls back
    // to the newest.
    final detectedTag = widget.updateRelease?.tagName;
    if (detectedTag != null &&
        detectedTag != oldWidget.updateRelease?.tagName) {
      _selectedTag = detectedTag;
    } else if (!_releases.any((r) => r.tagName == _selectedTag)) {
      _selectedTag = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final notifier = ref.read(updateProvider.notifier);
    final releases = _releases
      ..sort((a, b) => notifier.compareVersions(b.version, a.version));
    if (releases.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.accent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(theme.cornerRadius),
        ),
        child: Text(
          'Release notes will appear after checking for updates.',
          style: TextStyle(color: theme.textSecondary),
        ),
      );
    }
    final release = releases.firstWhere(
      (r) => r.tagName == _selectedTag,
      orElse: () => releases.first,
    );
    final updateState = ref.watch(updateProvider);
    final isCurrent =
        notifier.compareVersions(release.version, kAppVersion) == 0;
    final isSkipped = ref
        .watch(updatesSettingsProvider)
        .skippedVersions
        .contains(release.version);
    final isDownloading =
        updateState.isDownloading &&
        updateState.switchingToVersion == release.version;
    final isChecking = _checkingTag == release.tagName;
    final canDownload =
        !isChecking &&
        !isCurrent &&
        !isSkipped &&
        !updateState.isDownloading &&
        release.downloadUrl != null;
    final (tooltip, icon) = isCurrent
        ? ('Current version', Icons.check_circle)
        : isSkipped
        ? ('Skipped version', Icons.block)
        : isDownloading
        ? ('Downloading...', Icons.download)
        : isChecking
        ? ('Checking availability...', Icons.download)
        : release.downloadUrl == null
        ? ('Installer file not found', Icons.download)
        : ('Download', Icons.download);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        Row(
          spacing: 5,
          children: [
            Expanded(
              child: SettingsChoiceCard<String>(
                key: const ValueKey('changelog-version-selector'),
                label: 'Selected Version',
                menuMaxHeight: kDropdownMenuMaxHeight * 2,
                value: release.tagName,
                choices: [
                  for (final item in releases)
                    SettingsChoice(item.tagName, 'v${item.version}'),
                ],
                onChanged: (tag) {
                  if (tag == release.tagName) return;
                  setState(() => _selectedTag = tag);
                  _recheck(tag);
                },
              ),
            ),
            IconButton(
              tooltip: tooltip,
              style: theme.compactIconButtonStyle,
              // On the button rather than the icon, so it dims when there
              // is nothing to download.
              color: theme.accent,
              onPressed: canDownload
                  ? () => notifier.switchToVersion(release)
                  : null,
              icon: isDownloading || isChecking
                  ? const AppCircularProgressIndicator(size: 20)
                  : Icon(icon),
            ),
          ],
        ),
        // Each release opens at the top of its own notes.
        _NotesPanel(
          key: ValueKey(release.tagName),
          body: release.body,
          header: [
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
                    if (release.isPrerelease) ('Pre-release', theme.secondary),
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
              style: TextStyle(color: theme.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

/// A release's notes under their [header], scrolling within a share of the
/// window and shrinking to short notes.
///
/// They open with only the part in view, so a long changelog opens without
/// a stall. Once the dialog has opened, the rest is laid out a slice per
/// frame, so the scrollbar soon knows their full height instead of
/// estimating it from the blocks seen so far.
class const _NotesPanel({
  super.key,
  required final List<Widget> header,
  required final String body,
}) extends StatefulWidget {
  @override
  State<_NotesPanel> createState() => _NotesPanelState();
}

class _NotesPanelState extends State<_NotesPanel> {
  final _controller = ScrollController();

  /// How far past the view the notes are laid out.
  double _cacheExtent = 250;

  @override
  void initState() {
    super.initState();
    _layOutMore();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Lays out another slice after this frame, until all of the notes are.
  /// Nothing more is laid out while the dialog is still opening.
  void _layOutMore() => WidgetsBinding.instance
    ..addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final position = _controller.position;
      final opening = ModalRoute.of(context)?.animation?.isCompleted == false;
      if (!opening) {
        if (_cacheExtent >=
            position.maxScrollExtent + position.viewportDimension) {
          return;
        }
        setState(() => _cacheExtent += 2000);
      }
      _layOutMore();
    })
    ..scheduleFrame();

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    TextStyle text(double size, {bool bold = false, Color? color}) => TextStyle(
      color: color ?? theme.textPrimary,
      fontSize: size,
      fontWeight: bold ? FontWeight.bold : null,
    );
    return Container(
      key: const ValueKey('changelog-info-panel'),
      constraints: BoxConstraints(
        maxHeight: math.max(160, MediaQuery.sizeOf(context).height * 0.35),
      ),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        border: Border.all(color: theme.border),
      ),
      child: AppScrollbar(
        controller: _controller,
        thumbVisibility: true,
        child: CustomScrollView(
          key: const ValueKey('changelog-info-scroll'),
          controller: _controller,
          primary: false,
          shrinkWrap: true,
          scrollCacheExtent: ScrollCacheExtent.pixels(_cacheExtent),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 6,
                  children: [
                    ...widget.header,
                    Divider(height: 8, color: theme.border),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              sliver: _SliverMarkdown(
                data: widget.body.trim().isEmpty
                    ? 'No release notes were provided for this version.'
                    : widget.body,
                styleSheet: MarkdownStyleSheet(
                  p: text(13),
                  h1: text(16, bold: true),
                  h2: text(14, bold: true),
                  h3: text(13, bold: true),
                  h4: text(14, bold: true, color: theme.accent),
                  h5: text(13, bold: true, color: theme.accent),
                  h6: text(13, bold: true, color: theme.accent),
                  code: text(
                    12,
                    color: theme.accent,
                  ).copyWith(fontFamily: 'monospace'),
                  blockquote: text(13, color: theme.textSecondary),
                  listBullet: text(13),
                ),
                onTapLink: (_, href, _) async {
                  final uri = Uri.tryParse(href ?? '');
                  if (uri != null &&
                      (uri.scheme == 'https' || uri.scheme == 'http')) {
                    await _openExternal(uri);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Markdown as a sliver list, so only the blocks in view are built and laid
/// out. Each block keeps its own width, as in [MarkdownBody].
class const _SliverMarkdown({
  required super.data,
  super.styleSheet,
  super.onTapLink,
}) extends MarkdownWidget {
  this : super(styleSheetTheme: null, fitContent: true);

  @override
  Widget build(BuildContext context, List<Widget>? children) => SliverList.list(
    children: [
      for (final child in children ?? const <Widget>[])
        Align(alignment: AlignmentDirectional.centerStart, child: child),
    ],
  );
}
