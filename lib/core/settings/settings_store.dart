import 'package:shared_preferences/shared_preferences.dart';

import 'settings_model.dart';

/// Reads legacy preferences, encodes values, and preserves library paths and
/// custom themes when resetting. It has no provider or presentation dependency.
class SettingsStore {
  const SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  Map<String, dynamic> load() {
    // Retain old button positions; centered buttons map to the split layout.
    final legacyArrangementH = switch (_prefs.getString(
      'nav_bar_button_alignment',
    )) {
      'left' => NavButtonArrangement.start,
      'right' => NavButtonArrangement.end,
      _ =>
        _prefs.getBool('nav_bar_center_buttons') == false
            ? NavButtonArrangement.start
            : NavButtonArrangement.split,
    };
    return {
      for (final MapEntry(:key, :value) in settingDefaults.entries)
        key: _readPreference(key, value),
      SettingsKeys.autoCheckIntervalMinutes:
          DefaultSettings.autoCheckIntervalMinutes,
      // The current-theme alias falls back to the legacy active-theme key.
      SettingsKeys.currentTheme:
          _prefs.getString(SettingsKeys.currentTheme) ??
          _prefs.getString(SettingsKeys.activeTheme) ??
          DefaultSettings.activeTheme,
      for (final MapEntry(:key, value: (values, fallback))
          in enumSettingDefaults.entries)
        key: _readEnum(
          key,
          values,
          key == SettingsKeys.navButtonArrangementH
              ? legacyArrangementH
              : fallback,
        ),
      SettingsKeys.windowX: _prefs.getDouble(SettingsKeys.windowX),
      SettingsKeys.windowY: _prefs.getDouble(SettingsKeys.windowY),
    };
  }

  Object _readPreference(String key, Object fallback) => switch (fallback) {
    bool() => _prefs.getBool(key) ?? fallback,
    int() => _prefs.getInt(key) ?? fallback,
    double() => _prefs.getDouble(key) ?? fallback,
    String() => _prefs.getString(key) ?? fallback,
    List<String>() => _prefs.getStringList(key) ?? fallback,
    _ => throw ArgumentError.value(
      fallback,
      key,
      'Unsupported preference type',
    ),
  };

  Enum _readEnum(String key, List<Enum> values, Enum fallback) {
    final stored = _prefs.getString(key);
    return values.where((value) => value.name == stored).firstOrNull ??
        fallback;
  }

  Future<void> save(String key, Object? value) async {
    await switch (value) {
      final bool value => _prefs.setBool(key, value),
      final int value => _prefs.setInt(key, value),
      final double value => _prefs.setDouble(key, value),
      final String value => _prefs.setString(key, value),
      final List<String> value => _prefs.setStringList(key, value),
      final Enum value => _prefs.setString(key, value.name),
      _ => null,
    };
  }

  /// Reset all settings to defaults
  ///
  /// Preserve the active database choice, recent databases, and custom themes.
  /// Typed reads matter: platform stores return saved lists untyped, which
  /// [save] would not write back.
  Future<Map<String, dynamic>> resetToDefaults() async {
    final preserved = <String, Object>{
      SettingsKeys.databasePath: ?_prefs.getString(SettingsKeys.databasePath),
      for (final key in [
        SettingsKeys.customThemes,
        SettingsKeys.recentDatabasePaths,
      ])
        key: ?_prefs.getStringList(key),
    };
    await _prefs.clear();
    for (final entry in {
      ...preserved,
      SettingsKeys.syncEnabled: DefaultSettings.syncEnabled,
      SettingsKeys.syncAutoOnStartup: DefaultSettings.syncAutoOnStartup,
      SettingsKeys.experimentalInteractionCards:
          DefaultSettings.experimentalInteractionCards,
      SettingsKeys.settingsCardIndicatorStyle:
          DefaultSettings.settingsCardIndicatorStyle,
    }.entries) {
      await save(entry.key, entry.value);
    }

    return load();
  }
}
