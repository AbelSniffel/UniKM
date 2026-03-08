/// Legacy tag name list used only for one-time cleanup and pruning.
///
/// These were historically seeded into the database by older SteamKM/UniKM
/// versions. The current Flutter app no longer ships default tags, but existing
/// databases may still contain them.
library;

/// Common legacy default tag names.
///
/// Kept as a `Set` for fast membership checks.
const Set<String> kLegacyDefaultTagNames = {
  'RPG',
  'Survival',
  'Adventure',
  'Co-op',
  'AAA',
  'Indie',
  'Action',
  'Strategy',
  'Simulation',
  'Sports',
  'Racing',
  'Puzzle',
  'Horror',
  'First-Person Shooter',
  'Multiplayer',
  'Singleplayer',
  'VR',
  'Open World',
  'Sandbox',
  'Platformer',
};
