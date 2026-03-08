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

  static const SettingTextSpec fpsCounterSpec = SettingTextSpec(
    label: 'Show FPS counter in title bar',
    description: 'Display a live FPS value left of the window controls',
  );
  static const SettingTextSpec devWindowSpec = SettingTextSpec(
    label: 'Developer Window',
    description: 'Open a floating window with developer tools (Ctrl+Alt+D)',
  );
  static const SettingTextSpec resetSettingsSpec = SettingTextSpec(
    label: 'Reset settings',
    description: 'Restore all settings to defaults',
  );

  static const SettingsSearchGroup systemSearchGroup = SettingsSearchGroup(
    title: 'System',
    settings: [fpsCounterSpec, devWindowSpec, resetSettingsSpec],
  );

  static List<String> get sectionSearchTexts => [
    'Advanced Settings',
    ...systemSearchGroup.indexTexts,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showFpsCounter = ref.watch(
      settingsProvider.select(
        (s) =>
            (s[SettingsKeys.showFpsCounter] as bool?) ??
            DefaultSettings.showFpsCounter,
      ),
    );
    final settingsNotifier = ref.read(settingsProvider.notifier);

    final isSearching = searchQuery.trim().isNotEmpty;
    final showSystem = shouldShowSettingsGroup(
      query: searchQuery,
      matchesSearch: matchesSearch,
      group: systemSearchGroup,
    );

    if (isSearching && !showSystem) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSystem)
          SearchableSectionGroupBox(
            theme: theme,
            group: systemSearchGroup,
            titleIcon: Icons.settings,
            searchQuery: searchQuery,
            matchesSearch: matchesSearch,
            attachesToAbove: attachesToAbove,
            child: Column(
              children: [
                SpecToggleSettingRow(
                  theme: theme,
                  spec: fpsCounterSpec,
                  value: showFpsCounter,
                  showDividerBelow: true,
                  onChanged: (value) => settingsNotifier.setSetting(
                    SettingsKeys.showFpsCounter,
                    value,
                  ),
                ),

                SpecSettingRow(
                  theme: theme,
                  spec: devWindowSpec,
                  child: OutlinedButton(
                    onPressed: () {
                      DevWindowOverlay.toggle(context);
                    },
                    child: const Text('Open'),
                  ),
                ),

                SpecSettingRow(
                  theme: theme,
                  spec: resetSettingsSpec,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    onPressed: () async {
                      final confirmed = await showConfirmDialog(
                        context: context,
                        theme: theme,
                        title: 'Reset Settings?',
                        message:
                            'This will reset all settings to their default values. '
                            'Your games and data will not be affected.',
                        confirmLabel: 'Reset',
                        destructive: true,
                      );
                      if (confirmed) {
                        await settingsNotifier.resetToDefaults();
                        NotificationManager.instance.success(
                          'Settings reset to defaults',
                        );
                      }
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
