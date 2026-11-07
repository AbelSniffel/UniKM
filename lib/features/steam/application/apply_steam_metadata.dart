import '../../../core/database/database.dart';
import '../../../core/services/steam_service.dart';
import '../../library/data/library_repository.dart';

/// Applies everything fetched to the latest row in the originating session.
class ApplySteamMetadata {
  const ApplySteamMetadata({
    required this.database,
    required this.isCurrent,
    required this.downloadImage,
  });

  final AppDatabase database;
  final bool Function() isCurrent;
  /// Saves [appId]'s artwork as the cover for games titled [title].
  final Future<String?> Function(String appId, String title) downloadImage;

  void _checkSession() {
    if (!isCurrent()) {
      throw StateError('Database session changed or operation cancelled');
    }
  }

  Future<void> apply(int gameId, SteamSearchResult result) async {
    _checkSession();
    String? imagePath;
    try {
      final title = (await database.getGameById(gameId))?.title ?? '';
      imagePath = await downloadImage(result.appId, title);
    } catch (_) {
      // Keep the current cover if artwork cannot be downloaded.
    }
    _checkSession();
    await database.transaction(() async {
      _checkSession();
      final game = await database.getGameById(gameId);
      if (game == null) throw StateError('The game no longer exists');
      List<int>? tagIds;
      if (result.tags.isNotEmpty) {
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
          steamAppId: result.appId,
          developer: result.developer,
          reviewScore: result.reviewScore,
          reviewCount: result.reviewCount,
          coverImage: imagePath,
          updatedAt: DateTime.now(),
        ),
        tagIds: tagIds,
      );
      // A switch during any database await rolls back the entire operation.
      _checkSession();
    });
  }
}
