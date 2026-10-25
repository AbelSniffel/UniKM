/// Notifications settings section
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
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

  static const SettingTextSpec deadlineRemindersSpec = SettingTextSpec(
    label: 'Deadline reminders',
    description: 'Notify when keys are about to expire',
  );
  static const SettingTextSpec updateNotificationsSpec = SettingTextSpec(
    label: 'Update notifications',
    description: 'Notify when app updates are available',
  );

  static const SettingsSearchGroup typesSearchGroup = SettingsSearchGroup(
    title: 'Notification Types',
    settings: [deadlineRemindersSpec, updateNotificationsSpec],
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsSettingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    return SettingsSectionGroups(
      attachesToAbove: attachesToAbove,
      entries: [
        buildSearchableSectionEntry(
          theme: theme,
          group: typesSearchGroup,
          titleIcon: Icons.notifications_active,
          searchQuery: searchQuery,
          matchesSearch: matchesSearch,
          childBuilder: () => buildSpecToggleSettingList(
            theme: theme,
            entries: [
              (
                spec: deadlineRemindersSpec,
                value: notifications.deadlineReminders,
                onChanged: settingsNotifier.setter(
                  SettingsKeys.deadlineReminders,
                ),
              ),
              (
                spec: updateNotificationsSpec,
                value: notifications.updateNotifications,
                onChanged: settingsNotifier.setter(
                  SettingsKeys.updateNotifications,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
