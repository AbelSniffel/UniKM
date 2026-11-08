import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/section_groupbox.dart';
import '../../widgets/settings_card_indicator.dart';
import '../../widgets/toggle_switch.dart';
import 'settings_common.dart';
import 'settings_control_cards.dart';

class SettingsCardStyleSection extends ConsumerWidget {
  const SettingsCardStyleSection({
    super.key,
    required this.theme,
    required this.searchQuery,
    required this.groupPosition,
    required this.isAlternate,
  });

  static const SettingTextSpec indicatorStyleSpec = SettingTextSpec(
    label: 'Indicator Style',
    description: 'Choose the indicator used when interaction cards are enabled',
    icon: Icons.tune,
  );

  final AppThemeData theme;
  final String searchQuery;
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
      groupPosition: groupPosition,
      alternateBackground: isAlternate,
      headerCrossAxisAlignment: CrossAxisAlignment.center,
      // One card whose buttons are the indicators themselves, the chosen one
      // switched on.
      child: SettingsButtonGroupCard<SettingsCardIndicatorStyle>(
        theme: theme,
        label: indicatorStyleSpec.label,
        icon: indicatorStyleSpec.icon,
        description: selected.description,
        value: selected,
        choices: [
          for (final style in SettingsCardIndicatorStyle.values)
            SettingsChoice(style, style.displayName),
        ],
        onChanged: (style) => ref
            .read(settingsProvider.notifier)
            .setSetting(SettingsKeys.settingsCardIndicatorStyle, style),
        buttonBuilder: (choice, on, choose) => switch (choice.value) {
          SettingsCardIndicatorStyle.switchControl => AppToggleSwitch(
            key: ValueKey(choice.value),
            value: on,
            onChanged: choose == null ? null : (_) => choose(),
            theme: theme,
            // The switch alone, without its On/Off word.
            label: '',
          ),
          // The dot only shows; a click anywhere on it picks it.
          SettingsCardIndicatorStyle.miniDot => MouseRegion(
            key: ValueKey(choice.value),
            cursor: choose == null
                ? MouseCursor.defer
                : SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: choose,
              child: SettingsCardMiniDot(
                theme: theme,
                value: on,
                enabled: choose != null,
              ),
            ),
          ),
        },
      ),
    );
  }
}
