/// Common setting row widgets used across settings sections
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../widgets/toggle_switch.dart';
import '../../widgets/section_groupbox.dart';

const double kSectionGroupSpacing = 8.0;

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

/// An entry in a [SettingsSectionGroups] strip.
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

/// Renders a list of [SectionGroupEntry] items as a seamlessly connected
/// strip with zero gap and alternating backgrounds.
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
    final visible = entries.where((e) => e.visible).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < visible.length; i++)
          visible[i].builder(
            _positionFor(i, visible.length, attachesToAbove: attachesToAbove),
            i.isOdd, // alternating: index 0 = normal, 1 = alternate, 2 = normal…
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
        filled: true,
        fillColor: theme.inputBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(theme.cornerRadius),
          borderSide: BorderSide(color: theme.border),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
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

/// Setting row helper widget with label, optional description, and child content.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.theme,
    required this.label,
    required this.child,
    this.description,
    this.labelColor,
  });

  final AppThemeData theme;
  final String label;
  final String? description;
  final Color? labelColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
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
            ),
          ),
          child,
        ],
      ),
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
    this.showDividerBelow = false,
  });

  final AppThemeData theme;
  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;
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
          child: AppToggleSwitch(
            value: value,
            onChanged: onChanged,
            theme: theme,
          ),
        ),
        if (showDividerBelow) const Divider(),
      ],
    );
  }
}
