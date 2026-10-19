/// Common setting row widgets used across settings sections
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../widgets/toggle_switch.dart';
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
}) {
  final isSearching = query.trim().isNotEmpty;
  if (isSearching &&
      !matchesSettingsSearchGroup(
        query: query,
        matchesSearch: matchesSearch,
        group: group,
      )) {
    return false;
  }
  return true;
}

/// A convenience wrapper around [SectionGroupBox] that hides itself when
/// its [group] does not match the search query.
///
/// This reduces the boilerplate of computing `isSearching`/`showXXX` in
/// every section.
class SearchableSectionGroupBox extends StatelessWidget {
  const SearchableSectionGroupBox({
    super.key,
    required this.theme,
    required this.group,
    required this.searchQuery,
    required this.matchesSearch,
    required this.child,
    this.titleIcon,
    this.extraMatch,
    this.groupPosition = SectionGroupPosition.only,
    this.isAlternate = false,
    this.attachesToAbove = false,
  });

  final AppThemeData theme;
  final SettingsSearchGroup group;
  final String searchQuery;
  final bool Function(String) matchesSearch;
  final Widget child;
  final IconData? titleIcon;

  /// Additional predicate to decide visibility (example: theme list
  /// matching).  If provided, the section is shown when either the group
  /// matches or this returns true.
  final bool Function()? extraMatch;

  /// Position in a connected group strip (controls borders / corner radius).
  final SectionGroupPosition groupPosition;

  /// When true, uses the alternate background colour for visual banding.
  final bool isAlternate;

  /// When true, suppresses the top corner radius so this box visually attaches
  /// to a header widget placed directly above it.
  final bool attachesToAbove;

  bool get _isSearching => searchQuery.trim().isNotEmpty;

  bool get _show {
    if (!_isSearching) return true;
    if (matchesSettingsSearchGroup(
      query: searchQuery,
      matchesSearch: matchesSearch,
      group: group,
    )) {
      return true;
    }
    if (extraMatch != null && extraMatch!()) {
      return true;
    }
    return false;
  }

  /// Computes the effective [SectionGroupPosition] when [attachesToAbove] is
  /// set, mapping [only] → [onlyAttached] and [first] → [firstAttached].
  SectionGroupPosition get _effectivePosition {
    if (!attachesToAbove) return groupPosition;
    return switch (groupPosition) {
      SectionGroupPosition.only => SectionGroupPosition.onlyAttached,
      SectionGroupPosition.first => SectionGroupPosition.firstAttached,
      _ => groupPosition,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return SectionGroupBox(
      title: group.title,
      description: group.description,
      theme: theme,
      titleIcon: titleIcon,
      searchQuery: searchQuery,
      isSearchMatch: _isSearching,
      groupPosition: _effectivePosition,
      alternateBackground: isAlternate,
      child: child,
    );
  }
}

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
  return SectionGroupEntry(
    visible:
        visible ??
        (shouldShowSettingsGroup(
              query: searchQuery,
              matchesSearch: matchesSearch,
              group: group,
            ) ||
            (extraMatch?.call() ?? false)),
    builder: (position, isAlternate) => SearchableSectionGroupBox(
      theme: theme,
      group: group,
      searchQuery: searchQuery,
      matchesSearch: matchesSearch,
      titleIcon: titleIcon,
      extraMatch: extraMatch,
      groupPosition: position,
      isAlternate: isAlternate,
      attachesToAbove: attachesToAbove,
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
  }) {
    if (total == 1) {
      return attachesToAbove
          ? SectionGroupPosition.onlyAttached
          : SectionGroupPosition.only;
    }
    if (index == 0) {
      return attachesToAbove
          ? SectionGroupPosition.firstAttached
          : SectionGroupPosition.first;
    }
    if (index == total - 1) return SectionGroupPosition.last;
    return SectionGroupPosition.middle;
  }
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
    this.keyboardType,
    this.width,
    this.onChanged,
    this.onSubmitted,
  });

  final AppThemeData theme;
  final TextEditingController? controller;
  final String? hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final double? width;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    Widget field = TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: TextStyle(color: theme.textPrimary),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: theme.textHint),
      ),
      onChanged: onChanged,
    );

    if (width != null) {
      field = SizedBox(width: width, child: field);
    }
    return field;
  }
}

