/// Game model with additional computed properties and utilities
/// This extends the database model with business logic
library;

import 'package:flutter/material.dart';
import 'package:collection/collection.dart';

import '../core/constants/platform_patterns.dart';
import '../core/database/database.dart';
import '../core/utils/color_utils.dart';
import '../shared/time/calendar_date.dart';

/// Extended game model with tags and computed properties
class Game {
  static const _unchanged = Object();
  Game({
    required this.id,
    required this.title,
    required this.gameKey,
    required this.platform,
    required this.dateAdded,
    DateTime? updatedAt,
    this.notes = '',
    this.isUsed = false,
    this.coverImage = '',
    this.hasDeadline = false,
    this.deadlineDate,
    this.isDlc = false,
    this.steamAppId = '',
    this.developer = '',
    this.reviewScore = 0,
    this.reviewCount = 0,
    List<Tag> tags = const [],
  }) : tags = List.unmodifiable(tags),
       updatedAt = updatedAt ?? dateAdded;

  final int id;
  final String title;
  final String gameKey;
  final String platform;
  final DateTime dateAdded;
  final DateTime updatedAt;
  final String notes;
  final bool isUsed;
  final String coverImage;
  final bool hasDeadline;
  final DateTime? deadlineDate;
  final bool isDlc;
  final String steamAppId;
  final String developer;
  final int reviewScore;
  final int reviewCount;
  final List<Tag> tags;

  /// Create from database entry
  factory Game.fromEntry(GameEntry entry, {List<Tag> tags = const []}) {
    return Game(
      id: entry.id,
      title: entry.title,
      gameKey: entry.gameKey,
      platform: entry.platform,
      dateAdded: entry.dateAdded,
      updatedAt: entry.updatedAt,
      notes: entry.notes,
      isUsed: entry.isUsed,
      coverImage: entry.coverImage,
      hasDeadline: entry.hasDeadline,
      deadlineDate: entry.deadlineDate,
      isDlc: entry.isDlc,
      steamAppId: entry.steamAppId,
      reviewScore: entry.reviewScore,
      reviewCount: entry.reviewCount,
      developer: entry.developer,
      tags: tags,
    );
  }

  /// Get platform enum
  GamePlatform get platformEnum => GamePlatform.fromDisplayName(platform);

  DateTime? get _deadlineDateOnly {
    if (!hasDeadline || deadlineDate == null) return null;
    return DateUtils.dateOnly(deadlineDate!);
  }

  /// Get days until deadline using date-only values.
  int? get daysUntilDeadline {
    final normalizedDeadline = _deadlineDateOnly;
    if (normalizedDeadline == null) return null;

    final today = DateUtils.dateOnly(DateTime.now());
    return calendarDaysUntil(normalizedDeadline, today);
  }

  /// Check if the deadline has passed.
  bool get isExpired {
    final daysUntil = daysUntilDeadline;
    return daysUntil != null && daysUntil < 0;
  }

  /// Check if game has a cover image
  bool get hasCoverImage => coverImage.isNotEmpty;

  /// Get review rating for a given score (static helper for external use)
  static String reviewRatingFor(int score) {
    if (score >= 95) return 'Overwhelmingly Positive';
    if (score >= 80) return 'Very Positive';
    if (score >= 70) return 'Mostly Positive';
    if (score >= 40) return 'Mixed';
    if (score >= 20) return 'Mostly Negative';
    return 'Very Negative';
  }

  /// Get review rating as a string (e.g., "Very Positive")
  String get reviewRating {
    if (reviewCount == 0) return 'No Reviews';
    return reviewRatingFor(reviewScore);
  }

  /// Resolve negative review styling with the current theme color.
  Color reviewColorFor({required Color negativeColor}) {
    if (reviewCount == 0) return Colors.grey;
    if (reviewScore >= 70) return Colors.green;
    if (reviewScore >= 40) return Colors.orange;
    return negativeColor;
  }

