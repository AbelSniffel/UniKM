/// Update service for checking and downloading app updates from GitHub
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/state/session_value.dart';
import '../utils/format_utils.dart';

import '../constants/app_constants.dart';

/// Thrown when an in-progress download is cancelled by the user.
class DownloadCancelledException implements Exception {
  const DownloadCancelledException();
  @override
  String toString() => 'Download cancelled';
}

/// Platform-specific installer file extensions, ordered by preference.
List<String> get _platformExtensions {
  if (Platform.isAndroid) return ['.apk'];
  if (Platform.isIOS) return ['.ipa', '.zip'];
  if (Platform.isWindows) return ['.exe', '.msi', '.zip'];
  if (Platform.isMacOS) return ['.dmg', '.pkg'];
  if (Platform.isLinux) return ['.AppImage', '.deb', '.rpm', '.tar.gz'];
  return ['.zip'];
}

/// Represents a GitHub release
class GitHubRelease {
  const GitHubRelease({
    required this.tagName,
    required this.version,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.publishedAt,
    required this.isPrerelease,
    this.downloadUrl,
    this.downloadSize,
  });

  factory GitHubRelease.fromJson(Map<String, dynamic> json) {
    String? downloadUrl;
    int? downloadSize;

    // Find the best asset for the current platform by preferred extension order.
    final assets = json['assets'] as List<dynamic>? ?? [];
    final extensions = _platformExtensions;

    for (final ext in extensions) {
      for (final asset in assets) {
        final assetName = asset['name'] as String? ?? '';
        if (assetName.toLowerCase().endsWith(ext.toLowerCase())) {
          downloadUrl = asset['browser_download_url'] as String?;
          downloadSize = asset['size'] as int?;
          break;
        }
      }
      if (downloadUrl != null) break;
    }

    final tagName = json['tag_name'] as String? ?? '';
    // Remove 'v' prefix if present for version comparison
    final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;

    return GitHubRelease(
      tagName: tagName,
      version: version,
      name: json['name'] as String? ?? tagName,
      body: json['body'] as String? ?? '',
      htmlUrl: json['html_url'] as String? ?? '',
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? '') ?? DateTime.now(),
      isPrerelease: json['prerelease'] as bool? ?? false,
      downloadUrl: downloadUrl,
      downloadSize: downloadSize,
    );
  }

  /// Reconstruct from a cached JSON map (written by [toJson]).
  factory GitHubRelease.fromCacheJson(Map<String, dynamic> json) {
    return GitHubRelease(
      tagName: json['tagName'] as String? ?? '',
      version: json['version'] as String? ?? '',
      name: json['name'] as String? ?? '',
      body: json['body'] as String? ?? '',
      htmlUrl: json['htmlUrl'] as String? ?? '',
      publishedAt: DateTime.tryParse(json['publishedAt'] as String? ?? '') ?? DateTime.now(),
      isPrerelease: json['isPrerelease'] as bool? ?? false,
      downloadUrl: json['downloadUrl'] as String?,
      downloadSize: json['downloadSize'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'tagName': tagName,
    'version': version,
    'name': name,
    'body': body,
    'htmlUrl': htmlUrl,
    'publishedAt': publishedAt.toIso8601String(),
    'isPrerelease': isPrerelease,
    if (downloadUrl != null) 'downloadUrl': downloadUrl,
    if (downloadSize != null) 'downloadSize': downloadSize,
  };

  final String tagName;
  final String version;
  final String name;
  final String body;
  final String htmlUrl;
  final DateTime publishedAt;
  final bool isPrerelease;
  final String? downloadUrl;
  final int? downloadSize;

  /// Format download size as human-readable string
  String get formattedSize => formatFileSize(downloadSize);
}

/// Result of an update check
class UpdateCheckResult {
  const UpdateCheckResult({required this.hasUpdate, this.release, this.error});

  final bool hasUpdate;
  final GitHubRelease? release;
  final String? error;

  bool get isError => error != null;
}

/// Download progress callback
typedef DownloadProgressCallback = void Function(int received, int total);

class UpdateDownloadResult {
  const UpdateDownloadResult.local(this.filePath)
    : openedExternally = false;

  const UpdateDownloadResult.external()
    : filePath = null,
      openedExternally = true;

  final String? filePath;
  final bool openedExternally;
}

/// Update service for checking and downloading GitHub releases
class UpdateService {
  UpdateService({
    String? customRepo,
    this._githubToken,
    this._githubClient,
  }) : _repo = customRepo ?? kGitHubRepo;

  final String _repo;
  final String? _githubToken;
  final http.Client? _githubClient;

  // Cancellation state for the active download.
  http.Client? _activeDownloadClient;
  bool _downloadCancelled = false;

  /// Cancel an in-progress download.
  ///
  /// Closes the active HTTP connection. The [downloadUpdate] call will throw
  /// [DownloadCancelledException] and delete the partial file.
  void cancelActiveDownload() {
    _downloadCancelled = true;
    _activeDownloadClient?.close();
    _activeDownloadClient = null;
  }

  /// Get the API URL for all releases
  String get _allReleasesUrl => 'https://api.github.com/repos/$_repo/releases';

  /// Build HTTP headers for GitHub API
  Map<String, String> get _headers {
    final headers = <String, String>{
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'UniKM-Flutter/$kAppVersion',
    };
    final token = _githubToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  String _formatCheckError(Object error) {
    final message = error.toString();
    final lowerMessage = message.toLowerCase();

    if (error is SocketException || lowerMessage.contains('socketexception')) {
      if (lowerMessage.contains('failed host lookup')) {
        return 'Unable to reach GitHub right now. Check your internet connection and DNS settings, then try again.';
      }
      return 'Unable to reach GitHub right now. Check your internet connection and try again.';
    }

    if (error is HandshakeException) {
      return 'The secure connection to GitHub failed. Check your device date, time, and network settings, then try again.';
    }

    if (lowerMessage.contains('connection refused') ||
        lowerMessage.contains('network is unreachable') ||
        lowerMessage.contains('timed out')) {
      return 'GitHub could not be reached. Check your connection and try again.';
    }

    return 'Error checking for updates: $message';
  }

  // ---------------------------------------------------------------------------
  // Cache helpers
  // ---------------------------------------------------------------------------

  /// Returns the app data directory used for caches (same folder as keys.db).
  Future<Directory> _getDataDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'UniKM'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _getCacheFile() async {
    final dir = await _getDataDir();
    return File(p.join(dir.path, 'releases_cache.json'));
  }

  /// Load previously cached releases from disk. Returns an empty list on any error.
  Future<List<GitHubRelease>> loadCachedReleases() async {
    try {
      final file = await _getCacheFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final list = jsonDecode(content) as List<dynamic>;
      return list
          .cast<Map<String, dynamic>>()
          .map(GitHubRelease.fromCacheJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Persist a list of releases to the local cache file.
  Future<void> saveReleasesCache(List<GitHubRelease> releases) async {
    try {
      final file = await _getCacheFile();
      final encoded = jsonEncode(releases.map((r) => r.toJson()).toList());
      await file.writeAsString(encoded);
    } catch (_) {
      // Non-critical â€” ignore write errors.
    }
  }

  // ---------------------------------------------------------------------------
  // Release fetching
  // ---------------------------------------------------------------------------

  /// Check for updates
  ///
  /// [currentVersion] - Current app version to compare against
  /// [includePrerelease] - Whether to include prerelease versions
  /// [skippedVersions] - List of versions the user has chosen to skip
  Future<UpdateCheckResult> checkForUpdates({
    String currentVersion = kAppVersion,
    bool includePrerelease = false,
    List<String> skippedVersions = const [],
  }) async {
    try {
      final releases = await _fetchReleases();
      if (releases.isEmpty) return const UpdateCheckResult(hasUpdate: false);

      final release = _selectBestUpdateRelease(
        releases,
        currentVersion: currentVersion,
        includePrerelease: includePrerelease,
        skippedVersions: skippedVersions,
      );

      return UpdateCheckResult(hasUpdate: release != null, release: release);
    } catch (e) {
      return UpdateCheckResult(hasUpdate: false, error: _formatCheckError(e));
    }
  }

  /// Fetch all available releases from GitHub (for changelog/version switcher).
  /// Includes both stable and pre-release entries.
  Future<List<GitHubRelease>> fetchAllReleases() async {
    try {
      return await _fetchReleases();
    } catch (_) {
      return [];
    }
  }

  Future<List<GitHubRelease>> _fetchReleases() async {
    final client = _githubClient ?? http.Client();
    try {
      final response = await client.get(
        Uri.parse('$_allReleasesUrl?per_page=100'),
        headers: _headers,
      );

      if (response.statusCode != 200) {
        throw HttpException('Failed to fetch releases: ${response.statusCode}');
      }

      final list = jsonDecode(response.body) as List<dynamic>;
      return list
          .cast<Map<String, dynamic>>()
          .map(GitHubRelease.fromJson)
          .toList();
    } finally {
      if (_githubClient == null) client.close();
    }
  }

  GitHubRelease? _selectBestUpdateRelease(
    List<GitHubRelease> releases, {
    required String currentVersion,
    required bool includePrerelease,
    required List<String> skippedVersions,
  }) {
    GitHubRelease? bestRelease;

    for (final release in releases) {
      if (release.isPrerelease && !includePrerelease) continue;

      if (skippedVersions.contains(release.version) ||
          skippedVersions.contains(release.tagName)) {
        continue;
      }

      if (compareVersions(release.version, currentVersion) <= 0) continue;

      if (bestRelease == null ||
          _isBetterUpdateCandidate(release, bestRelease)) {
        bestRelease = release;
      }
    }

    return bestRelease;
  }

  bool _isBetterUpdateCandidate(
    GitHubRelease candidate,
    GitHubRelease currentBest,
  ) {
    final versionComparison = compareVersions(
      candidate.version,
      currentBest.version,
    );
    if (versionComparison != 0) return versionComparison > 0;

    if (candidate.isPrerelease != currentBest.isPrerelease) {
      return !candidate.isPrerelease;
    }

    return candidate.publishedAt.isAfter(currentBest.publishedAt);
  }

  // ---------------------------------------------------------------------------
  // Download
  // ---------------------------------------------------------------------------

  /// Download an update to a temporary location
  ///
  /// Returns the path to the downloaded file.
  /// Throws [DownloadCancelledException] if [cancelActiveDownload] is called.
  Future<UpdateDownloadResult> downloadUpdate(
    GitHubRelease release, {
    DownloadProgressCallback? onProgress,
  }) async {
    if (release.downloadUrl == null) {
      throw StateError('No download URL available for this release');
    }

    // iOS cannot sideload IPAs; hand off to the browser.
    // Android uses the in-app HTTP download path below so that the user gets
    // live progress and avoids Chrome's Play-Protect scan stalling the
    // download at 100%.
    if (Platform.isIOS) {
      final launched = await launchUrl(
        Uri.parse(release.downloadUrl!),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw StateError('Unable to hand off the update download to the system downloader');
      }
      return const UpdateDownloadResult.external();
    }

    _downloadCancelled = false;
    final client = http.Client();
    _activeDownloadClient = client;

    File? file;
    IOSink? sink;
    try {
      // Include destination preparation in client cleanup if it fails.
      final url = Uri.parse(release.downloadUrl!);
      final extension = p.extension(url.path);
      final fileName = 'UniKM-${release.version}$extension';
      final downloadsDir = await _getDownloadsDirectory();
      final filePath = p.join(downloadsDir.path, fileName);
      file = File(filePath);

      final request = http.Request('GET', url);
      request.headers.addAll(_headers);

      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw HttpException('Failed to download update: ${response.statusCode}');
      }

      sink = file.openWrite();
      final totalBytes = response.contentLength ?? 0;
      var receivedBytes = 0;

      try {
        await for (final chunk in response.stream) {
          receivedBytes += chunk.length;
          sink.add(chunk);
          onProgress?.call(receivedBytes, totalBytes);
        }
      } catch (_) {
        // Stream broke — could be normal cancellation or a network error.
        if (_downloadCancelled) {
          await sink.flush();
          await sink.close();
          sink = null;
          try { await file.delete(); } catch (_) {}
          throw const DownloadCancelledException();
        }
        rethrow;
      }

      if (_downloadCancelled) {
        await sink.flush();
        await sink.close();
        sink = null;
        try { await file.delete(); } catch (_) {}
        throw const DownloadCancelledException();
      }

      await sink.close();
      sink = null;
      return UpdateDownloadResult.local(filePath);
    } catch (e) {
      if (e is DownloadCancelledException) rethrow;
      // Unexpected error — clean up partial file.
      try { await sink?.close(); } catch (_) {}
      try { if (file != null && await file.exists()) await file.delete(); } catch (_) {}
      rethrow;
    } finally {
      client.close();
      _activeDownloadClient = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Platform helpers
  // ---------------------------------------------------------------------------

  /// Get the downloads directory for the current platform.
  Future<Directory> _getDownloadsDirectory() async {
    String? downloadsPath;

    if (Platform.isAndroid) {
      // Use the app's cache directory so FileProvider can serve the APK
      // to the system package installer without needing storage permissions.
      return getTemporaryDirectory();
    }

    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) downloadsPath = p.join(userProfile, 'Downloads');
    } else if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null) downloadsPath = p.join(home, 'Downloads');
    }

    if (downloadsPath != null) {
      final dir = Directory(downloadsPath);
      if (await dir.exists()) return dir;
    }

    // Fall back to app documents directory
    final appDir = await getApplicationDocumentsDirectory();
    final downloadsDir = Directory(p.join(appDir.path, 'UniKM', 'Downloads'));
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    return downloadsDir;
  }

  void _throwIfProcessResultFailed(
    String executable,
    List<String> args,
    ProcessResult result,
  ) {
    if (result.exitCode == 0) return;

    final stderr = '${result.stderr}'.trim();
    final stdout = '${result.stdout}'.trim();
    final details = stderr.isNotEmpty
        ? stderr
        : (stdout.isNotEmpty ? stdout : 'exit code ${result.exitCode}');

    throw ProcessException(
      executable,
      args,
      'Installer launch failed: $details',
      result.exitCode,
    );
  }

  Future<void> _throwIfProcessFailsQuickly(
    String executable,
    List<String> args, {
    bool runInShell = false,
  }) async {
    final process = await Process.start(
      executable,
      args,
      runInShell: runInShell,
    );

    final earlyExitCode = await Future.any<Object?>([
      process.exitCode.then<Object?>((code) => code),
      Future<Object?>.delayed(const Duration(seconds: 2), () => null),
    ]);

    if (earlyExitCode case final int code when code != 0) {
      throw ProcessException(
        executable,
        args,
        'Installer exited with an error before the app handoff completed.',
        code,
      );
    }
  }

  /// Launch the downloaded installer for the current platform.
  ///
  /// Returns `true` when the app should close after handing control to an
  /// installer process. Returns `false` for manual packages that were only
  /// opened in the OS shell.
  Future<bool> launchInstaller(String filePath) async {
    if (Platform.isWindows) {
      final extension = p.extension(filePath).toLowerCase();

      if (extension == '.exe') {
        await _throwIfProcessFailsQuickly(filePath, const [], runInShell: true);
        return true;
      }

      if (extension == '.msi') {
        await _throwIfProcessFailsQuickly(
          'msiexec',
          ['/i', filePath],
          runInShell: true,
        );
        return true;
      }

      final args = ['/c', 'start', '', filePath];
      final result = await Process.run('cmd', args);
      _throwIfProcessResultFailed('cmd', args, result);
      return false;
    }

    if (Platform.isMacOS) {
      final args = [filePath];
      final result = await Process.run('open', args);
      _throwIfProcessResultFailed('open', args, result);
      return false;
    }

    if (Platform.isLinux) {
      final args = [filePath];
      final result = await Process.run('xdg-open', args);
      _throwIfProcessResultFailed('xdg-open', args, result);
      return false;
    }

    if (Platform.isAndroid) {
      const channel = MethodChannel('com.example.unikm/installer');
      await channel.invokeMethod<void>('installApk', {'filePath': filePath});
      return false;
    }

    throw UnsupportedError('Automatic installer launch is not supported on this platform');
  }

  // ---------------------------------------------------------------------------
  // Version comparison
  // ---------------------------------------------------------------------------

  /// Shared release precedence for update checks and the changelog. Build
  /// metadata does not identify a newer release; prerelease identifiers do.
  int compareVersions(String a, String b) {
    try {
      return _parseVersion(a).compareTo(_parseVersion(b));
    } on FormatException {
      return a.compareTo(b);
    }
  }

  Version _parseVersion(String version) {
    final clean = version
        .trim()
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split('+')
        .first;
    final suffixAt = clean.indexOf('-');
    final core = (suffixAt < 0 ? clean : clean.substring(0, suffixAt)).split(
      '.',
    );
    // Retain support for older abbreviated tags such as v1 and v1.4.
    while (core.length < 3) {
      core.add('0');
    }
    return Version.parse(
      '${core.join('.')}${suffixAt < 0 ? '' : clean.substring(suffixAt)}',
    );
  }
}

/// State for the next scheduled automatic update check.
final nextAutoUpdateTimeProvider = sessionValueProvider<DateTime?>(null);
