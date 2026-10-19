/// Tags management settings section.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/constants/legacy_default_tag_names.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../dialogs/add_tags_dialog.dart';
import '../../dialogs/custom_tag_dialogs.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/tag_list.dart';
import '../../widgets/dialog_helpers.dart';
import '../../widgets/notification_system.dart';
import '../../widgets/section_groupbox.dart';
import 'settings_common.dart';

/// Tags management section
class TagsSection extends ConsumerStatefulWidget {
  const TagsSection({
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

  static const SettingTextSpec customTagsInputSpec = SettingTextSpec(
    label: 'Enter tag name...',
  );
  static const SettingTextSpec steamTagsInfoSpec = SettingTextSpec(
    label: 'No Steam tags imported yet',
    description:
        'Steam tags are added automatically when you look up games via the Steam API.',
  );
  static const SettingTextSpec maintenanceInfoSpec = SettingTextSpec(
    label: 'Old default tags found in this database.',
  );

  static const SettingsSearchGroup customTagsSearchGroup = SettingsSearchGroup(
    title: 'Custom Tags',
    settings: [customTagsInputSpec],
    extraTexts: [
      'Add Tag',
      'Delete All Custom Tags',
      'No custom tags created yet',
    ],
  );

  static const SettingsSearchGroup steamTagsSearchGroup = SettingsSearchGroup(
    title: 'Steam Tags',
    settings: [steamTagsInfoSpec],
    extraTexts: ['Clear unused Steam tags'],
  );

  static const SettingsSearchGroup maintenanceSearchGroup = SettingsSearchGroup(
    title: 'Tag Cleanup',
    settings: [maintenanceInfoSpec],
    extraTexts: ['Remove old default tags (one-time)', 'One-time Cleanup'],
  );

  static bool isMaintenanceAvailable({
    required bool cleanupDone,
    required Iterable<String> customTagNames,
  }) => !cleanupDone && customTagNames.any(kLegacyDefaultTagNames.contains);

  static List<String> get sectionSearchTexts => [
    'Tag Management',
    ...customTagsSearchGroup.indexTexts,
    ...steamTagsSearchGroup.indexTexts,
    ...maintenanceSearchGroup.indexTexts,
  ];

  @override
  ConsumerState<TagsSection> createState() => _TagsSectionState();
}

class _TagsSectionState extends ConsumerState<TagsSection> {
  Future<void> _showAddTagsDialog() => showAppDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AddTagsDialog(theme: widget.theme),
  );

  Future<void> _deleteTag(int tagId, String tagName) async {
    try {
      final deleted = await deleteTagWithConfirmation(
        context: context,
        theme: widget.theme,
        tagId: tagId,
        tagName: tagName,
      );
      if (deleted != null) {
        NotificationManager.instance.success('Tag "$tagName" deleted');
      }
    } catch (e) {
      NotificationManager.instance.error('Failed to delete tag: $e');
    }
  }

  Future<void> _deleteAllCustomTags() async {
    try {
      final deleted = await deleteAllCustomTagsWithConfirmation(
        context: context,
        theme: widget.theme,
      );
      if (deleted != null) {
        NotificationManager.instance.success('Deleted $deleted custom tags');
      }
    } catch (e) {
      NotificationManager.instance.error('Failed to delete tags: $e');
    }
  }

  Future<void> _cleanupLegacyDefaultTagsOnce(int legacyCustomCount) async {
    if (legacyCustomCount <= 0) {
      NotificationManager.instance.info('No legacy default tags found');
      return;
    }

    final confirmed = await showConfirmDialog(
      context: context,
      theme: widget.theme,
      title: 'One-time Cleanup',
      titleIcon: Icons.delete_forever,
      message:
          'Remove $legacyCustomCount old default tags (non-Steam)?\n\nThey will also be removed from any games.\nThis button disappears after running once.',
      confirmLabel: 'Remove',
      destructive: true,
    );

    if (!confirmed) return;

    try {
      final deletedCount = await ref
          .read(tagsProvider.notifier)
          .deleteLegacyDefaultCustomTags();
      await ref.read(gamesProvider.notifier).refresh();
      await ref
          .read(settingsProvider.notifier)
          .set(SettingsKeys.legacyDefaultTagsCleanupDone, true);

      if (deletedCount > 0) {
        NotificationManager.instance.success(
          'Removed $deletedCount legacy default tags',
        );
      } else {
        NotificationManager.instance.info('Nothing to remove');
      }
    } catch (e) {
      NotificationManager.instance.error('Cleanup failed: $e');
    }
  }

  Future<void> _clearUnusedNonUserTags() async {
    final confirmed = await showConfirmDialog(
      context: context,
      theme: widget.theme,
      title: 'Clear Unused Tags',
      titleIcon: Icons.delete_forever,
      message:
          'Delete Steam and old default tags not used by any game? Other custom tags stay.',
      confirmLabel: 'Delete',
      destructive: true,
    );

    if (!confirmed) return;

    try {
      final deletedCount = await ref
          .read(tagsProvider.notifier)
          .deleteUnusedNonUserTags();
      if (deletedCount > 0) {
        NotificationManager.instance.success(
          'Deleted $deletedCount unused tags',
        );
      } else {
        NotificationManager.instance.info('No unused tags to delete');
      }
    } catch (e) {
      NotificationManager.instance.error('Failed to clear unused tags: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(tagsProvider);
    final customTags = tags.where((t) => !t.isSteamTag).toList();
    final steamTags = tags.where((t) => t.isSteamTag).toList();
    final isSearching = widget.searchQuery.trim().isNotEmpty;

    final legacyCleanupDone = ref.watch(legacyDefaultTagsCleanupDoneProvider);

    final legacyCustomCount = customTags
        .where((t) => kLegacyDefaultTagNames.contains(t.name))
        .length;

    final showCustomTags = matchesSettingsSearchGroup(
      query: widget.searchQuery,
      matchesSearch: widget.matchesSearch,
      group: TagsSection.customTagsSearchGroup,
    );

    final showSteamTags = matchesSettingsSearchGroup(
      query: widget.searchQuery,
      matchesSearch: widget.matchesSearch,
      group: TagsSection.steamTagsSearchGroup,
    );

    final showTagMaintenance =
        TagsSection.isMaintenanceAvailable(
          cleanupDone: legacyCleanupDone,
          customTagNames: customTags.map((tag) => tag.name),
        ) &&
        matchesSettingsSearchGroup(
          query: widget.searchQuery,
          matchesSearch: widget.matchesSearch,
          group: TagsSection.maintenanceSearchGroup,
        );

    if (isSearching &&
        !showCustomTags &&
        !showSteamTags &&
        !showTagMaintenance) {
      return const SizedBox.shrink();
    }

    return SettingsSectionGroups(
      attachesToAbove: widget.attachesToAbove,
      entries: [
        // Custom tags section
        SectionGroupEntry(
          visible: showCustomTags,
          builder: (position, isAlternate) => SectionGroupBox(
            title:
                '${TagsSection.customTagsSearchGroup.title} (${customTags.length})',
            theme: widget.theme,
            titleIcon: Icons.label,
            titleLocation: SectionTitleLocation.top,
            headerCrossAxisAlignment: CrossAxisAlignment.center,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: kElementHSpacing,
              children: [
                IconButton(
                  tooltip: 'Add Tag',
                  onPressed: _showAddTagsDialog,
                  icon: const Icon(Icons.add, size: 26),
                  color: widget.theme.accent,
                ),
                if (customTags.isNotEmpty)
                  IconButton(
                    tooltip: 'Delete All Custom Tags',
                    onPressed: _deleteAllCustomTags,
                    icon: const Icon(Icons.delete, size: 26),
                    color: widget.theme.error,
                  ),
              ],
            ),
            searchQuery: widget.searchQuery,
            isSearchMatch: isSearching,
            groupPosition: position,
            alternateBackground: isAlternate,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (customTags.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'No custom tags created yet',
                      style: TextStyle(color: widget.theme.textHint),
                      textAlign: TextAlign.center,
                    ),
                  )
                else ...[
                  TagList(
                    tags: customTags,
                    theme: widget.theme,
                    allSelected: true,
                    onTagToggled: (tagId) {
                      final tag = customTags.firstWhere((t) => t.id == tagId);
                      _deleteTag(tag.id, tag.name);
                    },
                    maxHeight: 300,
                  ),
                ],
              ],
            ),
          ),
        ),
        // Steam tags section
        SectionGroupEntry(
          visible: showSteamTags,
          builder: (position, isAlternate) => SectionGroupBox(
            title:
                '${TagsSection.steamTagsSearchGroup.title} (${steamTags.length})',
            theme: widget.theme,
            titleIcon: FontAwesomeIcons.steam.data,
            titleLocation: SectionTitleLocation.top,
            headerCrossAxisAlignment: CrossAxisAlignment.center,
            trailing: steamTags.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear unused Steam tags',
                    onPressed: _clearUnusedNonUserTags,
                    icon: const Icon(Icons.delete, size: 26),
                    color: widget.theme.error,
                  ),
            searchQuery: widget.searchQuery,
            isSearchMatch: isSearching,
            groupPosition: position,
            alternateBackground: isAlternate,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (steamTags.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '${TagsSection.steamTagsInfoSpec.label}\n\n${TagsSection.steamTagsInfoSpec.description}',
                      style: TextStyle(color: widget.theme.textHint),
                      textAlign: TextAlign.center,
                    ),
                  )
                else ...[
                  TagList(
                    tags: steamTags,
                    theme: widget.theme,
                    allSelected: true,
                    maxHeight: 200,
                  ),
                ],
              ],
            ),
          ),
        ),
        SectionGroupEntry(
          visible: showTagMaintenance,
          builder: (position, isAlternate) => SectionGroupBox(
            title: TagsSection.maintenanceSearchGroup.title,
            titleIcon: Icons.cleaning_services,
            theme: widget.theme,
            searchQuery: widget.searchQuery,
            isSearchMatch: isSearching,
            groupPosition: position,
            alternateBackground: isAlternate,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  TagsSection.maintenanceInfoSpec.label,
                  style: TextStyle(
                    color: widget.theme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () =>
                      _cleanupLegacyDefaultTagsOnce(legacyCustomCount),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.theme.secondary,
                    foregroundColor: widget.theme.primaryButtonText,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.delete_sweep, size: 20),
                  label: const Text('Remove legacy tags'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
