import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/section_groupbox.dart';
import 'settings_control_cards.dart';

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
      child: SettingsControlWrap(
        children: [
          for (final style in SettingsCardIndicatorStyle.values)
            Tooltip(
              key: ValueKey(style),
              message: style.description,
              child: SettingsToggleCard(
                theme: theme,
                label: style.displayName,
                indicatorStyle: style,
                value: selected == style,
                onChanged: (_) => ref
                    .read(settingsProvider.notifier)
                    .setSetting(SettingsKeys.settingsCardIndicatorStyle, style),
              ),
            ),
        ],
      ),
    );
  }
}
