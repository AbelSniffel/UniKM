/// Theme providers: theme selection, custom themes, preview mode.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/settings_model.dart';
import '../core/theme/app_theme.dart';
import 'settings_providers.dart';

class ThemeImportResult {
  const ThemeImportResult({
    required this.importedCount,
    required this.invalidCount,
    this.activatedThemeId,
  });

  final int importedCount;
  final int invalidCount;
  final String? activatedThemeId;
}

// =============================================================================
// THEME PROVIDER
// =============================================================================

/// Theme state notifier
class ThemeNotifier extends Notifier<AppThemeData> {
  /// Store the original theme for preview mode
  AppThemeData? _previewOriginalTheme;
  List<String>? _cachedCustomThemesJson;
  List<AppThemeData>? _cachedAllThemes;

  @override
  AppThemeData build() {
    final themeSelectionToken = ref.watch(activeThemeNameProvider);
    final allThemes = getAllThemes();

    // Preferred path: settings store theme ID
    final byId = allThemes
        .where((t) => t.id == themeSelectionToken)
        .firstOrNull;
    if (byId != null) return byId;

    // Backward compatibility path: old settings may still store theme name
    final byName = allThemes
        .where((t) => t.name == themeSelectionToken)
        .firstOrNull;
    if (byName != null) return byName;

    // Default to dark theme
    return kDarkTheme;
  }

  /// Load theme (for initial load - no-op since build() loads it)
  Future<void> loadTheme() async {
    // Theme is automatically loaded through build() watching settingsProvider
  }

  /// Start previewing a theme without persisting
  /// Call cancelPreview() to restore the original theme
  /// Call savePreviewTheme() to persist the preview theme
  void startPreview(AppThemeData previewTheme) {
    if (_themeEquals(state, previewTheme)) {
      return;
    }
    _previewOriginalTheme ??= state;
    state = previewTheme;
  }

  bool _themeEquals(AppThemeData a, AppThemeData b) {
    return a.id == b.id &&
        a.name == b.name &&
        a.baseBackground == b.baseBackground &&
        a.basePrimary == b.basePrimary &&
        a.baseAccent == b.baseAccent &&
        a.iconData?.codePoint == b.iconData?.codePoint &&
        a.cornerRadius == b.cornerRadius &&
        a.scrollbarRadius == b.scrollbarRadius &&
        a.controlPaddingHorizontal == b.controlPaddingHorizontal &&
        a.controlPaddingVertical == b.controlPaddingVertical &&
        a.inputPaddingHorizontal == b.inputPaddingHorizontal &&
        a.inputPaddingVertical == b.inputPaddingVertical;
  }

  /// Cancel preview and restore the original theme
  void cancelPreview() {
    if (_previewOriginalTheme != null) {
      state = _previewOriginalTheme!;
      _previewOriginalTheme = null;
    }
  }

  /// Check if currently in preview mode
  bool get isPreviewMode => _previewOriginalTheme != null;

  /// Set the active theme
  Future<void> setTheme(AppThemeData theme) async {
    if (_themeEquals(state, theme)) {
      return;
    }

    _previewOriginalTheme = null; // Clear preview state
    state = theme;
    final settings = ref.read(settingsProvider.notifier);
    await settings.setMany({
      SettingsKeys.activeTheme: theme.id,
      SettingsKeys.currentTheme: theme.id,
    });
  }

  /// Set the active theme by unique ID
  Future<void> setThemeById(String themeId) async {
    final allThemes = getAllThemes();
    final theme = allThemes.where((t) => t.id == themeId).firstOrNull;
    if (theme != null) {
      await setTheme(theme);
      return;
    }

    // Fallback for stale IDs
    await setTheme(kDarkTheme);
  }

  /// Set the active theme by name
  Future<void> setThemeByName(String themeName) async {
    final allThemes = getAllThemes();
    final theme = allThemes.where((t) => t.name == themeName).firstOrNull;
    if (theme != null) {
      await setTheme(theme);
    } else {
      await setTheme(kDarkTheme);
    }
  }

  /// Save a custom theme
  Future<void> saveCustomTheme(AppThemeData theme) async {
    _previewOriginalTheme = null; // Clear preview state
    final settings = ref.read(settingsProvider.notifier);
    final customThemes = List<String>.from(ref.read(customThemesJsonProvider));

    // Replace existing theme with the same ID (edit flow), otherwise append.
    customThemes.removeWhere((json) {
      try {
        final existing = AppThemeData.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );
        return existing.id == theme.id;
      } catch (_) {
        return false;
      }
    });

