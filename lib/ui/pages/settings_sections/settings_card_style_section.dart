import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/preview_card.dart';
import '../../widgets/section_groupbox.dart';
import '../../widgets/settings_card_indicator.dart';
import '../../widgets/toggle_switch.dart';

class SettingsCardStyleSection extends ConsumerStatefulWidget {
  const SettingsCardStyleSection({
    super.key,
    required this.theme,
    required this.searchQuery,
    required this.isSearchMatch,
    required this.groupPosition,
    required this.isAlternate,
  });

  final AppThemeData theme;
  final String searchQuery;
  final bool isSearchMatch;
  final SectionGroupPosition groupPosition;
  final bool isAlternate;

  @override
  ConsumerState<SettingsCardStyleSection> createState() =>
      _SettingsCardStyleSectionState();
}

class _SettingsCardStyleSectionState
    extends ConsumerState<SettingsCardStyleSection> {
  /// Local preview state; trying a status control does not change settings.
  final _demoOn = {
    for (final style in SettingsCardIndicatorStyle.values) style: true,
  };

  void _toggleDemo(SettingsCardIndicatorStyle style, [bool? value]) =>
      setState(() => _demoOn[style] = value ?? !_demoOn[style]!);

  Widget _preview(SettingsCardIndicatorStyle style) {
    final theme = widget.theme;
    final on = _demoOn[style]!;
    return Semantics(
      label: '${style.displayName} status preview',
      toggled: on,
      onTap: () => _toggleDemo(style),
      child: ExcludeSemantics(
        child: switch (style) {
          SettingsCardIndicatorStyle.switchControl => AppToggleSwitch(
            value: on,
            onChanged: (value) => _toggleDemo(style, value),
            theme: theme,
            style: ref.watch(toggleStyleProvider),
          ),
          SettingsCardIndicatorStyle.retroSquare => MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _toggleDemo(style),
              child: SettingsCardIndicator(
                theme: theme,
                value: on,
                enabled: true,
              ),
            ),
          ),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(settingsCardIndicatorStyleProvider);
    return SectionGroupBox(
      title: 'Settings Card Style',
      titleIcon: Icons.tune,
      theme: widget.theme,
      searchQuery: widget.searchQuery,
      isSearchMatch: widget.isSearchMatch,
      groupPosition: widget.groupPosition,
      alternateBackground: widget.isAlternate,
      headerCrossAxisAlignment: CrossAxisAlignment.center,
      child: PreviewCardWrap(
        children: [
          for (final style in SettingsCardIndicatorStyle.values)
            Tooltip(
              key: ValueKey(style),
              message: style.description,
              child: StyleChoiceCard(
                name: style.displayName,
                theme: widget.theme,
                isSelected: selected == style,
                onTap: () => ref
                    .read(settingsProvider.notifier)
                    .setSetting(SettingsKeys.settingsCardIndicatorStyle, style),
                // The retro display belongs in the corner, as on real cards.
                previewAlignment:
                    style == SettingsCardIndicatorStyle.retroSquare
                    ? Alignment.topRight
                    : Alignment.centerRight,
                preview: _preview(style),
              ),
            ),
        ],
      ),
    );
  }
}
