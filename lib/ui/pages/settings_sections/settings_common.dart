/// Common setting row widgets used across settings sections
library;

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../widgets/search_highlight.dart';
import '../../widgets/section_groupbox.dart';
import 'settings_control_cards.dart';

/// Canonical setting text metadata that can drive both UI labels and search index text.
class const SettingTextSpec({
  required final String label,
  final String? description,

  /// Leads the setting's card.
  final IconData? icon,
}) {
  List<String> get indexTexts => [
    label,
    if (description != null && description!.trim().isNotEmpty) description!,
  ];
}

/// Returns true when the supplied [group] should be shown for the given
/// search state.  It handles trimming and the common
/// "isSearching && !match -> hide" case used throughout settings sections.
bool shouldShowSettingsGroup(String query, SettingsSearchGroup group) =>
    query.trim().isEmpty || matchesSettingsSearchGroup(query, group);

/// The gap between the headed groups of a settings panel.
const double kSettingsGroupSpacing = 20;

// ---------------------------------------------------------------------------
// Connected group strip helpers
// ---------------------------------------------------------------------------

/// An entry in a [SettingsSectionGroups] layout.
///
/// [visible] determines whether this entry participates in the layout at all.
/// [builder] receives the computed [SectionGroupPosition] and [isAlternate]
/// flag so it can forward them to the underlying [SectionGroupBox] or
/// [SearchableSectionGroupBox].
class const SectionGroupEntry({
  required final bool visible,
  required final Widget Function(
    SectionGroupPosition position,
    bool isAlternate,
  )
  builder,
});

/// Builds a [SectionGroupEntry] for the common searchable section pattern.
///
/// Visibility defaults to the group search match; callers can supply an explicit
/// value for additional conditions such as platform or feature availability.
/// The [childBuilder] is evaluated lazily so hidden groups do not build their
/// content until the connected strip decides they are visible.
SectionGroupEntry buildSearchableSectionEntry({
  bool? visible,
  required SettingsSearchGroup group,
  required String searchQuery,
  required Widget Function() childBuilder,
  IconData? titleIcon,
  bool Function()? extraMatch,
  bool attachesToAbove = false,
  bool showTitle = true,
}) {
  bool matches() =>
      shouldShowSettingsGroup(searchQuery, group) ||
      (extraMatch?.call() ?? false);
  return SectionGroupEntry(
    visible: visible ?? matches(),
    // An explicitly visible entry still hides when its group does not match.
    builder: (position, isAlternate) => !matches()
        ? const SizedBox.shrink()
        : SectionGroupBox(
            title: group.title,
            showTitle: showTitle,
            titleIcon: titleIcon,
            searchQuery: searchQuery,
            // Attached boxes drop the top corners that meet the header.
            groupPosition: !attachesToAbove
                ? position
                : switch (position) {
                    SectionGroupPosition.only =>
                      SectionGroupPosition.onlyAttached,
                    SectionGroupPosition.first =>
                      SectionGroupPosition.firstAttached,
                    _ => position,
                  },
            alternateBackground: isAlternate,
            // An info button centres on the title, as other title buttons do.
            headerCrossAxisAlignment: group.info == null
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            trailing: group.info == null
                ? null
                : SettingsInfoButton(message: group.info!),
            child: childBuilder(),
          ),
  );
}

/// An info icon whose tooltip also opens on tap, for a group's title bar.
class const SettingsInfoButton({super.key, required final String message})
    extends StatefulWidget {
  @override
  State<SettingsInfoButton> createState() => _SettingsInfoButtonState();
}

class _SettingsInfoButtonState extends State<SettingsInfoButton> {
  final _tooltip = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    // Tinted when the settings search matches the info.
    final query = SettingsSearchScope.queryOf(context);
    final matched =
        query.isNotEmpty && settingsSearchMatches(query, widget.message);
    return Tooltip(
      key: _tooltip,
      message: widget.message,
      child: IconButton(
        style: matched
            ? theme.compactIconButtonStyle.copyWith(
                backgroundColor: WidgetStatePropertyAll(
                  theme.accent.withValues(alpha: 0.3),
                ),
              )
            : theme.compactIconButtonStyle,
        icon: const Icon(Icons.info_outline, size: 26),
        color: theme.accent,
        onPressed: () => _tooltip.currentState?.ensureTooltipVisible(),
      ),
    );
  }
}

/// Renders the groupboxes inside a settings section as a connected vertical
/// strip, with zero gap and alternating backgrounds at every screen width.
///
/// Invisible entries (where [SectionGroupEntry.visible] is false) are
/// filtered out before position/alternation is computed, so the result is
/// always correct regardless of how many groups are hidden by search.
class const SettingsSectionGroups({
  super.key,
  required final List<SectionGroupEntry> entries,

  /// When true, the first visible group has its top corner radius suppressed so
  /// it attaches seamlessly to a header widget placed directly above the strip.
  final bool attachesToAbove = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final visible = entries.indexed.where((entry) => entry.$2.visible).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    final spaced = SpacedSettingsGroups.isEnabledOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < visible.length; i++)
          KeyedSubtree(
            key: ValueKey(visible[i].$1),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: spaced && i < visible.length - 1
                    ? kSettingsGroupSpacing
                    : 0,
              ),
              child: visible[i].$2.builder(
                spaced
                    ? SectionGroupPosition.only
                    : _positionFor(
                        i,
                        visible.length,
                        attachesToAbove: attachesToAbove,
                      ),
                !spaced && i.isOdd,
              ),
            ),
          ),
      ],
    );
  }

  static SectionGroupPosition _positionFor(
    int index,
    int total, {
    bool attachesToAbove = false,
  }) => switch (index) {
    _ when total == 1 =>
      attachesToAbove
          ? SectionGroupPosition.onlyAttached
          : SectionGroupPosition.only,
    0 =>
      attachesToAbove
          ? SectionGroupPosition.firstAttached
          : SectionGroupPosition.first,
    _ when index == total - 1 => SectionGroupPosition.last,
    _ => SectionGroupPosition.middle,
  };
}

/// Search descriptor for a settings group.
class const SettingsSearchGroup({
  required final String title,
  final List<SettingTextSpec> settings = const [],
  final List<String> extraTexts = const [],

  /// General notes on the group, behind an info button in its title bar.
  final String? info,
}) {
  List<String> get indexTexts => [
    title,
    ...settings.expand((setting) => setting.indexTexts),
    ...extraTexts,
    ?info,
  ];
}

bool matchesSettingsSearchGroup(String query, SettingsSearchGroup group) =>
    group.indexTexts.any((text) => settingsSearchMatches(query, text));

typedef SpecToggleSettingEntry = ({
  SettingTextSpec spec,
  bool value,
  ValueChanged<bool>? onChanged,
});

Widget buildSpecToggleSettingList({
  required List<SpecToggleSettingEntry> entries,
}) {
  if (entries.isEmpty) return const SizedBox.shrink();

  return SettingsControlWrap(
    children: [
      for (final entry in entries)
        SettingsToggleCard(
          label: entry.spec.label,
          description: entry.spec.description,
          icon: entry.spec.icon,
          value: entry.value,
          onChanged: entry.onChanged,
        ),
    ],
  );
}