    // Add new theme
    customThemes.add(jsonEncode(theme.toJson()));
    _cachedCustomThemesJson = null;
    _cachedAllThemes = null;
    await settings.setMany({
      SettingsKeys.customThemes: customThemes,
      SettingsKeys.activeTheme: theme.id,
      SettingsKeys.currentTheme: theme.id,
    });
    state = theme;
  }

  String exportThemesToJson({required List<AppThemeData> themes}) {
    final payload = {
      'schema': 'UniKM-theme-export-v1',
      'exported_at': DateTime.now().toIso8601String(),
      'themes': themes.map((theme) => theme.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<ThemeImportResult> importThemesFromJsonString(
    String jsonContent,
  ) async {
    final decoded = jsonDecode(jsonContent);

    final rawThemes = <Map<String, dynamic>>[];

    if (decoded is Map<String, dynamic>) {
      if (decoded.containsKey('themes') && decoded['themes'] is List) {
        for (final raw in decoded['themes'] as List<dynamic>) {
          if (raw is Map<String, dynamic>) {
            rawThemes.add(raw);
          }
        }
      } else {
        rawThemes.add(decoded);
      }
    } else if (decoded is List<dynamic>) {
      for (final raw in decoded) {
        if (raw is Map<String, dynamic>) {
          rawThemes.add(raw);
        }
      }
    } else {
      throw const FormatException('Unsupported theme file format');
    }

    if (rawThemes.isEmpty) {
      throw const FormatException('No themes found in selected file');
    }

    final settings = ref.read(settingsProvider.notifier);
    final customThemes = List<String>.from(ref.read(customThemesJsonProvider));

    var importedCount = 0;
    var invalidCount = 0;
    String? lastImportedId;

    for (final rawTheme in rawThemes) {
      try {
        final parsed = AppThemeData.fromJson(
          rawTheme,
        ).copyWith(id: AppThemeData.generateThemeId());

        customThemes.add(jsonEncode(parsed.toJson()));
        importedCount++;
        lastImportedId = parsed.id;
      } catch (_) {
        invalidCount++;
      }
    }

    _cachedCustomThemesJson = null;
    _cachedAllThemes = null;

    final updates = <String, dynamic>{SettingsKeys.customThemes: customThemes};

    if (lastImportedId != null) {
      updates[SettingsKeys.activeTheme] = lastImportedId;
      updates[SettingsKeys.currentTheme] = lastImportedId;
    }

    await settings.setMany(updates);

    if (lastImportedId != null) {
      final activatedTheme = getAllThemes()
          .where((t) => t.id == lastImportedId)
          .firstOrNull;
      if (activatedTheme != null) {
        state = activatedTheme;
      }
    }

    return ThemeImportResult(
      importedCount: importedCount,
      invalidCount: invalidCount,
      activatedThemeId: lastImportedId,
    );
  }

  /// Delete a custom theme
  Future<void> deleteCustomTheme(String id) async {
    // Check if deleted theme is currently active BEFORE removing
    final isActiveTheme = state.id == id;

    final settings = ref.read(settingsProvider.notifier);
    final customThemes = List<String>.from(ref.read(customThemesJsonProvider));

    customThemes.removeWhere((json) {
      try {
        final t = AppThemeData.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );
        return t.id == id;
      } catch (e) {
        return false;
      }
    });

    _cachedCustomThemesJson = null;
    _cachedAllThemes = null;
    await settings.set(SettingsKeys.customThemes, customThemes);

    // If current theme was deleted, switch to Dark theme
    if (isActiveTheme) {
      state = kDarkTheme;
      await settings.setMany({
        SettingsKeys.activeTheme: kDarkTheme.id,
        SettingsKeys.currentTheme: kDarkTheme.id,
      });
    }
  }

  /// Get all available themes (built-in + custom)
  List<AppThemeData> getAllThemes() {
    final customThemesJson = ref.read(customThemesJsonProvider);

    if (_cachedCustomThemesJson != null &&
        _listEquals(_cachedCustomThemesJson!, customThemesJson)) {
      return _cachedAllThemes!;
    }

    final customThemes = <AppThemeData>[];
    for (final json in customThemesJson) {
      try {
        customThemes.add(
          AppThemeData.fromJson(jsonDecode(json) as Map<String, dynamic>),
        );
      } catch (e) {
        // Ignore invalid themes
      }
    }

    _cachedCustomThemesJson = List<String>.unmodifiable(customThemesJson);
    _cachedAllThemes = List<AppThemeData>.unmodifiable([
      ...kBuiltInThemes,
      ...customThemes,
    ]);
    return _cachedAllThemes!;
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// Theme provider
final themeProvider = NotifierProvider<ThemeNotifier, AppThemeData>(() {
  return ThemeNotifier();
});

final Map<String, ThemeData> _themeDataCache = <String, ThemeData>{};

String _themeDataCacheKey(AppThemeData theme) {
  return [
    theme.id,
    theme.name,
    theme.baseBackground.toARGB32().toString(),
    theme.basePrimary.toARGB32().toString(),
    theme.baseAccent.toARGB32().toString(),
    theme.iconData?.codePoint.toString() ?? '',
    theme.cornerRadius.toString(),
    theme.scrollbarRadius.toString(),
    theme.controlPaddingHorizontal.toString(),
    theme.controlPaddingVertical.toString(),
    theme.inputPaddingHorizontal.toString(),
    theme.inputPaddingVertical.toString(),
  ].join('|');
}

/// Cached Material [ThemeData] derived from the current [AppThemeData].
///
/// This avoids rebuilding the full ThemeData object graph every time the app
/// root rebuilds, while still updating instantly when any theme field changes.
final themeDataProvider = Provider<ThemeData>((ref) {
  final theme = ref.watch(themeProvider);
  final key = _themeDataCacheKey(theme);
  return _themeDataCache.putIfAbsent(key, theme.toThemeData);
});
