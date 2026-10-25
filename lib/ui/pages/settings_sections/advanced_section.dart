/// Advanced settings section
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    required this.matchesSearch,
    this.attachesToAbove = false,
  });

  final AppThemeData theme;
  final String searchQuery;
  final bool Function(String) matchesSearch;
  final bool attachesToAbove;

  static const SettingTextSpec frameRateSpec = SettingTextSpec(
    label: 'Frame Rate',
    description:
        'Target frame rate for rendering. Auto uses the display default. '
        'Higher values require display and compositor support.',
  );
  static const SettingTextSpec devWindowSpec = SettingTextSpec(
    label: 'Developer Window',
    description:
        'Open a floating window with developer tools and FPS controls (Ctrl+Alt+D)',
  );
  static const SettingTextSpec resetSettingsSpec = SettingTextSpec(
    label: 'Reset settings',
    description:
        'Restore all settings, library filters, and sorting to defaults',
  );
  // Reserved for future experimental settings; hidden from UI and search.
  static const showExperimentalSettings = false;

  static const SettingTextSpec interactionCardsSpec = SettingTextSpec(
    label: 'Interaction cards',
    description:
        'Use compact interactive cards instead of full-width settings rows',
  );

  static const SettingsSearchGroup displaySearchGroup = SettingsSearchGroup(
    title: 'Display',
    settings: [frameRateSpec],
  );

  static const SettingsSearchGroup systemSearchGroup = SettingsSearchGroup(
    title: 'System',
    settings: [devWindowSpec, resetSettingsSpec],
  );
  static const SettingsSearchGroup experimentalSearchGroup =
      SettingsSearchGroup(
        title: 'Experimental',
        settings: [interactionCardsSpec],
        extraTexts: ['Legacy layout', 'Card style'],
      );

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
        if (showExperimentalSettings)
          buildSearchableSectionEntry(
            theme: theme,
            group: experimentalSearchGroup,
            titleIcon: Icons.science_outlined,
            searchQuery: searchQuery,
            matchesSearch: matchesSearch,
            childBuilder: () => SettingsControlWrap(
              children: [
                SettingsToggleCard(
                  theme: theme,
                  label: interactionCardsSpec.label,
                  description: interactionCardsSpec.description,
                  value: ref.watch(experimentalInteractionCardsProvider),
                  onChanged: settingsNotifier.setter(
                    SettingsKeys.experimentalInteractionCards,
                  ),
                ),
              ],
            ),
          ),
        buildSearchableSectionEntry(
          theme: theme,
          group: displaySearchGroup,
          titleIcon: Icons.speed,
          searchQuery: searchQuery,
          matchesSearch: matchesSearch,
          childBuilder: () => SettingsControlWrap(
            children: [
              SettingsChoiceCard<String>(
                theme: theme,
                label: frameRateSpec.label,
                description: frameRateSpec.description,
                value: currentFrameRate,
                choices: [
                  for (final option in _frameRateOptions)
                    SettingsChoice(option.key, option.value),
                ],
                onChanged: settingsNotifier.setter(
                  SettingsKeys.frameRatePreference,
                ),
              ),
            ],
          ),
        ),
        buildSearchableSectionEntry(
          theme: theme,
          group: systemSearchGroup,
          titleIcon: Icons.settings,
          searchQuery: searchQuery,
          matchesSearch: matchesSearch,
          childBuilder: () => Column(
            children: [
              SpecSettingRow(
                theme: theme,
                spec: devWindowSpec,
                child: OutlinedButton(
                  onPressed: () => DevWindowOverlay.toggle(context),
                  child: const Text('Open'),
                ),
              ),

              SpecSettingRow(
                theme: theme,
                spec: resetSettingsSpec,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.secondary,
                  ),
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
                  child: const Text('Reset'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
