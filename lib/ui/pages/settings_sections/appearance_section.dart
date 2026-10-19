/// Appearance settings: themes and interface control styles.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../widgets/app_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:unikm/core/constants/app_constants.dart';

import '../../../core/services/platform_file_actions.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/custom_theme_actions.dart';
import '../../widgets/preview_card.dart';
import '../../widgets/notification_system.dart';
import '../../widgets/section_groupbox.dart';
import '../../widgets/settings_header_actions.dart';
import '../../widgets/toggle_switch.dart';
import '../../widgets/theme_preview_card.dart';
import '../../widgets/theme_picker_actions.dart';
import '../../widgets/app_tab_bar.dart';
import 'settings_common.dart';
import 'settings_theme_editor.dart';
import 'settings_card_style_section.dart';

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

  static const SettingTextSpec toggleStyleSpec = SettingTextSpec(
    label: 'Toggle Style',
    description: 'Choose how toggle switches appear throughout the app',
  );
  static const SettingTextSpec cardIndicatorStyleSpec = SettingTextSpec(
    label: 'Settings card indicator',
    description: 'Choose the indicator used when interaction cards are enabled',
  );
  static SettingsSearchGroup get cardStylesSearchGroup => SettingsSearchGroup(
    title: 'Settings Card Style',
    settings: [cardIndicatorStyleSpec],
    extraTexts: [
      for (final style in SettingsCardIndicatorStyle.values) style.displayName,
    ],
  );
  static const SettingsSearchGroup themeSearchGroup = SettingsSearchGroup(
    title: 'Theme',
    settings: [],
    extraTexts: [
      'Built-in themes',
      'Default themes',
      'Custom themes',
      'All themes',
      'Create Theme',
      'Edit Theme',
      'Edit current theme',
      'Modify current custom theme',
      'Import Theme',
      'Export Theme',
      'Remove Theme',
      'Delete Theme',
      'Delete current theme',
    ],
  );

  static SettingsSearchGroup get controlStylesSearchGroup =>
      SettingsSearchGroup(
        title: 'Control Styles',
        settings: [toggleStyleSpec],
        extraTexts: [for (final style in ToggleStyle.values) style.displayName],
      );

  static List<SettingsSearchGroup> get searchGroups =>
      searchGroupsFor(interactionCards: true);

  static List<SettingsSearchGroup> searchGroupsFor({
    required bool interactionCards,
  }) => [
    themeSearchGroup,
    controlStylesSearchGroup,
    if (interactionCards) cardStylesSearchGroup,
  ];

  static List<String> get sectionSearchTexts => [
    'Appearance Settings',
    ...searchGroups.expand((group) => group.indexTexts),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(customThemesJsonProvider);
    final current = ref.watch(themeProvider);
    final builtInOverlayStyle = ref.watch(navPanelOverlayStyleSettingProvider);
    final builtInThemes = AppThemeData.builtInThemes;
    final themeNotifier = ref.read(themeProvider.notifier);
    final allThemes = themeNotifier.getAllThemes();
    final builtInIds = builtInThemes.map((theme) => theme.id).toSet();
    final customThemes = allThemes
        .where((t) => !builtInIds.contains(t.id))
        .toList();
    final isSearching = searchQuery.trim().isNotEmpty;
    final selectedTab = ref.watch(appearanceThemeTabProvider);
    List<AppThemeData> themesForTab(int tab) => switch (tab) {
      1 => builtInThemes,
      2 => customThemes,
      _ => allThemes,
    };
    // A name search can reveal a theme in the other collection without
    // replacing the user's remembered tab.
    final visibleTab =
        isSearching &&
            !themesForTab(selectedTab).any((t) => matchesSearch(t.name)) &&
            allThemes.any((t) => matchesSearch(t.name))
        ? 0
        : selectedTab;
    final visibleThemes = themesForTab(visibleTab);

    // Check which sections match search
    final showThemeSection =
        shouldShowSettingsGroup(
          query: searchQuery,
          matchesSearch: matchesSearch,
          group: themeSearchGroup,
        ) ||
        builtInThemes.any((t) => matchesSearch(t.name)) ||
        customThemes.any((t) => matchesSearch(t.name));
    final showToggleSection = shouldShowSettingsGroup(
      query: searchQuery,
      matchesSearch: matchesSearch,
      group: controlStylesSearchGroup,
    );
    final showCardStylesSection =
        ref.watch(experimentalInteractionCardsProvider) &&
        shouldShowSettingsGroup(
          query: searchQuery,
          matchesSearch: matchesSearch,
          group: cardStylesSearchGroup,
        );
    if (isSearching &&
        !showThemeSection &&
        !showToggleSection &&
        !showCardStylesSection) {
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
          childBuilder: () {
            final child = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTabBar(
                  theme: theme,
                  tabs: const [
                    AppTab('All'),
                    AppTab('Default'),
                    AppTab('Custom'),
                  ],
                  selectedIndex: visibleTab,
                  onChanged: (index) => ref
                      .read(appearanceThemeTabProvider.notifier)
                      .setIndex(index),
                ),
                const SizedBox(height: 10),
                AppTabTransition(
                  index: visibleTab,
                  child: visibleThemes.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            'No custom themes yet. Create one from your current colors.',
                            style: TextStyle(color: theme.textSecondary),
                          ),
                        )
                      : PreviewCardWrap(
                          spacing: kElementHSpacing,
                          runSpacing: 10,
                          children: [
                            for (final themeData in visibleThemes)
                              ThemePreviewCard(
                                key: ValueKey(themeData.id),
                                data: themeData,
                                theme: theme,
                                preview: builtInIds.contains(themeData.id)
                                    ? themeData.copyWith(
                                        navPanelOverlayStyle:
                                            builtInOverlayStyle,
                                      )
                                    : themeData,
                                selected: current.id == themeData.id,
                                onDoubleTap: builtInIds.contains(themeData.id)
                                    ? null
                                    : () => _openThemeEditor(
                                        context,
                                        ref,
                                        existing: themeData,
                                      ),
                                onTap: () => ref
                                    .read(themeProvider.notifier)
                                    .setTheme(themeData),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 10),
                ThemePickerActions(
                  theme: theme,
                  onCreate: () => _openThemeEditor(context, ref),
                  onEdit: builtInIds.contains(current.id)
                      ? null
                      : () => _openThemeEditor(context, ref, existing: current),
                  onDelete: builtInIds.contains(current.id)
                      ? null
                      : () => deleteCustomThemeWithConfirmation(
                          context,
                          ref,
                          current.id,
                          current.name,
                        ),
                ),
              ],
            );
            if (MediaQuery.disableAnimationsOf(context)) return child;
            return AnimatedSize(
              key: const ValueKey('appearance-theme-size'),
              duration: kTabTransition,
              curve: kTabTransitionCurve,
              alignment: Alignment.topLeft,
              child: child,
            );
          },
        ),
        SectionGroupEntry(
          visible: showToggleSection,
          builder: (position, isAlternate) => _ControlStylesSection(
            theme: theme,
            searchQuery: searchQuery,
            isSearchMatch: isSearching,
            groupPosition: position,
            isAlternate: isAlternate,
          ),
        ),
        SectionGroupEntry(
          visible: showCardStylesSection,
          builder: (position, isAlternate) => SettingsCardStyleSection(
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
}

void _openThemeEditor(
  BuildContext context,
  WidgetRef ref, {
  AppThemeData? existing,
}) {
  // Capture before opening: resizing may replace the footer while the editor
  // stays open, so its route builder must not read the initiating widget ref.
  final theme = ref.read(effectiveThemeProvider);
  showAppDialog<void>(
    context: context,
    builder: (_) => ThemeEditorDialog(theme: theme, existingTheme: existing),
  );
}

Future<void> _importThemes(BuildContext context, WidgetRef ref) async {
  try {
    final result = await FilePicker.pickFile(
      dialogTitle: 'Import Theme',
      type: FileType.any,
    );

    final selectedPath = result?.path;
    if (selectedPath == null || selectedPath.isEmpty) return;
    if (!selectedPath.toLowerCase().endsWith('.json')) {
      NotificationManager.instance.error(
        'Unsupported file type. Please select a .json theme file.',
      );
      return;
    }

    final content = await File(selectedPath).readAsString();
    final importResult = await ref
        .read(themeProvider.notifier)
        .importThemesFromJsonString(content);

    if (importResult.importedCount == 0) {
      NotificationManager.instance.warning('No themes were imported from file');
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

/// Import/export actions shared by the Appearance and search-result headers.
class ThemeHeaderActions extends ConsumerWidget {
  const ThemeHeaderActions({
    super.key,
    this.encapsulated = true,
    this.expanded = false,
  });

  final bool encapsulated;
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final buttons = <Widget>[
      SettingsHeaderAction(
        theme: theme,
        icon: Icons.download,
        tooltip: 'Import Theme',
        onTap: () => _importThemes(context, ref),
      ),
      SettingsHeaderAction(
        theme: theme,
        icon: Icons.upload,
        tooltip: 'Export Theme',
        onTap: theme.id.isEmpty
            ? null
            : () => _exportTheme(context, ref, theme),
      ),
    ];
    return SettingsHeaderActions(
      theme: theme,
      encapsulated: encapsulated,
      expanded: expanded,
      children: buttons,
    );
  }
}

// ---------------------------------------------------------------------------
// Toggle style selector
// ---------------------------------------------------------------------------

/// Settings section that lets the user pick between toggle switch styles.
class _ControlStylesSection extends ConsumerStatefulWidget {
  const _ControlStylesSection({
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
  ConsumerState<_ControlStylesSection> createState() =>
      _ControlStylesSectionState();
}

class _ControlStylesSectionState extends ConsumerState<_ControlStylesSection> {
  /// Local preview state; trying the switch does not change app settings.
  final _demoOn = {for (final style in ToggleStyle.values) style: true};

  @override
  Widget build(BuildContext context) {
    final currentStyle = ref.watch(toggleStyleProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    return SectionGroupBox(
      title: AppearanceSection.controlStylesSearchGroup.title,
      theme: widget.theme,
      titleIcon: Icons.toggle_on_outlined,
      searchQuery: widget.searchQuery,
      isSearchMatch: widget.isSearchMatch,
      groupPosition: widget.groupPosition,
      alternateBackground: widget.isAlternate,
      child: PreviewCardWrap(
        children: [
          for (final style in ToggleStyle.values)
            Tooltip(
              key: ValueKey(style),
              message: style.description,
              child: PreviewCard(
                name: style.displayName,
                height: 84,
                theme: widget.theme,
                isSelected: currentStyle == style,
                recessedSelection: true,
                onTap: () => settingsNotifier.setSetting(
                  SettingsKeys.toggleStyle,
                  style,
                ),
                backgroundBuilder: (_, _) => ColoredBox(
                  color: widget.theme.background.withValues(alpha: 0.65),
                ),
                foreground: Positioned(
                  right: 8,
                  bottom: 8,
                  child: Semantics(
                    label: '${style.displayName} toggle preview',
                    toggled: _demoOn[style],
                    onTap: () =>
                        setState(() => _demoOn[style] = !_demoOn[style]!),
                    child: ExcludeSemantics(
                      child: AppToggleSwitch(
                        value: _demoOn[style]!,
                        onChanged: (value) =>
                            setState(() => _demoOn[style] = value),
                        theme: widget.theme,
                        style: style,
                        label: '',
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
