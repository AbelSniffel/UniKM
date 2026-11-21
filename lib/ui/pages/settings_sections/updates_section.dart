/// Updates settings section.
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_model.dart';
import '../../../core/services/update_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/password_field.dart';
import 'settings_common.dart';
import 'settings_control_cards.dart';

/// Updates settings section
class const UpdatesSection({
  super.key,
  final String searchQuery = '',
  final bool attachesToAbove = false,
}) extends ConsumerStatefulWidget {
  static const SettingTextSpec includePrereleaseSpec = SettingTextSpec(
    label: 'Pre-releases',
    icon: Icons.science_outlined,
  );
  static const SettingTextSpec autoCheckSpec = SettingTextSpec(
    label: 'Update Checker',
    icon: Icons.update,
  );
  static const SettingTextSpec repositorySpec = SettingTextSpec(
    label: 'Repository',
    description: 'owner/repo (e.g., AbelSniffel/UniKM)',
  );
  static const SettingTextSpec githubTokenSpec = SettingTextSpec(
    label: 'GitHub API Token (optional)',
    description: 'For higher API rate limits',
  );

  static const List<SettingsSearchGroup> searchGroups = [
    SettingsSearchGroup(
      title: 'Update Settings',
      settings: [autoCheckSpec, includePrereleaseSpec],
      extraTexts: [
        'Next check in',
        'Enable',
        'Disable',
        'Update Preferences',
        'beta',
        'Automatic Update Checks',
      ],
    ),
    SettingsSearchGroup(
      title: 'GitHub Repository & API',
      settings: [repositorySpec, githubTokenSpec],
      info: 'A personal access token increases GitHub API rate limits.',
    ),
  ];

  @override
  ConsumerState<UpdatesSection> createState() => _UpdatesSectionState();
}

class _UpdatesSectionState extends ConsumerState<UpdatesSection> {
  final _repoController = TextEditingController();
  final _tokenController = TextEditingController();
  Timer? _countdownTicker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    final updates = ref.read(updatesSettingsProvider);
    _repoController.text = updates.updateRepo;
    _tokenController.text = updates.githubApiToken;
    _countdownTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    _repoController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  String _formatNextUpdateTime(DateTime nextTime) {
    final diff = nextTime.difference(_now);

    if (diff.isNegative) return 'Running now...';

    if (diff.inMinutes < 1) return 'In less than a minute';

    if (diff.inMinutes == 1) return 'In 1 minute';

    if (diff.inMinutes < 60) return 'In ${diff.inMinutes} minutes';

    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    if (minutes == 0) return 'In $hours hour${hours > 1 ? 's' : ''}';

    return 'In $hours hour${hours > 1 ? 's' : ''} $minutes min';
  }

  /// When the next check runs; nothing while checks are off.
  String? _automaticUpdateCheckDescription({
    required bool autoCheckEnabled,
    required DateTime? nextUpdateCheck,
  }) {
    if (!autoCheckEnabled) return null;
    if (nextUpdateCheck == null) return 'Next check is being scheduled';

    final relativeLabel = _formatNextUpdateTime(nextUpdateCheck);
    if (relativeLabel == 'Running now...') return 'Next check is running now';

    return 'Next check ${relativeLabel[0].toLowerCase()}${relativeLabel.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final updates = ref.watch(updatesSettingsProvider);
    final nextUpdateCheck = ref.watch(nextAutoUpdateTimeProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    return SettingsSectionGroups(
      attachesToAbove: widget.attachesToAbove,
      entries: [
        buildSearchableSectionEntry(
          group: UpdatesSection.searchGroups[0],
          searchQuery: widget.searchQuery,
          // The panel's header already says Updates.
          showTitle: false,
          // One per row, as the next check's time makes the first card
          // taller, as far apart as wrapped cards.
          childBuilder: () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              SettingsToggleCard(
                label: UpdatesSection.autoCheckSpec.label,
                icon: UpdatesSection.autoCheckSpec.icon,
                description: _automaticUpdateCheckDescription(
                  autoCheckEnabled: updates.autoCheckEnabled,
                  nextUpdateCheck: nextUpdateCheck,
                ),
                value: updates.autoCheckEnabled,
                onChanged: settingsNotifier.setter(
                  SettingsKeys.autoUpdateCheck,
                ),
              ),
              SettingsToggleCard(
                label: UpdatesSection.includePrereleaseSpec.label,
                icon: UpdatesSection.includePrereleaseSpec.icon,
                value: updates.includePrerelease,
                onChanged: settingsNotifier.setter(
                  SettingsKeys.includePreReleases,
                ),
              ),
            ],
          ),
        ),
        buildSearchableSectionEntry(
          group: UpdatesSection.searchGroups[1],
          titleIcon: Icons.code,
          searchQuery: widget.searchQuery,
          // Labelled inside the box, like the password dialogs' fields.
          childBuilder: () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              TextField(
                controller: _repoController,
                decoration: InputDecoration(
                  labelText: UpdatesSection.repositorySpec.label,
                  hintText: UpdatesSection.repositorySpec.description,
                  hintStyle: TextStyle(color: theme.textHint),
                  border: theme.resolveInputBorder(labelInside: true),
                ),
                onChanged: settingsNotifier.setter(SettingsKeys.updateRepo),
              ),
              PasswordField(
                controller: _tokenController,
                labelText: UpdatesSection.githubTokenSpec.label,
                hintText: UpdatesSection.githubTokenSpec.description,
                onChanged: settingsNotifier.setter(SettingsKeys.githubApiToken),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
