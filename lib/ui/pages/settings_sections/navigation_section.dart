/// Navigation panel layout and gradient bar animation settings.
library;

import 'package:material_ui/material_ui.dart';
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

class const NavigationSection({
  super.key,
  final String searchQuery = '',
  final bool attachesToAbove = false,
}) extends ConsumerWidget {
  static const SettingTextSpec navPositionSpec = SettingTextSpec(
    label: 'Panel Position',
    icon: Icons.view_sidebar_outlined,
  );
  // Horizontal and vertical panels keep separate placements with one label.
  static const SettingTextSpec navButtonArrangementHorizontalSpec =
      SettingTextSpec(
        label: 'Button Placement',
        icon: Icons.smart_button_outlined,
      );
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
      'Navigation Panel Position',
      'Left',
      'Right',
      'Top',
      'Bottom',
      'Split',
      'Panel',
      'Position',
      'Button',
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

    final showNavBarSection = shouldShowSettingsGroup(
      searchQuery,
      navigationSearchGroup,
    );
    final showGradientSection = shouldShowSettingsGroup(
      searchQuery,
      gradientSearchGroup,
    );
    if (!showNavBarSection && !showGradientSection) {
      return const SizedBox.shrink();
    }
    return SettingsSectionGroups(
      attachesToAbove: attachesToAbove,
      entries: [
        buildSearchableSectionEntry(
          visible: showNavBarSection,
          group: navigationSearchGroup,
          titleIcon: Icons.view_sidebar,
          searchQuery: searchQuery,
          // The section's own title names it.
          showTitle: false,
          // Each on its own full row: side by side, their buttons crowd
          // the names on narrow windows.
          childBuilder: () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              SettingsButtonGroupCard<NavBarPosition>(
                label: navPositionSpec.label,
                icon: navPositionSpec.icon,
                value: navBarPosition,
                choices: [
                  for (final position in NavBarPosition.values)
                    SettingsChoice(
                      position,
                      position.displayName,
                      icon: Icon(_arrowTowards(position)),
                    ),
                ],
                onChanged: settingsNotifier.setter(SettingsKeys.navBarPosition),
              ),
              SettingsButtonGroupCard<NavButtonArrangement>(
                label: navButtonArrangementHorizontalSpec.label,
                icon: navButtonArrangementHorizontalSpec.icon,
                value: navButtonArrangement,
                choices: [
                  for (final arrangement in NavButtonArrangement.values)
                    SettingsChoice(
                      arrangement,
                      arrangement.displayName(isHorizontal: isHorizontalPanel),
                      icon: _arrangementIcon(
                        arrangement,
                        isHorizontal: isHorizontalPanel,
                      ),
                    ),
                ],
                onChanged: (value) => settingsNotifier.set(
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
            searchQuery: searchQuery,
            groupPosition: position,
            isAlternate: isAlternate,
          ),
        ),
      ],
    );
  }
}

/// An arrow towards [position]'s side of the window.
IconData _arrowTowards(NavBarPosition position) => switch (position) {
  NavBarPosition.left => Icons.west_rounded,
  NavBarPosition.right => Icons.east_rounded,
  NavBarPosition.top => Icons.north_rounded,
  NavBarPosition.bottom => Icons.south_rounded,
};

/// An arrow towards the end the buttons gather at, or arrows out to both ends
/// when they split, along the panel.
Widget _arrangementIcon(
  NavButtonArrangement arrangement, {
  required bool isHorizontal,
}) => switch (arrangement) {
  NavButtonArrangement.start => Icon(
    isHorizontal ? Icons.west_rounded : Icons.north_rounded,
  ),
  NavButtonArrangement.end => Icon(
    isHorizontal ? Icons.east_rounded : Icons.south_rounded,
  ),
  NavButtonArrangement.split => RotatedBox(
    quarterTurns: isHorizontal ? 1 : 0,
    child: const Icon(Icons.expand_rounded),
  ),
};

// ---------------------------------------------------------------------------
// Gradient animation selector
// ---------------------------------------------------------------------------

/// Gradient animation effect selector section
class const _GradientAnimationSection({
  required final String searchQuery,
  final SectionGroupPosition groupPosition = SectionGroupPosition.only,
  final bool isAlternate = false,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.appTheme;
    final currentAnimation = ref.watch(
      appShellSettingsProvider.select((s) => s.gradientAnimation),
    );
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final swapGradientColors = ref.watch(swapGradientColorsProvider);
    final previewAnimationsPlaying = ref.watch(gradientPreviewPlayingProvider);
    final speed = ref.watch(gradientAnimationSpeedProvider);

    return SectionGroupBox(
      title: NavigationSection.gradientSearchGroup.title,
      titleIcon: Icons.gradient,
      headerCrossAxisAlignment: CrossAxisAlignment.center,
      searchQuery: searchQuery,
      groupPosition: groupPosition,
      alternateBackground: isAlternate,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: kElementHSpacing,
        children: [
          IconButton(
            tooltip: 'Swap primary and accent colors',
            onPressed: () => settingsNotifier.set(
              SettingsKeys.swapGradientColors,
              !swapGradientColors,
            ),
            icon: GradientOrderIcon(
              leading: swapGradientColors ? theme.secondary : theme.accent,
              trailing: swapGradientColors ? theme.accent : theme.secondary,
            ),
          ),
          SliderPopoverButton(
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
              onChanged: (value) => settingsNotifier.set(
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
                  isSelected: effect == currentAnimation,
                  isPlaying: previewAnimationsPlaying,
                  onTap: () => settingsNotifier.set(
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
class const GradientOrderIcon({
  required final Color leading,
  required final Color trailing,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(26),
    painter: _SwapArrowsPainter(leading: leading, trailing: trailing),
  );
}

/// The swap icon's two arrows, each wholly in its own colour: the top one
/// in [leading], the bottom one in [trailing]. The arrows overlap in height,
/// so colouring the icon's halves would tint each with the other's colour.
class _SwapArrowsPainter extends CustomPainter {
  _SwapArrowsPainter({required this.leading, required this.trailing});

  final Color leading;
  final Color trailing;

  // Icons.swap_horiz's arrows on its 24 px grid.
  static final _top = Path()
    ..moveTo(21, 9)
    ..lineTo(17.01, 5)
    ..lineTo(17.01, 8)
    ..lineTo(10, 8)
    ..lineTo(10, 10)
    ..lineTo(17.01, 10)
    ..lineTo(17.01, 13)
    ..close();
  static final _bottom = Path()
    ..moveTo(6.99, 11)
    ..lineTo(3, 15)
    ..lineTo(6.99, 19)
    ..lineTo(6.99, 16)
    ..lineTo(14, 16)
    ..lineTo(14, 14)
    ..lineTo(6.99, 14)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(_top, Paint()..color = leading);
    canvas.drawPath(_bottom, Paint()..color = trailing);
  }

  @override
  bool shouldRepaint(_SwapArrowsPainter old) =>
      old.leading != leading || old.trailing != trailing;
}
