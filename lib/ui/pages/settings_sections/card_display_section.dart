/// Card Visual settings section
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/platform_file_actions.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import 'settings_common.dart';

/// Card Visual settings section
class CardDisplaySection extends ConsumerWidget {
  const CardDisplaySection({
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

  static const SettingTextSpec showTitleSpec = SettingTextSpec(
    label: 'Show title chip',
    description: 'Display game title chip on cards',
  );
  static const SettingTextSpec showTitleOnNoPictureSpec = SettingTextSpec(
    label: 'Show title on only picture-less cards',
    description: 'Show the title chip only on cards that have no cover image',
  );
  static const SettingTextSpec showPlatformSpec = SettingTextSpec(
    label: 'Show platform chip',
    description: 'Display platform icon on game cards',
  );
  static const SettingTextSpec showTagsSpec = SettingTextSpec(
    label: 'Show tag chips',
    description: 'Display tags on game cards',
  );
  static const SettingTextSpec showTagsOnHoverOnlySpec = SettingTextSpec(
    label: 'Show game tags and ratings only on hover',
    description:
        'Hide tag chips and ratings at rest and reveal them only while hovering',
  );
  static const SettingTextSpec showDeadlineSpec = SettingTextSpec(
    label: 'Show deadline chip',
    description: 'Display deadline info on game cards',
  );
  static const SettingTextSpec showRatingsSpec = SettingTextSpec(
    label: 'Show ratings',
    description: 'Display review info on game cards',
  );
  static const SettingTextSpec compactListViewSpec = SettingTextSpec(
    label: 'List view mode',
    description:
        'Choose how dense list view cards should be',
  );

  static const SettingsSearchGroup viewOptionsSearchGroup = SettingsSearchGroup(
    title: 'Style Options',
    settings: [compactListViewSpec],
    extraTexts: ['regular', 'slim', 'list', 'dense'],
  );

  static const SettingsSearchGroup displayRulesSearchGroup =
      SettingsSearchGroup(
        title: 'Display Rules',
        settings: [showTagsOnHoverOnlySpec, showTitleOnNoPictureSpec],
        extraTexts: ['hover', 'picture-less', 'cover image'],
      );

  static const SettingsSearchGroup chipsSearchGroup = SettingsSearchGroup(
    title: 'Information Chips',
    settings: [
      showTitleSpec,
      showPlatformSpec,
      showTagsSpec,
      showDeadlineSpec,
      showRatingsSpec,
    ],
    extraTexts: ['card', 'display'],
  );

  static List<String> get sectionSearchTexts => [
    'Game Card Visual Settings',
    ...viewOptionsSearchGroup.indexTexts,
    ...displayRulesSearchGroup.indexTexts,
    ...chipsSearchGroup.indexTexts,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardSettings = ref.watch(gameCardSettingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final selectedListViewMode = resolveListViewDensityMode(
      slimListView: cardSettings.slimListView,
    );

    final showChipsSection = shouldShowSettingsGroup(
      query: searchQuery,
      matchesSearch: matchesSearch,
      group: chipsSearchGroup,
    );
    final showDisplayRulesSection = shouldShowSettingsGroup(
      query: searchQuery,
      matchesSearch: matchesSearch,
      group: displayRulesSearchGroup,
    );
    final showViewOptionsSection =
        !PlatformFileActions.isMobilePlatform &&
        shouldShowSettingsGroup(
          query: searchQuery,
          matchesSearch: matchesSearch,
          group: viewOptionsSearchGroup,
        );

    if (!showChipsSection &&
        !showDisplayRulesSection &&
        !showViewOptionsSection) {
      return const SizedBox.shrink();
    }

    return SettingsSectionGroups(
      attachesToAbove: attachesToAbove,
      entries: [
        buildSearchableSectionEntry(
          visible: showDisplayRulesSection,
          theme: theme,
          group: displayRulesSearchGroup,
          titleIcon: Icons.tune,
          searchQuery: searchQuery,
          matchesSearch: matchesSearch,
          childBuilder: () => buildSpecToggleSettingList(
            theme: theme,
            entries: [
              (
                spec: showTagsOnHoverOnlySpec,
                value: cardSettings.showTagsOnHoverOnly,
                onChanged: (value) => settingsNotifier.setSetting(
                  SettingsKeys.showTagsOnHoverOnly,
                  value,
                ),
              ),
              (
                spec: showTitleOnNoPictureSpec,
                value: cardSettings.showTitleOnNoPicture,
                onChanged: (value) => settingsNotifier.setSetting(
                  SettingsKeys.showTitleOnNoPicture,
                  value,
                ),
              ),
            ],
          ),
        ),
        buildSearchableSectionEntry(
          visible: showChipsSection,
          theme: theme,
          group: chipsSearchGroup,
          titleIcon: Icons.crop,
          searchQuery: searchQuery,
          matchesSearch: matchesSearch,
          childBuilder: () => buildSpecToggleSettingList(
            theme: theme,
            entries: [
              (
                spec: showTitleSpec,
                value: cardSettings.showTitle,
                onChanged: (value) => settingsNotifier.setSetting(
                  SettingsKeys.showTitleChip,
                  value,
                ),
              ),
              (
                spec: showPlatformSpec,
                value: cardSettings.showPlatform,
                onChanged: (value) => settingsNotifier.setSetting(
                  SettingsKeys.showPlatformChip,
                  value,
                ),
              ),
              (
                spec: showTagsSpec,
                value: cardSettings.showTags,
                onChanged: (value) => settingsNotifier.setSetting(
                  SettingsKeys.showTagsChip,
                  value,
                ),
              ),
              (
                spec: showDeadlineSpec,
                value: cardSettings.showDeadline,
                onChanged: (value) => settingsNotifier.setSetting(
                  SettingsKeys.showDeadlineChip,
                  value,
                ),
              ),
              (
                spec: showRatingsSpec,
                value: cardSettings.showRatings,
                onChanged: (value) => settingsNotifier.setSetting(
                  SettingsKeys.showRatings,
                  value,
                ),
              ),
            ],
          ),
        ),
        buildSearchableSectionEntry(
          visible: showViewOptionsSection,
          theme: theme,
          group: viewOptionsSearchGroup,
          titleIcon: Icons.view_list_outlined,
          searchQuery: searchQuery,
          matchesSearch: matchesSearch,
          childBuilder: () => SettingRow(
            theme: theme,
            label: compactListViewSpec.label,
            description: compactListViewSpec.description,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: DropdownButtonFormField<ListViewDensityMode>(
                initialValue: selectedListViewMode,
                isExpanded: true,
                menuMaxHeight: kDropdownMenuMaxHeight,
                borderRadius: BorderRadius.circular(theme.cornerRadius),
                dropdownColor: theme.surface,
                style: TextStyle(color: theme.textPrimary),
                items: [
                  const DropdownMenuItem(
                    value: ListViewDensityMode.regular,
                    child: Text('Regular'),
                  ),
                  const DropdownMenuItem(
                    value: ListViewDensityMode.slim,
                    child: Text('Slim'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  settingsNotifier.setMany(listViewDensityModeSettings(value));
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
