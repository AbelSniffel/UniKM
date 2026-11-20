import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import 'section_groupbox.dart';
import 'tag_list.dart';

/// A titled list of tags, as the settings Tags section and the game editors
/// show them: the icon and "Title (count)" over the chips, or [emptyText]
/// while there are none.
class const TagGroupBox({
  super.key,
  required final String title,
  required final IconData icon,
  required final List<Tag> tags,
  required final String emptyText,
  final Widget? trailing,

  /// Chips for these tags show selected; null shows every tag selected.
  final Set<int>? selectedTagIds,
  final bool deleteOnTap = false,
  final ValueChanged<int>? onTagToggled,
  final double? maxHeight,
  final int? maxRows,
  final String searchQuery = '',
  final SectionGroupPosition groupPosition = SectionGroupPosition.only,
  final bool alternateBackground = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return SectionGroupBox(
      title: '$title (${tags.length})',
      titleIcon: icon,
      headerCrossAxisAlignment: CrossAxisAlignment.center,
      trailing: trailing,
      searchQuery: searchQuery,
      groupPosition: groupPosition,
      alternateBackground: alternateBackground,
      child: tags.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                emptyText,
                style: TextStyle(color: theme.textHint),
                textAlign: TextAlign.center,
              ),
            )
          : TagList(
              tags: tags,
              theme: theme,
              selectedTagIds: selectedTagIds,
              allSelected: selectedTagIds == null,
              deleteOnTap: deleteOnTap,
              onTagToggled: onTagToggled,
              maxHeight: maxHeight,
              maxRows: maxRows,
            ),
    );
  }
}
