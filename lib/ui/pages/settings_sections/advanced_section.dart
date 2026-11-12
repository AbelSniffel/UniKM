/// Advanced settings section
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/notification_system.dart';
import '../../widgets/dialog_helpers.dart';
import '../../widgets/dev_window.dart';
import 'settings_common.dart';
import 'settings_control_cards.dart';

/// Advanced settings section
class AdvancedSection extends ConsumerWidget {
  const AdvancedSection({
    super.key,
    required this.theme,
    this.searchQuery = '',
    this.attachesToAbove = false,
  });

  final AppThemeData theme;
  final String searchQuery;
  final bool attachesToAbove;

  static const SettingTextSpec frameRateSpec = SettingTextSpec(
    label: 'Frame Rate',
    icon: Icons.speed,
  );
  static const SettingTextSpec devWindowSpec = SettingTextSpec(
    label: 'Developer Window',
    description: 'Shortcut: Ctrl+Alt+D',
  );
  static const SettingTextSpec resetSettingsSpec = SettingTextSpec(
    label: 'Reset settings',
  );
  static const SettingsSearchGroup systemSearchGroup = SettingsSearchGroup(
    title: 'System',
    settings: [frameRateSpec, devWindowSpec, resetSettingsSpec],
    extraTexts: ['Display', 'FPS', 'defaults'],
  );

  static List<SettingsSearchGroup> get searchGroups => [systemSearchGroup];

  static const _frameRateOptions = <MapEntry<String, String>>[
    MapEntry('auto', 'Auto'),
    MapEntry('60', '60 fps'),
    MapEntry('90', '90 fps'),
    MapEntry('120', '120 fps'),
    MapEntry('144', '144 fps'),
    MapEntry('240', '240 fps'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final currentFrameRate = ref.watch(
      settingsProvider.select(
        (s) => s[SettingsKeys.frameRatePreference] as String? ?? 'auto',
      ),
    );

    return SettingsSectionGroups(
      attachesToAbove: attachesToAbove,
      entries: [
        buildSearchableSectionEntry(
          theme: theme,
          group: systemSearchGroup,
          titleIcon: Icons.settings,
          searchQuery: searchQuery,
          childBuilder: () => Column(
            children: [
              SettingsChoiceCard<String>(
                theme: theme,
                label: frameRateSpec.label,
                icon: frameRateSpec.icon,
                value: currentFrameRate,
                choices: [
                  for (final option in _frameRateOptions)
                    SettingsChoice(option.key, option.value),
                ],
                onChanged: settingsNotifier.setter(
                  SettingsKeys.frameRatePreference,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                spacing: kElementHSpacing,
                children: [
                  Expanded(
                    child: Tooltip(
                      message: devWindowSpec.description,
                      child: ElevatedButton(
                        onPressed: () => DevWindowOverlay.toggle(context),
                        child: const Text('Open Dev Window'),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ElevatedButton(
                      style: themedFilledButtonStyle(theme, destructive: true),
                      onPressed: () async {
                        final confirmed = await showConfirmDialog(
                          context: context,
                          theme: theme,
                          title: 'Reset Settings?',
                          titleIcon: Icons.warning_amber_rounded,
                          message:
                              'This will reset all settings, library filters, and sorting to their default values. '
                              'Your database choice, games, and data will be kept.',
                          confirmLabel: 'Reset',
                          destructive: true,
                        );
                        if (!confirmed || !context.mounted) return;
                        final gamesNotifier = ref.read(gamesProvider.notifier);
                        await settingsNotifier.resetToDefaults();
                        gamesNotifier.clearAllFilters();
                        await gamesNotifier.setSortMode(
                          DefaultSettings.gameSortMode,
                        );
                        NotificationManager.instance.success(
                          'Settings reset to defaults',
                        );
                      },
                      child: const Text('Reset Settings'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
