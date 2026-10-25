/// Navigation panel layout, background, and animation settings.
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
import '../../widgets/navigation_panel_overlay.dart';
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
    description: 'Select the position of the navigation bar in the app',
  );
  static const SettingTextSpec navButtonArrangementHorizontalSpec =
      SettingTextSpec(
        label: 'Navigation Button Placement',
        description: 'Position the page buttons relative to the gradient bar',
      );
  static const SettingTextSpec navButtonArrangementVerticalSpec =
      SettingTextSpec(
        label: 'Navigation Button Placement',
        description: 'Position the page buttons relative to the gradient bar',
      );
  static const SettingTextSpec navPanelOverlayStyleSpec = SettingTextSpec(
    label: 'Navigation panel overlay style',
    description: 'Add decorative overlays for the navigation panel',
  );
  static const SettingTextSpec gradientSwapSpec = SettingTextSpec(
    label: 'Swap primary & accent colors',
    description: 'Alternative look for the gradient bar',
  );
  static const SettingsSearchGroup navigationSearchGroup = SettingsSearchGroup(
    title: 'Layout',
    settings: [
      navPositionSpec,
      navButtonArrangementHorizontalSpec,
      navButtonArrangementVerticalSpec,
    ],
    extraTexts: ['Left', 'Right', 'Top', 'Bottom', 'Split'],
  );

  static const SettingsSearchGroup navOverlaySearchGroup = SettingsSearchGroup(
    title: 'Navigation Panel Background',
    settings: [navPanelOverlayStyleSpec],
    extraTexts: [
      'None',
      'Diagonal',
      'Crosshatch',
      'Gradient',
      'Hex Pattern',
      'Ripple',
      'Built-in themes',
      'Default themes',
      'Custom themes',
      'Persistent setting',
      'Saved with custom theme',
      'Theme override',
      'Overlay saved in custom theme',
    ],
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
    navOverlaySearchGroup,
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
    final showNavOverlaySection = shouldShowSettingsGroup(
      query: searchQuery,
      matchesSearch: matchesSearch,
      group: navOverlaySearchGroup,
    );
    if (!showNavBarSection && !showNavOverlaySection && !showGradientSection) {
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
                description: navPositionSpec.description,
                value: navBarPosition,
                choices: [
                  for (final position in NavBarPosition.values)
                    SettingsChoice(position, position.displayName),
                ],
                onChanged: settingsNotifier.setter(SettingsKeys.navBarPosition),
              ),
              _buildNavArrangementRow(
                theme: theme,
                spec: isHorizontalPanel
                    ? navButtonArrangementHorizontalSpec
                    : navButtonArrangementVerticalSpec,
                value: navButtonArrangement,
                isHorizontal: isHorizontalPanel,
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
          visible: showNavOverlaySection,
          builder: (position, isAlternate) => _NavigationPanelOverlaySection(
            theme: theme,
            searchQuery: searchQuery,
            isSearchMatch: isSearching,
            groupPosition: position,
            isAlternate: isAlternate,
            onOverlaySelected: (style) =>
                _applyNavPanelOverlayStyle(ref, style),
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

  Future<void> _applyNavPanelOverlayStyle(
    WidgetRef ref,
    NavPanelOverlayStyle style,
  ) async {
    final effectiveOverlayStyle = ref.read(
      effectiveNavPanelOverlayStyleProvider,
    );
    if (effectiveOverlayStyle == style) return;

    final currentTheme = ref.read(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);
    final isBuiltInTheme = ref.read(currentThemeIsBuiltInProvider);

    if (isBuiltInTheme) {
      await ref
          .read(settingsProvider.notifier)
          .setSetting(SettingsKeys.navPanelOverlayStyle, style);
      return;
    }

    await themeNotifier.saveCustomTheme(
      currentTheme.copyWith(navPanelOverlayStyle: style),
    );
  }

  Widget _buildNavArrangementRow({
    required AppThemeData theme,
    required SettingTextSpec spec,
    required NavButtonArrangement value,
    required bool isHorizontal,
    required ValueChanged<NavButtonArrangement> onChanged,
  }) {
    return SettingsChoiceCard<NavButtonArrangement>(
      theme: theme,
      label: spec.label,
      description: spec.description,
      value: value,
      choices: [
        for (final arrangement in NavButtonArrangement.values)
          SettingsChoice(
            arrangement,
            arrangement.displayName(isHorizontal: isHorizontal),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _NavigationPanelOverlaySection extends ConsumerWidget {
  const _NavigationPanelOverlaySection({
    required this.theme,
    required this.searchQuery,
    required this.isSearchMatch,
    required this.onOverlaySelected,
    this.groupPosition = SectionGroupPosition.only,
    this.isAlternate = false,
  });

  final AppThemeData theme;
  final String searchQuery;
  final bool isSearchMatch;
  final Future<void> Function(NavPanelOverlayStyle style) onOverlaySelected;
  final SectionGroupPosition groupPosition;
  final bool isAlternate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTheme = ref.watch(themeProvider);
    final effectiveOverlayStyle = ref.watch(
      effectiveNavPanelOverlayStyleProvider,
    );
    final effectiveTheme = ref.watch(effectiveThemeProvider);

    return SectionGroupBox(
      title: NavigationSection.navOverlaySearchGroup.title,
      theme: theme,
      titleIcon: Icons.layers_outlined,
      searchQuery: searchQuery,
      isSearchMatch: isSearchMatch,
      groupPosition: groupPosition,
      alternateBackground: isAlternate,
      child: PreviewCardWrap(
        children: NavPanelOverlayStyle.values.map((style) {
          return PreviewCard(
            key: ValueKey(style),
            name: style.displayName,
            theme: theme,
            isSelected: effectiveOverlayStyle == style,
            onTap: () => onOverlaySelected(style),
            backgroundBuilder: (context, _) => Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: effectiveTheme.navBackground,
                  ),
                ),
                if (style != NavPanelOverlayStyle.none)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: NavigationPanelOverlayPaint(
                        theme: currentTheme.copyWith(
                          navPanelOverlayStyle: style,
                        ),
                        preview: true,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
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
            icon: Icon(
              Icons.swap_horiz,
              color: swapGradientColors ? theme.accent : theme.textSecondary,
              size: 26,
            ),
          ),
          _GradientSpeedButton(theme: theme),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PreviewCardWrap(
            children: GradientAnimation.values.map((effect) {
              final isSelected = effect == currentAnimation;
              return GradientEffectPreview(
                key: ValueKey(effect),
                effect: effect,
                theme: theme,
                isSelected: isSelected,
                isPlaying: previewAnimationsPlaying,
                onTap: () {
                  settingsNotifier.setSetting(
                    SettingsKeys.gradientAnimation,
                    effect,
                  );
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _GradientSpeedButton extends ConsumerWidget {
  const _GradientSpeedButton({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(gradientAnimationSpeedProvider);
    final previewAnimationsPlaying = ref.watch(gradientPreviewPlayingProvider);
    return AnimatedPopover(
      theme: theme,
      child: SizedBox(
        width: 260,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Animation speed',
                            style: TextStyle(
                              color: theme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message:
                              '${speed.displayName} (${speed.multiplier.toStringAsFixed(speed == GradientAnimationSpeed.standard ? 0 : 1)}×)',
                          child: GradientSpeedIcon(
                            speed: speed,
                            color: theme.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
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
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              Slider(
                value: speed.index.toDouble(),
                min: 0,
                max: 2,
                divisions: 2,
                label: speed.displayName,
                semanticFormatterCallback: (value) =>
                    GradientAnimationSpeed.values[value.round()].displayName,
                onChanged: (value) => ref
                    .read(settingsProvider.notifier)
                    .setSetting(
                      SettingsKeys.gradientAnimationSpeed,
                      GradientAnimationSpeed.values[value.round()],
                    ),
              ),
            ],
          ),
        ),
      ),
      builder: (context, toggle) => IconButton(
        tooltip: 'Animation speed',
        onPressed: toggle,
        icon: Icon(Icons.speed_rounded, color: theme.accent, size: 26),
      ),
    );
  }
}
