import '../../../core/database/database.dart';
import '../../../core/services/steam_service.dart';
import '../../library/data/library_repository.dart';

class SteamApplyOptions {
  const SteamApplyOptions({
    required this.applyAppId,
    required this.applyTags,
    required this.applyImage,
    required this.applyReviews,
    required this.applyDeveloper,
  });

  final bool applyAppId;
  final bool applyTags;
  final bool applyImage;
  final bool applyReviews;
  final bool applyDeveloper;

  static const defaults = SteamApplyOptions(
    applyAppId: true,
    applyTags: true,
    applyImage: true,
    applyReviews: true,
    applyDeveloper: true,
  );

  SteamApplyOptions copyWith({
    bool? applyAppId,
    bool? applyTags,
    bool? applyImage,
    bool? applyReviews,
    bool? applyDeveloper,
  }) => SteamApplyOptions(
    applyAppId: applyAppId ?? this.applyAppId,
    applyTags: applyTags ?? this.applyTags,
    applyImage: applyImage ?? this.applyImage,
    applyReviews: applyReviews ?? this.applyReviews,
    applyDeveloper: applyDeveloper ?? this.applyDeveloper,
  );
}

/// Applies only fetched fields to the latest row in the originating session.
class ApplySteamMetadata {
  const ApplySteamMetadata({
    required this.database,
    required this.isCurrent,
    required this.downloadImage,
  });

  final AppDatabase database;
  final bool Function() isCurrent;
  final Future<String?> Function(String appId) downloadImage;

  void _checkSession() {
    if (!isCurrent()) {
      throw StateError('Database session changed or operation cancelled');
    }
  }

  Future<void> apply(
    int gameId,
    SteamSearchResult result,
    SteamApplyOptions options,
  ) async {
    _checkSession();
    String? imagePath;
    if (options.applyImage) {
      try {
        imagePath = await downloadImage(result.appId);
      } catch (_) {
        // Keep the current cover if artwork cannot be downloaded.
      }
    }
    _checkSession();
    await database.transaction(() async {
      _checkSession();
      final game = await database.getGameById(gameId);
      if (game == null) throw StateError('The game no longer exists');
      List<int>? tagIds;
      if (options.applyTags && result.tags.isNotEmpty) {
        final existing = await database.getTagsForGame(gameId);
        tagIds = existing
            .where((tag) => !tag.isSteamTag)
            .map((tag) => tag.id)
            .toList();
        for (final name in result.tags) {
          tagIds.add(
            (await database.getOrCreateTag(name, isSteamTag: true)).id,
          );
        }
      }
      await LibraryRepository(database).updateGame(
        game.copyWith(
          isDlc: result.isDlc,
          steamAppId: options.applyAppId ? result.appId : null,
          developer: options.applyDeveloper ? result.developer : null,
          reviewScore: options.applyReviews ? result.reviewScore : null,
          reviewCount: options.applyReviews ? result.reviewCount : null,
          coverImage: options.applyImage ? imagePath : null,
          updatedAt: DateTime.now(),
        ),
        tagIds: tagIds,
      );
      // A switch during any database await rolls back the entire operation.
      _checkSession();
    });
  }
}
