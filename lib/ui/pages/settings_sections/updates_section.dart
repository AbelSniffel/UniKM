/// Updates settings section.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_model.dart';
import '../../../core/services/update_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../../core/constants/app_constants.dart';
import 'settings_common.dart';
import 'settings_control_cards.dart';

/// Updates settings section
class UpdatesSection extends ConsumerStatefulWidget {
  const UpdatesSection({
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

  static const SettingTextSpec includePrereleaseSpec = SettingTextSpec(
    label: 'Include pre-release versions',
    description: 'Get beta updates before stable release',
  );
  static const SettingTextSpec autoCheckSpec = SettingTextSpec(
    label: 'Automatic Update Check',
    description:
        'Control background update checks and view the next scheduled run',
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
      title: 'Update Preferences',
      settings: [autoCheckSpec, includePrereleaseSpec],
      extraTexts: [
        'Next check in',
        'Automatic update check is disabled',
        'Enable',
        'Disable',
      ],
    ),
    SettingsSearchGroup(
      title: 'GitHub Repository & API',
      settings: [repositorySpec, githubTokenSpec],
      extraTexts: ['A personal access token increases GitHub API rate limits.'],
    ),
  ];

  @override
  ConsumerState<UpdatesSection> createState() => _UpdatesSectionState();
}

class _UpdatesSectionState extends ConsumerState<UpdatesSection> {
  final _repoController = TextEditingController();
  final _tokenController = TextEditingController();
  final _tokenInfoKey = GlobalKey<TooltipState>();
  Timer? _countdownTicker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    final updates = ref.read(updatesSettingsProvider);
    _repoController.text = updates.updateRepo;
    _tokenController.text = updates.githubApiToken;
    _countdownTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _now = DateTime.now();
      });
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

    if (diff.isNegative) {
      return 'Running now...';
    }

    if (diff.inMinutes < 1) {
      return 'In less than a minute';
    }

    if (diff.inMinutes == 1) {
      return 'In 1 minute';
    }

    if (diff.inMinutes < 60) {
      return 'In ${diff.inMinutes} minutes';
    }

    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    if (minutes == 0) {
      return 'In $hours hour${hours > 1 ? 's' : ''}';
    }

    return 'In $hours hour${hours > 1 ? 's' : ''} $minutes min';
  }

  String _automaticUpdateCheckDescription({
    required bool autoCheckEnabled,
    required DateTime? nextUpdateCheck,
  }) {
    if (!autoCheckEnabled) {
      return 'Automatic update check is disabled';
    }
    if (nextUpdateCheck == null) {
      return 'Next check is being scheduled';
    }

    final relativeLabel = _formatNextUpdateTime(nextUpdateCheck);
    if (relativeLabel == 'Running now...') {
      return 'Next check is running now';
    }

    return 'Next check ${relativeLabel[0].toLowerCase()}${relativeLabel.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final updates = ref.watch(updatesSettingsProvider);
    final nextUpdateCheck = ref.watch(nextAutoUpdateTimeProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    return SettingsSectionGroups(
      attachesToAbove: widget.attachesToAbove,
      entries: [
        buildSearchableSectionEntry(
          theme: widget.theme,
          group: UpdatesSection.searchGroups[0],
          titleIcon: Icons.download_rounded,
          searchQuery: widget.searchQuery,
          matchesSearch: widget.matchesSearch,
          childBuilder: () => SettingsControlWrap(
            children: [
              SettingsToggleCard(
                theme: widget.theme,
                label: UpdatesSection.autoCheckSpec.label,
                description: _automaticUpdateCheckDescription(
                  autoCheckEnabled: updates.autoCheckEnabled,
                  nextUpdateCheck: nextUpdateCheck,
                ),
                value: updates.autoCheckEnabled,
                onChanged: (value) => settingsNotifier.setSetting(
                  SettingsKeys.autoUpdateCheck,
                  value,
                ),
              ),
              SettingsToggleCard(
                theme: widget.theme,
                label: UpdatesSection.includePrereleaseSpec.label,
                description: UpdatesSection.includePrereleaseSpec.description,
                value: updates.includePrerelease,
                onChanged: (value) => settingsNotifier.setSetting(
                  SettingsKeys.includePreReleases,
                  value,
                ),
              ),
            ],
          ),
        ),
        buildSearchableSectionEntry(
          theme: widget.theme,
          group: UpdatesSection.searchGroups[1],
          titleIcon: Icons.code,
          searchQuery: widget.searchQuery,
          matchesSearch: widget.matchesSearch,
          childBuilder: () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                UpdatesSection.repositorySpec.label,
                style: TextStyle(
                  color: widget.theme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: kElementVSpacing),
              ThemedTextField(
                theme: widget.theme,
                controller: _repoController,
                hintText: UpdatesSection.repositorySpec.description,
                onChanged: (value) {
                  settingsNotifier.setSetting(SettingsKeys.updateRepo, value);
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      UpdatesSection.githubTokenSpec.label,
                      style: TextStyle(
                        color: widget.theme.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Tooltip(
                    key: _tokenInfoKey,
                    message:
                        'A personal access token increases GitHub API rate limits.',
                    child: IconButton(
                      icon: const Icon(Icons.info_outline, size: 26),
                      color: widget.theme.accent,
                      onPressed: () =>
                          _tokenInfoKey.currentState?.ensureTooltipVisible(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: kElementVSpacing),
              ThemedTextField(
                theme: widget.theme,
                controller: _tokenController,
                obscureText: true,
                hintText: UpdatesSection.githubTokenSpec.description,
                onChanged: (value) {
                  settingsNotifier.setSetting(
                    SettingsKeys.githubApiToken,
                    value,
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
