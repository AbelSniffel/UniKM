/// Notifications settings section
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import 'settings_common.dart';

/// Notifications settings section
class const NotificationsSection({
  super.key,
  final String searchQuery = '',
  final bool attachesToAbove = false,
}) extends ConsumerWidget {
  static const SettingTextSpec deadlineRemindersSpec = SettingTextSpec(
    label: 'Deadlines',
    icon: Icons.notifications_active_outlined,
  );
  static const SettingTextSpec updateNotificationsSpec = SettingTextSpec(
    label: 'Updates',
    icon: Icons.system_update_alt,
  );

  static const SettingsSearchGroup typesSearchGroup = SettingsSearchGroup(
    title: 'Notify Me About',
    settings: [deadlineRemindersSpec, updateNotificationsSpec],
    extraTexts: ['Notification Types', 'reminders', 'expire'],
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsSettingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    return SettingsSectionGroups(
      attachesToAbove: attachesToAbove,
      entries: [
        buildSearchableSectionEntry(
          group: typesSearchGroup,
          titleIcon: Icons.notifications_active,
          searchQuery: searchQuery,
          // The section's own title names it.
          showTitle: false,
          childBuilder: () => buildSpecToggleSettingList(
            theme: context.appTheme,
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
