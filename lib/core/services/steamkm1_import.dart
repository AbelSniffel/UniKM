library;

// Text exports are parsed line by line; compile these once.
final _lineBreakPattern = RegExp(r'\r?\n');
final _titleKeyLinePattern = RegExp(r'^(.+?)\s+([A-Za-z0-9-]{15,})$');
final _nonAlphanumericPattern = RegExp(r'[^A-Za-z0-9]');

class SteamKm1ImportedGame {
  const SteamKm1ImportedGame({
    required this.title,
    required this.key,
    this.category,
    this.appId,
    this.iconPath,
    this.reviewScore,
    this.reviewCount,
    this.developer,
  });

  final String title;
  final String key;
  final String? category;
  final String? appId;
  final String? iconPath;
  final int? reviewScore;
  final int? reviewCount;
  final String? developer;
}

bool looksLikeSteamKm1JsonExportData(Object? data) {
  if (data is List) {
    return data.any((item) => item is Map && _looksLikeSteamKm1GameMap(item));
  }

  if (data is Map) {
    if (data['games'] is List) {
      return false;
    }

    if (_looksLikeSteamKm1GameMap(data)) {
      return true;
    }

    return data.values.whereType<Map>().any(_looksLikeSteamKm1GameMap);
  }

  return false;
}

List<SteamKm1ImportedGame> parseSteamKm1JsonExportData(Object? data) {
  if (!looksLikeSteamKm1JsonExportData(data)) {
    throw const FormatException('Not a SteamKM1 JSON export');
  }

  final sourceItems = <Map<dynamic, dynamic>>[];
  if (data is List) {
    sourceItems.addAll(data.whereType<Map>());
  } else if (data is Map) {
    if (_looksLikeSteamKm1GameMap(data)) {
      sourceItems.add(data);
    } else {
      sourceItems.addAll(data.values.whereType<Map>());
    }
  }

  final records = <SteamKm1ImportedGame>[];
  for (final item in sourceItems) {
    final record = _fromSteamKm1Map(item);
    if (record != null) {
      records.add(record);
    }
  }
  return records;
}

List<SteamKm1ImportedGame> parseSteamKm1TextExport(String content) {
  final records = <SteamKm1ImportedGame>[];
  for (final rawLine in content.split(_lineBreakPattern)) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }

    final pipeIndex = line.lastIndexOf('|');
    String? title;
    String? key;

    if (pipeIndex > 0) {
      title = line.substring(0, pipeIndex).trim();
      key = line.substring(pipeIndex + 1).trim();
    } else {
      final match = _titleKeyLinePattern.firstMatch(line);
      if (match != null) {
        title = match.group(1)?.trim();
        key = match.group(2)?.trim();
      }
    }

    final normalizedKey = _normalizeKey(key);
    if (title == null || title.isEmpty || normalizedKey == null) {
      continue;
    }

    records.add(SteamKm1ImportedGame(title: title, key: normalizedKey));
  }

  return records;
}

bool _looksLikeSteamKm1GameMap(Map<dynamic, dynamic> data) {
  return (data['title'] is String &&
          (data['key'] is String || data['code'] is String)) ||
      (data['app_id'] is String && data['category'] is String);
}

SteamKm1ImportedGame? _fromSteamKm1Map(Map<dynamic, dynamic> data) {
  final title = (data['title'] as String?)?.trim();
  final key = _normalizeKey((data['key'] ?? data['code']) as String?);
  if (title == null || title.isEmpty || key == null) {
    return null;
  }

  final reviewData = data['review_data'];
  final reviewScore = _parseOptionalInt(
    reviewData is Map ? reviewData['percentage'] : null,
  );
  final reviewCount = _parseOptionalInt(
    reviewData is Map ? reviewData['review_count'] : null,
  );

  return SteamKm1ImportedGame(
    title: title,
    key: key,
    category: (data['category'] as String?)?.trim(),
    appId: (data['app_id'] as String?)?.trim(),
    iconPath: (data['icon_path'] as String?)?.trim(),
    reviewScore: reviewScore,
    reviewCount: reviewCount,
    developer: (data['developer'] as String?)?.trim(),
  );
}

String? _normalizeKey(String? rawKey) {
  if (rawKey == null) {
    return null;
  }

  final compact = rawKey.replaceAll(_nonAlphanumericPattern, '').toUpperCase();
  if (compact.length != 15) {
    return null;
  }

  return '${compact.substring(0, 5)}-${compact.substring(5, 10)}-${compact.substring(10)}';
}

int? _parseOptionalInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}