  /// Alias for dateAdded (createdAt)
  DateTime get createdAt => dateAdded;

  /// Get rating (alias for reviewScore for UI compatibility)
  int get rating => reviewScore;

  /// Get tag IDs
  List<int> get tagIds => tags.map((t) => t.id).toList();

  /// Copy with new values
  Game copyWith({
    int? id,
    String? title,
    String? gameKey,
    String? platform,
    DateTime? dateAdded,
    DateTime? updatedAt,
    String? notes,
    bool? isUsed,
    String? coverImage,
    bool? hasDeadline,
    Object? deadlineDate = _unchanged,
    bool? isDlc,
    String? steamAppId,
    String? developer,
    int? reviewScore,
    int? reviewCount,
    List<Tag>? tags,
  }) {
    return Game(
      id: id ?? this.id,
      title: title ?? this.title,
      gameKey: gameKey ?? this.gameKey,
      platform: platform ?? this.platform,
      dateAdded: dateAdded ?? this.dateAdded,
      updatedAt: updatedAt ?? this.updatedAt,
      notes: notes ?? this.notes,
      isUsed: isUsed ?? this.isUsed,
      coverImage: coverImage ?? this.coverImage,
      hasDeadline: hasDeadline ?? this.hasDeadline,
      deadlineDate: identical(deadlineDate, _unchanged)
          ? this.deadlineDate
          : deadlineDate as DateTime?,
      isDlc: isDlc ?? this.isDlc,
      steamAppId: steamAppId ?? this.steamAppId,
      developer: developer ?? this.developer,
      reviewScore: reviewScore ?? this.reviewScore,
      reviewCount: reviewCount ?? this.reviewCount,
      tags: tags ?? this.tags,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Game &&
        id == other.id &&
        title == other.title &&
        gameKey == other.gameKey &&
        platform == other.platform &&
        dateAdded == other.dateAdded &&
        updatedAt == other.updatedAt &&
        notes == other.notes &&
        isUsed == other.isUsed &&
        coverImage == other.coverImage &&
        hasDeadline == other.hasDeadline &&
        deadlineDate == other.deadlineDate &&
        isDlc == other.isDlc &&
        steamAppId == other.steamAppId &&
        developer == other.developer &&
        reviewScore == other.reviewScore &&
        reviewCount == other.reviewCount &&
        const ListEquality<Tag>().equals(tags, other.tags);
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    gameKey,
    platform,
    dateAdded,
    updatedAt,
    notes,
    isUsed,
    coverImage,
    hasDeadline,
    deadlineDate,
    isDlc,
    steamAppId,
    developer,
    reviewScore,
    reviewCount,
    const ListEquality<Tag>().hash(tags),
  );
}

/// Tag model with color parsing
class Tag {
  Tag({
    required this.id,
    required this.name,
    required this.colorHex,
    this.isSteamTag = false,
  });

  final int id;
  final String name;
  final String colorHex;
  final bool isSteamTag;

  /// Cached parsed color (lazy initialization)
  Color? _cachedColor;

  /// Create from database entry
  factory Tag.fromEntry(TagEntry entry) {
    return Tag(
      id: entry.id,
      name: entry.name,
      colorHex: entry.color,
      isSteamTag: entry.isSteamTag,
    );
  }

  /// Parse and cache color from hex string
  Color get color => _cachedColor ??= parseHexColor(colorHex);

  /// Get contrasting text color (black or white)
  Color get textColor => contrastColor(color);

  /// Copy with new values
  Tag copyWith({int? id, String? name, String? colorHex, bool? isSteamTag}) {
    return Tag(
      id: id ?? this.id,
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      isSteamTag: isSteamTag ?? this.isSteamTag,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Tag &&
        other.id == id &&
        other.name == name &&
        other.colorHex == colorHex &&
        other.isSteamTag == isSteamTag;
  }

  @override
  int get hashCode => Object.hash(id, name, colorHex, isSteamTag);
}
