/// Riverpod providers for tag management.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/database.dart';
import '../models/game.dart';
import 'database_providers.dart';

// =============================================================================
// TAGS NOTIFIER
// =============================================================================

/// Tags state notifier
class TagsNotifier extends Notifier<List<Tag>> {
  int _lastLoadedRevision = -1;
  bool _isLoading = false;
  List<Tag> _cachedTags = const [];

  @override
  List<Tag> build() {
    // Watch the database state so we reload when the database changes
    final dbState = ref.watch(databaseNotifierProvider);
    
    // If database isn't ready yet, return empty list
    if (dbState.database == null) {
      return _cachedTags;
    }

    if (_lastLoadedRevision != dbState.revision && !_isLoading) {
      _lastLoadedRevision = dbState.revision;
      Future.microtask(_loadTags);
    }

    return _cachedTags;
  }

  Future<void> _loadTags() async {
    if (_isLoading) return;
    _isLoading = true;
    try {
      final db = ref.read(requireDatabaseProvider);
      final entries = await db.getAllTags();
      final tags = entries.map((e) => Tag.fromEntry(e)).toList();
      _replaceTags(tags);
    } finally {
      _isLoading = false;
    }
  }

  void _replaceTags(List<Tag> tags) {
    _cachedTags = List<Tag>.unmodifiable(tags);
    state = _cachedTags;
  }

  void _upsertTag(Tag tag) {
    final next = List<Tag>.from(_cachedTags);
    final index = next.indexWhere((t) => t.id == tag.id);
    if (index == -1) {
      next.add(tag);
    } else {
      next[index] = tag;
    }
    _replaceTags(next);
  }

  void _removeTagById(int id) {
    if (_cachedTags.every((t) => t.id != id)) {
      return;
    }
    final next = _cachedTags.where((t) => t.id != id).toList();
    _replaceTags(next);
  }

  /// Public method to load tags (for initial load)
  Future<void> loadTags() => _loadTags();

  Future<void> refresh() => _loadTags();

  Future<Tag?> addTag(String name, String colorHex, {bool isSteamTag = false}) async {
    try {
      final db = ref.read(requireDatabaseProvider);
      final entry = await db.getOrCreateTag(name, color: colorHex, isSteamTag: isSteamTag);
      final tag = Tag.fromEntry(entry);
      _upsertTag(tag);
      await persistEncryptedDbIfNeeded(ref);
      return tag;
    } catch (e) {
      return null;
    }
  }

  Future<bool> updateTag(Tag tag) async {
    try {
      final db = ref.read(requireDatabaseProvider);
      await db.updateTag(TagEntry(
        id: tag.id,
        name: tag.name,
        color: tag.colorHex,
        isSteamTag: tag.isSteamTag,
      ));
      _upsertTag(tag);
      await persistEncryptedDbIfNeeded(ref);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteTag(int id) async {
    try {
      final db = ref.read(requireDatabaseProvider);
      await db.deleteTag(id);
      _removeTagById(id);
      await persistEncryptedDbIfNeeded(ref);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<int> deleteUnusedTags() async {
    final db = ref.read(requireDatabaseProvider);
    final count = await db.deleteUnusedTags();
    await refresh();
    await persistEncryptedDbIfNeeded(ref);
    return count;
  }

  /// One-time cleanup: remove legacy default tags (custom-only).
  Future<int> deleteLegacyDefaultCustomTags() async {
    final db = ref.read(requireDatabaseProvider);
    final count = await db.deleteLegacyDefaultCustomTags();
    await refresh();
    await persistEncryptedDbIfNeeded(ref);
    return count;
  }

  /// Clear unused tags that are not user-created custom tags.
  ///
  /// This clears unused Steam tags as well.
  Future<int> deleteUnusedNonUserTags() async {
    final db = ref.read(requireDatabaseProvider);
    final count = await db.deleteUnusedNonUserTags();
    await refresh();
    await persistEncryptedDbIfNeeded(ref);
    return count;
  }
}

/// Tags provider
final tagsProvider = NotifierProvider<TagsNotifier, List<Tag>>(() {
  return TagsNotifier();
});

final tagsByIdProvider = Provider<Map<int, Tag>>((ref) {
  final tags = ref.watch(tagsProvider);
  return {for (final tag in tags) tag.id: tag};
});

final customTagsProvider = Provider<List<Tag>>((ref) {
  final tags = ref.watch(tagsProvider);
  return tags.where((tag) => !tag.isSteamTag).toList();
});

final steamTagsProvider = Provider<List<Tag>>((ref) {
  final tags = ref.watch(tagsProvider);
  return tags.where((tag) => tag.isSteamTag).toList();
});
