/// Game model with additional computed properties and utilities
/// This extends the database model with business logic
library;

import 'package:flutter/material.dart';

import '../core/constants/platform_patterns.dart';
import '../core/database/database.dart';
import '../core/utils/color_utils.dart';

/// Extended game model with tags and computed properties
class Game {
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
    this.reviewScore = 0,
    this.reviewCount = 0,
    this.tags = const [],
  }) : updatedAt = updatedAt ?? dateAdded;

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
      tags: tags,
    );
  }

  /// Get platform enum
  GamePlatform get platformEnum => GamePlatform.fromDisplayName(platform);

  /// Check if the deadline has passed
  bool get isExpired {
    if (!hasDeadline || deadlineDate == null) return false;
    return DateTime.now().isAfter(deadlineDate!);
  }

  /// Check if deadline is within 7 days
  bool get isDeadlineSoon {
    if (!hasDeadline || deadlineDate == null) return false;
    final daysUntil = deadlineDate!.difference(DateTime.now()).inDays;
    return daysUntil >= 0 && daysUntil <= 7;
  }

  /// Get days until deadline
  int? get daysUntilDeadline {
    if (!hasDeadline || deadlineDate == null) return null;
    return deadlineDate!.difference(DateTime.now()).inDays;
  }

  /// Check if game has a cover image
  bool get hasCoverImage => coverImage.isNotEmpty;

  /// Get review rating as a string (e.g., "Very Positive")
  String get reviewRating {
    if (reviewCount == 0) return 'No Reviews';
    if (reviewScore >= 95) return 'Overwhelmingly Positive';
    if (reviewScore >= 80) return 'Very Positive';
    if (reviewScore >= 70) return 'Mostly Positive';
    if (reviewScore >= 40) return 'Mixed';
    if (reviewScore >= 20) return 'Mostly Negative';
    return 'Very Negative';
  }

  /// Get review rating color
  Color get reviewColor {
    if (reviewCount == 0) return Colors.grey;
    if (reviewScore >= 70) return Colors.green;
    if (reviewScore >= 40) return Colors.orange;
    return Colors.red;
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
    DateTime? deadlineDate,
    bool? isDlc,
    String? steamAppId,
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
      deadlineDate: deadlineDate ?? this.deadlineDate,
      isDlc: isDlc ?? this.isDlc,
      steamAppId: steamAppId ?? this.steamAppId,
      reviewScore: reviewScore ?? this.reviewScore,
      reviewCount: reviewCount ?? this.reviewCount,
      tags: tags ?? this.tags,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Game && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
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
  Tag copyWith({
    int? id,
    String? name,
    String? colorHex,
    bool? isSteamTag,
  }) {
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
    return other is Tag && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
