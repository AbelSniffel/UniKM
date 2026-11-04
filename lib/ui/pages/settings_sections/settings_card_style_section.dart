import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/section_groupbox.dart';
import '../../widgets/settings_card_indicator.dart';
import '../../widgets/tinted_tiles.dart';
import '../../widgets/toggle_switch.dart';

class SettingsCardStyleSection extends ConsumerWidget {
  const SettingsCardStyleSection({
    super.key,
    required this.theme,
    required this.searchQuery,
    required this.isSearchMatch,
    required this.groupPosition,
    required this.isAlternate,
  });

  final AppThemeData theme;
  final String searchQuery;
  final bool isSearchMatch;
  final SectionGroupPosition groupPosition;
  final bool isAlternate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(settingsCardIndicatorStyleProvider);
    return SectionGroupBox(
      title: 'Settings Card Style',
      titleIcon: Icons.tune,
      theme: theme,
      searchQuery: searchQuery,
      isSearchMatch: isSearchMatch,
      groupPosition: groupPosition,
      alternateBackground: isAlternate,
      headerCrossAxisAlignment: CrossAxisAlignment.center,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          for (final style in SettingsCardIndicatorStyle.values)
            TintedOptionTile(
              key: ValueKey(style),
              theme: theme,
              // The indicator itself, switched on while chosen.
              indicator: switch (style) {
                SettingsCardIndicatorStyle.switchControl => AppToggleSwitch(
                  value: selected == style,
                  onChanged: (_) {},
                  theme: theme,
                  label: '',
                ),
                SettingsCardIndicatorStyle.miniDot => SettingsCardMiniDot(
                  theme: theme,
                  value: selected == style,
                  enabled: true,
                ),
              },
              title: style.displayName,
              subtitle: style.description,
              selected: selected == style,
              onTap: () => ref
                  .read(settingsProvider.notifier)
                  .setSetting(SettingsKeys.settingsCardIndicatorStyle, style),
            ),
        ],
      ),
    );
  }
}