/// Search descriptor for a settings group.
class SettingsSearchGroup {
  const SettingsSearchGroup({
    required this.title,
    this.settings = const [],
    this.extraTexts = const [],
    this.description,
  });

  final String title;
  final String? description;
  final List<SettingTextSpec> settings;
  final List<String> extraTexts;

  List<String> get indexTexts => [
    title,
    if (description != null && description!.trim().isNotEmpty) description!,
    ...settings.expand((setting) => setting.indexTexts),
    ...extraTexts,
  ];
}

bool matchesSettingsSearchGroup({
  required String query,
  required bool Function(String) matchesSearch,
  required SettingsSearchGroup group,
}) {
  query.trim();
  return group.indexTexts.any(matchesSearch);
}

bool matchesAnySettingsSearchGroup({
  required String query,
  required bool Function(String) matchesSearch,
  required List<SettingsSearchGroup> groups,
}) {
  query.trim();
  return groups.any(
    (group) => matchesSettingsSearchGroup(
      query: query,
      matchesSearch: matchesSearch,
      group: group,
    ),
  );
}

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
  Widget build(BuildContext context) {
    return SettingRow(
      theme: theme,
      label: spec.label,
      description: spec.description,
      child: child,
    );
  }
}

/// Toggle setting row that takes a canonical [SettingTextSpec].
class SpecToggleSettingRow extends StatelessWidget {
  const SpecToggleSettingRow({
    super.key,
    required this.theme,
    required this.spec,
    required this.value,
    required this.onChanged,
    this.showDividerBelow = false,
  });

  final AppThemeData theme;
  final SettingTextSpec spec;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showDividerBelow;

  @override
  Widget build(BuildContext context) {
    return ToggleSettingRow(
      theme: theme,
      label: spec.label,
      description: spec.description,
      value: value,
      onChanged: onChanged,
      showDividerBelow: showDividerBelow,
    );
  }
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
  if (entries.isEmpty) {
    return const SizedBox.shrink();
  }

  return SettingsControlWrap(
    children: [
      for (var index = 0; index < entries.length; index++)
        SettingsToggleCard(
          theme: theme,
          label: entries[index].spec.label,
          description: entries[index].spec.description,
          value: entries[index].value,
          onChanged: entries[index].onChanged,
        ),
    ],
  );
}

/// Setting row helper widget with label, optional description, and child content.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.theme,
    required this.label,
    required this.child,
    this.description,
    this.labelColor,
    this.onLabelTap,
    this.stackedBreakpoint,
  });

  final AppThemeData theme;
  final String label;
  final String? description;
  final Color? labelColor;
  final Widget child;

  /// Optional callback invoked when the user taps the label/description area
  final VoidCallback? onLabelTap;

  /// When set, stacks the trailing child under the label once the available
  /// width drops below this breakpoint.
  final double? stackedBreakpoint;

  @override
  Widget build(BuildContext context) {
    final labelColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: labelColor ?? theme.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 2),
          Text(
            description!,
            style: TextStyle(color: theme.textSecondary, fontSize: 12),
          ),
        ],
      ],
    );

    final expandedLabel = onLabelTap != null
        ? MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onLabelTap,
              child: labelColumn,
            ),
          )
        : labelColumn;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            stackedBreakpoint != null &&
            constraints.maxWidth < stackedBreakpoint!;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    expandedLabel,
                    const SizedBox(height: kElementVSpacing),
                    Align(alignment: Alignment.centerLeft, child: child),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: expandedLabel),
                    child,
                  ],
                ),
        );
      },
    );
  }
}

/// A toggle switch setting row with label, description, and divider option.
class ToggleSettingRow extends StatelessWidget {
  const ToggleSettingRow({
    super.key,
    required this.theme,
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
    this.trailing,
    this.showDividerBelow = false,
  });

  final AppThemeData theme;
  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? trailing;
  final bool showDividerBelow;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingRow(
          theme: theme,
          label: label,
          description: description,
          onLabelTap: onChanged != null ? () => onChanged!(!value) : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (trailing != null) ...[
                trailing!,
                const SizedBox(width: kElementHSpacing),
              ],
              AppToggleSwitch(value: value, onChanged: onChanged, theme: theme),
            ],
          ),
        ),
        if (showDividerBelow) const Divider(height: 16),
      ],
    );
  }
}
