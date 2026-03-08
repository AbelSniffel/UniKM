/// Appearance settings section: theme selection, navigation bar, gradient animation.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/animated_gradient_bar.dart';
import '../../widgets/hover_preview_card.dart';
import '../../widgets/notification_system.dart';
import '../../widgets/section_groupbox.dart';
import 'settings_common.dart';
import 'settings_theme_editor.dart';

final gradientPreviewPlayingProvider =
    NotifierProvider.autoDispose<GradientPreviewPlayingNotifier, bool>(
      GradientPreviewPlayingNotifier.new,
    );

class GradientPreviewPlayingNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void setPlaying(bool isPlaying) {
    state = isPlaying;
  }
}

class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({
    super.key,
    required this.theme,
    this.searchQuery = '',
    required this.matchesSearch,
    this.attachesToAbove = false,
  });

  final AppThemeData theme;
  final String searchQuery;
  final bool Function(String) matchesSearch;
  final bool attachesToAbove;

  static const SettingTextSpec themeIntroSpec = SettingTextSpec(
    label: 'Select a theme for the application',
  );
  static const SettingTextSpec navPositionSpec = SettingTextSpec(
    label: 'Position',
    description: 'Move the navigation bar to a different edge',
  );
  static const SettingTextSpec centerNavButtonsSpec = SettingTextSpec(
    label: 'Center navigation buttons',
    description:
        'When the bar is horizontal, keep page buttons centered instead of left-aligned.',
  );
  static const SettingTextSpec gradientSwapSpec = SettingTextSpec(
    label: 'Swap primary & accent colors',
    description:
        'Apply the theme accent color where primary is normally used for gradient bars.',
  );
  static const SettingTextSpec gradientIntroSpec = SettingTextSpec(
    label: 'Select an animation for the gradient bar',
  );

  static const SettingsSearchGroup themeSearchGroup = SettingsSearchGroup(
    title: 'Theme',
    settings: [themeIntroSpec],
    extraTexts: ['Import Theme', 'Export Theme', 'Create'],
  );

  static const SettingsSearchGroup navigationSearchGroup = SettingsSearchGroup(
    title: 'Navigation Bar',
    settings: [navPositionSpec, centerNavButtonsSpec],
    extraTexts: ['Left', 'Right', 'Top', 'Bottom'],
  );

  static SettingsSearchGroup get gradientSearchGroup => SettingsSearchGroup(
    title: 'Gradient Bar Effect',
    settings: [gradientIntroSpec, gradientSwapSpec],
    extraTexts: [
      ...GradientAnimation.values.map((effect) => effect.displayName),
    ],
  );

  static List<String> get sectionSearchTexts => [
    'Appearance Settings',
    ...themeSearchGroup.indexTexts,
    ...navigationSearchGroup.indexTexts,
    ...gradientSearchGroup.indexTexts,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(customThemesJsonProvider);
    final appearance = ref.watch(appearanceSettingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final navBarPosition = ref.watch(
      appShellSettingsProvider.select((s) => s.navBarPosition),
    );
    final navBarCenterButtons = ref.watch(navBarCenterButtonsProvider);

    final builtInThemes = AppThemeData.builtInThemes;
    final themeNotifier = ref.read(themeProvider.notifier);
    final allThemes = themeNotifier.getAllThemes();
    final builtInIds = builtInThemes.map((theme) => theme.id).toSet();
    final customThemes = allThemes
        .where((t) => !builtInIds.contains(t.id))
        .toList();
    final isSearching = searchQuery.trim().isNotEmpty;

    // Check which sections match search
    final showThemeSection =
        shouldShowSettingsGroup(
          query: searchQuery,
          matchesSearch: matchesSearch,
          group: themeSearchGroup,
        ) ||
        builtInThemes.any((t) => matchesSearch(t.name)) ||
        customThemes.any((t) => matchesSearch(t.name));
    final showNavBarSection = shouldShowSettingsGroup(
      query: searchQuery,
      matchesSearch: matchesSearch,
      group: navigationSearchGroup,
    );
    final showGradientSection = shouldShowSettingsGroup(
      query: searchQuery,
      matchesSearch: matchesSearch,
      group: gradientSearchGroup,
    );

    if (isSearching &&
        !showThemeSection &&
        !showNavBarSection &&
        !showGradientSection) {
      return const SizedBox.shrink();
    }

    return SettingsSectionGroups(
      attachesToAbove: attachesToAbove,
      entries: [
        SectionGroupEntry(
          visible: showThemeSection,
          builder: (position, isAlternate) => SearchableSectionGroupBox(
            theme: theme,
            group: themeSearchGroup,
            titleIcon: Icons.color_lens,
            searchQuery: searchQuery,
            matchesSearch: matchesSearch,
            groupPosition: position,
            isAlternate: isAlternate,
            extraMatch: () =>
                builtInThemes.any((t) => matchesSearch(t.name)) ||
                customThemes.any((t) => matchesSearch(t.name)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  themeIntroSpec.label,
                  style: TextStyle(color: theme.textSecondary),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (ctx) => ThemeEditorDialog(theme: theme),
                        );
                      },
                      icon: const Icon(Icons.add_outlined, size: 16),
                      label: const Text('Create Theme'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _importThemes(context, ref),
                      icon: const Icon(Icons.file_upload_outlined, size: 16),
                      label: const Text('Import Theme'),
                    ),
                    if (appearance.currentTheme.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () {
                          final current = ref.read(themeProvider);
                          _exportTheme(context, ref, current);
                        },
                        icon: const Icon(
                          Icons.file_download_outlined,
                          size: 16,
                        ),
                        label: const Text('Export Theme'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    // Built-in themes
                    ...builtInThemes.map((themeData) {
                      final isSelected =
                          appearance.currentTheme == themeData.id;
                      return ThemeCard(
                        themeData: themeData,
                        isSelected: isSelected,
                        isCustom: false,
                        onTap: () {
                          ref
                              .read(themeProvider.notifier)
                              .setThemeById(themeData.id);
                        },
                        onSecondaryTapDown: (details) => _showThemeContextMenu(
                          context,
                          ref,
                          themeData,
                          details,
                        ),
                      );
                    }),
                    // Custom themes with edit/delete
                    ...customThemes.map((themeData) {
                      final isSelected =
                          appearance.currentTheme == themeData.id;
                      return ThemeCard(
                        themeData: themeData,
                        isSelected: isSelected,
                        isCustom: true,
                        onTap: () {
                          ref
                              .read(themeProvider.notifier)
                              .setThemeById(themeData.id);
                        },
                        onEdit: () => _editCustomTheme(context, ref, themeData),
                        onDelete: () => _deleteCustomTheme(
                          context,
                          ref,
                          themeData.id,
                          themeData.name,
                        ),
                        onSecondaryTapDown: (details) => _showThemeContextMenu(
                          context,
                          ref,
                          themeData,
                          details,
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
        ),
        SectionGroupEntry(
          visible: showGradientSection,
          builder: (position, isAlternate) => _GradientAnimationSection(
            theme: theme,
            searchQuery: searchQuery,
            isSearchMatch: isSearching,
            groupPosition: position,
            isAlternate: isAlternate,
          ),
        ),
        SectionGroupEntry(
          visible: showNavBarSection,
          builder: (position, isAlternate) => SearchableSectionGroupBox(
            theme: theme,
            group: navigationSearchGroup,
            titleIcon: Icons.view_sidebar,
            searchQuery: searchQuery,
            matchesSearch: matchesSearch,
            groupPosition: position,
            isAlternate: isAlternate,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SpecSettingRow(
                  theme: theme,
                  spec: navPositionSpec,
                  child: SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<NavBarPosition>(
                      initialValue: navBarPosition,
                      isExpanded: true,
                      onChanged: (value) {
                        if (value == null) return;
                        settingsNotifier.setSetting(
                          SettingsKeys.navBarPosition,
                          value,
                        );
                      },
                      style: TextStyle(color: theme.textPrimary),
                      dropdownColor: theme.surface,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: theme.inputBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            theme.cornerRadius,
                          ),
                          borderSide: BorderSide(color: theme.border),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      items: NavBarPosition.values
                          .map(
                            (position) => DropdownMenuItem(
                              value: position,
                              child: Text(
                                position.displayName,
                                style: TextStyle(color: theme.textPrimary),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
                SpecToggleSettingRow(
                  theme: theme,
                  spec: centerNavButtonsSpec,
                  value: navBarCenterButtons,
                  onChanged: (value) => settingsNotifier.setSetting(
                    SettingsKeys.navBarCenterButtons,
                    value,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _editCustomTheme(
    BuildContext context,
    WidgetRef ref,
    AppThemeData themeData,
  ) {
    final appearance = ref.read(appearanceSettingsProvider);
    if (appearance.currentTheme != themeData.id) {
      ref.read(themeProvider.notifier).setThemeById(themeData.id);
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ThemeEditorDialog(
        theme: ref.read(themeProvider),
        existingTheme: themeData,
      ),
    );
  }

  Future<void> _deleteCustomTheme(
    BuildContext context,
    WidgetRef ref,
    String id,
    String name,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.background,
        title: Text('Delete Theme', style: TextStyle(color: theme.textPrimary)),
        content: Text(
          'Are you sure you want to delete "$name"?',
          style: TextStyle(color: theme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: theme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(themeProvider.notifier).deleteCustomTheme(id);
      NotificationManager.instance.success('Theme "$name" deleted');
    }
  }

  Future<void> _showThemeContextMenu(
    BuildContext context,
    WidgetRef ref,
    AppThemeData themeData,
    TapDownDetails details,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selectedAction = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          details.globalPosition.dx,
          details.globalPosition.dy,
          1,
          1,
        ),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem<String>(value: 'export', child: Text('Export Theme')),
      ],
    );

    if (selectedAction == 'export' && context.mounted) {
      await _exportTheme(context, ref, themeData);
    }
  }

  Future<void> _importThemes(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Import Theme',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        allowMultiple: false,
      );

      final selectedPath = result?.files.single.path;
      if (selectedPath == null || selectedPath.isEmpty) return;

      final content = await File(selectedPath).readAsString();
      final importResult = await ref
          .read(themeProvider.notifier)
          .importThemesFromJsonString(content);

      if (importResult.importedCount == 0) {
        NotificationManager.instance.warning(
          'No themes were imported from file',
        );
        return;
      }

      var message = 'Imported ${importResult.importedCount} theme(s)';
      if (importResult.invalidCount > 0) {
        message += ' • ${importResult.invalidCount} invalid';
      }
      NotificationManager.instance.success(message);
    } on FormatException catch (e) {
      NotificationManager.instance.error('Import failed: ${e.message}');
    } catch (e) {
      NotificationManager.instance.error('Import failed: $e');
    }
  }

  Future<void> _exportTheme(
    BuildContext context,
    WidgetRef ref,
    AppThemeData selectedTheme,
  ) async {
    try {
      final defaultName =
          '${selectedTheme.name.toLowerCase().replaceAll(' ', '_')}_theme.json';
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Theme',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );

      if (outputPath == null || outputPath.isEmpty) return;

      final content = ref
          .read(themeProvider.notifier)
          .exportThemesToJson(themes: [selectedTheme]);
      await File(outputPath).writeAsString(content);

      NotificationManager.instance.success(
        'Theme "${selectedTheme.name}" exported to ${p.basename(outputPath)}',
      );
    } catch (e) {
      NotificationManager.instance.error('Export failed: $e');
    }
  }
}

/// Individual theme card widget
class ThemeCard extends StatelessWidget {
  const ThemeCard({
    super.key,
    required this.themeData,
    required this.isSelected,
    required this.isCustom,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.onSecondaryTapDown,
  });

  final AppThemeData themeData;
  final bool isSelected;
  final bool isCustom;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final void Function(TapDownDetails)? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    return HoverPreviewCard(
      name: themeData.name,
      theme: themeData,
      isSelected: isSelected,
      isCustom: isCustom,
      onTap: onTap,
      onEdit: onEdit,
      onDelete: onDelete,
      onSecondaryTapDown: onSecondaryTapDown,
      icon: themeData.icon,
      backgroundBuilder: (context, innerRadius) {
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                themeData.background,
                themeData.primary,
                themeData.accent,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

/// Gradient animation effect selector section
class _GradientAnimationSection extends ConsumerWidget {
  const _GradientAnimationSection({
    required this.theme,
    required this.searchQuery,
    required this.isSearchMatch,
    this.groupPosition = SectionGroupPosition.only,
    this.isAlternate = false,
  });

  final AppThemeData theme;
  final String searchQuery;
  final bool isSearchMatch;
  final SectionGroupPosition groupPosition;
  final bool isAlternate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentAnimation = ref.watch(
      appShellSettingsProvider.select((s) => s.gradientAnimation),
    );
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final swapGradientColors = ref.watch(swapGradientColorsProvider);
    final previewAnimationsPlaying = ref.watch(gradientPreviewPlayingProvider);

    return SectionGroupBox(
      title: AppearanceSection.gradientSearchGroup.title,
      theme: theme,
      titleIcon: Icons.gradient,
      searchQuery: searchQuery,
      isSearchMatch: isSearchMatch,
      groupPosition: groupPosition,
      alternateBackground: isAlternate,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppearanceSection.gradientIntroSpec.label,
            style: TextStyle(color: theme.textSecondary),
          ),
          const SizedBox(height: 12),
          // horizontal layout containing the gradient previews and a
          // dedicated area for the play/pause control.  By putting the
          // button in its own container on the right we "reserve" the space
          // without affecting how the wrap of cards behaves – the Wrap is
          // wrapped inside an Expanded so it gets whatever width remains after
          // the button is laid out.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // animations take up all available space, wrapping naturally
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: GradientAnimation.values.map((effect) {
                    final isSelected = effect == currentAnimation;
                    return GradientEffectPreview(
                      effect: effect,
                      theme: theme,
                      isSelected: isSelected,
                      isPlaying: previewAnimationsPlaying,
                      onTap: () {
                        settingsNotifier.setSetting(
                          SettingsKeys.gradientAnimation,
                          effect,
                        );
                      },
                    );
                  }).toList(),
                ),
              ),

              // fixed-width container for the play/pause icon button; using
              // SizedBox ensures the Wrap's layout space is reserved even when
              // the button isn't visible (e.g. in tests).
              Padding(
                padding: const EdgeInsets.all(0),
                child: SizedBox(
                  width: 40,
                  child: IconButton(
                    tooltip: previewAnimationsPlaying
                        ? 'Pause preview animations'
                        : 'Play preview animations',
                    onPressed: () {
                      ref
                          .read(gradientPreviewPlayingProvider.notifier)
                          .setPlaying(!previewAnimationsPlaying);
                    },
                    icon: Icon(
                      previewAnimationsPlaying
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline,
                      color: theme.accent,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          SpecToggleSettingRow(
            theme: theme,
            spec: AppearanceSection.gradientSwapSpec,
            value: swapGradientColors,
            onChanged: (v) =>
                settingsNotifier.setSetting(SettingsKeys.swapGradientColors, v),
          ),
        ],
      ),
    );
  }
}
