library;

import '../../core/services/steam_service.dart';
import '../../models/game.dart';

class SteamPreviewData {
  const SteamPreviewData({
    required this.appId,
    required this.isDlc,
    this.coverImagePath,
    this.reviewScore,
    this.reviewCount,
  });

  final String appId;
  final bool isDlc;
  final String? coverImagePath;
  final int? reviewScore;
  final int? reviewCount;
}

class SteamResultMapper {
  SteamResultMapper._();

  static SteamPreviewData toPreviewData(
    SteamSearchResult result, {
    String? downloadedImagePath,
  }) {
    return SteamPreviewData(
      appId: result.appId,
      isDlc: result.isDlc,
      coverImagePath: downloadedImagePath ?? result.imageUrl,
      reviewScore: result.reviewScore,
      reviewCount: result.reviewCount,
    );
  }

  static Game applyToGame(
    Game game,
    SteamSearchResult result, {
    String? downloadedImagePath,
  }) {
    return game.copyWith(
      isDlc: result.isDlc,
      steamAppId: result.appId,
      reviewScore: result.reviewScore ?? game.reviewScore,
      reviewCount: result.reviewCount ?? game.reviewCount,
      coverImage: downloadedImagePath ?? (result.imageUrl ?? game.coverImage),
    );
  }
}
