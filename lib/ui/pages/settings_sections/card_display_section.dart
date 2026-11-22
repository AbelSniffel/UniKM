/// Card Visual settings section
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import 'settings_common.dart';

/// Card Visual settings section
class const CardDisplaySection({
  super.key,
  final String searchQuery = '',
  final bool attachesToAbove = false,
}) extends ConsumerWidget {
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
  static const SettingsSearchGroup chipsSearchGroup = SettingsSearchGroup(
    title: 'Card Chips',
    settings: [
      showPlatformSpec,
      showTagsSpec,
      showDeadlineSpec,
      showRatingsSpec,
    ],
    extraTexts: ['Information Chips', 'card', 'display', 'review'],
  );

  static const SettingsSearchGroup displayRulesSearchGroup =
      SettingsSearchGroup(
        title: 'Hide Chips',
        settings: [showTagsOnHoverOnlySpec, showPlatformOnHoverOnlySpec],
        extraTexts: ['Display Rules', 'hover'],
        info: 'Hovering a card shows its hidden chips.',
      );

  // List view density lives in the navigation panel's More menu.
  static const searchGroups = [chipsSearchGroup, displayRulesSearchGroup];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.appTheme;
    final cardSettings = ref.watch(gameCardSettingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    return SettingsSectionGroups(
      attachesToAbove: attachesToAbove,
      entries: [
        buildSearchableSectionEntry(
          group: chipsSearchGroup,
          titleIcon: Icons.style_outlined,
          searchQuery: searchQuery,
          // The section's own title names it.
          showTitle: false,
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
