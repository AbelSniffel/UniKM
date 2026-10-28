/// Tags management settings section.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/constants/legacy_default_tag_names.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/game.dart';
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

  // Confirms a destructive tag cleanup, then reports how many tags went.
  Future<void> _confirmCleanup({
    required String title,
    required String message,
    required String confirmLabel,
    required Future<int> Function() delete,
    required String Function(int count) removed,
    required String nothingRemoved,
    required String failed,
  }) async {
    final confirmed = await showConfirmDialog(
      context: context,
      theme: widget.theme,
      title: title,
      titleIcon: Icons.delete_forever,
      message: message,
      confirmLabel: confirmLabel,
      destructive: true,
    );
    if (!confirmed) return;

    try {
      final deletedCount = await delete();
      if (deletedCount > 0) {
        NotificationManager.instance.success(removed(deletedCount));
      } else {
        NotificationManager.instance.info(nothingRemoved);
      }
    } catch (e) {
      NotificationManager.instance.error('$failed: $e');
    }
  }

  Future<void> _cleanupLegacyDefaultTagsOnce(int legacyCustomCount) async {
    if (legacyCustomCount <= 0) {
      NotificationManager.instance.info('No legacy default tags found');
      return;
    }
    await _confirmCleanup(
      title: 'One-time Cleanup',
      message:
          'Remove $legacyCustomCount old default tags (non-Steam)?\n\nThey will also be removed from any games.\nThis button disappears after running once.',
      confirmLabel: 'Remove',
      delete: () async {
        final deletedCount = await ref
            .read(tagsProvider.notifier)
            .deleteLegacyDefaultCustomTags();
        await ref.read(gamesProvider.notifier).refresh();
        await ref
            .read(settingsProvider.notifier)
            .set(SettingsKeys.legacyDefaultTagsCleanupDone, true);
        return deletedCount;
      },
      removed: (count) => 'Removed $count legacy default tags',
      nothingRemoved: 'Nothing to remove',
      failed: 'Cleanup failed',
    );
  }

  Future<void> _clearUnusedNonUserTags() => _confirmCleanup(
    title: 'Clear Unused Tags',
    message:
        'Delete Steam and old default tags not used by any game? Other custom tags stay.',
    confirmLabel: 'Delete',
    delete: ref.read(tagsProvider.notifier).deleteUnusedNonUserTags,
    removed: (count) => 'Deleted $count unused tags',
    nothingRemoved: 'No unused tags to delete',
    failed: 'Failed to clear unused tags',
  );

  IconButton _iconButton(
    String tooltip,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 26),
    color: color,
  );

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final tags = ref.watch(tagsProvider);
    final customTags = tags.where((t) => !t.isSteamTag).toList();
    final steamTags = tags.where((t) => t.isSteamTag).toList();
    final isSearching = widget.searchQuery.trim().isNotEmpty;
    final legacyCleanupDone = ref.watch(legacyDefaultTagsCleanupDoneProvider);
    final legacyCustomCount = customTags
        .where((t) => kLegacyDefaultTagNames.contains(t.name))
        .length;
    bool matches(SettingsSearchGroup group) => matchesSettingsSearchGroup(
      matchesSearch: widget.matchesSearch,
      group: group,
    );

    // A counted tag list, or a hint while there are none.
    SectionGroupEntry tagGroup(
      SettingsSearchGroup group,
      IconData icon,
      List<Tag> groupTags, {
      required Widget? trailing,
      required String emptyText,
      required double maxHeight,
      ValueChanged<int>? onTagToggled,
    }) => SectionGroupEntry(
      visible: matches(group),
      builder: (position, isAlternate) => SectionGroupBox(
        title: '${group.title} (${groupTags.length})',
        theme: theme,
        titleIcon: icon,
        titleLocation: SectionTitleLocation.top,
        headerCrossAxisAlignment: CrossAxisAlignment.center,
        trailing: trailing,
        searchQuery: widget.searchQuery,
        isSearchMatch: isSearching,
        groupPosition: position,
        alternateBackground: isAlternate,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (groupTags.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  emptyText,
                  style: TextStyle(color: theme.textHint),
                  textAlign: TextAlign.center,
                ),
              )
            else
              TagList(
                tags: groupTags,
                theme: theme,
                allSelected: true,
                deleteOnTap: onTagToggled != null,
                onTagToggled: onTagToggled,
                maxHeight: maxHeight,
              ),
          ],
        ),
      ),
    );

    return SettingsSectionGroups(
      attachesToAbove: widget.attachesToAbove,
      entries: [
        tagGroup(
          TagsSection.customTagsSearchGroup,
          Icons.label,
          customTags,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: kElementHSpacing,
            children: [
              _iconButton(
                'Add Tag',
                Icons.add,
                theme.accent,
                _showAddTagsDialog,
              ),
              if (customTags.isNotEmpty)
                _iconButton(
                  'Delete All Custom Tags',
                  Icons.delete,
                  theme.error,
                  _deleteAllCustomTags,
                ),
            ],
          ),
          emptyText: 'No custom tags created yet',
          maxHeight: 300,
          onTagToggled: (tagId) {
            final tag = customTags.firstWhere((t) => t.id == tagId);
            _deleteTag(tag.id, tag.name);
          },
        ),
        tagGroup(
          TagsSection.steamTagsSearchGroup,
          FontAwesomeIcons.steam.data,
          steamTags,
          trailing: steamTags.isEmpty
              ? null
              : _iconButton(
                  'Clear unused Steam tags',
                  Icons.delete,
                  theme.error,
                  _clearUnusedNonUserTags,
                ),
          emptyText:
              '${TagsSection.steamTagsInfoSpec.label}\n\n${TagsSection.steamTagsInfoSpec.description}',
          maxHeight: 200,
        ),
        SectionGroupEntry(
          visible:
              TagsSection.isMaintenanceAvailable(
                cleanupDone: legacyCleanupDone,
                customTagNames: customTags.map((tag) => tag.name),
              ) &&
              matches(TagsSection.maintenanceSearchGroup),
          builder: (position, isAlternate) => SectionGroupBox(
            title: TagsSection.maintenanceSearchGroup.title,
            titleIcon: Icons.cleaning_services,
            theme: theme,
            searchQuery: widget.searchQuery,
            isSearchMatch: isSearching,
            groupPosition: position,
            alternateBackground: isAlternate,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  TagsSection.maintenanceInfoSpec.label,
                  style: TextStyle(color: theme.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () =>
                      _cleanupLegacyDefaultTagsOnce(legacyCustomCount),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.secondary,
                    foregroundColor: theme.onSecondaryText,
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
