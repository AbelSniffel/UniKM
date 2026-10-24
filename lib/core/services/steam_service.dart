/// Steam API integration service
/// Provides functionality to search for games, fetch AppIDs, tags, images, and reviews
library;

import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../constants/app_constants.dart';
import '../database/database.dart';

import 'logging.dart';
import '../utils/title_similarity.dart';

export '../utils/title_similarity.dart'
    show cleanTitleForSearch, weightedSimilarity;

/// Steam API URLs
class SteamApi {
  static final storeSearch = steamStoreApiUrl('storesearch/');
  static const communitySearch =
      'https://steamcommunity.com/actions/SearchApps/';
  static final appDetails = steamStoreApiUrl('appdetails');
  static const steamSpy = 'https://steamspy.com/api.php';

  /// CDN URLs for images
  static String headerImage(String appId) =>
      steamCdnAppImageUrl(appId, 'header.jpg');
  static String libraryImage(String appId) =>
      steamCdnAppImageUrl(appId, 'library_600x900.jpg');
  static String appReviews(String appId) => steamStoreUrl('appreviews/$appId');
}

// cleanTitleForSearch and weightedSimilarity are now in
// package:unikm/core/utils/title_similarity.dart
// and re-exported via the import above.

/// Disk cache helpers
final _cacheKeyStripPattern = RegExp(r'[^a-z0-9]');

String _normalizeCacheKey(String title) {
  return title.toLowerCase().replaceAll(_cacheKeyStripPattern, '');
}

Future<String> _getCacheFilePath() async {
  // place cache file alongside the database instead of the platform
  // application support directory. That keeps all user data in one place
  // and makes it easier to back up or move the database folder.
  try {
    final dbPath = await AppDatabase.getDatabasePath();
    final dbDir = Directory(p.dirname(dbPath));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    return p.join(dbDir.path, 'steam_cache.json');
  } catch (_) {
    // fall back to previous behaviour if something goes wrong
    final appDir = await getApplicationSupportDirectory();
    return p.join(appDir.path, 'steam_cache.json');
  }
}

/// In-memory disk cache (loaded once, write-through updates)
class _DiskCache {
  static _DiskCache? _instance;
  static _DiskCache get instance => _instance ??= _DiskCache._();

  _DiskCache._();

  Map<String, dynamic>? _cache;
  Future<void> _writeTail = Future.value();
  int _requestedRevision = 0;
  int _savedRevision = 0;

  // Single shared Future used by all concurrent callers so we only read the
  // file once even when multiple async operations call _ensureLoaded at the
  // same time.  After the load completes, _cache is non-null and the Future
  // is kept around (the null check below makes it a no-op on re-entry).
  Future<void>? _loadFuture;

  /// Load cache from disk into memory (call once at app startup or first access)
  Future<void> _ensureLoaded() {
    if (_cache != null) return Future.value();
    // All concurrent callers share the same Future so disk is only read once.
    return _loadFuture ??= _loadFromDisk();
  }

  Future<void> _loadFromDisk() async {
    try {
      final path = await _getCacheFilePath();
      final file = File(path);
      if (await file.exists()) {
        final text = await file.readAsString();
        _cache = json.decode(text) as Map<String, dynamic>;
        return;
      }
      _cache = {};
    } catch (_) {
      _cache = {};
    }
  }

