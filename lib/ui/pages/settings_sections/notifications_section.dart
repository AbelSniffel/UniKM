/// Notifications settings section
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/notification_system.dart';
import '../../widgets/toggle_switch.dart';
import 'settings_common.dart';

/// Notifications settings section
class NotificationsSection extends ConsumerWidget {
  const NotificationsSection({
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

  static const SettingTextSpec enableNotificationsSpec = SettingTextSpec(
    label: 'Enable notifications',
    description: 'Show toast notifications for events',
  );
  static const SettingTextSpec deadlineRemindersSpec = SettingTextSpec(
    label: 'Deadline reminders',
    description: 'Notify when keys are about to expire',
  );
  static const SettingTextSpec updateNotificationsSpec = SettingTextSpec(
    label: 'Update notifications',
    description: 'Notify when app updates are available',
  );

  static const SettingsSearchGroup displaySearchGroup = SettingsSearchGroup(
    title: 'Notification Display',
    settings: [enableNotificationsSpec],
  );

  static const SettingsSearchGroup typesSearchGroup = SettingsSearchGroup(
    title: 'Notification Types',
    settings: [deadlineRemindersSpec, updateNotificationsSpec],
  );

  static const SettingsSearchGroup testSearchGroup = SettingsSearchGroup(
    title: 'Test Notification',
    extraTexts: ['This is a test notification!'],
  );

  static List<String> get sectionSearchTexts => [
    'Notification Settings',
    ...displaySearchGroup.indexTexts,
    ...typesSearchGroup.indexTexts,
    ...testSearchGroup.indexTexts,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsSettingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final isSearching = searchQuery.trim().isNotEmpty;

    final showDisplay = shouldShowSettingsGroup(
      query: searchQuery,
      matchesSearch: matchesSearch,
      group: displaySearchGroup,
    );
    final showTypes = shouldShowSettingsGroup(
      query: searchQuery,
      matchesSearch: matchesSearch,
      group: typesSearchGroup,
    );
    final showTest = shouldShowSettingsGroup(
      query: searchQuery,
      matchesSearch: matchesSearch,
      group: testSearchGroup,
    );

    if (isSearching && !showDisplay && !showTypes && !showTest) {
      return const SizedBox.shrink();
    }

    return SettingsSectionGroups(
      attachesToAbove: attachesToAbove,
      entries: [
        SectionGroupEntry(
          visible: showDisplay,
          builder: (position, isAlternate) => SearchableSectionGroupBox(
            theme: theme,
            group: displaySearchGroup,
            titleIcon: Icons.notifications_active,
            searchQuery: searchQuery,
            matchesSearch: matchesSearch,
            groupPosition: position,
            isAlternate: isAlternate,
            extraMatch: showTest ? () => true : null,
            child: Column(
              children: [
                // Show the enable toggle and the Test Notification button on the same row
                SettingRow(
                  theme: theme,
                  label: enableNotificationsSpec.label,
                  description: enableNotificationsSpec.description,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showTest) ...[
                        OutlinedButton.icon(
                          onPressed: notifications.enabled
                              ? () => NotificationManager.instance.info(
                                  'This is a test notification!',
                                )
                              : null,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Test Notification'),
                        ),
                      ],
                      AppToggleSwitch(
                        value: notifications.enabled,
                        onChanged: (value) => settingsNotifier.setSetting(
                          SettingsKeys.notificationsEnabled,
                          value,
                        ),
                        theme: theme,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SectionGroupEntry(
          visible: showTypes,
          builder: (position, isAlternate) => SearchableSectionGroupBox(
            theme: theme,
            group: typesSearchGroup,
            titleIcon: Icons.tune,
            searchQuery: searchQuery,
            matchesSearch: matchesSearch,
            groupPosition: position,
            isAlternate: isAlternate,
            child: Column(
              children: [
                SpecToggleSettingRow(
                  theme: theme,
                  spec: deadlineRemindersSpec,
                  value: notifications.deadlineReminders,
                  onChanged: (value) => settingsNotifier.setSetting(
                    SettingsKeys.deadlineReminders,
                    value,
                  ),
                ),
                SpecToggleSettingRow(
                  theme: theme,
                  spec: updateNotificationsSpec,
                  value: notifications.updateNotifications,
                  showDividerBelow: false,
                  onChanged: (value) => settingsNotifier.setSetting(
                    SettingsKeys.updateNotifications,
                    value,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
