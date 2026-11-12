/// Card Visual settings section
library;

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
    this.attachesToAbove = false,
  });

  final AppThemeData theme;
  final String searchQuery;
  final bool attachesToAbove;

  static const SettingTextSpec showPlatformSpec = SettingTextSpec(
    label: 'Platform',
    icon: Icons.storefront_outlined,
  );
  static const SettingTextSpec showTagsSpec = SettingTextSpec(
    label: 'Tags',
    icon: Icons.label_outline,
  );
  static const SettingTextSpec showTagsOnHoverOnlySpec = SettingTextSpec(
    label: 'Tags & ratings until hover',
    icon: Icons.mouse_outlined,
  );
  static const SettingTextSpec showPlatformOnHoverOnlySpec = SettingTextSpec(
    label: 'Platform until hover',
    icon: Icons.ads_click,
  );
  static const SettingTextSpec showDeadlineSpec = SettingTextSpec(
    label: 'Deadline',
    icon: Icons.event_outlined,
  );
  static const SettingTextSpec showRatingsSpec = SettingTextSpec(
    label: 'Ratings',
    icon: Icons.thumb_up_outlined,
  );
  static const SettingTextSpec listViewModeSpec = SettingTextSpec(
    label: 'Density',
    icon: Icons.view_agenda_outlined,
  );

  static const SettingsSearchGroup listViewSearchGroup = SettingsSearchGroup(
    title: 'List View',
    settings: [listViewModeSpec],
    extraTexts: ['List view mode', 'regular', 'slim', 'list', 'dense'],
  );

  static const SettingsSearchGroup chipsSearchGroup = SettingsSearchGroup(
    title: 'Card Chips',
    settings: [
      showPlatformSpec,
      showTagsSpec,
      showDeadlineSpec,
      showRatingsSpec,
    ],
    extraTexts: ['Information Chips', 'card', 'display', 'review'],
    info: 'Chips shown on game cards.',
  );

  static const SettingsSearchGroup displayRulesSearchGroup =
      SettingsSearchGroup(
        title: 'Hide Chips',
        settings: [showTagsOnHoverOnlySpec, showPlatformOnHoverOnlySpec],
        extraTexts: ['Display Rules', 'hover'],
        info: 'Hovering a card shows its hidden chips.',
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
    chipsSearchGroup,
    displayRulesSearchGroup,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardSettings = ref.watch(gameCardSettingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final showListViewSection =
        supportsListViewMode(Theme.of(context).platform) &&
        shouldShowSettingsGroup(searchQuery, listViewSearchGroup);

    return SettingsSectionGroups(
      attachesToAbove: attachesToAbove,
      entries: [
        buildSearchableSectionEntry(
          visible: showListViewSection,
          theme: theme,
          group: listViewSearchGroup,
          titleIcon: Icons.view_list_outlined,
          searchQuery: searchQuery,
          childBuilder: () => SettingsButtonGroupCard<ListViewDensityMode>(
            theme: theme,
            label: listViewModeSpec.label,
            icon: listViewModeSpec.icon,
            value: resolveListViewDensityMode(
              slimListView: cardSettings.slimListView,
            ),
            // The More menu's list view icons.
            choices: const [
              SettingsChoice(
                ListViewDensityMode.regular,
                'Regular',
                icon: Icon(Icons.view_list),
              ),
              SettingsChoice(
                ListViewDensityMode.slim,
                'Slim',
                icon: Icon(Icons.view_headline),
              ),
            ],
            onChanged: (value) =>
                settingsNotifier.setMany(listViewDensityModeSettings(value)),
          ),
        ),
        buildSearchableSectionEntry(
          theme: theme,
          group: chipsSearchGroup,
          titleIcon: Icons.style_outlined,
          searchQuery: searchQuery,
          childBuilder: () => buildSpecToggleSettingList(
            theme: theme,
            entries: [
              (
                spec: showPlatformSpec,
                value: cardSettings.showPlatform,
                onChanged: settingsNotifier.setter(
                  SettingsKeys.showPlatformChip,
                ),
              ),
              (
                spec: showTagsSpec,
                value: cardSettings.showTags,
                onChanged: settingsNotifier.setter(SettingsKeys.showTagsChip),
              ),
              (
                spec: showDeadlineSpec,
                value: cardSettings.showDeadline,
                onChanged: settingsNotifier.setter(
                  SettingsKeys.showDeadlineChip,
                ),
              ),
              (
                spec: showRatingsSpec,
                value: cardSettings.showRatings,
                onChanged: settingsNotifier.setter(SettingsKeys.showRatings),
              ),
            ],
          ),
        ),
        buildSearchableSectionEntry(
          theme: theme,
          group: displayRulesSearchGroup,
          titleIcon: Icons.visibility_outlined,
          searchQuery: searchQuery,
          childBuilder: () => buildSpecToggleSettingList(
            theme: theme,
            entries: [
              (
                spec: showTagsOnHoverOnlySpec,
                value: cardSettings.showTagsOnHoverOnly,
                onChanged: settingsNotifier.setter(
                  SettingsKeys.showTagsOnHoverOnly,
                ),
              ),
              (
                spec: showPlatformOnHoverOnlySpec,
                value: cardSettings.showPlatformOnHoverOnly,
                onChanged: settingsNotifier.setter(
                  SettingsKeys.showPlatformOnHoverOnly,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