  /// Get cached result (memory-first)
  Future<SteamSearchResult?> getCachedResult(String title) async {
    await _ensureLoaded();
    final key = _normalizeCacheKey(title);
    final entry = _cache?[key] as Map<String, dynamic>?;
    if (entry == null) return null;
    return SteamSearchResult(
      appId: entry['app_id']?.toString() ?? '',
      name: entry['name']?.toString() ?? title,
      imageUrl: entry['image_url']?.toString(),
      tags:
          (entry['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      reviewScore: entry['review_score'] as int?,
      reviewCount: entry['review_count'] as int?,
      isDlc: entry['is_dlc'] as bool? ?? false,
      developer: entry['developer']?.toString(),
      searchSource: SteamSearchSource.values
          .where((source) => source.name == entry['search_source'])
          .firstOrNull,
      searchSourcesTried: SteamSearchSource.values
          .where(
            (source) =>
                (entry['search_sources_tried'] as List?)?.contains(
                  source.name,
                ) ??
                false,
          )
          .toList(),
      dataSources: SteamDataSource.values
          .where(
            (source) =>
                (entry['data_sources'] as List?)?.contains(source.name) ??
                false,
          )
          .toList(),
    );
  }

  /// Get cached timestamp
  Future<DateTime?> getCachedAt(String title) async {
    await _ensureLoaded();
    final key = _normalizeCacheKey(title);
    final entry = _cache?[key] as Map<String, dynamic>?;
    if (entry == null) return null;
    final cachedAt = entry['cached_at'];
    if (cachedAt == null) return null;
    final ms = (cachedAt is num)
        ? (cachedAt * 1000).toInt()
        : int.tryParse(cachedAt.toString()) ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Write-through: update memory and persist to disk
  Future<void> writeEntry(String key, SteamSearchResult r) async {
    await _ensureLoaded();
    final entry = {
      'app_id': r.appId,
      'name': r.name,
      'tags': r.tags,
      'review_count': r.reviewCount,
      'review_score': r.reviewScore,
      'is_dlc': r.isDlc,
      'image_url': r.imageUrl,
      'developer': r.developer,
      'search_source': r.searchSource?.name,
      'search_sources_tried': r.searchSourcesTried.map((s) => s.name).toList(),
      'data_sources': r.dataSources.map((s) => s.name).toList(),
      'cached_at': DateTime.now().millisecondsSinceEpoch / 1000.0,
    };

    _cache ??= {};
    _cache![key] = entry;

    // Also write under normalized result name key
    final keyFromName = _normalizeCacheKey(r.name);
    if (keyFromName != key) _cache![keyFromName] = entry;

    await _persist();
  }

  Future<Map<String, dynamic>> exportForSync() async {
    await _ensureLoaded();
    final source = _cache ?? const <String, dynamic>{};
    final out = <String, dynamic>{};
    for (final entry in source.entries) {
      final value = entry.value;
      if (value is Map) {
        out[entry.key] = Map<String, dynamic>.from(value);
      }
    }
    return out;
  }

  Future<void> mergeFromSync(Map<String, dynamic> incoming) async {
    await _ensureLoaded();
    _cache ??= <String, dynamic>{};

    for (final entry in incoming.entries) {
      final key = entry.key;
      final remote = entry.value;
      if (remote is! Map) continue;

      final remoteMap = Map<String, dynamic>.from(remote);
      final localExisting = _cache![key];
      final localMap = localExisting is Map
          ? Map<String, dynamic>.from(localExisting)
          : <String, dynamic>{};

      // Preserve this device's image_url while overwriting other fields.
      final localImageUrl = localMap['image_url'];
      final merged = <String, dynamic>{...remoteMap};
      if (localImageUrl != null) {
        merged['image_url'] = localImageUrl;
      } else {
        merged.remove('image_url');
      }

      _cache![key] = merged;
    }

    await _persist();
  }

  Future<void> _persist() {
    final requested = ++_requestedRevision;
    // Serialize writes to the same file. A queued write captures the newest
    // snapshot, so requests already included in it need no additional I/O.
    return _writeTail = _writeTail.then((_) async {
      if (_savedRevision >= requested) return;
      final snapshotRevision = _requestedRevision;
      try {
        final jsonStr = json.encode(_cache);
        final path = await _getCacheFilePath();
        await File(path).writeAsString(jsonStr);
        _savedRevision = snapshotRevision;
      } catch (_) {
        // Keep failed revisions pending so a later update can retry them.
        // Cache failures remain non-fatal, as before.
      }
    });
  }
}

Future<DateTime?> getCachedAtForTitle(String title) async {
  return _DiskCache.instance.getCachedAt(title);
}

Future<SteamSearchResult?> getCachedResultForTitle(String title) async {
  return _DiskCache.instance.getCachedResult(title);
}

Future<Map<String, dynamic>> exportSteamCacheSnapshotForSync() async {
  return _DiskCache.instance.exportForSync();
}

Future<void> mergeSteamCacheSnapshotFromSync(
  Map<String, dynamic> incoming,
) async {
  await _DiskCache.instance.mergeFromSync(incoming);
}

/// Tags to ignore - Steam platform features, not gameplay descriptors
const _ignoredTags = <String>{
  'steam achievements',
  'achievements',
  'steam trading cards',
  'trading cards',
  'steam cloud',
  'cloud saves',
  'steam workshop',
  'workshop',
  'steam leaderboards',
  'leaderboards',
  'full controller support',
  'controller support',
  'partial controller support',
  'controller',
  'gamepad',
  'mouse only option',
  'keyboard only option',
  'remote play',
  'remote play on phone',
  'remote play on tablet',
  'remote play on tv',
  'remote play together',
  'steam input api',
  'in-app purchases',
  'microtransactions',
  'downloadable content',
  'family sharing',
  'family share',
  'steam family sharing',
  'valve anti-cheat enabled',
  'anti-cheat',
  'vac',
  'steam turn notifications',
  'stats',
  'steam stats',
  'captions available',
  'subtitles',
  'closed captions',
  'includes level editor',
  'level editor',
  'commentary available',
  'includes source sdk',
  'windows',
  'macos',
  'mac os x',
  'linux',
  'steamos',
  'steamdeck verified',
  'steam deck verified',
  'steam deck playable',
  'steamvr',
  'oculus',
  'htc vive',
  'valve index',
  'tracked motion controller support',
  'tracked controller support',
  'seated',
  'standing',
  'room-scale',
  'free to play',
  'free',
  'free-to-play',
  'f2p',
  'demo available',
  'demo',
  'early access',
  'software',
  'utilities',
  'video production',
  'audio production',
  'game development',
  'animation & modeling',
  'design & illustration',
  'photo editing',
  'web publishing',
};

/// Tag normalization mapping (Steam tag -> our preferred format)
const Map<String, String> _tagMapping = {
  'fps': 'First-Person Shooter',
  'tps': 'Third-Person Shooter',
  'role-playing': 'RPG',
  'action rpg': 'RPG',
  'jrpg': 'RPG',
  'crpg': 'RPG',
  'single-player': 'Singleplayer',
  'multi-player': 'Multiplayer',
  'co-op': 'Co-op',
  'cooperative': 'Co-op',
  'virtual reality': 'VR',
  'vr supported': 'VR',
  'indie': 'Indie',
  'open world': 'Open World',
  'sandbox': 'Sandbox',
  'survival horror': 'Horror',
  'psychological horror': 'Horror',
  'action-adventure': 'Adventure',
  'hack & slash': 'Hack and Slash',
  'hack-and-slash': 'Hack and Slash',
};

enum SteamSearchSource {
  store('Steam Store'),
  community('Steam Community');

  const SteamSearchSource(this.label);
  final String label;
}

enum SteamDataSource {
  steamSpy('SteamSpy'),
  storeDetails('Steam Store details'),
  reviews('Steam Reviews');

  const SteamDataSource(this.label);
  final String label;
}

/// Result from a Steam search, including the services that supplied it.
class SteamSearchResult {
  final String appId;
  final String name;
  final String? imageUrl;
  final List<String> tags;
  final int? reviewScore;
  final int? reviewCount;
  final bool isDlc;
  final String? developer;
  final SteamSearchSource? searchSource;
  final List<SteamSearchSource> searchSourcesTried;
  final List<SteamDataSource> dataSources;

  const SteamSearchResult({
    required this.appId,
    required this.name,
    this.imageUrl,
    this.tags = const [],
    this.reviewScore,
    this.reviewCount,
    this.isDlc = false,
    this.developer,
    this.searchSource,
    this.searchSourcesTried = const [],
    this.dataSources = const [],
  });

  @override
  String toString() => 'SteamSearchResult(appId: $appId, name: $name)';
}

/// Insertion order tracks recency; reads and writes move entries to the end.
class _LruCache<K, V extends Object> {
  final int maxSize;
  final _cache = <K, V>{};

  _LruCache(this.maxSize);

  V? get(K key) {
    final value = _cache.remove(key);
    if (value != null) _cache[key] = value;
    return value;
  }

  void put(K key, V value) {
    _cache.remove(key);
    if (_cache.length >= maxSize) _cache.remove(_cache.keys.first);
    _cache[key] = value;
  }
}

/// Steam integration service
class SteamService {
  // Matching runs per candidate; compile each pattern once.
  static final _addonPattern = RegExp(
    r'\b(dlc|expansion|expansions|season\s*pass|soundtrack|artbook|booster|bonus|pack|skin\s*pack|supporter\s*pack)\b',
  );
  static final _trademarkPattern = RegExp(r'[™®©]');
  static final _whitespacePattern = RegExp(r'\s+');
  static final _searchEditionPattern = RegExp(
    r"\s*(GOTY|Game of the Year|Deluxe|Premium|Gold|Complete|Enhanced|Remastered?|Definitive|Ultimate|Special|Collectors?|Anniversary)\s*Edition\s*",
    caseSensitive: false,
  );
  static final _parentheticalPattern = RegExp(r'\s*\([^)]*\)\s*');
  static final _arabicSequelPattern = RegExp(r'\s\d+([: -]|\b)');
  static final _romanSequelPattern = RegExp(
    r'\s[ivxlcdm]+([: -]|\b)',
    caseSensitive: false,
  );

  final Dio _dio;

  /// LRU cache with 500 entry limit to prevent unbounded memory growth
  final _LruCache<String, SteamSearchResult> _cache = _LruCache(500);
  Directory? _imagesDir;
  DateTime? _lastRequestAt;
  final Duration _minRequestInterval = const Duration(milliseconds: 350);

  SteamService({Dio? dio, Directory? imagesDirectory})
    : _dio = dio ?? Dio(),
      _imagesDir = imagesDirectory {
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 15);
    // Use a more permissive User-Agent and Accept headers like the Sonnet implementation
    _dio.options.headers['User-Agent'] =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
    _dio.options.headers['Accept'] = 'application/json,text/html,*/*';
    _dio.options.headers['Accept-Language'] = 'en-US,en;q=0.9';
  }

  /// Release HTTP connections and cancel in-flight requests on disposal.
  void dispose() => _dio.close(force: true);

  /// Initialize the service (get images directory)
  Future<void> init() async {
    try {
      _imagesDir = await AppDatabase.getSteamImagesDirectory();
    } catch (e) {
      developer.log(
        'Failed to init Steam image cache: $e',
        name: 'SteamService',
      );
      _imagesDir = null;
    }
  }

  Future<void> _throttle() async {
    final now = DateTime.now();
    final last = _lastRequestAt;
    if (last != null) {
      final elapsed = now.difference(last);
      final wait = _minRequestInterval - elapsed;
      if (wait > Duration.zero) {
        await Future.delayed(wait);
      }
    }
    _lastRequestAt = DateTime.now();
  }

  bool _shouldRetryStatus(int? statusCode) {
    return statusCode == 429 ||
        statusCode == 403 ||
        statusCode == 500 ||
        statusCode == 502 ||
        statusCode == 503 ||
        statusCode == 504;
  }

  bool _shouldRetryError(DioException error) {
    if (_shouldRetryStatus(error.response?.statusCode)) {
      return true;
    }

    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError;
  }

  Future<void> _backoff(int attempt) async {
    final ms = 400 * (1 << attempt);
    await Future.delayed(Duration(milliseconds: ms.clamp(400, 2400)));
  }

  Future<Response<T>> _getWithRetry<T>(
    String url, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    int retries = 2,
  }) async {
    var attempt = 0;
    while (true) {
      await _throttle();
      try {
        final response = await _dio.get<T>(
          url,
          queryParameters: queryParameters,
          options: options,
        );
        if (_shouldRetryStatus(response.statusCode) && attempt < retries) {
          await _backoff(attempt);
          attempt++;
          continue;
        }
        return response;
      } on DioException catch (error) {
        if (!_shouldRetryError(error) || attempt >= retries) {
          rethrow;
        }
        await _backoff(attempt);
        attempt++;
      }
    }
  }

  /// Search for a game by title
  /// Set [forceRefresh] to true to skip any in-memory or on-disk cache
  Future<SteamSearchResult?> searchGame(
    String title, {
    bool forceRefresh = false,
    bool fetchTags = true,
    bool fetchReviews = true,
  }) async {
    if (title.trim().isEmpty) return null;

    // Check in-memory cache first unless we're forcing a refresh
    final normalizedTitle = _normalizeCacheKey(title);
    if (!forceRefresh) {
      final cached = _cache.get(normalizedTitle);
      if (cached != null) return cached;

      // Fall back to the persistent disk cache so that results from previous
      // sessions (or earlier in the same batch) are reused without another
      // network round-trip.
      final diskCached = await getCachedResultForTitle(title);
      if (diskCached != null) {
        // Warm the LRU cache so subsequent calls for the same title are
        // instant without touching the disk again.
        _cache.put(normalizedTitle, diskCached);
        return diskCached;
      }
    }

    // Generate search variants
    final variants = _generateSearchVariants(title);
    final searchSourcesTried = <SteamSearchSource>{};

    for (final variant in variants) {
      // Preserve Store-first search and Community fallback for each variant.
      for (final source in const [
        SteamSearchSource.store,
        SteamSearchSource.community,
      ]) {
        searchSourcesTried.add(source);
        final items = await switch (source) {
          SteamSearchSource.store => _searchStoreApi(variant),
          SteamSearchSource.community => _searchCommunityApi(variant),
        };
        final result = await _fetchBestMatchResult(
          title,
          items,
          fetchTags: fetchTags,
          fetchReviews: fetchReviews,
          searchSource: source,
          searchSourcesTried: List.unmodifiable(searchSourcesTried),
        );
        if (result != null) {
          await _cacheResultSafely(normalizedTitle, result);
          return result;
        }
      }
    }

    return null;
  }

  Future<SteamSearchResult?> _fetchBestMatchResult(
    String title,
    List<Map<String, dynamic>> items, {
    required bool fetchTags,
    required bool fetchReviews,
    required SteamSearchSource searchSource,
    required List<SteamSearchSource> searchSourcesTried,
  }) async {
    if (items.isEmpty) return null;

    final match = _findBestMatch(title, items);
    if (match == null) return null;

    final primaryResult = await _fetchGameDetails(
      match['id'].toString(),
      match['name'] as String,
      fetchTags: fetchTags,
      fetchReviews: fetchReviews,
      searchSource: searchSource,
      searchSourcesTried: searchSourcesTried,
    );
    if (primaryResult == null || !primaryResult.isDlc) {
      return primaryResult;
    }

    // If the query itself doesn't look like DLC content, attempt a non-DLC
    // fallback from the remaining candidates before accepting the DLC result.
    if (_searchLooksLikeDlc(title)) {
      return primaryResult;
    }

    final alternatives = items
        .where((item) => item['id'].toString() != primaryResult.appId)
        .toList();
    if (alternatives.isEmpty) {
      return primaryResult;
    }

    final cleanSearch = cleanTitleForSearch(title).toLowerCase();
    // Similarity includes edit-distance scoring: compute it once per candidate
    // rather than on both sides of every comparison during sorting.
    final ranked = [
      for (final item in alternatives)
        (item, _scoreCandidate(cleanSearch, item)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));

    for (final (candidate, _) in ranked.take(8)) {
      final altResult = await _fetchGameDetails(
        candidate['id'].toString(),
        candidate['name'] as String?,
        fetchTags: fetchTags,
        fetchReviews: fetchReviews,
        searchSource: searchSource,
        searchSourcesTried: searchSourcesTried,
      );
      if (altResult != null && !altResult.isDlc) {
        return altResult;
      }
    }

    return primaryResult;
  }

  bool _searchLooksLikeDlc(String title) {
    return _looksLikeAddonTitle(title.toLowerCase());
  }

  bool _looksLikeAddonTitle(String titleLower) {
    return _addonPattern.hasMatch(titleLower);
  }

  double _scoreCandidate(String cleanSearch, Map<String, dynamic> item) {
    final name = item['name'] as String? ?? '';
    final itemLower = name.toLowerCase().trim();
    final itemClean = cleanTitleForSearch(name).toLowerCase();

    var score = weightedSimilarity(cleanSearch, itemClean);
    if (itemLower == cleanSearch || itemClean == cleanSearch) {
      score += 0.4;
    }
    if (_looksLikeAddonTitle(itemLower)) {
      score -= 0.2;
    }
    return score;
  }

  Future<void> _cacheResultSafely(String key, SteamSearchResult result) async {
    try {
      _cache.put(key, result);
      await _DiskCache.instance.writeEntry(key, result);
    } catch (e) {
      AppLog.d('Failed to cache search result: $e');
    }
  }

  /// Download and save game image, returns local path
  Future<String?> downloadImage(
    String appId, {
    bool useLibraryImage = false,
    String? imageUrl,
  }) async {
    if (_imagesDir == null) await init();
    if (_imagesDir == null) return null;

    final localPath = p.join(_imagesDir!.path, '$appId.jpg');

    // Check if already downloaded
    if (File(localPath).existsSync()) {
      return localPath;
    }

    // Resolve current artwork even for old cached results: newer apps use
    // hashed store_item_assets paths rather than the legacy CDN layout.
    final urls = <String>{};
    if (!useLibraryImage) {
      try {
        final response = await _getWithRetry(
          SteamApi.appDetails,
          queryParameters: {'appids': appId},
        );
        final header = response.data?[appId]?['data']?['header_image'];
        if (header is String && header.isNotEmpty) urls.add(header);
      } catch (_) {
        // Cached artwork and legacy URLs remain usable when metadata is offline.
      }
      if (imageUrl != null && imageUrl.isNotEmpty) urls.add(imageUrl);
      urls.add(SteamApi.headerImage(appId));
    }
    urls.add(SteamApi.libraryImage(appId));
    for (final url in urls) {
      try {
        final response = await _getWithRetry<List<int>>(
          url,
          retries: 1,
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 8),
            validateStatus: (status) => status != null && status < 500,
          ),
        );
        final bytes = response.data;
        if (response.statusCode == 200 && bytes != null && bytes.isNotEmpty) {
          await File(localPath).writeAsBytes(bytes);
          return localPath;
        }
      } catch (e) {
        developer.log(
          'Image download failed for AppID $appId: $e',
          name: 'SteamService',
        );
      }
    }

