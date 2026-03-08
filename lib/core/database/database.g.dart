// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $GamesTable extends Games with TableInfo<$GamesTable, GameEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GamesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 500,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gameKeyMeta = const VerificationMeta(
    'gameKey',
  );
  @override
  late final GeneratedColumn<String> gameKey = GeneratedColumn<String>(
    'game_key',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 500,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _platformMeta = const VerificationMeta(
    'platform',
  );
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Steam'),
  );
  static const VerificationMeta _dateAddedMeta = const VerificationMeta(
    'dateAdded',
  );
  @override
  late final GeneratedColumn<DateTime> dateAdded = GeneratedColumn<DateTime>(
    'date_added',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _isUsedMeta = const VerificationMeta('isUsed');
  @override
  late final GeneratedColumn<bool> isUsed = GeneratedColumn<bool>(
    'is_used',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_used" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _coverImageMeta = const VerificationMeta(
    'coverImage',
  );
  @override
  late final GeneratedColumn<String> coverImage = GeneratedColumn<String>(
    'cover_image',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _hasDeadlineMeta = const VerificationMeta(
    'hasDeadline',
  );
  @override
  late final GeneratedColumn<bool> hasDeadline = GeneratedColumn<bool>(
    'has_deadline',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_deadline" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deadlineDateMeta = const VerificationMeta(
    'deadlineDate',
  );
  @override
  late final GeneratedColumn<DateTime> deadlineDate = GeneratedColumn<DateTime>(
    'deadline_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isDlcMeta = const VerificationMeta('isDlc');
  @override
  late final GeneratedColumn<bool> isDlc = GeneratedColumn<bool>(
    'is_dlc',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_dlc" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _steamAppIdMeta = const VerificationMeta(
    'steamAppId',
  );
  @override
  late final GeneratedColumn<String> steamAppId = GeneratedColumn<String>(
    'steam_app_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _reviewScoreMeta = const VerificationMeta(
    'reviewScore',
  );
  @override
  late final GeneratedColumn<int> reviewScore = GeneratedColumn<int>(
    'review_score',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _reviewCountMeta = const VerificationMeta(
    'reviewCount',
  );
  @override
  late final GeneratedColumn<int> reviewCount = GeneratedColumn<int>(
    'review_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
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
    reviewScore,
    reviewCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'games';
  @override
  VerificationContext validateIntegrity(
    Insertable<GameEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('game_key')) {
      context.handle(
        _gameKeyMeta,
        gameKey.isAcceptableOrUnknown(data['game_key']!, _gameKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_gameKeyMeta);
    }
    if (data.containsKey('platform')) {
      context.handle(
        _platformMeta,
        platform.isAcceptableOrUnknown(data['platform']!, _platformMeta),
      );
    }
    if (data.containsKey('date_added')) {
      context.handle(
        _dateAddedMeta,
        dateAdded.isAcceptableOrUnknown(data['date_added']!, _dateAddedMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('is_used')) {
      context.handle(
        _isUsedMeta,
        isUsed.isAcceptableOrUnknown(data['is_used']!, _isUsedMeta),
      );
    }
    if (data.containsKey('cover_image')) {
      context.handle(
        _coverImageMeta,
        coverImage.isAcceptableOrUnknown(data['cover_image']!, _coverImageMeta),
      );
    }
    if (data.containsKey('has_deadline')) {
      context.handle(
        _hasDeadlineMeta,
        hasDeadline.isAcceptableOrUnknown(
          data['has_deadline']!,
          _hasDeadlineMeta,
        ),
      );
    }
    if (data.containsKey('deadline_date')) {
      context.handle(
        _deadlineDateMeta,
        deadlineDate.isAcceptableOrUnknown(
          data['deadline_date']!,
          _deadlineDateMeta,
        ),
      );
    }
    if (data.containsKey('is_dlc')) {
      context.handle(
        _isDlcMeta,
        isDlc.isAcceptableOrUnknown(data['is_dlc']!, _isDlcMeta),
      );
    }
    if (data.containsKey('steam_app_id')) {
      context.handle(
        _steamAppIdMeta,
        steamAppId.isAcceptableOrUnknown(
          data['steam_app_id']!,
          _steamAppIdMeta,
        ),
      );
    }
    if (data.containsKey('review_score')) {
      context.handle(
        _reviewScoreMeta,
        reviewScore.isAcceptableOrUnknown(
          data['review_score']!,
          _reviewScoreMeta,
        ),
      );
    }
    if (data.containsKey('review_count')) {
      context.handle(
        _reviewCountMeta,
        reviewCount.isAcceptableOrUnknown(
          data['review_count']!,
          _reviewCountMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GameEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GameEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      gameKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}game_key'],
      )!,
      platform: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}platform'],
      )!,
      dateAdded: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date_added'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
      isUsed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_used'],
      )!,
      coverImage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_image'],
      )!,
      hasDeadline: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_deadline'],
      )!,
      deadlineDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deadline_date'],
      ),
      isDlc: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_dlc'],
      )!,
      steamAppId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}steam_app_id'],
      )!,
      reviewScore: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}review_score'],
      )!,
      reviewCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}review_count'],
      )!,
    );
  }

  @override
  $GamesTable createAlias(String alias) {
    return $GamesTable(attachedDatabase, alias);
  }
}

class GameEntry extends DataClass implements Insertable<GameEntry> {
  /// Primary key, auto-increment
  final int id;

  /// Game title (required)
  final String title;

  /// Activation key (required)
  final String gameKey;

  /// Platform (Steam, Epic, GOG, etc.)
  final String platform;

  /// Date the game was added to the database
  final DateTime dateAdded;

  /// Date the game was last updated in the database
  final DateTime updatedAt;

  /// User notes
  final String notes;

  /// Whether the key has been redeemed/used
  final bool isUsed;

  /// Path or URL to cover image
  final String coverImage;

  /// Whether the game has a time-limited redemption deadline
  final bool hasDeadline;

  /// The deadline datetime (if hasDeadline is true)
  final DateTime? deadlineDate;

