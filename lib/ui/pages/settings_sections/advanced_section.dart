/// Advanced settings section
library;

import 'package:material_ui/material_ui.dart';
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
class const AdvancedSection({
  super.key,
  final String searchQuery = '',
  final bool attachesToAbove = false,
}) extends ConsumerWidget {
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
    settings: [frameRateSpec, if (kDevTools) devWindowSpec, resetSettingsSpec],
    extraTexts: ['Display', 'FPS', 'defaults'],
  );

  static List<SettingsSearchGroup> get searchGroups => [systemSearchGroup];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.appTheme;
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
          group: systemSearchGroup,
          titleIcon: Icons.settings,
          searchQuery: searchQuery,
          // The section's own title names it.
          showTitle: false,
          childBuilder: () => Column(
            children: [
              SettingsChoiceCard<String>(
                label: frameRateSpec.label,
                icon: frameRateSpec.icon,
                value: currentFrameRate,
                choices: [
                  const SettingsChoice('auto', 'Auto'),
                  for (final fps in const [60, 90, 120, 144, 240])
                    SettingsChoice('$fps', '$fps fps'),
                ],
                onChanged: settingsNotifier.setter(
                  SettingsKeys.frameRatePreference,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                spacing: kElementHSpacing,
                children: [
                  if (kDevTools)
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
