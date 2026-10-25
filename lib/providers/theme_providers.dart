/// Theme providers: theme selection, custom themes, preview mode.
library;

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/settings_model.dart';
import '../core/theme/app_theme.dart';
import 'settings_providers.dart';

class ThemeImportResult {
  const ThemeImportResult({
    required this.importedCount,
    required this.invalidCount,
  });

  final int importedCount;
  final int invalidCount;
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
    final token = ref.watch(activeThemeNameProvider);
    final allThemes = getAllThemes();
    // Settings store the theme ID; older settings may still store its name.
    return allThemes.where((t) => t.id == token).firstOrNull ??
        allThemes.where((t) => t.name == token).firstOrNull ??
        kDarkTheme;
  }

  /// Settings that make [id] the active theme.
  static Map<String, dynamic> _activeTheme(String id) => {
    SettingsKeys.activeTheme: id,
    SettingsKeys.currentTheme: id,
  };

  /// Start previewing a theme without persisting
  /// Call cancelPreview() to restore the original theme
  /// Call savePreviewTheme() to persist the preview theme
  void startPreview(AppThemeData previewTheme) {
    if (_themeEquals(state, previewTheme)) return;
    _previewOriginalTheme ??= state;
    state = previewTheme;
  }

  bool _themeEquals(AppThemeData a, AppThemeData b) =>
      a.id == b.id &&
      a.name == b.name &&
      a.baseBackground == b.baseBackground &&
      a.baseSecondary == b.baseSecondary &&
      a.baseAccent == b.baseAccent &&
      a.navPanelOverlayStyle == b.navPanelOverlayStyle &&
      a.iconData?.codePoint == b.iconData?.codePoint &&
      a.cornerRadius == b.cornerRadius &&
      a.useThemeToggleRadius == b.useThemeToggleRadius &&
      a.scrollbarRadius == b.scrollbarRadius &&
      a.inputPaddingHorizontal == b.inputPaddingHorizontal &&
      a.inputPaddingVertical == b.inputPaddingVertical &&
      a.progressIndicatorStrokeWidth == b.progressIndicatorStrokeWidth;

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
    if (_themeEquals(state, theme)) return;

    _previewOriginalTheme = null; // Clear preview state
    state = theme;
    await ref.read(settingsProvider.notifier).setMany(_activeTheme(theme.id));
  }

  /// Save a custom theme
  Future<void> saveCustomTheme(AppThemeData theme) async {
    _previewOriginalTheme = null; // Clear preview state
    final settings = ref.read(settingsProvider.notifier);
    final customThemes = List<String>.from(ref.read(customThemesJsonProvider));

    // Replace existing theme with the same ID (edit flow), otherwise append.
    customThemes.removeWhere(
      (json) => _decodeCustomTheme(json)?.id == theme.id,
    );

    // Add new theme
    customThemes.add(jsonEncode(theme.toJson()));
    await settings.setMany({
      SettingsKeys.customThemes: customThemes,
      ..._activeTheme(theme.id),
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

    final candidates = switch (decoded) {
      {'themes': final List themes} => themes,
      final Map<String, dynamic> theme => [theme],
      final List themes => themes,
      _ => throw const FormatException('Unsupported theme file format'),
    };
    final rawThemes = candidates.whereType<Map<String, dynamic>>().toList();

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

    await settings.setMany({
      SettingsKeys.customThemes: customThemes,
      if (lastImportedId != null) ..._activeTheme(lastImportedId),
    });

    if (lastImportedId != null) {
      final activatedTheme = getAllThemes()
          .where((t) => t.id == lastImportedId)
          .firstOrNull;
      if (activatedTheme != null) state = activatedTheme;
    }

    return ThemeImportResult(
      importedCount: importedCount,
      invalidCount: invalidCount,
    );
  }

  /// Delete a custom theme
  Future<void> deleteCustomTheme(String id) async {
    // Check if deleted theme is currently active BEFORE removing
    final isActiveTheme = state.id == id;

    final settings = ref.read(settingsProvider.notifier);
    final customThemes = List<String>.from(ref.read(customThemesJsonProvider));

    customThemes.removeWhere((json) => _decodeCustomTheme(json)?.id == id);
    await settings.set(SettingsKeys.customThemes, customThemes);

    // If current theme was deleted, switch to Dark theme
    if (isActiveTheme) {
      state = kDarkTheme;
      await settings.setMany(_activeTheme(kDarkTheme.id));
    }
  }

  // Malformed saved entries are ignored for display and retained during edits.
  AppThemeData? _decodeCustomTheme(String json) {
    try {
      return AppThemeData.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Get all available themes (built-in + custom). The list is rebuilt only
  /// when the stored custom theme JSON changes.
  List<AppThemeData> getAllThemes() {
    final customThemesJson = ref.read(customThemesJsonProvider);

    if (_cachedCustomThemesJson != null &&
        const ListEquality<String>().equals(
          _cachedCustomThemesJson!,
          customThemesJson,
        )) {
      return _cachedAllThemes!;
    }

    final customThemes = customThemesJson
        .map(_decodeCustomTheme)
        .whereType<AppThemeData>();

    _cachedCustomThemesJson = List<String>.unmodifiable(customThemesJson);
    _cachedAllThemes = List<AppThemeData>.unmodifiable([
      ...kBuiltInThemes,
      ...customThemes,
    ]);
    return _cachedAllThemes!;
  }
}

/// Theme provider
final themeProvider = NotifierProvider<ThemeNotifier, AppThemeData>(
  ThemeNotifier.new,
);

final builtInThemeIdsProvider = Provider<Set<String>>(
  (ref) => AppThemeData.builtInThemes.map((theme) => theme.id).toSet(),
);

final currentThemeIsBuiltInProvider = Provider<bool>((ref) {
  final activeThemeId = ref.watch(themeProvider.select((theme) => theme.id));
  final builtInIds = ref.watch(builtInThemeIdsProvider);
  return builtInIds.contains(activeThemeId);
});

final effectiveNavPanelOverlayStyleProvider = Provider<NavPanelOverlayStyle>((
  ref,
) {
  final theme = ref.watch(themeProvider);
  return ref.watch(currentThemeIsBuiltInProvider)
      ? ref.watch(navPanelOverlayStyleSettingProvider)
      : theme.navPanelOverlayStyle;
});

final effectiveThemeProvider = Provider<AppThemeData>((ref) {
  final theme = ref.watch(themeProvider);
  final overlayStyle = ref.watch(effectiveNavPanelOverlayStyleProvider);
  if (overlayStyle == theme.navPanelOverlayStyle) return theme;
  return theme.copyWith(navPanelOverlayStyle: overlayStyle);
});

/// Cache recent Material themes within this provider's lifetime. Live color
/// previews can produce thousands of variants, so retain at most 16 of them.
final themeDataProvider = NotifierProvider<_ThemeDataNotifier, ThemeData>(
  _ThemeDataNotifier.new,
);

class _ThemeDataNotifier extends Notifier<ThemeData> {
  final _cache = <Record, ThemeData>{};

  @override
  ThemeData build() {
    final theme = ref.watch(themeProvider);
    // Include every extension field and the platform's control sizing. A
    // cached ThemeData must expose the current AppThemeData extension too.
    final key = (
      theme.id,
      theme.name,
      theme.baseBackground,
      theme.baseSecondary,
      theme.baseAccent,
      theme.iconData,
      theme.cornerRadius,
      theme.useThemeToggleRadius,
      theme.scrollbarRadius,
      theme.inputPaddingHorizontal,
      theme.inputPaddingVertical,
      theme.progressIndicatorStrokeWidth,
      theme.navPanelOverlayStyle,
      defaultTargetPlatform,
    );
    final cached = _cache.remove(key);
    if (_cache.length >= 16) _cache.remove(_cache.keys.first);
    return _cache[key] = cached ?? theme.toThemeData();
  }
}