  /// Whether this is DLC content
  final bool isDlc;

  /// Steam AppID for API integration
  final String steamAppId;

  /// Review score from Steam (0-100)
  final int reviewScore;

  /// Number of reviews from Steam
  final int reviewCount;
  const GameEntry({
    required this.id,
    required this.title,
    required this.gameKey,
    required this.platform,
    required this.dateAdded,
    required this.updatedAt,
    required this.notes,
    required this.isUsed,
    required this.coverImage,
    required this.hasDeadline,
    this.deadlineDate,
    required this.isDlc,
    required this.steamAppId,
    required this.reviewScore,
    required this.reviewCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    map['game_key'] = Variable<String>(gameKey);
    map['platform'] = Variable<String>(platform);
    map['date_added'] = Variable<DateTime>(dateAdded);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['notes'] = Variable<String>(notes);
    map['is_used'] = Variable<bool>(isUsed);
    map['cover_image'] = Variable<String>(coverImage);
    map['has_deadline'] = Variable<bool>(hasDeadline);
    if (!nullToAbsent || deadlineDate != null) {
      map['deadline_date'] = Variable<DateTime>(deadlineDate);
    }
    map['is_dlc'] = Variable<bool>(isDlc);
    map['steam_app_id'] = Variable<String>(steamAppId);
    map['review_score'] = Variable<int>(reviewScore);
    map['review_count'] = Variable<int>(reviewCount);
    return map;
  }

  GamesCompanion toCompanion(bool nullToAbsent) {
    return GamesCompanion(
      id: Value(id),
      title: Value(title),
      gameKey: Value(gameKey),
      platform: Value(platform),
      dateAdded: Value(dateAdded),
      updatedAt: Value(updatedAt),
      notes: Value(notes),
      isUsed: Value(isUsed),
      coverImage: Value(coverImage),
      hasDeadline: Value(hasDeadline),
      deadlineDate: deadlineDate == null && nullToAbsent
          ? const Value.absent()
          : Value(deadlineDate),
      isDlc: Value(isDlc),
      steamAppId: Value(steamAppId),
      reviewScore: Value(reviewScore),
      reviewCount: Value(reviewCount),
    );
  }

  factory GameEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GameEntry(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      gameKey: serializer.fromJson<String>(json['gameKey']),
      platform: serializer.fromJson<String>(json['platform']),
      dateAdded: serializer.fromJson<DateTime>(json['dateAdded']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      notes: serializer.fromJson<String>(json['notes']),
      isUsed: serializer.fromJson<bool>(json['isUsed']),
      coverImage: serializer.fromJson<String>(json['coverImage']),
      hasDeadline: serializer.fromJson<bool>(json['hasDeadline']),
      deadlineDate: serializer.fromJson<DateTime?>(json['deadlineDate']),
      isDlc: serializer.fromJson<bool>(json['isDlc']),
      steamAppId: serializer.fromJson<String>(json['steamAppId']),
      reviewScore: serializer.fromJson<int>(json['reviewScore']),
      reviewCount: serializer.fromJson<int>(json['reviewCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'gameKey': serializer.toJson<String>(gameKey),
      'platform': serializer.toJson<String>(platform),
      'dateAdded': serializer.toJson<DateTime>(dateAdded),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'notes': serializer.toJson<String>(notes),
      'isUsed': serializer.toJson<bool>(isUsed),
      'coverImage': serializer.toJson<String>(coverImage),
      'hasDeadline': serializer.toJson<bool>(hasDeadline),
      'deadlineDate': serializer.toJson<DateTime?>(deadlineDate),
      'isDlc': serializer.toJson<bool>(isDlc),
      'steamAppId': serializer.toJson<String>(steamAppId),
      'reviewScore': serializer.toJson<int>(reviewScore),
      'reviewCount': serializer.toJson<int>(reviewCount),
    };
  }

  GameEntry copyWith({
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
    Value<DateTime?> deadlineDate = const Value.absent(),
    bool? isDlc,
    String? steamAppId,
    int? reviewScore,
    int? reviewCount,
  }) => GameEntry(
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
    deadlineDate: deadlineDate.present ? deadlineDate.value : this.deadlineDate,
    isDlc: isDlc ?? this.isDlc,
    steamAppId: steamAppId ?? this.steamAppId,
    reviewScore: reviewScore ?? this.reviewScore,
    reviewCount: reviewCount ?? this.reviewCount,
  );
  GameEntry copyWithCompanion(GamesCompanion data) {
    return GameEntry(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      gameKey: data.gameKey.present ? data.gameKey.value : this.gameKey,
      platform: data.platform.present ? data.platform.value : this.platform,
      dateAdded: data.dateAdded.present ? data.dateAdded.value : this.dateAdded,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      notes: data.notes.present ? data.notes.value : this.notes,
      isUsed: data.isUsed.present ? data.isUsed.value : this.isUsed,
      coverImage: data.coverImage.present
          ? data.coverImage.value
          : this.coverImage,
      hasDeadline: data.hasDeadline.present
          ? data.hasDeadline.value
          : this.hasDeadline,
      deadlineDate: data.deadlineDate.present
          ? data.deadlineDate.value
          : this.deadlineDate,
      isDlc: data.isDlc.present ? data.isDlc.value : this.isDlc,
      steamAppId: data.steamAppId.present
          ? data.steamAppId.value
          : this.steamAppId,
      reviewScore: data.reviewScore.present
          ? data.reviewScore.value
          : this.reviewScore,
      reviewCount: data.reviewCount.present
          ? data.reviewCount.value
          : this.reviewCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GameEntry(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('gameKey: $gameKey, ')
          ..write('platform: $platform, ')
          ..write('dateAdded: $dateAdded, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('notes: $notes, ')
          ..write('isUsed: $isUsed, ')
          ..write('coverImage: $coverImage, ')
          ..write('hasDeadline: $hasDeadline, ')
          ..write('deadlineDate: $deadlineDate, ')
          ..write('isDlc: $isDlc, ')
          ..write('steamAppId: $steamAppId, ')
          ..write('reviewScore: $reviewScore, ')
          ..write('reviewCount: $reviewCount')
          ..write(')'))
        .toString();
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
    reviewScore,
    reviewCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GameEntry &&
          other.id == this.id &&
          other.title == this.title &&
          other.gameKey == this.gameKey &&
          other.platform == this.platform &&
          other.dateAdded == this.dateAdded &&
          other.updatedAt == this.updatedAt &&
          other.notes == this.notes &&
          other.isUsed == this.isUsed &&
          other.coverImage == this.coverImage &&
          other.hasDeadline == this.hasDeadline &&
          other.deadlineDate == this.deadlineDate &&
          other.isDlc == this.isDlc &&
          other.steamAppId == this.steamAppId &&
          other.reviewScore == this.reviewScore &&
          other.reviewCount == this.reviewCount);
}

class GamesCompanion extends UpdateCompanion<GameEntry> {
  final Value<int> id;
  final Value<String> title;
  final Value<String> gameKey;
  final Value<String> platform;
  final Value<DateTime> dateAdded;
  final Value<DateTime> updatedAt;
  final Value<String> notes;
  final Value<bool> isUsed;
  final Value<String> coverImage;
  final Value<bool> hasDeadline;
  final Value<DateTime?> deadlineDate;
  final Value<bool> isDlc;
  final Value<String> steamAppId;
  final Value<int> reviewScore;
  final Value<int> reviewCount;
  const GamesCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.gameKey = const Value.absent(),
    this.platform = const Value.absent(),
    this.dateAdded = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.notes = const Value.absent(),
    this.isUsed = const Value.absent(),
    this.coverImage = const Value.absent(),
    this.hasDeadline = const Value.absent(),
    this.deadlineDate = const Value.absent(),
    this.isDlc = const Value.absent(),
    this.steamAppId = const Value.absent(),
    this.reviewScore = const Value.absent(),
    this.reviewCount = const Value.absent(),
  });
  GamesCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    required String gameKey,
    this.platform = const Value.absent(),
    this.dateAdded = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.notes = const Value.absent(),
    this.isUsed = const Value.absent(),
    this.coverImage = const Value.absent(),
    this.hasDeadline = const Value.absent(),
    this.deadlineDate = const Value.absent(),
    this.isDlc = const Value.absent(),
    this.steamAppId = const Value.absent(),
    this.reviewScore = const Value.absent(),
    this.reviewCount = const Value.absent(),
  }) : title = Value(title),
       gameKey = Value(gameKey);
  static Insertable<GameEntry> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<String>? gameKey,
    Expression<String>? platform,
    Expression<DateTime>? dateAdded,
    Expression<DateTime>? updatedAt,
    Expression<String>? notes,
    Expression<bool>? isUsed,
    Expression<String>? coverImage,
    Expression<bool>? hasDeadline,
    Expression<DateTime>? deadlineDate,
    Expression<bool>? isDlc,
    Expression<String>? steamAppId,
    Expression<int>? reviewScore,
    Expression<int>? reviewCount,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (gameKey != null) 'game_key': gameKey,
      if (platform != null) 'platform': platform,
      if (dateAdded != null) 'date_added': dateAdded,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (notes != null) 'notes': notes,
      if (isUsed != null) 'is_used': isUsed,
      if (coverImage != null) 'cover_image': coverImage,
      if (hasDeadline != null) 'has_deadline': hasDeadline,
      if (deadlineDate != null) 'deadline_date': deadlineDate,
      if (isDlc != null) 'is_dlc': isDlc,
      if (steamAppId != null) 'steam_app_id': steamAppId,
      if (reviewScore != null) 'review_score': reviewScore,
      if (reviewCount != null) 'review_count': reviewCount,
    });
  }

  GamesCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<String>? gameKey,
    Value<String>? platform,
    Value<DateTime>? dateAdded,
    Value<DateTime>? updatedAt,
    Value<String>? notes,
    Value<bool>? isUsed,
    Value<String>? coverImage,
    Value<bool>? hasDeadline,
    Value<DateTime?>? deadlineDate,
    Value<bool>? isDlc,
    Value<String>? steamAppId,
    Value<int>? reviewScore,
    Value<int>? reviewCount,
  }) {
    return GamesCompanion(
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
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (gameKey.present) {
      map['game_key'] = Variable<String>(gameKey.value);
    }
    if (platform.present) {
      map['platform'] = Variable<String>(platform.value);
    }
    if (dateAdded.present) {
      map['date_added'] = Variable<DateTime>(dateAdded.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (isUsed.present) {
      map['is_used'] = Variable<bool>(isUsed.value);
    }
    if (coverImage.present) {
      map['cover_image'] = Variable<String>(coverImage.value);
    }
    if (hasDeadline.present) {
      map['has_deadline'] = Variable<bool>(hasDeadline.value);
    }
    if (deadlineDate.present) {
      map['deadline_date'] = Variable<DateTime>(deadlineDate.value);
    }
    if (isDlc.present) {
      map['is_dlc'] = Variable<bool>(isDlc.value);
    }
    if (steamAppId.present) {
      map['steam_app_id'] = Variable<String>(steamAppId.value);
    }
    if (reviewScore.present) {
      map['review_score'] = Variable<int>(reviewScore.value);
    }
    if (reviewCount.present) {
      map['review_count'] = Variable<int>(reviewCount.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GamesCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('gameKey: $gameKey, ')
          ..write('platform: $platform, ')
          ..write('dateAdded: $dateAdded, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('notes: $notes, ')
          ..write('isUsed: $isUsed, ')
          ..write('coverImage: $coverImage, ')
          ..write('hasDeadline: $hasDeadline, ')
          ..write('deadlineDate: $deadlineDate, ')
          ..write('isDlc: $isDlc, ')
          ..write('steamAppId: $steamAppId, ')
          ..write('reviewScore: $reviewScore, ')
          ..write('reviewCount: $reviewCount')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, TagEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 100,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('#0078d4'),
  );
  static const VerificationMeta _isSteamTagMeta = const VerificationMeta(
    'isSteamTag',
  );
  @override
  late final GeneratedColumn<bool> isSteamTag = GeneratedColumn<bool>(
    'is_steam_tag',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_steam_tag" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, color, isSteamTag];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<TagEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('is_steam_tag')) {
      context.handle(
        _isSteamTagMeta,
        isSteamTag.isAcceptableOrUnknown(
          data['is_steam_tag']!,
          _isSteamTagMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TagEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TagEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      )!,
      isSteamTag: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_steam_tag'],
      )!,
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }
}

class TagEntry extends DataClass implements Insertable<TagEntry> {
  /// Primary key, auto-increment
  final int id;

  /// Tag name (unique)
  final String name;

  /// Hex color code (e.g., #0078d4)
  final String color;

  /// Whether this tag was fetched from Steam
  final bool isSteamTag;
  const TagEntry({
    required this.id,
    required this.name,
    required this.color,
    required this.isSteamTag,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['color'] = Variable<String>(color);
    map['is_steam_tag'] = Variable<bool>(isSteamTag);
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      id: Value(id),
      name: Value(name),
      color: Value(color),
      isSteamTag: Value(isSteamTag),
    );
  }

  factory TagEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TagEntry(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<String>(json['color']),
      isSteamTag: serializer.fromJson<bool>(json['isSteamTag']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<String>(color),
      'isSteamTag': serializer.toJson<bool>(isSteamTag),
    };
  }

  TagEntry copyWith({int? id, String? name, String? color, bool? isSteamTag}) =>
      TagEntry(
        id: id ?? this.id,
        name: name ?? this.name,
        color: color ?? this.color,
        isSteamTag: isSteamTag ?? this.isSteamTag,
      );
  TagEntry copyWithCompanion(TagsCompanion data) {
    return TagEntry(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
      isSteamTag: data.isSteamTag.present
          ? data.isSteamTag.value
          : this.isSteamTag,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TagEntry(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('isSteamTag: $isSteamTag')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, color, isSteamTag);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TagEntry &&
          other.id == this.id &&
          other.name == this.name &&
          other.color == this.color &&
          other.isSteamTag == this.isSteamTag);
}

class TagsCompanion extends UpdateCompanion<TagEntry> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> color;
  final Value<bool> isSteamTag;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.isSteamTag = const Value.absent(),
  });
  TagsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.color = const Value.absent(),
    this.isSteamTag = const Value.absent(),
  }) : name = Value(name);
  static Insertable<TagEntry> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? color,
    Expression<bool>? isSteamTag,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (isSteamTag != null) 'is_steam_tag': isSteamTag,
    });
  }

  TagsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? color,
    Value<bool>? isSteamTag,
  }) {
    return TagsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      isSteamTag: isSteamTag ?? this.isSteamTag,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (isSteamTag.present) {
      map['is_steam_tag'] = Variable<bool>(isSteamTag.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('isSteamTag: $isSteamTag')
          ..write(')'))
        .toString();
  }
}

