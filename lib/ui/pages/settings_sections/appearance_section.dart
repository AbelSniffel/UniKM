/// Appearance settings section: theme selection, navigation bar, gradient animation.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:unikm/core/constants/app_constants.dart';

import '../../../core/services/platform_file_actions.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/animated_gradient_bar.dart';
import '../../widgets/dialog_helpers.dart';
import '../../widgets/hover_preview_card.dart';
import '../../widgets/navigation_panel_overlay.dart';
import '../../widgets/notification_system.dart';
import '../../widgets/popup_menu_helpers.dart';
import '../../widgets/section_groupbox.dart';
import '../../widgets/toggle_switch.dart';
import 'settings_common.dart';
import 'settings_theme_editor.dart';

final gradientPreviewPlayingProvider =
    NotifierProvider<_GradientPreviewPlayingNotifier, bool>(
      _GradientPreviewPlayingNotifier.new,
    );

class _GradientPreviewPlayingNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void setPlaying(bool isPlaying) {
    state = isPlaying;
  }
}

/// Appearance settings section
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

  static const SettingTextSpec navPositionSpec = SettingTextSpec(
    label: 'Position',
    description: 'Move the navigation bar to a different edge',
  );
  static const SettingTextSpec navBarButtonAlignmentSpec = SettingTextSpec(
    label: 'Horizontal Navigation Button Placement',
    description: 'Standard panel layout',
  );
  static const SettingTextSpec navBarButtonAlignmentVerticalSpec =
      SettingTextSpec(
        label: 'Vertical Navigation Button Placement',
        description: 'Standard panel layout',
      );
  static const SettingTextSpec navPanelGradientBarSpec = SettingTextSpec(
    label: 'Integrated Gradient Bar',
    description:
        'Place a full-size animated gradient bar inside the navigation panel',
  );
  static const SettingTextSpec navButtonArrangementHorizontalSpec =
      SettingTextSpec(
        label: 'Horizontal Navigation Button Placement',
        description: 'Position the page buttons relative to the gradient bar',
      );
  static const SettingTextSpec navButtonArrangementVerticalSpec =
      SettingTextSpec(
        label: 'Vertical Navigation Button Placement',
        description: 'Position the page buttons relative to the gradient bar',
      );
  static const SettingTextSpec navPanelOverlayStyleSpec = SettingTextSpec(
    label: 'Navigation panel overlay style',
    description: 'Add decorative overlays for the navigation panel',
  );
  static const SettingTextSpec gradientSwapSpec = SettingTextSpec(
    label: 'Swap primary & accent colors',
    description: 'Alternative look for the gradient bar',
  );
  static const SettingTextSpec gradientIntroSpec = SettingTextSpec(
    label: 'Select an animation for the gradient bar',
  );
  static const SettingTextSpec toggleStyleSpec = SettingTextSpec(
    label: 'Toggle Style',
    description: 'Choose how toggle switches appear throughout the app',
  );
  static const SettingsSearchGroup themeSearchGroup = SettingsSearchGroup(
    title: 'Theme',
    settings: [],
    extraTexts: [
      'Built-in themes',
      'Default themes',
      'Custom themes',
      'Create Theme',
      'Edit Theme',
      'Import Theme',
      'Export Theme',
      'Remove Theme',
    ],
  );

  static const SettingsSearchGroup navigationSearchGroup = SettingsSearchGroup(
    title: 'Navigation Panel',
    settings: [
      navPositionSpec,
      navBarButtonAlignmentSpec,
      navBarButtonAlignmentVerticalSpec,
      navPanelGradientBarSpec,
      navButtonArrangementHorizontalSpec,
      navButtonArrangementVerticalSpec,
    ],
    extraTexts: ['Left', 'Center', 'Right', 'Top', 'Bottom', 'Split'],
  );

  static const SettingsSearchGroup navOverlaySearchGroup = SettingsSearchGroup(
    title: 'Navigation Panel Overlay',
    settings: [navPanelOverlayStyleSpec],
    extraTexts: [
      'None',
      'Diagonal',
      'Crosshatch',
      'Gradient',
      'Hex Pattern',
      'Ripple',
      'Built-in themes',
      'Default themes',
      'Custom themes',
      'Persistent setting',
      'Saved with custom theme',
      'Theme override',
      'Overlay saved in custom theme',
    ],
  );

  static SettingsSearchGroup get gradientSearchGroup => SettingsSearchGroup(
    title: 'Gradient Bar Effect',
    description: gradientIntroSpec.label,
    settings: [gradientIntroSpec, gradientSwapSpec],
    extraTexts: [
      ...GradientAnimation.values.map((effect) => effect.displayName),
    ],
  );

  static SettingsSearchGroup get toggleSearchGroup => const SettingsSearchGroup(
    title: 'Toggle Switches',
    settings: [toggleStyleSpec],
    extraTexts: ['Regular', 'Dot', 'Morph Dot'],
  );

  static List<SettingsSearchGroup> get searchGroups => [
    themeSearchGroup,
    navigationSearchGroup,
    navOverlaySearchGroup,
    gradientSearchGroup,
    toggleSearchGroup,
  ];

  static List<String> get sectionSearchTexts => [
    'Appearance Settings',
    ...searchGroups.expand((group) => group.indexTexts),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(customThemesJsonProvider);
    final currentTheme = ref.watch(themeProvider);
    final activeThemeId = ref.watch(themeProvider.select((value) => value.id));
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final effectiveTheme = ref.watch(effectiveThemeProvider);
    final builtInOverlayStyle = ref.watch(navPanelOverlayStyleSettingProvider);
    final navBarPosition = ref.watch(
      appShellSettingsProvider.select((s) => s.navBarPosition),
    );
    final navPanelGradientBar = ref.watch(navPanelGradientBarProvider);
    final isHorizontalPanel =
        navBarPosition == NavBarPosition.top ||
        navBarPosition == NavBarPosition.bottom;
    final navButtonArrangementH = ref.watch(navButtonArrangementHProvider);
    final navButtonArrangementV = ref.watch(navButtonArrangementVProvider);
    final navButtonArrangement = isHorizontalPanel
        ? navButtonArrangementH
        : navButtonArrangementV;

    final builtInThemes = AppThemeData.builtInThemes;
    final themeNotifier = ref.read(themeProvider.notifier);
    final allThemes = themeNotifier.getAllThemes();
    final builtInIds = builtInThemes.map((theme) => theme.id).toSet();
    final customThemes = allThemes
        .where((t) => !builtInIds.contains(t.id))
        .toList();
    final isCurrentThemeCustom =
        activeThemeId.isNotEmpty && !builtInIds.contains(activeThemeId);
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
    final showNavOverlaySection = shouldShowSettingsGroup(
      query: searchQuery,
      matchesSearch: matchesSearch,
      group: navOverlaySearchGroup,
    );
    final showToggleSection = shouldShowSettingsGroup(
      query: searchQuery,
      matchesSearch: matchesSearch,
      group: toggleSearchGroup,
    );
    if (isSearching &&
        !showThemeSection &&
        !showNavBarSection &&
        !showNavOverlaySection &&
        !showGradientSection &&
        !showToggleSection) {
      return const SizedBox.shrink();
    }

    return SettingsSectionGroups(
      attachesToAbove: attachesToAbove,
      entries: [
        buildSearchableSectionEntry(
          visible: showThemeSection,
          theme: theme,
          group: themeSearchGroup,
          titleIcon: Icons.color_lens,
          searchQuery: searchQuery,
          matchesSearch: matchesSearch,
          extraMatch: () =>
              builtInThemes.any((t) => matchesSearch(t.name)) ||
              customThemes.any((t) => matchesSearch(t.name)),
          childBuilder: () => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isVeryNarrow =
                      constraints.maxWidth < kVeryNarrowLayoutBreakpoint;
                  Widget withIconOnlyTooltip({
                    required String message,
                    required Widget child,
                  }) {
                    return Tooltip(message: message, child: child);
                  }
                  final iconOnlyButtonStyle = ButtonStyle(
                    padding: WidgetStatePropertyAll(EdgeInsets.zero),
                    minimumSize: WidgetStatePropertyAll(
                      Size.square(kElementHeight),
                    ),
                    fixedSize: WidgetStatePropertyAll(
                      Size.square(kElementHeight),
                    ),
                    maximumSize: WidgetStatePropertyAll(
                      Size.square(kElementHeight),
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  );
                  return Wrap(
                    spacing: kElementHSpacing,
                    runSpacing: kElementVSpacing,
                    children: isVeryNarrow
                        ? [
                            withIconOnlyTooltip(
                              message: 'Create Theme',
                              child: ElevatedButton(
                                style: iconOnlyButtonStyle,
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => ThemeEditorDialog(
                                      theme: effectiveTheme,
                                    ),
                                  );
                                },
                                child: const Icon(Icons.create),
                              ),
                            ),
                            if (activeThemeId.isNotEmpty)
                              withIconOnlyTooltip(
                                message: 'Remove Theme',
                                child: OutlinedButton(
                                  style: iconOnlyButtonStyle,
                                  onPressed: isCurrentThemeCustom
                                      ? () => _deleteCustomTheme(
                                          context,
                                          ref,
                                          currentTheme.id,
                                          currentTheme.name,
                                        )
                                      : null,
                                  child: const Icon(Icons.delete),
                                ),
                              ),
                            withIconOnlyTooltip(
                              message: 'Import Theme',
                              child: OutlinedButton(
                                style: iconOnlyButtonStyle,
                                onPressed: () => _importThemes(context, ref),
                                child: const Icon(Icons.download),
                              ),
                            ),
                            if (activeThemeId.isNotEmpty)
                              withIconOnlyTooltip(
                                message: 'Export Theme',
                                child: OutlinedButton(
                                  style: iconOnlyButtonStyle,
                                  onPressed: () {
                                    _exportTheme(context, ref, currentTheme);
                                  },
                                  child: const Icon(Icons.upload),
                                ),
                              ),
                          ]
                        : [
                            ElevatedButton.icon(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (ctx) =>
                                      ThemeEditorDialog(theme: effectiveTheme),
                                );
                              },
                              icon: const Icon(Icons.create),
                              label: const Text('Create Theme'),
                            ),
                            if (activeThemeId.isNotEmpty)
                              OutlinedButton.icon(
                                onPressed: isCurrentThemeCustom
                                    ? () => _deleteCustomTheme(
                                        context,
                                        ref,
                                        currentTheme.id,
                                        currentTheme.name,
                                      )
                                    : null,
                                icon: const Icon(Icons.delete),
                                label: const Text('Remove Theme'),
                              ),
                            OutlinedButton.icon(
                              onPressed: () => _importThemes(context, ref),
                              icon: const Icon(Icons.download),
                              label: const Text('Import Theme'),
                            ),
                            if (activeThemeId.isNotEmpty)
                              OutlinedButton.icon(
                                onPressed: () {
                                  _exportTheme(context, ref, currentTheme);
                                },
                                icon: const Icon(Icons.upload),
                                label: const Text('Export Theme'),
                              ),
                          ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: kElementHSpacing,
                runSpacing: kElementVSpacing,
                children: [
                  ...builtInThemes.map((themeData) {
                    final isSelected = activeThemeId == themeData.id;
                    return ThemeCard(
                      themeData: themeData,
                      previewCornerRadius: theme.cornerRadius,
                      previewThemeData: themeData.copyWith(
                        navPanelOverlayStyle: builtInOverlayStyle,
                      ),
                      isSelected: isSelected,
                      isCustom: false,
                      onTap: () {
                        ref.read(themeProvider.notifier).setTheme(themeData);
                      },
                      onSecondaryTapDown: (details) => _showThemeContextMenu(
                        context,
                        ref,
                        themeData,
                        details,
                      ),
                    );
                  }),
                  ...customThemes.map((themeData) {
                    final isSelected = activeThemeId == themeData.id;
                    return ThemeCard(
                      themeData: themeData,
                      previewCornerRadius: theme.cornerRadius,
                      isSelected: isSelected,
                      isCustom: true,
                      onTap: () {
                        ref.read(themeProvider.notifier).setTheme(themeData);
                      },
                      onDoubleTap: () =>
                          _editCustomTheme(context, ref, themeData),
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
        buildSearchableSectionEntry(
          visible: showNavBarSection,
          theme: theme,
          group: navigationSearchGroup,
          titleIcon: Icons.view_sidebar,
          searchQuery: searchQuery,
          matchesSearch: matchesSearch,
          childBuilder: () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!PlatformFileActions.isMobilePlatform)
                SpecToggleSettingRow(
                  theme: theme,
                  spec: navPanelGradientBarSpec,
                  value: navPanelGradientBar,
                  onChanged: (value) => settingsNotifier.setSetting(
                    SettingsKeys.navPanelGradientBar,
                    value,
                  ),
                ),
              SpecSettingRow(
                theme: theme,
                spec: navPositionSpec,
                child: SizedBox(
                  width: 110,
                  child: DropdownButtonFormField<NavBarPosition>(
                    initialValue: navBarPosition,
                    isExpanded: true,
                    menuMaxHeight: 320,
                    borderRadius: BorderRadius.circular(theme.cornerRadius),
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
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
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
              _buildNavArrangementRow(
                theme: theme,
                spec: isHorizontalPanel
                    ? (navPanelGradientBar
                          ? navButtonArrangementHorizontalSpec
                          : navBarButtonAlignmentSpec)
                    : (navPanelGradientBar
                          ? navButtonArrangementVerticalSpec
                          : navBarButtonAlignmentVerticalSpec),
                value: navButtonArrangement,
                isHorizontal: isHorizontalPanel,
                useIntegratedLabels: navPanelGradientBar,
                onChanged: (value) => settingsNotifier.setSetting(
                  isHorizontalPanel
                      ? SettingsKeys.navButtonArrangementH
                      : SettingsKeys.navButtonArrangementV,
                  value,
                ),
              ),
            ],
          ),
        ),
        SectionGroupEntry(
          visible: showNavOverlaySection,
          builder: (position, isAlternate) => _NavigationPanelOverlaySection(
            theme: theme,
            searchQuery: searchQuery,
            isSearchMatch: isSearching,
            groupPosition: position,
            isAlternate: isAlternate,
            onOverlaySelected: (style) =>
                _applyNavPanelOverlayStyle(ref, style),
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
          visible: showToggleSection,
          builder: (position, isAlternate) => _ToggleStyleSection(
            theme: theme,
            searchQuery: searchQuery,
            isSearchMatch: isSearching,
            groupPosition: position,
            isAlternate: isAlternate,
          ),
        ),
      ],
    );
  }

  Future<void> _applyNavPanelOverlayStyle(
    WidgetRef ref,
    NavPanelOverlayStyle style,
  ) async {
    final effectiveOverlayStyle = ref.read(
      effectiveNavPanelOverlayStyleProvider,
    );
    if (effectiveOverlayStyle == style) {
      return;
    }

    final currentTheme = ref.read(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);
    final isBuiltInTheme = ref.read(currentThemeIsBuiltInProvider);

    if (isBuiltInTheme) {
      await ref
          .read(settingsProvider.notifier)
          .setSetting(SettingsKeys.navPanelOverlayStyle, style);
      return;
    }

    await themeNotifier.saveCustomTheme(
      currentTheme.copyWith(navPanelOverlayStyle: style),
    );
  }

  Widget _buildNavArrangementRow({
    required AppThemeData theme,
    required SettingTextSpec spec,
    required NavButtonArrangement value,
    required bool isHorizontal,
    required bool useIntegratedLabels,
    required ValueChanged<NavButtonArrangement> onChanged,
  }) {
    final availableArrangements = useIntegratedLabels
        ? NavButtonArrangement.values
              .where(
                (arrangement) => arrangement != NavButtonArrangement.center,
              )
              .toList(growable: false)
        : NavButtonArrangement.values;
    final resolvedValue =
        useIntegratedLabels && value == NavButtonArrangement.center
        ? NavButtonArrangement.split
        : value;

    return SpecSettingRow(
      theme: theme,
      spec: spec,
      child: SizedBox(
        width: 110,
        child: DropdownButtonFormField<NavButtonArrangement>(
          initialValue: resolvedValue,
          isExpanded: true,
          menuMaxHeight: 320,
          borderRadius: BorderRadius.circular(theme.cornerRadius),
          onChanged: (nextValue) {
            if (nextValue == null) return;
            onChanged(nextValue);
          },
          style: TextStyle(color: theme.textPrimary),
          dropdownColor: theme.surface,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: availableArrangements
              .map(
                (arrangement) => DropdownMenuItem(
                  value: arrangement,
                  child: Text(
                    useIntegratedLabels
                        ? arrangement.displayNameForIntegrated(
                            isHorizontal: isHorizontal,
                          )
                        : arrangement.displayNameForStandard(
                            isHorizontal: isHorizontal,
                          ),
                    style: TextStyle(color: theme.textPrimary),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  void _editCustomTheme(
    BuildContext context,
    WidgetRef ref,
    AppThemeData themeData,
  ) {
    final activeThemeId = ref.read(themeProvider).id;
    if (activeThemeId != themeData.id) {
      ref.read(themeProvider.notifier).setThemeById(themeData.id);
    }

    showDialog(
      context: context,
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
    final confirmed = await showConfirmDialog(
      context: context,
      theme: theme,
      title: 'Delete Theme',
      message: 'Are you sure you want to delete "$name"?',
      confirmLabel: 'Delete',
      confirmIcon: Icons.delete,
      destructive: true,
    );

    if (confirmed) {
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
    final isCustomTheme = !ref
        .read(builtInThemeIdsProvider)
        .contains(themeData.id);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selectedAction = await showAppMenu<String>(
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
      items: [
        if (isCustomTheme)
          const PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
        if (isCustomTheme)
          const PopupMenuItem<String>(value: 'remove', child: Text('Remove')),
        if (isCustomTheme) const PopupMenuDivider(height: 1),
        const PopupMenuItem<String>(
          value: 'export',
          child: Text('Export Theme'),
        ),
      ],
    );

    if (!context.mounted) {
      return;
    }

    switch (selectedAction) {
      case 'edit':
        _editCustomTheme(context, ref, themeData);
        break;
      case 'remove':
        await _deleteCustomTheme(context, ref, themeData.id, themeData.name);
        break;
      case 'export':
        await _exportTheme(context, ref, themeData);
        break;
    }
  }

  Future<void> _importThemes(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.pickFiles(
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
      final target = await PlatformFileActions.prepareExportTarget(
        dialogTitle: 'Export Theme',
        fileName: defaultName,
        allowedExtensions: const ['json'],
      );

      if (target == null) return;

      final content = ref
          .read(themeProvider.notifier)
          .exportThemesToJson(themes: [selectedTheme]);
      await target.file.writeAsString(content);

      if (target.shouldShareAfterWrite) {
        final shared = await PlatformFileActions.shareFile(
          target.file,
          subject: 'UniKM theme export',
        );
        if (!shared) {
          try {
            if (await target.file.exists()) {
              await target.file.delete();
            }
          } catch (_) {
            // Best effort cleanup only.
          }
          return;
        }
      }

      NotificationManager.instance.success(
        'Theme "${selectedTheme.name}" exported to ${p.basename(target.file.path)}',
      );
    } catch (e) {
      NotificationManager.instance.error('Export failed: $e');
    }
  }
}

class ThemeCard extends StatelessWidget {
  const ThemeCard({
    super.key,
    required this.themeData,
    required this.previewCornerRadius,
    required this.isSelected,
    required this.isCustom,
    required this.onTap,
    this.previewThemeData,
    this.onDoubleTap,
    this.onEdit,
    this.onDelete,
    this.onSecondaryTapDown,
  });

  final AppThemeData themeData;
  final double previewCornerRadius;
  final AppThemeData? previewThemeData;
  final bool isSelected;
  final bool isCustom;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final void Function(TapDownDetails)? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final resolvedThemeData = previewThemeData ?? themeData;

    return HoverPreviewCard(
      name: themeData.name,
      theme: resolvedThemeData,
      cornerRadiusOverride: previewCornerRadius,
      isSelected: isSelected,
      isCustom: isCustom,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onEdit: onEdit,
      onDelete: onDelete,
      onSecondaryTapDown: onSecondaryTapDown,
      icon: resolvedThemeData.icon,
      backgroundBuilder: (context, innerRadius) {
        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    resolvedThemeData.background,
                    resolvedThemeData.accent,
                    resolvedThemeData.secondary,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
            if (resolvedThemeData.navPanelOverlayStyle !=
                NavPanelOverlayStyle.none)
              Positioned.fill(
                child: IgnorePointer(
                  child: NavigationPanelOverlayPaint(
                    theme: resolvedThemeData,
                    preview: true,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _NavigationPanelOverlaySection extends ConsumerWidget {
  const _NavigationPanelOverlaySection({
    required this.theme,
    required this.searchQuery,
    required this.isSearchMatch,
    required this.onOverlaySelected,
    this.groupPosition = SectionGroupPosition.only,
    this.isAlternate = false,
  });

  final AppThemeData theme;
  final String searchQuery;
  final bool isSearchMatch;
  final Future<void> Function(NavPanelOverlayStyle style) onOverlaySelected;
  final SectionGroupPosition groupPosition;
  final bool isAlternate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTheme = ref.watch(themeProvider);
    final effectiveOverlayStyle = ref.watch(
      effectiveNavPanelOverlayStyleProvider,
    );
    final effectiveTheme = ref.watch(effectiveThemeProvider);

    return SectionGroupBox(
      title: AppearanceSection.navOverlaySearchGroup.title,
      description: AppearanceSection.navPanelOverlayStyleSpec.description,
      theme: theme,
      titleIcon: Icons.layers_outlined,
      searchQuery: searchQuery,
      isSearchMatch: isSearchMatch,
      groupPosition: groupPosition,
      alternateBackground: isAlternate,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: NavPanelOverlayStyle.values.map((style) {
          return HoverPreviewCard(
            name: style.displayName,
            theme: theme,
            isSelected: effectiveOverlayStyle == style,
            onTap: () => onOverlaySelected(style),
            backgroundBuilder: (context, innerRadius) => ClipRRect(
              borderRadius: BorderRadius.circular(innerRadius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: effectiveTheme.navBackground,
                    ),
                  ),
                  if (style != NavPanelOverlayStyle.none)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: NavigationPanelOverlayPaint(
                          theme: currentTheme.copyWith(
                            navPanelOverlayStyle: style,
                          ),
                          preview: true,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Toggle style selector
// ---------------------------------------------------------------------------

/// Settings section that lets the user pick between toggle switch styles.
class _ToggleStyleSection extends ConsumerStatefulWidget {
  const _ToggleStyleSection({
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
  ConsumerState<_ToggleStyleSection> createState() =>
      _ToggleStyleSectionState();
}

class _ToggleStyleSectionState extends ConsumerState<_ToggleStyleSection> {
  /// Shared demo value — toggling either card's switch toggles this state,
  /// and both preview switches reflect it in real time.
  bool _demoOn = true;

  @override
  Widget build(BuildContext context) {
    final currentStyle = ref.watch(toggleStyleProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    return SectionGroupBox(
      title: AppearanceSection.toggleSearchGroup.title,
      description: AppearanceSection.toggleStyleSpec.description,
      theme: widget.theme,
      titleIcon: Icons.toggle_on_outlined,
      searchQuery: widget.searchQuery,
      isSearchMatch: widget.isSearchMatch,
      groupPosition: widget.groupPosition,
      alternateBackground: widget.isAlternate,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: ToggleStyle.values.map((style) {
          return HoverPreviewCard(
            name: style.displayName,
            theme: widget.theme,
            isSelected: style == currentStyle,
            onTap: () =>
                settingsNotifier.setSetting(SettingsKeys.toggleStyle, style),
            backgroundBuilder: (context, _) =>
                Container(color: widget.theme.surface),
            overlayWidget: Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 6),
              child: AppToggleSwitch(
                value: _demoOn,
                onChanged: (v) => setState(() => _demoOn = v),
                theme: widget.theme,
                style: style,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Gradient animation selector
// ---------------------------------------------------------------------------

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
    final navPanelGradientBar = ref.watch(navPanelGradientBarProvider);
    final currentAnimation = ref.watch(
      appShellSettingsProvider.select((s) => s.gradientAnimation),
    );
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final swapGradientColors = ref.watch(swapGradientColorsProvider);
    final previewAnimationsPlaying = ref.watch(gradientPreviewPlayingProvider);
    final visibleEffects = navPanelGradientBar
        ? GradientAnimation.values.toList(growable: false)
        : GradientAnimation.values
              .where((effect) => effect != GradientAnimation.wave)
              .toList(growable: false);

    return SectionGroupBox(
      title: AppearanceSection.gradientSearchGroup.title,
      description: AppearanceSection.gradientSearchGroup.description,
      theme: theme,
      titleIcon: Icons.gradient,
      searchQuery: searchQuery,
      isSearchMatch: isSearchMatch,
      groupPosition: groupPosition,
      alternateBackground: isAlternate,
      trailing: IconButton(
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
          size: 22,
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        visualDensity: VisualDensity.compact,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: visibleEffects.map((effect) {
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
