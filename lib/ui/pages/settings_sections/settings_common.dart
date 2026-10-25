/// Common setting row widgets used across settings sections
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../widgets/section_groupbox.dart';
import '../../../core/constants/app_constants.dart';
import 'settings_control_cards.dart';

/// Canonical setting text metadata that can drive both UI labels and search index text.
class SettingTextSpec {
  const SettingTextSpec({required this.label, this.description});

  final String label;
  final String? description;

  List<String> get indexTexts => [
    label,
    if (description != null && description!.trim().isNotEmpty) description!,
  ];
}

/// Returns true when the supplied [group] should be shown for the given
/// search state.  It handles trimming and the common
/// "isSearching && !match -> hide" case used throughout settings sections.
bool shouldShowSettingsGroup({
  required String query,
  required bool Function(String) matchesSearch,
  required SettingsSearchGroup group,
}) =>
    query.trim().isEmpty ||
    matchesSettingsSearchGroup(matchesSearch: matchesSearch, group: group);

// ---------------------------------------------------------------------------
// Connected group strip helpers
// ---------------------------------------------------------------------------

/// An entry in a [SettingsSectionGroups] layout.
///
/// [visible] determines whether this entry participates in the layout at all.
/// [builder] receives the computed [SectionGroupPosition] and [isAlternate]
/// flag so it can forward them to the underlying [SectionGroupBox] or
/// [SearchableSectionGroupBox].
class SectionGroupEntry {
  const SectionGroupEntry({required this.visible, required this.builder});

  final bool visible;
  final Widget Function(SectionGroupPosition position, bool isAlternate)
  builder;
}

/// Builds a [SectionGroupEntry] for the common searchable section pattern.
///
/// Visibility defaults to the group search match; callers can supply an explicit
/// value for additional conditions such as platform or feature availability.
/// The [childBuilder] is evaluated lazily so hidden groups do not build their
/// content until the connected strip decides they are visible.
SectionGroupEntry buildSearchableSectionEntry({
  bool? visible,
  required AppThemeData theme,
  required SettingsSearchGroup group,
  required String searchQuery,
  required bool Function(String) matchesSearch,
  required Widget Function() childBuilder,
  IconData? titleIcon,
  bool Function()? extraMatch,
  bool attachesToAbove = false,
}) {
  bool matches() =>
      shouldShowSettingsGroup(
        query: searchQuery,
        matchesSearch: matchesSearch,
        group: group,
      ) ||
      (extraMatch?.call() ?? false);
  return SectionGroupEntry(
    visible: visible ?? matches(),
    // An explicitly visible entry still hides when its group does not match.
    builder: (position, isAlternate) => !matches()
        ? const SizedBox.shrink()
        : SectionGroupBox(
            title: group.title,
            theme: theme,
            titleIcon: titleIcon,
            searchQuery: searchQuery,
            isSearchMatch: searchQuery.trim().isNotEmpty,
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
            child: childBuilder(),
          ),
  );
}

/// Renders the groupboxes inside a settings section as a connected vertical
/// strip, with zero gap and alternating backgrounds at every screen width.
///
/// Invisible entries (where [SectionGroupEntry.visible] is false) are
/// filtered out before position/alternation is computed, so the result is
/// always correct regardless of how many groups are hidden by search.
class SettingsSectionGroups extends StatelessWidget {
  const SettingsSectionGroups({
    super.key,
    required this.entries,
    this.attachesToAbove = false,
  });

  final List<SectionGroupEntry> entries;

  /// When true, the first visible group has its top corner radius suppressed so
  /// it attaches seamlessly to a header widget placed directly above the strip.
  final bool attachesToAbove;

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
                bottom: spaced && i < visible.length - 1 ? kGroupBoxSpacing : 0,
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

/// A text field styled to match the settings UI.  Many sections previously
/// duplicated identical [InputDecoration] code.
class ThemedTextField extends StatelessWidget {
  const ThemedTextField({
    super.key,
    required this.theme,
    this.controller,
    this.hintText,
    this.obscureText = false,
    this.onChanged,
  });

  final AppThemeData theme;
  final TextEditingController? controller;
  final String? hintText;
  final bool obscureText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    obscureText: obscureText,
    style: TextStyle(color: theme.textPrimary),
    decoration: InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: theme.textHint),
    ),
    onChanged: onChanged,
  );
}

/// Search descriptor for a settings group.
class SettingsSearchGroup {
  const SettingsSearchGroup({
    required this.title,
    this.settings = const [],
    this.extraTexts = const [],
  });

  final String title;
  final List<SettingTextSpec> settings;
  final List<String> extraTexts;

  List<String> get indexTexts => [
    title,
    ...settings.expand((setting) => setting.indexTexts),
    ...extraTexts,
  ];
}

bool matchesSettingsSearchGroup({
  required bool Function(String) matchesSearch,
  required SettingsSearchGroup group,
}) => group.indexTexts.any(matchesSearch);

bool matchesAnySettingsSearchGroup({
  required bool Function(String) matchesSearch,
  required List<SettingsSearchGroup> groups,
}) => groups.any(
  (group) =>
      matchesSettingsSearchGroup(matchesSearch: matchesSearch, group: group),
);

/// Setting row that takes a canonical [SettingTextSpec].
class SpecSettingRow extends StatelessWidget {
  const SpecSettingRow({
    super.key,
    required this.theme,
    required this.spec,
    required this.child,
  });

  final AppThemeData theme;
  final SettingTextSpec spec;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                spec.label,
                style: TextStyle(
                  color: theme.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (spec.description case final description?) ...[
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(color: theme.textSecondary, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        child,
      ],
    ),
  );
}

typedef SpecToggleSettingEntry = ({
  SettingTextSpec spec,
  bool value,
  ValueChanged<bool> onChanged,
});

Widget buildSpecToggleSettingList({
  required AppThemeData theme,
  required List<SpecToggleSettingEntry> entries,
}) {
  if (entries.isEmpty) return const SizedBox.shrink();

  return SettingsControlWrap(
    children: [
      for (final entry in entries)
        SettingsToggleCard(
          theme: theme,
          label: entry.spec.label,
          description: entry.spec.description,
          value: entry.value,
          onChanged: entry.onChanged,
        ),
    ],
  );
}