class $GameTagsTable extends GameTags
    with TableInfo<$GameTagsTable, GameTagEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GameTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _gameIdMeta = const VerificationMeta('gameId');
  @override
  late final GeneratedColumn<int> gameId = GeneratedColumn<int>(
    'game_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES games (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<int> tagId = GeneratedColumn<int>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tags (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [gameId, tagId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'game_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<GameTagEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('game_id')) {
      context.handle(
        _gameIdMeta,
        gameId.isAcceptableOrUnknown(data['game_id']!, _gameIdMeta),
      );
    } else if (isInserting) {
      context.missing(_gameIdMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {gameId, tagId};
  @override
  GameTagEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GameTagEntry(
      gameId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}game_id'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tag_id'],
      )!,
    );
  }

  @override
  $GameTagsTable createAlias(String alias) {
    return $GameTagsTable(attachedDatabase, alias);
  }
}

class GameTagEntry extends DataClass implements Insertable<GameTagEntry> {
  /// Foreign key to games.id (CASCADE delete)
  final int gameId;

  /// Foreign key to tags.id (CASCADE delete)
  final int tagId;
  const GameTagEntry({required this.gameId, required this.tagId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['game_id'] = Variable<int>(gameId);
    map['tag_id'] = Variable<int>(tagId);
    return map;
  }

  GameTagsCompanion toCompanion(bool nullToAbsent) {
    return GameTagsCompanion(gameId: Value(gameId), tagId: Value(tagId));
  }

  factory GameTagEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GameTagEntry(
      gameId: serializer.fromJson<int>(json['gameId']),
      tagId: serializer.fromJson<int>(json['tagId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'gameId': serializer.toJson<int>(gameId),
      'tagId': serializer.toJson<int>(tagId),
    };
  }

  GameTagEntry copyWith({int? gameId, int? tagId}) =>
      GameTagEntry(gameId: gameId ?? this.gameId, tagId: tagId ?? this.tagId);
  GameTagEntry copyWithCompanion(GameTagsCompanion data) {
    return GameTagEntry(
      gameId: data.gameId.present ? data.gameId.value : this.gameId,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GameTagEntry(')
          ..write('gameId: $gameId, ')
          ..write('tagId: $tagId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(gameId, tagId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GameTagEntry &&
          other.gameId == this.gameId &&
          other.tagId == this.tagId);
}

class GameTagsCompanion extends UpdateCompanion<GameTagEntry> {
  final Value<int> gameId;
  final Value<int> tagId;
  final Value<int> rowid;
  const GameTagsCompanion({
    this.gameId = const Value.absent(),
    this.tagId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GameTagsCompanion.insert({
    required int gameId,
    required int tagId,
    this.rowid = const Value.absent(),
  }) : gameId = Value(gameId),
       tagId = Value(tagId);
  static Insertable<GameTagEntry> custom({
    Expression<int>? gameId,
    Expression<int>? tagId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (gameId != null) 'game_id': gameId,
      if (tagId != null) 'tag_id': tagId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GameTagsCompanion copyWith({
    Value<int>? gameId,
    Value<int>? tagId,
    Value<int>? rowid,
  }) {
    return GameTagsCompanion(
      gameId: gameId ?? this.gameId,
      tagId: tagId ?? this.tagId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (gameId.present) {
      map['game_id'] = Variable<int>(gameId.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<int>(tagId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GameTagsCompanion(')
          ..write('gameId: $gameId, ')
          ..write('tagId: $tagId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BackupsTable extends Backups with TableInfo<$BackupsTable, BackupEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BackupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _filenameMeta = const VerificationMeta(
    'filename',
  );
  @override
  late final GeneratedColumn<String> filename = GeneratedColumn<String>(
    'filename',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('auto'),
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    filename,
    createdAt,
    label,
    sizeBytes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'backups';
  @override
  VerificationContext validateIntegrity(
    Insertable<BackupEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('filename')) {
      context.handle(
        _filenameMeta,
        filename.isAcceptableOrUnknown(data['filename']!, _filenameMeta),
      );
    } else if (isInserting) {
      context.missing(_filenameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BackupEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BackupEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      filename: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filename'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
    );
  }

  @override
  $BackupsTable createAlias(String alias) {
    return $BackupsTable(attachedDatabase, alias);
  }
}

class BackupEntry extends DataClass implements Insertable<BackupEntry> {
  /// Primary key, auto-increment
  final int id;

  /// Backup filename
  final String filename;

  /// Backup creation timestamp
  final DateTime createdAt;

  /// Backup label (manual, auto, pre-migration)
  final String label;

  /// File size in bytes
  final int sizeBytes;
  const BackupEntry({
    required this.id,
    required this.filename,
    required this.createdAt,
    required this.label,
    required this.sizeBytes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['filename'] = Variable<String>(filename);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['label'] = Variable<String>(label);
    map['size_bytes'] = Variable<int>(sizeBytes);
    return map;
  }

  BackupsCompanion toCompanion(bool nullToAbsent) {
    return BackupsCompanion(
      id: Value(id),
      filename: Value(filename),
      createdAt: Value(createdAt),
      label: Value(label),
      sizeBytes: Value(sizeBytes),
    );
  }

  factory BackupEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BackupEntry(
      id: serializer.fromJson<int>(json['id']),
      filename: serializer.fromJson<String>(json['filename']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      label: serializer.fromJson<String>(json['label']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'filename': serializer.toJson<String>(filename),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'label': serializer.toJson<String>(label),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
    };
  }

  BackupEntry copyWith({
    int? id,
    String? filename,
    DateTime? createdAt,
    String? label,
    int? sizeBytes,
  }) => BackupEntry(
    id: id ?? this.id,
    filename: filename ?? this.filename,
    createdAt: createdAt ?? this.createdAt,
    label: label ?? this.label,
    sizeBytes: sizeBytes ?? this.sizeBytes,
  );
  BackupEntry copyWithCompanion(BackupsCompanion data) {
    return BackupEntry(
      id: data.id.present ? data.id.value : this.id,
      filename: data.filename.present ? data.filename.value : this.filename,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      label: data.label.present ? data.label.value : this.label,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BackupEntry(')
          ..write('id: $id, ')
          ..write('filename: $filename, ')
          ..write('createdAt: $createdAt, ')
          ..write('label: $label, ')
          ..write('sizeBytes: $sizeBytes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, filename, createdAt, label, sizeBytes);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BackupEntry &&
          other.id == this.id &&
          other.filename == this.filename &&
          other.createdAt == this.createdAt &&
          other.label == this.label &&
          other.sizeBytes == this.sizeBytes);
}

class BackupsCompanion extends UpdateCompanion<BackupEntry> {
  final Value<int> id;
  final Value<String> filename;
  final Value<DateTime> createdAt;
  final Value<String> label;
  final Value<int> sizeBytes;
  const BackupsCompanion({
    this.id = const Value.absent(),
    this.filename = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.label = const Value.absent(),
    this.sizeBytes = const Value.absent(),
  });
  BackupsCompanion.insert({
    this.id = const Value.absent(),
    required String filename,
    this.createdAt = const Value.absent(),
    this.label = const Value.absent(),
    this.sizeBytes = const Value.absent(),
  }) : filename = Value(filename);
  static Insertable<BackupEntry> custom({
    Expression<int>? id,
    Expression<String>? filename,
    Expression<DateTime>? createdAt,
    Expression<String>? label,
    Expression<int>? sizeBytes,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (filename != null) 'filename': filename,
      if (createdAt != null) 'created_at': createdAt,
      if (label != null) 'label': label,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
    });
  }

  BackupsCompanion copyWith({
    Value<int>? id,
    Value<String>? filename,
    Value<DateTime>? createdAt,
    Value<String>? label,
    Value<int>? sizeBytes,
  }) {
    return BackupsCompanion(
      id: id ?? this.id,
      filename: filename ?? this.filename,
      createdAt: createdAt ?? this.createdAt,
      label: label ?? this.label,
      sizeBytes: sizeBytes ?? this.sizeBytes,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (filename.present) {
      map['filename'] = Variable<String>(filename.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BackupsCompanion(')
          ..write('id: $id, ')
          ..write('filename: $filename, ')
          ..write('createdAt: $createdAt, ')
          ..write('label: $label, ')
          ..write('sizeBytes: $sizeBytes')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $GamesTable games = $GamesTable(this);
  late final $TagsTable tags = $TagsTable(this);
  late final $GameTagsTable gameTags = $GameTagsTable(this);
  late final $BackupsTable backups = $BackupsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    games,
    tags,
    gameTags,
    backups,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'games',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('game_tags', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tags',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('game_tags', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$GamesTableCreateCompanionBuilder =
    GamesCompanion Function({
      Value<int> id,
      required String title,
      required String gameKey,
      Value<String> platform,
      Value<DateTime> dateAdded,
      Value<DateTime> updatedAt,
      Value<String> notes,
      Value<bool> isUsed,
      Value<String> coverImage,
      Value<bool> hasDeadline,
      Value<DateTime?> deadlineDate,
      Value<bool> isDlc,
      Value<String> steamAppId,
      Value<int> reviewScore,
      Value<int> reviewCount,
    });
typedef $$GamesTableUpdateCompanionBuilder =
    GamesCompanion Function({
      Value<int> id,
      Value<String> title,
      Value<String> gameKey,
      Value<String> platform,
      Value<DateTime> dateAdded,
      Value<DateTime> updatedAt,
      Value<String> notes,
      Value<bool> isUsed,
      Value<String> coverImage,
      Value<bool> hasDeadline,
      Value<DateTime?> deadlineDate,
      Value<bool> isDlc,
      Value<String> steamAppId,
      Value<int> reviewScore,
      Value<int> reviewCount,
    });

final class $$GamesTableReferences
    extends BaseReferences<_$AppDatabase, $GamesTable, GameEntry> {
  $$GamesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$GameTagsTable, List<GameTagEntry>>
  _gameTagsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.gameTags,
    aliasName: $_aliasNameGenerator(db.games.id, db.gameTags.gameId),
  );

  $$GameTagsTableProcessedTableManager get gameTagsRefs {
    final manager = $$GameTagsTableTableManager(
      $_db,
      $_db.gameTags,
    ).filter((f) => f.gameId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_gameTagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$GamesTableFilterComposer extends Composer<_$AppDatabase, $GamesTable> {
  $$GamesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gameKey => $composableBuilder(
    column: $table.gameKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isUsed => $composableBuilder(
    column: $table.isUsed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverImage => $composableBuilder(
    column: $table.coverImage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasDeadline => $composableBuilder(
    column: $table.hasDeadline,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deadlineDate => $composableBuilder(
    column: $table.deadlineDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDlc => $composableBuilder(
    column: $table.isDlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get steamAppId => $composableBuilder(
    column: $table.steamAppId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reviewScore => $composableBuilder(
    column: $table.reviewScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reviewCount => $composableBuilder(
    column: $table.reviewCount,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> gameTagsRefs(
    Expression<bool> Function($$GameTagsTableFilterComposer f) f,
  ) {
    final $$GameTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.gameTags,
      getReferencedColumn: (t) => t.gameId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GameTagsTableFilterComposer(
            $db: $db,
            $table: $db.gameTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GamesTableOrderingComposer
    extends Composer<_$AppDatabase, $GamesTable> {
  $$GamesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gameKey => $composableBuilder(
    column: $table.gameKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isUsed => $composableBuilder(
    column: $table.isUsed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverImage => $composableBuilder(
    column: $table.coverImage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasDeadline => $composableBuilder(
    column: $table.hasDeadline,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deadlineDate => $composableBuilder(
    column: $table.deadlineDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDlc => $composableBuilder(
    column: $table.isDlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get steamAppId => $composableBuilder(
    column: $table.steamAppId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reviewScore => $composableBuilder(
    column: $table.reviewScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reviewCount => $composableBuilder(
    column: $table.reviewCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GamesTableAnnotationComposer
    extends Composer<_$AppDatabase, $GamesTable> {
  $$GamesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get gameKey =>
      $composableBuilder(column: $table.gameKey, builder: (column) => column);

  GeneratedColumn<String> get platform =>
      $composableBuilder(column: $table.platform, builder: (column) => column);

  GeneratedColumn<DateTime> get dateAdded =>
      $composableBuilder(column: $table.dateAdded, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<bool> get isUsed =>
      $composableBuilder(column: $table.isUsed, builder: (column) => column);

  GeneratedColumn<String> get coverImage => $composableBuilder(
    column: $table.coverImage,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hasDeadline => $composableBuilder(
    column: $table.hasDeadline,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deadlineDate => $composableBuilder(
    column: $table.deadlineDate,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDlc =>
      $composableBuilder(column: $table.isDlc, builder: (column) => column);

  GeneratedColumn<String> get steamAppId => $composableBuilder(
    column: $table.steamAppId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reviewScore => $composableBuilder(
    column: $table.reviewScore,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reviewCount => $composableBuilder(
    column: $table.reviewCount,
    builder: (column) => column,
  );

  Expression<T> gameTagsRefs<T extends Object>(
    Expression<T> Function($$GameTagsTableAnnotationComposer a) f,
  ) {
    final $$GameTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.gameTags,
      getReferencedColumn: (t) => t.gameId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GameTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.gameTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GamesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GamesTable,
          GameEntry,
          $$GamesTableFilterComposer,
          $$GamesTableOrderingComposer,
          $$GamesTableAnnotationComposer,
          $$GamesTableCreateCompanionBuilder,
          $$GamesTableUpdateCompanionBuilder,
          (GameEntry, $$GamesTableReferences),
          GameEntry,
          PrefetchHooks Function({bool gameTagsRefs})
        > {
  $$GamesTableTableManager(_$AppDatabase db, $GamesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GamesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GamesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GamesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> gameKey = const Value.absent(),
                Value<String> platform = const Value.absent(),
                Value<DateTime> dateAdded = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<bool> isUsed = const Value.absent(),
                Value<String> coverImage = const Value.absent(),
                Value<bool> hasDeadline = const Value.absent(),
                Value<DateTime?> deadlineDate = const Value.absent(),
                Value<bool> isDlc = const Value.absent(),
                Value<String> steamAppId = const Value.absent(),
                Value<int> reviewScore = const Value.absent(),
                Value<int> reviewCount = const Value.absent(),
              }) => GamesCompanion(
                id: id,
                title: title,
                gameKey: gameKey,
                platform: platform,
                dateAdded: dateAdded,
                updatedAt: updatedAt,
                notes: notes,
                isUsed: isUsed,
                coverImage: coverImage,
                hasDeadline: hasDeadline,
                deadlineDate: deadlineDate,
                isDlc: isDlc,
                steamAppId: steamAppId,
                reviewScore: reviewScore,
                reviewCount: reviewCount,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String title,
                required String gameKey,
                Value<String> platform = const Value.absent(),
                Value<DateTime> dateAdded = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<bool> isUsed = const Value.absent(),
                Value<String> coverImage = const Value.absent(),
                Value<bool> hasDeadline = const Value.absent(),
                Value<DateTime?> deadlineDate = const Value.absent(),
                Value<bool> isDlc = const Value.absent(),
                Value<String> steamAppId = const Value.absent(),
                Value<int> reviewScore = const Value.absent(),
                Value<int> reviewCount = const Value.absent(),
              }) => GamesCompanion.insert(
                id: id,
                title: title,
                gameKey: gameKey,
                platform: platform,
                dateAdded: dateAdded,
                updatedAt: updatedAt,
                notes: notes,
                isUsed: isUsed,
                coverImage: coverImage,
                hasDeadline: hasDeadline,
                deadlineDate: deadlineDate,
                isDlc: isDlc,
                steamAppId: steamAppId,
                reviewScore: reviewScore,
                reviewCount: reviewCount,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$GamesTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({gameTagsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (gameTagsRefs) db.gameTags],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (gameTagsRefs)
                    await $_getPrefetchedData<
                      GameEntry,
                      $GamesTable,
                      GameTagEntry
                    >(
                      currentTable: table,
                      referencedTable: $$GamesTableReferences
                          ._gameTagsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$GamesTableReferences(db, table, p0).gameTagsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.gameId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$GamesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GamesTable,
      GameEntry,
      $$GamesTableFilterComposer,
      $$GamesTableOrderingComposer,
      $$GamesTableAnnotationComposer,
      $$GamesTableCreateCompanionBuilder,
      $$GamesTableUpdateCompanionBuilder,
      (GameEntry, $$GamesTableReferences),
      GameEntry,
      PrefetchHooks Function({bool gameTagsRefs})
    >;
typedef $$TagsTableCreateCompanionBuilder =
    TagsCompanion Function({
      Value<int> id,
      required String name,
      Value<String> color,
      Value<bool> isSteamTag,
    });
typedef $$TagsTableUpdateCompanionBuilder =
    TagsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> color,
      Value<bool> isSteamTag,
    });

final class $$TagsTableReferences
    extends BaseReferences<_$AppDatabase, $TagsTable, TagEntry> {
  $$TagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$GameTagsTable, List<GameTagEntry>>
  _gameTagsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.gameTags,
    aliasName: $_aliasNameGenerator(db.tags.id, db.gameTags.tagId),
  );

  $$GameTagsTableProcessedTableManager get gameTagsRefs {
    final manager = $$GameTagsTableTableManager(
      $_db,
      $_db.gameTags,
    ).filter((f) => f.tagId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_gameTagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TagsTableFilterComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSteamTag => $composableBuilder(
    column: $table.isSteamTag,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> gameTagsRefs(
    Expression<bool> Function($$GameTagsTableFilterComposer f) f,
  ) {
    final $$GameTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.gameTags,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GameTagsTableFilterComposer(
            $db: $db,
            $table: $db.gameTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TagsTableOrderingComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSteamTag => $composableBuilder(
    column: $table.isSteamTag,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<bool> get isSteamTag => $composableBuilder(
    column: $table.isSteamTag,
    builder: (column) => column,
  );

  Expression<T> gameTagsRefs<T extends Object>(
    Expression<T> Function($$GameTagsTableAnnotationComposer a) f,
  ) {
    final $$GameTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.gameTags,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GameTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.gameTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TagsTable,
          TagEntry,
          $$TagsTableFilterComposer,
          $$TagsTableOrderingComposer,
          $$TagsTableAnnotationComposer,
          $$TagsTableCreateCompanionBuilder,
          $$TagsTableUpdateCompanionBuilder,
          (TagEntry, $$TagsTableReferences),
          TagEntry,
          PrefetchHooks Function({bool gameTagsRefs})
        > {
  $$TagsTableTableManager(_$AppDatabase db, $TagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<bool> isSteamTag = const Value.absent(),
              }) => TagsCompanion(
                id: id,
                name: name,
                color: color,
                isSteamTag: isSteamTag,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String> color = const Value.absent(),
                Value<bool> isSteamTag = const Value.absent(),
              }) => TagsCompanion.insert(
                id: id,
                name: name,
                color: color,
                isSteamTag: isSteamTag,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$TagsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({gameTagsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (gameTagsRefs) db.gameTags],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (gameTagsRefs)
                    await $_getPrefetchedData<
                      TagEntry,
                      $TagsTable,
                      GameTagEntry
                    >(
                      currentTable: table,
                      referencedTable: $$TagsTableReferences._gameTagsRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $$TagsTableReferences(db, table, p0).gameTagsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.tagId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TagsTable,
      TagEntry,
      $$TagsTableFilterComposer,
      $$TagsTableOrderingComposer,
      $$TagsTableAnnotationComposer,
      $$TagsTableCreateCompanionBuilder,
      $$TagsTableUpdateCompanionBuilder,
      (TagEntry, $$TagsTableReferences),
      TagEntry,
      PrefetchHooks Function({bool gameTagsRefs})
    >;
typedef $$GameTagsTableCreateCompanionBuilder =
    GameTagsCompanion Function({
      required int gameId,
      required int tagId,
      Value<int> rowid,
    });
typedef $$GameTagsTableUpdateCompanionBuilder =
    GameTagsCompanion Function({
      Value<int> gameId,
      Value<int> tagId,
      Value<int> rowid,
    });

final class $$GameTagsTableReferences
    extends BaseReferences<_$AppDatabase, $GameTagsTable, GameTagEntry> {
  $$GameTagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $GamesTable _gameIdTable(_$AppDatabase db) => db.games.createAlias(
    $_aliasNameGenerator(db.gameTags.gameId, db.games.id),
  );

  $$GamesTableProcessedTableManager get gameId {
    final $_column = $_itemColumn<int>('game_id')!;

    final manager = $$GamesTableTableManager(
      $_db,
      $_db.games,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_gameIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TagsTable _tagIdTable(_$AppDatabase db) =>
      db.tags.createAlias($_aliasNameGenerator(db.gameTags.tagId, db.tags.id));

  $$TagsTableProcessedTableManager get tagId {
    final $_column = $_itemColumn<int>('tag_id')!;

    final manager = $$TagsTableTableManager(
      $_db,
      $_db.tags,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_tagIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$GameTagsTableFilterComposer
    extends Composer<_$AppDatabase, $GameTagsTable> {
  $$GameTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$GamesTableFilterComposer get gameId {
    final $$GamesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.gameId,
      referencedTable: $db.games,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GamesTableFilterComposer(
            $db: $db,
            $table: $db.games,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableFilterComposer get tagId {
    final $$TagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableFilterComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GameTagsTableOrderingComposer
    extends Composer<_$AppDatabase, $GameTagsTable> {
  $$GameTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$GamesTableOrderingComposer get gameId {
    final $$GamesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.gameId,
      referencedTable: $db.games,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GamesTableOrderingComposer(
            $db: $db,
            $table: $db.games,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableOrderingComposer get tagId {
    final $$TagsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableOrderingComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GameTagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GameTagsTable> {
  $$GameTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$GamesTableAnnotationComposer get gameId {
    final $$GamesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.gameId,
      referencedTable: $db.games,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GamesTableAnnotationComposer(
            $db: $db,
            $table: $db.games,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableAnnotationComposer get tagId {
    final $$TagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableAnnotationComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GameTagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GameTagsTable,
          GameTagEntry,
          $$GameTagsTableFilterComposer,
          $$GameTagsTableOrderingComposer,
          $$GameTagsTableAnnotationComposer,
          $$GameTagsTableCreateCompanionBuilder,
          $$GameTagsTableUpdateCompanionBuilder,
          (GameTagEntry, $$GameTagsTableReferences),
          GameTagEntry,
          PrefetchHooks Function({bool gameId, bool tagId})
        > {
  $$GameTagsTableTableManager(_$AppDatabase db, $GameTagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GameTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GameTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GameTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> gameId = const Value.absent(),
                Value<int> tagId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) =>
                  GameTagsCompanion(gameId: gameId, tagId: tagId, rowid: rowid),
          createCompanionCallback:
              ({
                required int gameId,
                required int tagId,
                Value<int> rowid = const Value.absent(),
              }) => GameTagsCompanion.insert(
                gameId: gameId,
                tagId: tagId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$GameTagsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({gameId = false, tagId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (gameId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.gameId,
                                referencedTable: $$GameTagsTableReferences
                                    ._gameIdTable(db),
                                referencedColumn: $$GameTagsTableReferences
                                    ._gameIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (tagId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.tagId,
                                referencedTable: $$GameTagsTableReferences
                                    ._tagIdTable(db),
                                referencedColumn: $$GameTagsTableReferences
                                    ._tagIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$GameTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GameTagsTable,
      GameTagEntry,
      $$GameTagsTableFilterComposer,
      $$GameTagsTableOrderingComposer,
      $$GameTagsTableAnnotationComposer,
      $$GameTagsTableCreateCompanionBuilder,
      $$GameTagsTableUpdateCompanionBuilder,
      (GameTagEntry, $$GameTagsTableReferences),
      GameTagEntry,
      PrefetchHooks Function({bool gameId, bool tagId})
    >;
typedef $$BackupsTableCreateCompanionBuilder =
    BackupsCompanion Function({
      Value<int> id,
      required String filename,
      Value<DateTime> createdAt,
      Value<String> label,
      Value<int> sizeBytes,
    });
typedef $$BackupsTableUpdateCompanionBuilder =
    BackupsCompanion Function({
      Value<int> id,
      Value<String> filename,
      Value<DateTime> createdAt,
      Value<String> label,
      Value<int> sizeBytes,
    });

class $$BackupsTableFilterComposer
    extends Composer<_$AppDatabase, $BackupsTable> {
  $$BackupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BackupsTableOrderingComposer
    extends Composer<_$AppDatabase, $BackupsTable> {
  $$BackupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BackupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BackupsTable> {
  $$BackupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get filename =>
      $composableBuilder(column: $table.filename, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);
}

class $$BackupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BackupsTable,
          BackupEntry,
          $$BackupsTableFilterComposer,
          $$BackupsTableOrderingComposer,
          $$BackupsTableAnnotationComposer,
          $$BackupsTableCreateCompanionBuilder,
          $$BackupsTableUpdateCompanionBuilder,
          (
            BackupEntry,
            BaseReferences<_$AppDatabase, $BackupsTable, BackupEntry>,
          ),
          BackupEntry,
          PrefetchHooks Function()
        > {
  $$BackupsTableTableManager(_$AppDatabase db, $BackupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BackupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BackupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BackupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> filename = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
              }) => BackupsCompanion(
                id: id,
                filename: filename,
                createdAt: createdAt,
                label: label,
                sizeBytes: sizeBytes,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String filename,
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
              }) => BackupsCompanion.insert(
                id: id,
                filename: filename,
                createdAt: createdAt,
                label: label,
                sizeBytes: sizeBytes,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BackupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BackupsTable,
      BackupEntry,
      $$BackupsTableFilterComposer,
      $$BackupsTableOrderingComposer,
      $$BackupsTableAnnotationComposer,
      $$BackupsTableCreateCompanionBuilder,
      $$BackupsTableUpdateCompanionBuilder,
      (BackupEntry, BaseReferences<_$AppDatabase, $BackupsTable, BackupEntry>),
      BackupEntry,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$GamesTableTableManager get games =>
      $$GamesTableTableManager(_db, _db.games);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
  $$GameTagsTableTableManager get gameTags =>
      $$GameTagsTableTableManager(_db, _db.gameTags);
  $$BackupsTableTableManager get backups =>
      $$BackupsTableTableManager(_db, _db.backups);
}
