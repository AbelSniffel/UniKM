/// Card Visual settings section
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import 'settings_common.dart';
import 'settings_control_cards.dart';

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
  static const SettingTextSpec showPlatformOnHoverOnlySpec = SettingTextSpec(
    label: 'Show platform type only on hover',
    description:
        'Hide the platform chip at rest and reveal it only while hovering',
  );
  static const SettingTextSpec showDeadlineSpec = SettingTextSpec(
    label: 'Show deadline chip',
    description: 'Display deadline info on game cards',
  );
  static const SettingTextSpec showRatingsSpec = SettingTextSpec(
    label: 'Show ratings',
    description: 'Display review info on game cards',
  );
  static const SettingTextSpec listViewModeSpec = SettingTextSpec(
    label: 'List view mode',
    description: 'Choose how dense list view cards should be',
  );

  static const SettingsSearchGroup listViewSearchGroup = SettingsSearchGroup(
    title: 'List View',
    settings: [listViewModeSpec],
    extraTexts: ['regular', 'slim', 'list', 'dense'],
  );

  static const SettingsSearchGroup displayRulesSearchGroup =
      SettingsSearchGroup(
        title: 'Display Rules',
        settings: [
          showTagsOnHoverOnlySpec,
          showPlatformOnHoverOnlySpec,
          showTitleOnNoPictureSpec,
        ],
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

  static bool supportsListViewMode(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.linux ||
        TargetPlatform.macOS ||
        TargetPlatform.windows => true,
        _ => false,
      };

  static List<SettingsSearchGroup> searchGroupsFor(TargetPlatform platform) => [
    if (supportsListViewMode(platform)) listViewSearchGroup,
    displayRulesSearchGroup,
    chipsSearchGroup,
  ];

  static List<SettingsSearchGroup> get searchGroups =>
      searchGroupsFor(defaultTargetPlatform);

  static List<String> get sectionSearchTexts => [
    'Game Card Visual Settings',
    for (final group in searchGroups) ...group.indexTexts,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardSettings = ref.watch(gameCardSettingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final showListViewSection =
        supportsListViewMode(Theme.of(context).platform) &&
        shouldShowSettingsGroup(
          query: searchQuery,
          matchesSearch: matchesSearch,
          group: listViewSearchGroup,
        );

    return SettingsSectionGroups(
      attachesToAbove: attachesToAbove,
      entries: [
        buildSearchableSectionEntry(
          visible: showListViewSection,
          theme: theme,
          group: listViewSearchGroup,
          titleIcon: Icons.view_list_outlined,
          searchQuery: searchQuery,
          matchesSearch: matchesSearch,
          childBuilder: () => SettingsControlWrap(
            children: [
              SettingsChoiceCard<ListViewDensityMode>(
                theme: theme,
                label: listViewModeSpec.label,
                description: listViewModeSpec.description,
                value: resolveListViewDensityMode(
                  slimListView: cardSettings.slimListView,
                ),
                choices: const [
                  SettingsChoice(ListViewDensityMode.regular, 'Regular'),
                  SettingsChoice(ListViewDensityMode.slim, 'Slim'),
                ],
                onChanged: (value) => settingsNotifier.setMany(
                  listViewDensityModeSettings(value),
                ),
              ),
            ],
          ),
        ),
        buildSearchableSectionEntry(
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
                spec: showPlatformOnHoverOnlySpec,
                value: cardSettings.showPlatformOnHoverOnly,
                onChanged: (value) => settingsNotifier.setSetting(
                  SettingsKeys.showPlatformOnHoverOnly,
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
      ],
    );
  }
}
