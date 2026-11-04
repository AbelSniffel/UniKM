/// Navigation panel layout and gradient bar animation settings.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../../shared/state/session_value.dart';
import '../../widgets/animated_gradient_bar.dart';
import '../../widgets/animated_popover.dart';
import '../../widgets/gradient_speed_icon.dart';
import '../../widgets/preview_card.dart';
import '../../widgets/section_groupbox.dart';
import 'settings_common.dart';
import 'settings_control_cards.dart';

final gradientPreviewPlayingProvider = sessionValueProvider(true);

class NavigationSection extends ConsumerWidget {
  const NavigationSection({
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

  static const SettingTextSpec navPositionSpec = SettingTextSpec(
    label: 'Position',
    icon: Icons.view_sidebar_outlined,
  );
  // Horizontal and vertical panels keep separate placements with one label.
  static const SettingTextSpec navButtonArrangementHorizontalSpec =
      SettingTextSpec(label: 'Buttons', icon: Icons.smart_button_outlined);
  static const navButtonArrangementVerticalSpec =
      navButtonArrangementHorizontalSpec;
  static const SettingTextSpec gradientSwapSpec = SettingTextSpec(
    label: 'Swap primary & accent colors',
    description: 'Alternative look for the gradient bar',
  );
  static const SettingsSearchGroup navigationSearchGroup = SettingsSearchGroup(
    title: 'Navigation Bar',
    settings: [
      navPositionSpec,
      navButtonArrangementHorizontalSpec,
      navButtonArrangementVerticalSpec,
    ],
    extraTexts: [
      'Layout',
      'Navigation Button Placement',
      'Left',
      'Right',
      'Top',
      'Bottom',
      'Split',
    ],
    info: 'Where the bar sits and where its page buttons go.',
  );

  static SettingsSearchGroup get gradientSearchGroup => SettingsSearchGroup(
    title: 'Gradient Bar Animation',
    settings: [gradientSwapSpec],
    extraTexts: [
      ...GradientAnimation.values.map((effect) => effect.displayName),
      'Animation speed',
      'Slow',
      'Default',
      'Fast',
    ],
  );

  static List<SettingsSearchGroup> get searchGroups => [
    navigationSearchGroup,
    gradientSearchGroup,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final navBarPosition = ref.watch(
      appShellSettingsProvider.select((s) => s.navBarPosition),
    );
    final isHorizontalPanel =
        navBarPosition == NavBarPosition.top ||
        navBarPosition == NavBarPosition.bottom;
    final navButtonArrangementH = ref.watch(navButtonArrangementHProvider);
    final navButtonArrangementV = ref.watch(navButtonArrangementVProvider);
    final navButtonArrangement = isHorizontalPanel
        ? navButtonArrangementH
        : navButtonArrangementV;

    final isSearching = searchQuery.trim().isNotEmpty;
    final showNavBarSection = shouldShowSettingsGroup(
      query: searchQuery,
      matchesSearch: matchesSearch,
      group: navigationSearchGroup,
    );
    final showGradientSection = shouldShowSettingsGroup(
      query: searchQuery,
      matchesSearch: matchesSearch,
      group: gradientSearchGroup,
    );
    if (!showNavBarSection && !showGradientSection) {
      return const SizedBox.shrink();
    }
    return SettingsSectionGroups(
      attachesToAbove: attachesToAbove,
      entries: [
        buildSearchableSectionEntry(
          visible: showNavBarSection,
          theme: theme,
          group: navigationSearchGroup,
          titleIcon: Icons.view_sidebar,
          searchQuery: searchQuery,
          matchesSearch: matchesSearch,
          childBuilder: () => SettingsControlWrap(
            children: [
              SettingsChoiceCard<NavBarPosition>(
                theme: theme,
                label: navPositionSpec.label,
                icon: navPositionSpec.icon,
                value: navBarPosition,
                choices: [
                  for (final position in NavBarPosition.values)
                    SettingsChoice(position, position.displayName),
                ],
                onChanged: settingsNotifier.setter(SettingsKeys.navBarPosition),
              ),
              SettingsChoiceCard<NavButtonArrangement>(
                theme: theme,
                label: navButtonArrangementHorizontalSpec.label,
                icon: navButtonArrangementHorizontalSpec.icon,
                value: navButtonArrangement,
                choices: [
                  for (final arrangement in NavButtonArrangement.values)
                    SettingsChoice(
                      arrangement,
                      arrangement.displayName(isHorizontal: isHorizontalPanel),
                    ),
                ],
                onChanged: (value) => settingsNotifier.setSetting(
                  isHorizontalPanel
                      ? SettingsKeys.navButtonArrangementH
                      : SettingsKeys.navButtonArrangementV,
                  value,
                ),
              ),
            ],
          ),
        ),
        SectionGroupEntry(
          visible: showGradientSection,
          builder: (position, isAlternate) => _GradientAnimationSection(
            theme: theme,
            searchQuery: searchQuery,
            isSearchMatch: isSearching,
            groupPosition: position,
            isAlternate: isAlternate,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Gradient animation selector
// ---------------------------------------------------------------------------

/// Gradient animation effect selector section
class _GradientAnimationSection extends ConsumerWidget {
  const _GradientAnimationSection({
    required this.theme,
    required this.searchQuery,
    required this.isSearchMatch,
    this.groupPosition = SectionGroupPosition.only,
    this.isAlternate = false,
  });

  final AppThemeData theme;
  final String searchQuery;
  final bool isSearchMatch;
  final SectionGroupPosition groupPosition;
  final bool isAlternate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentAnimation = ref.watch(
      appShellSettingsProvider.select((s) => s.gradientAnimation),
    );
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final swapGradientColors = ref.watch(swapGradientColorsProvider);
    final previewAnimationsPlaying = ref.watch(gradientPreviewPlayingProvider);
    final speed = ref.watch(gradientAnimationSpeedProvider);

    return SectionGroupBox(
      title: NavigationSection.gradientSearchGroup.title,
      theme: theme,
      titleIcon: Icons.gradient,
      headerCrossAxisAlignment: CrossAxisAlignment.center,
      searchQuery: searchQuery,
      isSearchMatch: isSearchMatch,
      groupPosition: groupPosition,
      alternateBackground: isAlternate,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: kElementHSpacing,
        children: [
          IconButton(
            tooltip: 'Swap primary and accent colors',
            onPressed: () => settingsNotifier.setSetting(
              SettingsKeys.swapGradientColors,
              !swapGradientColors,
            ),
            icon: _GradientOrderIcon(
              leading: swapGradientColors ? theme.secondary : theme.accent,
              trailing: swapGradientColors ? theme.accent : theme.secondary,
            ),
          ),
          SliderPopoverButton(
            theme: theme,
            title: 'Animation speed',
            value:
                '${speed.multiplier.toStringAsFixed(speed.multiplier % 1 == 0 ? 0 : 1)}×',
            icon: GradientSpeedIcon(
              speed: speed,
              color: theme.accent,
              paused: !previewAnimationsPlaying,
            ),
            action: IconButton(
              tooltip: previewAnimationsPlaying
                  ? 'Pause preview animations'
                  : 'Play preview animations',
              onPressed: () => ref
                  .read(gradientPreviewPlayingProvider.notifier)
                  .set(!previewAnimationsPlaying),
              icon: Icon(
                previewAnimationsPlaying
                    ? Icons.pause_circle_rounded
                    : Icons.play_circle_rounded,
                color: theme.accent,
                size: 26,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              visualDensity: VisualDensity.compact,
            ),
            slider: Slider(
              value: speed.index.toDouble(),
              max: GradientAnimationSpeed.values.length - 1,
              divisions: GradientAnimationSpeed.values.length - 1,
              label: speed.displayName,
              semanticFormatterCallback: (value) =>
                  GradientAnimationSpeed.values[value.round()].displayName,
              onChanged: (value) => settingsNotifier.setSetting(
                SettingsKeys.gradientAnimationSpeed,
                GradientAnimationSpeed.values[value.round()],
              ),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PreviewCardWrap(
            children: [
              for (final effect in GradientAnimation.values)
                GradientEffectPreview(
                  key: ValueKey(effect),
                  effect: effect,
                  theme: theme,
                  isSelected: effect == currentAnimation,
                  isPlaying: previewAnimationsPlaying,
                  onTap: () => settingsNotifier.setSetting(
                    SettingsKeys.gradientAnimation,
                    effect,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The swap icon in the gradient's colours: its top arrow in the colour the
/// bar leads with (and solid bars use), its bottom arrow in the other.
class _GradientOrderIcon extends StatelessWidget {
  const _GradientOrderIcon({required this.leading, required this.trailing});

  final Color leading;
  final Color trailing;

  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.srcIn,
    shaderCallback: (bounds) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [leading, leading, trailing, trailing],
      stops: const [0, 0.5, 0.5, 1],
    ).createShader(bounds),
    child: const Icon(Icons.swap_horiz, size: 26),
  );
}
