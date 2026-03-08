/// Updates settings section.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import 'settings_common.dart';

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
    label: 'Automatically check for updates',
    description: 'Periodically check for new versions in the background',
  );
  static const SettingTextSpec intervalSpec = SettingTextSpec(
    label: 'Check interval (minutes)',
    description: 'How often to check for updates',
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
      settings: [includePrereleaseSpec, autoCheckSpec, intervalSpec],
    ),
    SettingsSearchGroup(
      title: 'GitHub Repository & API',
      settings: [repositorySpec, githubTokenSpec],
      extraTexts: ['A personal access token increases GitHub API rate limits.'],
    ),
  ];

  static List<String> get sectionSearchTexts => [
    'Update Settings',
    ...searchGroups.expand((group) => group.indexTexts),
  ];

  @override
  ConsumerState<UpdatesSection> createState() => _UpdatesSectionState();
}

class _UpdatesSectionState extends ConsumerState<UpdatesSection> {
  final _repoController = TextEditingController();
  final _tokenController = TextEditingController();
  final _intervalController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final updates = ref.read(updatesSettingsProvider);
    _repoController.text = updates.updateRepo;
    _tokenController.text = updates.githubApiToken;
    _intervalController.text = updates.autoCheckIntervalMinutes.toString();
  }

  @override
  void dispose() {
    _repoController.dispose();
    _tokenController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final updates = ref.watch(updatesSettingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final isSearching = widget.searchQuery.trim().isNotEmpty;

    final showUpdatePreferences = shouldShowSettingsGroup(
      query: widget.searchQuery,
      matchesSearch: widget.matchesSearch,
      group: UpdatesSection.searchGroups[0],
    );

    final showGithubGroup = shouldShowSettingsGroup(
      query: widget.searchQuery,
      matchesSearch: widget.matchesSearch,
      group: UpdatesSection.searchGroups[1],
    );

    if (isSearching && !showUpdatePreferences && !showGithubGroup) {
      return const SizedBox.shrink();
    }

    return SettingsSectionGroups(
      attachesToAbove: widget.attachesToAbove,
      entries: [
        SectionGroupEntry(
          visible: showUpdatePreferences,
          builder: (position, isAlternate) => SearchableSectionGroupBox(
            theme: widget.theme,
            group: UpdatesSection.searchGroups[0],
            titleIcon: Icons.update,
            searchQuery: widget.searchQuery,
            matchesSearch: widget.matchesSearch,
            groupPosition: position,
            isAlternate: isAlternate,
            child: Column(
              children: [
                SpecToggleSettingRow(
                  theme: widget.theme,
                  spec: UpdatesSection.includePrereleaseSpec,
                  value: updates.includePrerelease,
                  showDividerBelow: false,
                  onChanged: (value) => settingsNotifier.setSetting(
                    SettingsKeys.includePreReleases,
                    value,
                  ),
                ),

                const Divider(),

                SpecToggleSettingRow(
                  theme: widget.theme,
                  spec: UpdatesSection.autoCheckSpec,
                  value: updates.autoCheckEnabled,
                  onChanged: (value) => settingsNotifier.setSetting(
                    SettingsKeys.autoUpdateCheck,
                    value,
                  ),
                ),

                SpecSettingRow(
                  theme: widget.theme,
                  spec: UpdatesSection.intervalSpec,
                  child: ThemedTextField(
                    theme: widget.theme,
                    controller: _intervalController,
                    keyboardType: TextInputType.number,
                    width: 100,
                    onChanged: (value) {
                      final intValue = int.tryParse(value);
                      if (intValue != null && intValue > 0) {
                        settingsNotifier.setSetting(
                          SettingsKeys.autoCheckIntervalMinutes,
                          intValue,
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        SectionGroupEntry(
          visible: showGithubGroup,
          builder: (position, isAlternate) => SearchableSectionGroupBox(
            theme: widget.theme,
            group: UpdatesSection.searchGroups[1],
            titleIcon: Icons.code,
            searchQuery: widget.searchQuery,
            matchesSearch: widget.matchesSearch,
            groupPosition: position,
            isAlternate: isAlternate,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  UpdatesSection.repositorySpec.label,
                  style: TextStyle(
                    color: widget.theme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                ThemedTextField(
                  theme: widget.theme,
                  controller: _repoController,
                  hintText: UpdatesSection.repositorySpec.description,
                  onChanged: (value) {
                    settingsNotifier.setSetting(SettingsKeys.updateRepo, value);
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  UpdatesSection.githubTokenSpec.label,
                  style: TextStyle(
                    color: widget.theme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
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
                const SizedBox(height: 8),
                Text(
                  'A personal access token increases GitHub API rate limits.',
                  style: TextStyle(color: widget.theme.textHint, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
