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

import '../database/database.dart';

import 'logging.dart';
import '../utils/title_similarity.dart';

export '../utils/title_similarity.dart' show cleanTitleForSearch, weightedSimilarity;

/// Steam API URLs
class SteamApi {
  static const storeSearch = 'https://store.steampowered.com/api/storesearch/';
  static const communitySearch =
      'https://steamcommunity.com/actions/SearchApps/';
  static const appDetails = 'https://store.steampowered.com/api/appdetails';
  static const steamSpy = 'https://steamspy.com/api.php';

  /// CDN URLs for images
  static String headerImage(String appId) =>
      'https://steamcdn-a.akamaihd.net/steam/apps/$appId/header.jpg';
  static String libraryImage(String appId) =>
      'https://steamcdn-a.akamaihd.net/steam/apps/$appId/library_600x900.jpg';
  static String capsuleImage(String appId) =>
      'https://steamcdn-a.akamaihd.net/steam/apps/$appId/capsule_231x87.jpg';
}

// cleanTitleForSearch and weightedSimilarity are now in
// package:unikm/core/utils/title_similarity.dart
// and re-exported via the import above.

/// Disk cache helpers
String _normalizeCacheKey(String title) {
  return title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
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
  bool _isLoading = false;
  
  /// Load cache from disk into memory (call once at app startup or first access)
  Future<void> _ensureLoaded() async {
    if (_cache != null || _isLoading) return;
    _isLoading = true;
    try {
      final path = await _getCacheFilePath();
      final file = File(path);
      if (await file.exists()) {
        final text = await file.readAsString();
        _cache = json.decode(text) as Map<String, dynamic>;
      } else {
        _cache = {};
      }
    } catch (_) {
      _cache = {};
    } finally {
      _isLoading = false;
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
      tags: (entry['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ?? [],
      reviewScore: entry['review_score'] as int?,
      reviewCount: entry['review_count'] as int?,
      isDlc: entry['is_dlc'] as bool? ?? false,
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
      'cached_at': DateTime.now().millisecondsSinceEpoch / 1000.0,
    };
    
    _cache ??= {};
    _cache![key] = entry;
    
    // Also write under normalized result name key
    final keyFromName = _normalizeCacheKey(r.name);
    if (keyFromName != key) _cache![keyFromName] = entry;
    
    // Persist to disk
    try {
      final path = await _getCacheFilePath();
      await File(path).writeAsString(json.encode(_cache));
    } catch (_) {
      // Ignore cache write failures
    }
  }
}

Future<void> _writeCacheEntry(String key, SteamSearchResult r) async {
  await _DiskCache.instance.writeEntry(key, r);
}

Future<DateTime?> getCachedAtForTitle(String title) async {
  return _DiskCache.instance.getCachedAt(title);
}

Future<SteamSearchResult?> getCachedResultForTitle(String title) async {
  return _DiskCache.instance.getCachedResult(title);
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

/// Result from a Steam search
class SteamSearchResult {
  final String appId;
  final String name;
  final String? imageUrl;
  final List<String> tags;
  final int? reviewScore;
  final int? reviewCount;
  final bool isDlc;

  const SteamSearchResult({
    required this.appId,
    required this.name,
    this.imageUrl,
    this.tags = const [],
    this.reviewScore,
    this.reviewCount,
    this.isDlc = false,
  });

  @override
  String toString() => 'SteamSearchResult(appId: $appId, name: $name)';
}

/// Simple LRU cache implementation with max size limit
class _LruCache<K, V> {
  final int maxSize;
  final _cache = <K, V>{};
  final _accessOrder = <K>[];

  _LruCache(this.maxSize);

  V? get(K key) {
    final value = _cache[key];
    if (value != null) {
      // Move to end (most recently used)
      _accessOrder.remove(key);
      _accessOrder.add(key);
    }
    return value;
  }

  void put(K key, V value) {
    if (_cache.containsKey(key)) {
      _accessOrder.remove(key);
    } else if (_cache.length >= maxSize) {
      // Evict least recently used
      final lruKey = _accessOrder.removeAt(0);
      _cache.remove(lruKey);
    }
    _cache[key] = value;
    _accessOrder.add(key);
  }

  bool containsKey(K key) => _cache.containsKey(key);

  void clear() {
    _cache.clear();
    _accessOrder.clear();
  }

  int get length => _cache.length;
}

/// Steam integration service
class SteamService {
  final Dio _dio;
  /// LRU cache with 500 entry limit to prevent unbounded memory growth
  final _LruCache<String, SteamSearchResult> _cache = _LruCache(500);
  Directory? _imagesDir;
  DateTime? _lastRequestAt;
  final Duration _minRequestInterval = const Duration(milliseconds: 350);

  SteamService() : _dio = Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 15);
    // Use a more permissive User-Agent and Accept headers like the Sonnet implementation
    _dio.options.headers['User-Agent'] =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
    _dio.options.headers['Accept'] = 'application/json,text/html,*/*';
    _dio.options.headers['Accept-Language'] = 'en-US,en;q=0.9';
  }

  /// Initialize the service (get images directory)
  Future<void> init() async {
    try {
      // images should live next to the database so that a user can move or
      // back up the entire "data" folder in one go.  We keep the same
      // "images/steam" sub‑directory for organisation but start from the
      // database directory instead of the application support directory.
      final dbPath = await AppDatabase.getDatabasePath();
      final dbDir = Directory(p.dirname(dbPath));
      _imagesDir = Directory(p.join(dbDir.path, 'images', 'steam'));
      if (!_imagesDir!.existsSync()) {
        await _imagesDir!.create(recursive: true);
      }
    } catch (e) {
      developer.log('Failed to init Steam image cache: $e', name: 'SteamService');
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
      } on DioException catch (_) {
        if (attempt >= retries) rethrow;
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
    final normalizedTitle = _normalizeTitle(title);
    if (!forceRefresh) {
      final cached = _cache.get(normalizedTitle);
      if (cached != null) return cached;
    }

    // Generate search variants
    final variants = _generateSearchVariants(title);

    for (final variant in variants) {
      // Try store API first
      final storeResults = await _searchStoreApi(variant);
      final storeResult = await _fetchBestMatchResult(
        title,
        storeResults,
        fetchTags: fetchTags,
        fetchReviews: fetchReviews,
      );
      if (storeResult != null) {
        await _cacheResultSafely(normalizedTitle, storeResult);
        return storeResult;
      }

      // Try community API as fallback
      final communityResults = await _searchCommunityApi(variant);
      final communityResult = await _fetchBestMatchResult(
        title,
        communityResults,
        fetchTags: fetchTags,
        fetchReviews: fetchReviews,
      );
      if (communityResult != null) {
        await _cacheResultSafely(normalizedTitle, communityResult);
        return communityResult;
      }
    }

    return null;
  }

  Future<SteamSearchResult?> _fetchBestMatchResult(
    String title,
    List<Map<String, dynamic>> items, {
    required bool fetchTags,
    required bool fetchReviews,
  }) async {
    if (items.isEmpty) return null;

    final match = _findBestMatch(title, items);
    if (match == null) return null;

    return _fetchGameDetails(
      match['id'].toString(),
      match['name'] as String,
      fetchTags: fetchTags,
      fetchReviews: fetchReviews,
    );
  }

  Future<void> _cacheResultSafely(String key, SteamSearchResult result) async {
    try {
      _cache.put(key, result);
      await _writeCacheEntry(key, result);
    } catch (e) {
      AppLog.d('Failed to cache search result: $e');
    }
  }

  /// Download and save game image, returns local path
  Future<String?> downloadImage(
    String appId, {
    bool useLibraryImage = false,
  }) async {
    if (_imagesDir == null) await init();
    if (_imagesDir == null) return null;

    final localPath = p.join(_imagesDir!.path, '$appId.jpg');

    // Check if already downloaded
    if (File(localPath).existsSync()) {
      return localPath;
    }

    try {
      final url = useLibraryImage
          ? SteamApi.libraryImage(appId)
          : SteamApi.headerImage(appId);

      final response = await _getWithRetry<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode == 200 && response.data != null) {
        await File(localPath).writeAsBytes(response.data!);
        return localPath;
      }
    } catch (e) {
      developer.log(
        'Image download failed for AppID $appId: $e',
        name: 'SteamService',
      );
      // Try fallback image
      if (!useLibraryImage) {
        return downloadImage(appId, useLibraryImage: true);
      }
    }

    return null;
  }

  /// Get local image path if it exists
  String? getLocalImagePath(String appId) {
    if (_imagesDir == null) return null;
    final path = p.join(_imagesDir!.path, '$appId.jpg');
    return File(path).existsSync() ? path : null;
  }

  // Private methods

  String _normalizeTitle(String title) {
    return title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Normalize and map Steam tag names. Returns null if tag should be ignored.
  String? _normalizeTag(String tag) {
    if (tag.trim().isEmpty) return null;
    final t = tag.trim().toLowerCase();
    if (_ignoredTags.contains(t)) return null;
    if (_tagMapping.containsKey(t)) return _tagMapping[t];
    // Title-case remaining tags (e.g., 'action adventure' -> 'Action Adventure')
    return t
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
        .replaceAll(RegExp(r'[™®©]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned != original) variants.add(cleaned);

    // 3. Remove edition names
    final editionPattern = RegExp(
      r"\s*(GOTY|Game of the Year|Deluxe|Premium|Gold|Complete|Enhanced|Remastered?|Definitive|Ultimate|Special|Collectors?|Anniversary)\s*Edition\s*",
      caseSensitive: false,
    );
    final noEdition = cleaned.replaceAll(editionPattern, '').trim();
    if (noEdition.isNotEmpty && noEdition != cleaned) variants.add(noEdition);

    // 4. Remove parenthetical content
    final noParens = cleaned.replaceAll(RegExp(r'\s*\([^)]*\)\s*'), ' ').trim();
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
    List<Map<String, dynamic>> items, [
    String? searchVariant,
  ]) {
    if (items.isEmpty) return null;

    final searchTitle = originalTitle.toLowerCase().trim();
    final cleanSearch = cleanTitleForSearch(originalTitle).toLowerCase();
    final variantLower = (searchVariant ?? originalTitle).toLowerCase().trim();

    // 1. Exact match first (case-insensitive)
    for (final item in items) {
      final itemName = (item['name'] as String? ?? '').toLowerCase();
      if (itemName == searchTitle) return item;
    }

    // 2. Exact match with cleaned title
    for (final item in items) {
      final itemName = item['name'] as String? ?? '';
      final itemClean = _cleanTitleForSearch(itemName).toLowerCase();
      if (itemClean == cleanSearch) return item;
    }

    // 3. If we used a search variant, check cleaned equality against that
    if (searchVariant != null) {
      for (final item in items) {
        final itemClean = _cleanTitleForSearch(
          item['name'] as String? ?? '',
        ).toLowerCase();
        if (itemClean == variantLower) return item;
      }
    }

    // 4. Contains match (original in item OR item in original) - avoid sequels
    for (final item in items) {
      final itemName = item['name'] as String? ?? '';
      final itemLower = itemName.toLowerCase();
      if (itemLower.contains(searchTitle) || searchTitle.contains(itemLower)) {
        if (!_isSequelMismatch(originalTitle, itemName)) return item;
      }
    }

    // 5. Contains match with cleaned versions - avoid sequels
    for (final item in items) {
      final itemName = item['name'] as String? ?? '';
      final itemClean = _cleanTitleForSearch(itemName).toLowerCase();
      if (cleanSearch.contains(itemClean) || itemClean.contains(cleanSearch)) {
        if (!_isSequelMismatch(originalTitle, itemName)) return item;
      }
    }

    // 6. Second pass: allow contains matches even if it's less strict (but still reject clear sequel mismatches)
    for (final item in items) {
      final itemName = item['name'] as String? ?? '';
      final itemLower = itemName.toLowerCase();
      final itemClean = _cleanTitleForSearch(itemName).toLowerCase();
      if ((itemLower.contains(searchTitle) ||
          searchTitle.contains(itemLower) ||
          itemClean.contains(cleanSearch) ||
          cleanSearch.contains(itemClean))) {
        if (!_isSequelMismatch(originalTitle, itemName)) return item;
      }
    }

    // 7. Fallback: return first result ONLY if it's not a sequel mismatch AND has reasonable similarity
    final firstItem = items[0];
    final firstName = firstItem['name'] as String? ?? '';
    if (!_isSequelMismatch(originalTitle, firstName)) {
      final firstClean = cleanTitleForSearch(firstName).toLowerCase();
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

  String _cleanTitleForSearch(String title) {
    // Delegate to shared helper to keep logic consistent and testable
    return cleanTitleForSearch(title);
  }

  bool _isSequelMismatch(String searchTitle, String resultName) {
    final s = searchTitle.toLowerCase();
    // If search explicitly contains a number or roman numeral, don't treat as mismatch
    if (RegExp(r'\s\d+([: -]|\b)').hasMatch(s) ||
        RegExp(r'\s[ivxlcdm]+([: -]|\b)', caseSensitive: false).hasMatch(s)) {
      return false;
    }

    final item = resultName.toLowerCase();
    // If result contains an Arabic number suffix (e.g., ' 2') or roman numerals, it's likely a sequel
    if (RegExp(r'\s\d+([: -]|\b)').hasMatch(item) ||
        RegExp(
          r'\s[ivxlcdm]+([: -]|\b)',
          caseSensitive: false,
        ).hasMatch(item)) {
      return true;
    }
    return false;
  }

  Future<SteamSearchResult?> _fetchGameDetails(
    String appId,
    String? name, {
    bool fetchTags = true,
    bool fetchReviews = true,
  }) async {
    try {
      // Collect tags (SteamSpy first, then app details genres/categories)
      final tags = <String>[];
      final seen = <String>{};

      if (fetchTags) {
        final steamspyTags = await _fetchSteamSpyTags(appId);
        if (steamspyTags.isNotEmpty) {
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
      int? reviewScore;
      int? reviewCount;

      if (detailsResponse.statusCode == 200 && detailsResponse.data != null) {
        final data = detailsResponse.data as Map<String, dynamic>;
        final appData = data[appId] as Map<String, dynamic>?;

        if (appData != null && appData['success'] == true) {
          final details = appData['data'] as Map<String, dynamic>;
          gameName = details['name'] as String? ?? gameName;
          isDlc = (details['type'] == 'dlc');

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
            'https://store.steampowered.com/appreviews/$appId',
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
        imageUrl: SteamApi.headerImage(appId),
        tags: tags,
        reviewScore: reviewScore,
        reviewCount: reviewCount,
        isDlc: isDlc,
      );
      final key = _normalizeTitle(result.name);
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
      );
      final key = _normalizeTitle(result.name);
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
        final tagsMap = data['tags'] as Map<String, dynamic>?;

        if (tagsMap != null && tagsMap.isNotEmpty) {
          final entries = tagsMap.entries.toList()
            ..sort((a, b) => (b.value as int).compareTo(a.value as int));

          final tags = <String>[];
          for (final e in entries) {
            final raw = e.key;
            final normalized = _normalizeTag(raw);
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

  /// Clear the in-memory cache
  void clearCache() {
    _cache.clear();
  }
}

/// Provider for SteamService
final steamServiceProvider = Provider<SteamService>((ref) {
  final service = SteamService();
  // Initialize asynchronously
  service.init();
  return service;
});
