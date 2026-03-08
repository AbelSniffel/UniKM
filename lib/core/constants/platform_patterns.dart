/// Platform detection patterns for game keys
/// Matches the patterns from the original Python PlatformDetector
library;

/// Supported gaming platforms
enum GamePlatform {
  steam('Steam', 'STEAM'),
  epicGames('Epic Games', 'EPIC'),
  gog('GOG', 'GOG'),
  origin('Origin/EA', 'ORIGIN'),
  ubisoft('Ubisoft', 'UBISOFT'),
  xbox('Xbox', 'XBOX'),
  playStation('PlayStation', 'PLAYSTATION'),
  nintendo('Nintendo', 'NINTENDO'),
  humble('Humble Bundle', 'HUMBLE'),
  itchio('itch.io', 'ITCHIO'),
  webLink('Web Link', 'WEBLINK'),
  other('Other', 'OTHER');

  const GamePlatform(this.displayName, this.code);
  
  final String displayName;
  final String code;
  
  static GamePlatform fromCode(String code) {
    return GamePlatform.values.firstWhere(
      (p) => p.code.toUpperCase() == code.toUpperCase(),
      orElse: () => GamePlatform.other,
    );
  }
  
  static GamePlatform fromDisplayName(String name) {
    return GamePlatform.values.firstWhere(
      (p) => p.displayName.toLowerCase() == name.toLowerCase(),
      orElse: () => GamePlatform.other,
    );
  }
}

/// Utility class for detecting platform from key format
class PlatformDetector {
  PlatformDetector._();

  // Steam: XXXXX-XXXXX-XXXXX (5-5-5 alphanumeric)
  static final RegExp _steamPattern = RegExp(
    r'^[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$',
    caseSensitive: false,
  );

  // Epic Games: 32-char hex or UUID format
  static final RegExp _epicHexPattern = RegExp(
    r'^[A-F0-9]{32}$',
    caseSensitive: false,
  );
  static final RegExp _epicUuidPattern = RegExp(
    r'^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}$',
    caseSensitive: false,
  );

  // Origin/EA: XXXX-XXXX-XXXX-XXXX-XXXX (4-4-4-4-4 alphanumeric)
  static final RegExp _originPattern = RegExp(
    r'^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$',
    caseSensitive: false,
  );

  // Ubisoft: XXXX-XXXX-XXXX-XXXX (4-4-4-4 alphanumeric)
  static final RegExp _ubisoftPattern = RegExp(
    r'^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$',
    caseSensitive: false,
  );

  // GOG: 8-16 character alphanumeric
  static final RegExp _gogPattern = RegExp(
    r'^[A-Z0-9]{8,16}$',
    caseSensitive: false,
  );

  // Xbox: 25-character alphanumeric (5 groups of 5)
  static final RegExp _xboxPattern = RegExp(
    r'^[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$',
    caseSensitive: false,
  );

  // PlayStation: 12-character alphanumeric
  static final RegExp _playstationPattern = RegExp(
    r'^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$',
    caseSensitive: false,
  );

  // URL patterns
  static final RegExp _urlPattern = RegExp(
    r'^https?://',
    caseSensitive: false,
  );

  /// Detect platform from a game key string
  static GamePlatform detectPlatform(String key) {
    final trimmedKey = key.trim();
    
    if (trimmedKey.isEmpty) {
      return GamePlatform.other;
    }

    // Check for URLs first
    if (_urlPattern.hasMatch(trimmedKey)) {
      return GamePlatform.webLink;
    }

    // Steam pattern (most common)
    if (_steamPattern.hasMatch(trimmedKey)) {
      return GamePlatform.steam;
    }

    // Xbox pattern (5x5, similar to Steam but longer)
    if (_xboxPattern.hasMatch(trimmedKey)) {
      return GamePlatform.xbox;
    }

    // Origin/EA pattern
    if (_originPattern.hasMatch(trimmedKey)) {
      return GamePlatform.origin;
    }

    // Ubisoft pattern
    if (_ubisoftPattern.hasMatch(trimmedKey)) {
      return GamePlatform.ubisoft;
    }

    // PlayStation pattern
    if (_playstationPattern.hasMatch(trimmedKey)) {
      return GamePlatform.playStation;
    }

    // Epic Games patterns
    if (_epicHexPattern.hasMatch(trimmedKey) || 
        _epicUuidPattern.hasMatch(trimmedKey)) {
      return GamePlatform.epicGames;
    }

    // GOG pattern (generic alphanumeric, check last)
    if (_gogPattern.hasMatch(trimmedKey)) {
      return GamePlatform.gog;
    }

    return GamePlatform.other;
  }

  /// Get a list of all platform display names
  static List<String> get allPlatformNames {
    return GamePlatform.values.map((p) => p.displayName).toList();
  }
}