    return null;
  }

  /// Normalize and map Steam tag names. Returns null if tag should be ignored.
  String? _normalizeTag(String tag) {
    if (tag.trim().isEmpty) return null;
    final trimmed = tag.trim();
    final t = trimmed.toLowerCase();
    if (_ignoredTags.contains(t)) return null;
    if (_tagMapping.containsKey(t)) return _tagMapping[t];
    // Title-case using the original trimmed text so that acronyms and mixed-case
    // words (e.g. "VR", "6DOF", "Online PvP") are preserved as-is.
    return trimmed
        .split(' ')
        .map(
          (w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '',
        )
        .join(' ');
  }

  List<String> _generateSearchVariants(String title) {
    final variants = <String>[];
    final original = title.trim();

    // 1. Original title
    variants.add(original);

    // 2. Clean special characters
    final cleaned = original
        .replaceAll(_trademarkPattern, '')
        .replaceAll(_whitespacePattern, ' ')
        .trim();
    if (cleaned != original) variants.add(cleaned);

    // 3. Remove edition names
    final noEdition = cleaned.replaceAll(_searchEditionPattern, '').trim();
    if (noEdition.isNotEmpty && noEdition != cleaned) variants.add(noEdition);

    // 4. Remove parenthetical content
    final noParens = cleaned.replaceAll(_parentheticalPattern, ' ').trim();
    if (noParens.isNotEmpty &&
        noParens != cleaned &&
        !variants.contains(noParens)) {
      variants.add(noParens);
    }

    // 5. Base title before colon
    if (original.contains(':')) {
      final base = original.split(':').first.trim();
      if (base.isNotEmpty &&
          base.split(' ').length >= 2 &&
          !variants.contains(base)) {
        variants.add(base);
      }
    }

    // 6. Base title before dash
    if (original.contains(' - ')) {
      final base = original.split(' - ').first.trim();
      if (base.isNotEmpty &&
          base.split(' ').length >= 2 &&
          !variants.contains(base)) {
        variants.add(base);
      }
    }

    return variants;
  }

  Future<List<Map<String, dynamic>>> _searchStoreApi(String term) async {
    try {
      final response = await _getWithRetry(
        SteamApi.storeSearch,
        queryParameters: {'term': term, 'l': 'english', 'cc': 'us'},
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final items = data['items'] as List<dynamic>?;
        return items?.cast<Map<String, dynamic>>() ?? [];
      }
    } catch (e) {
      developer.log(
        'Store API search failed for "$term": $e',
        name: 'SteamService',
      );
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> _searchCommunityApi(String term) async {
    try {
      final response = await _getWithRetry(
        '${SteamApi.communitySearch}${Uri.encodeComponent(term)}',
      );

      if (response.statusCode == 200 && response.data != null) {
        final items = response.data as List<dynamic>;
        return items.map((item) {
          final map = item as Map<String, dynamic>;
          // Normalize appid to id
          if (map.containsKey('appid')) {
            map['id'] = map['appid'];
          }
          return map;
        }).toList();
      }
    } catch (e) {
      developer.log(
        'Community API search failed for "$term": $e',
        name: 'SteamService',
      );
    }
    return [];
  }

  Map<String, dynamic>? _findBestMatch(
    String originalTitle,
    List<Map<String, dynamic>> items,
  ) {
    if (items.isEmpty) return null;

    final searchTitle = originalTitle.toLowerCase().trim();
    final cleanSearch = cleanTitleForSearch(originalTitle).toLowerCase();

    // 1. Exact match first (case-insensitive)
    for (final item in items) {
      final itemName = (item['name'] as String? ?? '').toLowerCase();
      if (itemName == searchTitle) return item;
    }

    // 2. Exact match with cleaned title. Retain these strings for later stages
    // of this search instead of repeating edition/punctuation cleanup.
    final cleanedNames = <String>[];
    for (final item in items) {
      final itemName = item['name'] as String? ?? '';
      final itemClean = cleanTitleForSearch(itemName).toLowerCase();
      cleanedNames.add(itemClean);
      if (itemClean == cleanSearch) return item;
    }

    // 3. Contains match (original in item OR item in original) - avoid sequels
    for (final item in items) {
      final itemName = item['name'] as String? ?? '';
      final itemLower = itemName.toLowerCase();
      if (itemLower.contains(searchTitle) || searchTitle.contains(itemLower)) {
        if (!_isSequelMismatch(originalTitle, itemName)) return item;
      }
    }

    // 4. Contains match with cleaned versions - avoid sequels
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final itemName = item['name'] as String? ?? '';
      final itemClean = cleanedNames[i];
      if (cleanSearch.contains(itemClean) || itemClean.contains(cleanSearch)) {
        if (!_isSequelMismatch(originalTitle, itemName)) return item;
      }
    }

    // 5. Fallback: return first result ONLY if it's not a sequel mismatch AND has reasonable similarity
    final firstItem = items[0];
    final firstName = firstItem['name'] as String? ?? '';
    if (!_isSequelMismatch(originalTitle, firstName)) {
      final firstClean = cleanedNames.first;
      final ratio = weightedSimilarity(cleanSearch, firstClean);
      // If ratio is decent, accept it. We use a slightly stricter threshold now that
      // the token-weighted scorer gives more accurate results for numbered titles.
      if (ratio > 0.50) return firstItem;

      developer.log(
        "Rejected fallback '$firstName' due to low similarity (${ratio.toStringAsFixed(2)}) with '$cleanSearch'",
        name: 'SteamService',
      );
    }

    return null;
  }

  bool _hasSequelNumber(String titleLower) =>
      _arabicSequelPattern.hasMatch(titleLower) ||
      _romanSequelPattern.hasMatch(titleLower);

  bool _isSequelMismatch(String searchTitle, String resultName) {
    // If search explicitly contains a number or roman numeral, don't treat as mismatch
    if (_hasSequelNumber(searchTitle.toLowerCase())) return false;
    // If result contains an Arabic number suffix (e.g., ' 2') or roman numerals, it's likely a sequel
    return _hasSequelNumber(resultName.toLowerCase());
  }

  Future<SteamSearchResult?> _fetchGameDetails(
    String appId,
    String? name, {
    bool fetchTags = true,
    bool fetchReviews = true,
    required SteamSearchSource searchSource,
    required List<SteamSearchSource> searchSourcesTried,
  }) async {
    try {
      // Collect tags (SteamSpy first, then app details genres/categories)
      final tags = <String>[];
      final seen = <String>{};
      final dataSources = <SteamDataSource>[];
      String? headerImage;

      if (fetchTags) {
        final steamspyTags = await _fetchSteamSpyTags(appId);
        if (steamspyTags.isNotEmpty) {
          dataSources.add(SteamDataSource.steamSpy);
          for (final t in steamspyTags) {
            if (!seen.contains(t)) {
              tags.add(t);
              seen.add(t);
              if (tags.length >= 30) break;
            }
          }
        }
      }

      // Fetch app details from Steam
      final detailsResponse = await _getWithRetry(
        SteamApi.appDetails,
        queryParameters: {'appids': appId},
      );

      String gameName = name ?? 'Unknown';
      bool isDlc = false;
      String? developer;
      int? reviewScore;
      int? reviewCount;

      if (detailsResponse.statusCode == 200 && detailsResponse.data != null) {
        final data = detailsResponse.data as Map<String, dynamic>;
        final appData = data[appId] as Map<String, dynamic>?;

        if (appData != null && appData['success'] == true) {
          final details = appData['data'] as Map<String, dynamic>;
          dataSources.add(SteamDataSource.storeDetails);
          headerImage = details['header_image'] as String?;
          gameName = details['name'] as String? ?? gameName;
          isDlc = (details['type'] == 'dlc');
          final developers = (details['developers'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .where((s) => s.isNotEmpty)
              .toList();
          developer = developers != null && developers.isNotEmpty
              ? developers.join(', ')
              : null;

          reviewCount = (details['recommendations'] != null)
              ? (details['recommendations']['total'] as int?)
              : null;

          if (fetchTags) {
            // Add genres and categories as tags
            final List<dynamic> genres =
                details['genres'] as List<dynamic>? ?? [];
            final List<dynamic> categories =
                details['categories'] as List<dynamic>? ?? [];
            for (final item in [...genres, ...categories]) {
              final desc = item['description'] as String? ?? '';
              final normalized = _normalizeTag(desc);
              if (normalized != null && !seen.contains(normalized)) {
                tags.add(normalized);
                seen.add(normalized);
                if (tags.length >= 30) break;
              }
            }
          }
        }
      }

      if (fetchReviews) {
        // Attempt to fetch review summary from the Steam "appreviews" endpoint
        try {
          final reviewsResp = await _getWithRetry(
            SteamApi.appReviews(appId),
            queryParameters: {
              'json': '1',
              'language': 'all',
              'filter': 'all',
              'num_per_page': '0',
            },
          );

          if (reviewsResp.statusCode == 200 && reviewsResp.data != null) {
            final summary =
                (reviewsResp.data as Map<String, dynamic>)['query_summary']
                    as Map<String, dynamic>?;
            if (summary != null) {
              final totalPositive = (summary['total_positive'] as int?) ?? 0;
              final totalNegative = (summary['total_negative'] as int?) ?? 0;
              final total = totalPositive + totalNegative;
              if (total > 0) {
                dataSources.add(SteamDataSource.reviews);
                reviewCount = total;
                reviewScore = ((totalPositive / total) * 100).round();
              }
            }
          }
        } catch (e) {
          // Ignore review fetch errors - reviews are optional
        }
      }

      // Return result even if tags are empty (image/review data are useful on their own)
      final result = SteamSearchResult(
        appId: appId,
        name: gameName,
        imageUrl: headerImage ?? SteamApi.headerImage(appId),
        tags: tags,
        reviewScore: reviewScore,
        reviewCount: reviewCount,
        isDlc: isDlc,
        developer: developer,
        searchSource: searchSource,
        searchSourcesTried: searchSourcesTried,
        dataSources: List.unmodifiable(dataSources),
      );
      final key = _normalizeCacheKey(result.name);
      await _cacheResultSafely(key, result);
      return result;
    } catch (e) {
      // Return basic result without details
      developer.log(
        'Failed to fetch details for AppID $appId: $e',
        name: 'SteamService',
      );
      final result = SteamSearchResult(
        appId: appId,
        name: name ?? 'Unknown',
        imageUrl: SteamApi.headerImage(appId),
        searchSource: searchSource,
        searchSourcesTried: searchSourcesTried,
      );
      final key = _normalizeCacheKey(result.name);
      await _cacheResultSafely(key, result);
      return result;
    }
  }

  Future<List<String>> _fetchSteamSpyTags(String appId) async {
    try {
      final response = await _getWithRetry(
        SteamApi.steamSpy,
        queryParameters: {'request': 'appdetails', 'appid': appId},
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final tagEntries = _parseSteamSpyTags(data['tags']);

        if (tagEntries.isNotEmpty) {
          tagEntries.sort((a, b) => b.score.compareTo(a.score));

          final tags = <String>[];
          for (final entry in tagEntries) {
            final normalized = _normalizeTag(entry.tag);
            if (normalized != null && !tags.contains(normalized)) {
              tags.add(normalized);
              if (tags.length >= 30) break;
            }
          }
          return tags;
        }
      }
    } catch (e) {
      developer.log(
        'SteamSpy tags fetch failed for AppID $appId: $e',
        name: 'SteamService',
      );
    }
    return [];
  }

  List<({String tag, int score})> _parseSteamSpyTags(dynamic rawTags) {
    final entries = <({String tag, int score})>[];

    if (rawTags is Map) {
      rawTags.forEach((key, value) {
        final tag = key.toString().trim();
        if (tag.isEmpty) return;
        entries.add((tag: tag, score: _coerceTagScore(value)));
      });
      return entries;
    }

    if (rawTags is List) {
      for (final item in rawTags) {
        if (item is String) {
          final tag = item.trim();
          if (tag.isNotEmpty) {
            entries.add((tag: tag, score: 0));
          }
          continue;
        }

        if (item is Map) {
          final dynamic rawTag =
              item['tag'] ?? item['name'] ?? item['label'] ?? item['id'];
          final tag = rawTag?.toString().trim() ?? '';
          if (tag.isEmpty) continue;
          final score = _coerceTagScore(
            item['score'] ?? item['votes'] ?? item['count'] ?? item['weight'],
          );
          entries.add((tag: tag, score: score));
        }
      }
    }

    return entries;
  }

  int _coerceTagScore(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

/// Provider for SteamService
final steamServiceProvider = Provider<SteamService>((ref) {
  final service = SteamService();
  ref.onDispose(service.dispose);
  // Initialize asynchronously
  service.init();
  return service;
});
