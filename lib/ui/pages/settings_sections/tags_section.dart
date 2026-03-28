/// Tags management settings section.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/constants/legacy_default_tag_names.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/color_utils.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/app_tag_chip.dart';
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
      'Create',
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
    title: 'Tag Maintenance',
    settings: [maintenanceInfoSpec],
    extraTexts: ['Remove old default tags (one-time)', 'One-time Cleanup'],
  );

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
  final _newTagController = TextEditingController();

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  Future<void> _createTag() async {
    final name = _newTagController.text.trim();
    if (name.isEmpty) {
      NotificationManager.instance.warning('Please enter a tag name');
      return;
    }

    try {
      final db = ref.read(requireDatabaseProvider);
      final colorHex = colorToHex(widget.theme.primary);
      await db.getOrCreateTag(name, color: colorHex);
      await ref.read(tagsProvider.notifier).refresh();
      // Clear field and show notification immediately — don't wait for
      // encryption, which can be slow and would delay visible UI feedback.
      _newTagController.clear();
      NotificationManager.instance.success('Tag "$name" created');
      await persistEncryptedDbIfNeeded(ref);
    } catch (e) {
      NotificationManager.instance.error('Failed to create tag: $e');
    }
  }

  Future<void> _deleteTag(int tagId, String tagName) async {
    final confirmed = await showConfirmDialog(
      context: context,
      theme: widget.theme,
      title: 'Delete Tag',
      message:
          'Are you sure you want to delete "$tagName"?\n\nThis will remove the tag from all games.',
      confirmLabel: 'Delete',
      confirmIcon: Icons.delete,
      destructive: true,
    );

    if (confirmed) {
      try {
        final db = ref.read(requireDatabaseProvider);
        await db.deleteTag(tagId);
        await ref.read(tagsProvider.notifier).refresh();
        await ref.read(gamesProvider.notifier).refresh();
        await persistEncryptedDbIfNeeded(ref);
        NotificationManager.instance.success('Tag "$tagName" deleted');
      } catch (e) {
        NotificationManager.instance.error('Failed to delete tag: $e');
      }
    }
  }

  Future<void> _deleteAllCustomTags() async {
    final tags = ref.read(tagsProvider);
    final customTags = tags.where((t) => !t.isSteamTag).toList();

    if (customTags.isEmpty) {
      NotificationManager.instance.info('No custom tags to delete');
      return;
    }

    final confirmed = await showConfirmDialog(
      context: context,
      theme: widget.theme,
      title: 'Delete All Custom Tags',
      message:
          'Are you sure you want to delete ${customTags.length} custom tags?\n\nThis will remove them from all games. Steam tags will not be affected.',
      confirmLabel: 'Delete All',
      confirmIcon: Icons.delete_sweep,
      destructive: true,
    );

    if (confirmed) {
      try {
        final db = ref.read(requireDatabaseProvider);
        for (final tag in customTags) {
          await db.deleteTag(tag.id);
        }
        await ref.read(tagsProvider.notifier).refresh();
        await ref.read(gamesProvider.notifier).refresh();
        await persistEncryptedDbIfNeeded(ref);
        NotificationManager.instance.success(
          'Deleted ${customTags.length} custom tags',
        );
      } catch (e) {
        NotificationManager.instance.error('Failed to delete tags: $e');
      }
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
      message:
          'Remove $legacyCustomCount old default tags (non-Steam)?\n\nThey will also be removed from any games.\nThis button disappears after running once.',
      confirmLabel: 'Remove',
      confirmIcon: Icons.delete_forever,
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
      message:
          'Delete unused Steam tags?\n\nUnused custom (user-made) tags will be kept.',
      confirmLabel: 'Clear',
      confirmIcon: Icons.delete_sweep,
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
        !legacyCleanupDone &&
        legacyCustomCount > 0 &&
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
            searchQuery: widget.searchQuery,
            isSearchMatch: isSearching,
            groupPosition: position,
            alternateBackground: isAlternate,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: AppSearchField(
                        theme: widget.theme,
                        controller: _newTagController,
                        hintText: TagsSection.customTagsInputSpec.label,
                        prefixIcon: Icons.label_outline,
                        onChanged: (_) {},
                        onSubmitted: (_) => _createTag(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _createTag,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Create'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
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
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final maxH = constraints.maxHeight.isFinite
                          ? constraints.maxHeight
                          : 300.0;
                      return ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: maxH),
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: customTags
                                .map(
                                  (tag) => AppTagChip(
                                    tag: tag,
                                    theme: widget.theme,
                                    isSelected: true,
                                    onDelete: () => _deleteTag(tag.id, tag.name),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _deleteAllCustomTags,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        icon: const Icon(Icons.delete_sweep, size: 18),
                        label: const Text('Delete All Custom Tags'),
                      ),
                    ],
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
            titleIcon: FontAwesomeIcons.steam,
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
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final maxH = constraints.maxHeight.isFinite
                          ? constraints.maxHeight
                          : 200.0;
                      return ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: maxH),
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: steamTags
                                .map(
                                  (tag) => AppTagChip(
                                    tag: tag,
                                    theme: widget.theme,
                                    isSelected: true,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _clearUnusedNonUserTags,
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        icon: const Icon(Icons.delete_sweep, size: 18),
                        label: const Text('Clear unused Steam tags'),
                      ),
                    ],
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
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.cleaning_services, size: 18),
                  label: const Text('Remove old default tags (one-time)'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
