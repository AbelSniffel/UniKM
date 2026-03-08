/// Update service for checking and downloading app updates from GitHub
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  const UpdateCheckResult({
    required this.hasUpdate,
    this.release,
    this.error,
  });

  final bool hasUpdate;
  final GitHubRelease? release;
  final String? error;

  bool get isError => error != null;
}

/// Download progress callback
typedef DownloadProgressCallback = void Function(int received, int total);

/// Update service for checking and downloading GitHub releases
class UpdateService {
  UpdateService({
    String? customRepo,
    String? githubToken,
  })  : _repo = customRepo ?? kGitHubRepo,
        _githubToken = githubToken;

  final String _repo;
  final String? _githubToken;

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

  /// Get the releases page URL
  String get releasesPageUrl => 'https://github.com/$_repo/releases';

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
      // Always fetch all releases so we can walk past skipped entries and
      // correctly respect the pre-release filter regardless of what the
      // "latest" stable release endpoint happens to return.
      final response = await http.get(
        Uri.parse(_allReleasesUrl),
        headers: _headers,
      );

      if (response.statusCode != 200) {
        return UpdateCheckResult(
          hasUpdate: false,
          error: 'Failed to check for updates: ${response.statusCode}',
        );
      }

      final releases = jsonDecode(response.body) as List<dynamic>;
      if (releases.isEmpty) {
        return const UpdateCheckResult(hasUpdate: false);
      }

      // Walk releases (newest first) to find the best candidate.
      for (final raw in releases) {
        final release = GitHubRelease.fromJson(raw as Map<String, dynamic>);

        // Respect the pre-release filter: skip pre-releases when toggle is off.
        if (release.isPrerelease && !includePrerelease) continue;

        // Walk past versions the user has explicitly chosen to skip.
        if (skippedVersions.contains(release.version) ||
            skippedVersions.contains(release.tagName)) {
          continue;
        }

        // Found the best candidate — check whether it is actually newer.
        final hasUpdate = _isNewerVersion(release.version, currentVersion);
        return UpdateCheckResult(hasUpdate: hasUpdate, release: release);
      }

      // Every release was filtered out (all skipped, or pre-release-only when
      // the toggle is off).
      return const UpdateCheckResult(hasUpdate: false);
    } catch (e) {
      return UpdateCheckResult(
        hasUpdate: false,
        error: 'Error checking for updates: $e',
      );
    }
  }

  /// Fetch all available releases from GitHub (for changelog/version switcher).
  /// Includes both stable and pre-release entries.
  Future<List<GitHubRelease>> fetchAllReleases() async {
    try {
      final response = await http.get(
        Uri.parse('$_allReleasesUrl?per_page=100'),
        headers: _headers,
      );

      if (response.statusCode != 200) return [];

      final list = jsonDecode(response.body) as List<dynamic>;
      return list
          .cast<Map<String, dynamic>>()
          .map(GitHubRelease.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Download
  // ---------------------------------------------------------------------------

  /// Download an update to a temporary location
  /// 
  /// Returns the path to the downloaded file.
  /// Throws [DownloadCancelledException] if [cancelActiveDownload] is called.
  Future<String> downloadUpdate(
    GitHubRelease release, {
    DownloadProgressCallback? onProgress,
  }) async {
    if (release.downloadUrl == null) {
      throw StateError('No download URL available for this release');
    }

    _downloadCancelled = false;
    final client = http.Client();
    _activeDownloadClient = client;

    // Determine destination path up-front so we can delete it on cancel.
    final urlPath = Uri.parse(release.downloadUrl!).path;
    final extension = p.extension(urlPath);
    final fileName = 'UniKM-${release.version}$extension';
    final downloadsDir = await _getDownloadsDirectory();
    final filePath = p.join(downloadsDir.path, fileName);
    final file = File(filePath);

    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(release.downloadUrl!));
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
      return filePath;
    } catch (e) {
      if (e is DownloadCancelledException) rethrow;
      // Unexpected error — clean up partial file.
      try { await sink?.close(); } catch (_) {}
      try { if (await file.exists()) await file.delete(); } catch (_) {}
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

    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        downloadsPath = p.join(userProfile, 'Downloads');
      }
    } else if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        downloadsPath = p.join(home, 'Downloads');
      }
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

  /// Launch the downloaded installer for the current platform.
  Future<void> launchInstaller(String filePath) async {
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', filePath]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [filePath]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [filePath]);
    } else {
      throw UnsupportedError('Automatic installer launch is not supported on this platform');
    }
  }

  // ---------------------------------------------------------------------------
  // Version comparison
  // ---------------------------------------------------------------------------

  /// Compare two semantic versions
  /// Returns true if [newVersion] is newer than [currentVersion]
  bool _isNewerVersion(String newVersion, String currentVersion) {
    try {
      final newParts = _parseVersion(newVersion);
      final currentParts = _parseVersion(currentVersion);

      for (var i = 0; i < 3; i++) {
        if (newParts[i] > currentParts[i]) return true;
        if (newParts[i] < currentParts[i]) return false;
      }

      return false; // Versions are equal
    } catch (e) {
      // If parsing fails, do a simple string comparison
      return newVersion.compareTo(currentVersion) > 0;
    }
  }

  /// Returns a positive value if [a] is newer, negative if older, 0 if equal.
  int compareVersions(String a, String b) {
    try {
      final aParts = _parseVersion(a);
      final bParts = _parseVersion(b);
      for (var i = 0; i < 3; i++) {
        if (aParts[i] > bParts[i]) return 1;
        if (aParts[i] < bParts[i]) return -1;
      }
      return 0;
    } catch (_) {
      return a.compareTo(b);
    }
  }

  /// Parse a semantic version string into [major, minor, patch]
  List<int> _parseVersion(String version) {
    // Remove 'v' prefix if present
    final cleanVersion = version.startsWith('v') ? version.substring(1) : version;

    // Remove any prerelease suffix (e.g., "-beta.1")
    final baseParts = cleanVersion.split('-')[0].split('.');

    final result = <int>[0, 0, 0];
    for (var i = 0; i < baseParts.length && i < 3; i++) {
      result[i] = int.tryParse(baseParts[i]) ?? 0;
    }

    return result;
  }
}

