/// Platform detection patterns for game keys
/// Matches the patterns from the original Python PlatformDetector
library;

/// Supported gaming platforms
enum GamePlatform {
  steam('Steam'),
  epicGames('Epic Games'),
  gog('GOG'),
  origin('Origin/EA'),
  ubisoft('Ubisoft'),
  xbox('Xbox'),
  playStation('PlayStation'),
  nintendo('Nintendo'),
  humble('Humble Bundle'),
  itchio('itch.io'),
  webLink('Web Link'),
  other('Other');

  const GamePlatform(this.displayName);

  final String displayName;

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

  // Specific formats precede generic ones. Keep this suffix-matching order so
  // batch entry consumes a whole key before trying its shorter suffixes.
  static const _keyFormats = <(GamePlatform, String)>[
    (
      GamePlatform.epicGames,
      r'[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}',
    ),
    (GamePlatform.epicGames, r'[A-F0-9]{32}'),
    (
      GamePlatform.xbox,
      r'[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}',
    ),
    (
      GamePlatform.origin,
      r'[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}',
    ),
    (GamePlatform.steam, r'[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}'),
    (GamePlatform.ubisoft, r'[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}'),
    (GamePlatform.playStation, r'[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}'),
    (GamePlatform.gog, r'[A-Z0-9]{8,16}'),
  ];

  static final _keyPatterns = [
    for (final (platform, pattern) in _keyFormats)
      (platform, RegExp('^$pattern\$', caseSensitive: false)),
  ];
  static final _urlPattern = RegExp(r'^https?://', caseSensitive: false);

  /// Batch extraction requires a complete trailing URL; platform detection
  /// accepts the URL prefix while the user is still typing.
  static final trailingKeyPatterns = List<RegExp>.unmodifiable([
    RegExp(r'https?://\S+$', caseSensitive: false),
    for (final (_, pattern) in _keyFormats)
      RegExp('$pattern\$', caseSensitive: false),
  ]);

  /// Detect platform from a game key string.
  static GamePlatform detectPlatform(String key) {
    final trimmedKey = key.trim();
    if (_urlPattern.hasMatch(trimmedKey)) return GamePlatform.webLink;
    for (final (platform, pattern) in _keyPatterns) {
      if (pattern.hasMatch(trimmedKey)) return platform;
    }
    return GamePlatform.other;
  }
}
