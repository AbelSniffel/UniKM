/// Card Visual settings section
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  static const SettingsSearchGroup chipsSearchGroup = SettingsSearchGroup(
    title: 'Information Chips',
    settings: [
      showTagsOnHoverOnlySpec,
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
    ...chipsSearchGroup.indexTexts,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardSettings = ref.watch(gameCardSettingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    // Check if section matches search
    final showSection = shouldShowSettingsGroup(
      query: searchQuery,
      matchesSearch: matchesSearch,
      group: chipsSearchGroup,
    );

    if (!showSection) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Card Visual options
        SearchableSectionGroupBox(
          theme: theme,
          group: chipsSearchGroup,
          titleIcon: Icons.crop,
          searchQuery: searchQuery,
          matchesSearch: matchesSearch,
          attachesToAbove: attachesToAbove,
          child: Column(
            children: [
              SpecToggleSettingRow(
                theme: theme,
                spec: showTagsOnHoverOnlySpec,
                value: cardSettings.showTagsOnHoverOnly,
                showDividerBelow: true,
                onChanged: (value) => settingsNotifier.setSetting(
                  SettingsKeys.showTagsOnHoverOnly,
                  value,
                ),
              ),

              SpecToggleSettingRow(
                theme: theme,
                spec: showTitleSpec,
                value: cardSettings.showTitle,
                onChanged: (value) => settingsNotifier.setSetting(
                  SettingsKeys.showTitleChip,
                  value,
                ),
              ),
              SpecToggleSettingRow(
                theme: theme,
                spec: showPlatformSpec,
                value: cardSettings.showPlatform,
                onChanged: (value) => settingsNotifier.setSetting(
                  SettingsKeys.showPlatformChip,
                  value,
                ),
              ),
              SpecToggleSettingRow(
                theme: theme,
                spec: showTagsSpec,
                value: cardSettings.showTags,
                onChanged: (value) => settingsNotifier.setSetting(
                  SettingsKeys.showTagsChip,
                  value,
                ),
              ),
              SpecToggleSettingRow(
                theme: theme,
                spec: showDeadlineSpec,
                value: cardSettings.showDeadline,
                onChanged: (value) => settingsNotifier.setSetting(
                  SettingsKeys.showDeadlineChip,
                  value,
                ),
              ),
              SpecToggleSettingRow(
                theme: theme,
                spec: showRatingsSpec,
                value: cardSettings.showRatings,
                showDividerBelow: false,
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
