/// Riverpod providers for tag management.
library;

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/database.dart';
import '../models/game.dart';
import 'database_providers.dart';

// =============================================================================
// TAGS NOTIFIER
// =============================================================================

/// Tags state notifier
class TagsNotifier extends Notifier<List<Tag>> {
  StreamSubscription<List<TagEntry>>? _subscription;
  int _generation = 0;
  int _snapshotEpoch = 0;
  AppDatabase? _activeDatabase;
  List<Tag> _cachedTags = const [];

  @override
  List<Tag> build() {
    // Watch the database state so we reload when the database changes
    final dbState = ref.watch(databaseNotifierProvider);

    if (!identical(_activeDatabase, dbState.database)) {
      _activeDatabase = dbState.database;
      _generation++;
      _cachedTags = const [];
    }

    // If database isn't ready yet, return empty list
    if (dbState.database == null) return _cachedTags;

    final db = dbState.database!;
    _subscription = db.watchAllTags().listen(
      (entries) {
        if (ref.mounted && identical(ref.read(databaseProvider), db)) {
          _replaceTags(entries.map(Tag.fromEntry).toList());
        }
      },
      onError: (Object _) {
        // Explicit refresh reports errors; never publish data from an old session.
      },
    );
    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
    });

    return _cachedTags;
  }

  Future<void> _loadTags() async {
    final generation = ++_generation;
    final db = ref.read(databaseProvider);
    if (db == null) return;
    try {
      final snapshotEpoch = _snapshotEpoch;
      final entries = await db.getAllTags();
      final tags = entries.map((e) => Tag.fromEntry(e)).toList();
      if (ref.mounted &&
          generation == _generation &&
          identical(ref.read(databaseProvider), db)) {
        // Stream delivery may overtake this read. Re-read rather than publish
        // stale rows or return before an intervening cleanup is reflected.
        if (snapshotEpoch != _snapshotEpoch) return _loadTags();
        _replaceTags(tags);
      }
    } catch (_) {
      // A closing old session must not surface an unhandled microtask error.
      if (ref.mounted && identical(ref.read(databaseProvider), db)) rethrow;
    }
  }

  void _replaceTags(List<Tag> tags) {
    _snapshotEpoch++;
    // Still advance the epoch so an overlapping refresh cannot publish stale
    // rows, but don't rebuild tag controls for an identical snapshot.
    if (const ListEquality<Tag>().equals(_cachedTags, tags)) return;
    _cachedTags = List<Tag>.unmodifiable(tags);
    state = _cachedTags;
  }

  Future<void> refresh() => _loadTags();

  /// Persist against the database captured before the write. Cleanup operations
  /// refresh first and propagate errors; individual edits retain fallback results.
  Future<T> _persist<T>(
    Future<T> Function(AppDatabase db) action, {
    bool refreshAfter = false,
  }) async {
    final db = ref.read(requireDatabaseProvider);
    final result = await action(db);
    if (refreshAfter) await refresh();
    await persistEncryptedDbIfNeeded(ref, database: db);
    return result;
  }

  Future<T> _edit<T>(
    Future<T> Function(AppDatabase db) action, {
    required T failure,
  }) async {
    try {
      return await _persist(action);
    } catch (_) {
      return failure;
    }
  }

  Future<Tag?> addTag(
    String name,
    String colorHex, {
    bool isSteamTag = false,
  }) => _edit<Tag?>((db) async {
    final entry = await db.getOrCreateTag(
      name,
      color: colorHex,
      isSteamTag: isSteamTag,
    );
    return Tag.fromEntry(entry);
  }, failure: null);

  Future<bool> updateTag(Tag tag) => _edit((db) async {
    await db.updateTag(
      TagEntry(
        id: tag.id,
        name: tag.name,
        color: tag.colorHex,
        isSteamTag: tag.isSteamTag,
      ),
    );
    return true;
  }, failure: false);

  Future<bool> deleteTag(int id) => _edit((db) async {
    await db.deleteTag(id);
    return true;
  }, failure: false);

  Future<int> deleteUnusedTags() =>
      _persist((db) => db.deleteUnusedTags(), refreshAfter: true);

  /// One-time cleanup: remove legacy default tags (custom-only).
  Future<int> deleteLegacyDefaultCustomTags() =>
      _persist((db) => db.deleteLegacyDefaultCustomTags(), refreshAfter: true);

  /// Clear unused tags that are not user-created custom tags, including Steam tags.
  Future<int> deleteUnusedNonUserTags() =>
      _persist((db) => db.deleteUnusedNonUserTags(), refreshAfter: true);
}

/// Tags provider
final tagsProvider = NotifierProvider<TagsNotifier, List<Tag>>(() {
  return TagsNotifier();
});

final customTagsProvider = Provider<List<Tag>>((ref) {
  final tags = ref.watch(tagsProvider);
  return tags.where((tag) => !tag.isSteamTag).toList();
});

final steamTagsProvider = Provider<List<Tag>>((ref) {
  final tags = ref.watch(tagsProvider);
  return tags.where((tag) => tag.isSteamTag).toList();
});
