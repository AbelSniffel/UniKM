/// Navigation panel widget with configurable position and appearance
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
export '../../core/constants/app_constants.dart'
    show kNavigationPanelHorizontalExtent;
import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import 'animated_gradient_bar.dart';
import 'nav_button_group.dart';
import 'navigation_more_menu.dart';
import 'background_pattern.dart';
import 'navigation_theme_menu.dart';

const kNavigationPanelCollapsedWidth = 64.0;
const kNavigationPanelExpandedWidth = 108.0;

/// Match the shell's narrow mode against the navigation panel's expanded size.
/// Using the collapsed size would move the breakpoint during resizing.
bool isVeryNarrowAppLayout(
  double viewportWidth, {
  required NavBarPosition position,
  required NavBarAppearance appearance,
}) {
  final sideNavigation =
      position == NavBarPosition.left || position == NavBarPosition.right;
  final navWidth = appearance == NavBarAppearance.iconOnly
      ? kNavigationPanelCollapsedWidth
      : kNavigationPanelExpandedWidth;
  final projectedWidth = sideNavigation
      ? viewportWidth - navWidth
      : viewportWidth;
  return projectedWidth < kVeryNarrowLayoutBreakpoint;
}

/// Navigation item data
class const NavItem({
  required final String label,
  required final IconData icon,
  final IconData? selectedIcon,
  final bool hasNotification = false,

  /// When set, overrides all icon rendering with a custom widget builder.
  /// Takes the resolved icon [color] and [size] as arguments.
  final Widget Function(Color color, double size)? iconBuilder,
  final String? tooltipLabel,
});

/// Navigation panel widget
class const NavigationPanel({
  super.key,
  required final List<NavItem> items,
  required final int selectedIndex,
  required final ValueChanged<int> onItemSelected,
  required final NavBarPosition position,
  required final NavBarAppearance appearance,
  required final GradientAnimation gradientAnimation,
  final bool forceCollapsed = false,
  final Set<int> lockedIndices = const {},
}) extends ConsumerWidget {
  bool get _isHorizontal =>
      position == NavBarPosition.top || position == NavBarPosition.bottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectiveTheme = ref.watch(themeProvider);
    final expansionMode = ref.watch(
      appShellSettingsProvider.select((settings) => settings.navExpansionMode),
    );
    final isCollapsed =
        forceCollapsed || expansionMode == NavExpansionMode.collapsed;
    final arrangement = _isHorizontal
        ? ref.watch(navButtonArrangementHProvider)
        : ref.watch(navButtonArrangementVProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: effectiveTheme.navBackground,
        boxShadow: [
          BoxShadow(
            color: effectiveTheme.border.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRect(
        child: RepaintBoundary(
          child: PanelPatternSurface(
            child: Column(
              mainAxisSize: _isHorizontal ? MainAxisSize.min : MainAxisSize.max,
              children: [
                _isHorizontal
                    ? _buildHorizontal(isCollapsed, arrangement, expansionMode)
                    : _buildVertical(isCollapsed, arrangement, expansionMode),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontal(
    bool isCollapsed,
    NavButtonArrangement arrangement,
    NavExpansionMode expansionMode,
  ) {
    final isSplit = _isSplit(arrangement);
    return SizedBox(
      height: kNavigationPanelHorizontalExtent,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Keep both gradient controls accessible when expanded labels
            // need more space than a narrow horizontal panel can provide.
            final groupSpace =
                (constraints.maxWidth -
                        (forceCollapsed ? 48 : 88) -
                        kElementHSpacing * (isSplit ? 2 : 1))
                    .clamp(0.0, double.infinity);
            // Each button, the More button included, takes an equal share.
            Widget buildGroup(List<int> indices) => ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: groupSpace * indices.length / (items.length + 1),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _buildPageButtonContainer(
                  indices: indices,
                  isHorizontal: true,
                  isCollapsed: isCollapsed,
                  expansionMode: expansionMode,
                ),
              ),
            );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _arrangedChildren(
                arrangement,
                buildGroup,
                const SizedBox(width: kElementHSpacing),
              ),
            );
          },
        ),
      ),
    );
  }

  bool _isSplit(NavButtonArrangement arrangement) =>
      arrangement == NavButtonArrangement.split &&
      _trailingGroupIndices.isNotEmpty;

  /// Page button groups around the theme selector, in the chosen arrangement.
  List<Widget> _arrangedChildren(
    NavButtonArrangement arrangement,
    Widget Function(List<int> indices) buildGroup,
    Widget gap,
  ) {
    final isSplit = _isSplit(arrangement);
    final atEnd = arrangement == NavButtonArrangement.end;
    return [
      if (!atEnd) ...[
        buildGroup(isSplit ? _leadingGroupIndices : _allGroupIndices),
        gap,
      ],
      Expanded(
        child: _ThemeSelector(
          position: position,
          gradientAnimation: gradientAnimation,
          showExpansionControl: !forceCollapsed,
        ),
      ),
      if (isSplit) ...[gap, buildGroup(_trailingGroupIndices)],
      if (atEnd) ...[gap, buildGroup(_allGroupIndices)],
    ];
  }

  /// The More menu button's place among the indices, after every page.
  int get _menuIndex => items.length;

  /// Library and Add make the first group when the buttons are split.
  int get _leadingCount => items.length < 2 ? items.length : 2;

  List<int> get _leadingGroupIndices => [
    for (var i = 0; i < _leadingCount; i++) i,
  ];

  List<int> get _allGroupIndices => [for (var i = 0; i <= _menuIndex; i++) i];

  /// The rest (Settings), then the More menu button.
  List<int> get _trailingGroupIndices => [
    for (var i = _leadingCount; i <= _menuIndex; i++) i,
  ];

  Widget _buildPageButtonContainer({
    required List<int> indices,
    required bool isHorizontal,
    required bool isCollapsed,
    required NavExpansionMode expansionMode,
  }) => NavButtonGroup(
    isHorizontal: isHorizontal,
    accented: true,
    children: [
      for (final index in indices)
        if (index == _menuIndex)
          NavigationMoreMenuButton(position: position)
        else
          _buildIndexedNavButton(
            index,
            isHorizontal,
            isCollapsed,
            expansionMode,
          ),
    ],
  );

  Widget _buildIndexedNavButton(
    int index,
    bool isHorizontal,
    bool isCollapsed,
    NavExpansionMode expansionMode,
  ) => _NavButton(
    key: ValueKey<String>('nav-button-${items[index].label}'),
    item: items[index],
    isSelected: index == selectedIndex,
    onTap: () => onItemSelected(index),
    appearance: appearance,
    isHorizontal: isHorizontal,
    isCollapsed:
        isCollapsed ||
        (expansionMode == NavExpansionMode.automatic && index != selectedIndex),
    isLocked: lockedIndices.contains(index),
  );

  Widget _buildVertical(
    bool isCollapsed,
    NavButtonArrangement arrangement,
    NavExpansionMode expansionMode,
  ) {
    Widget buildGroup(List<int> indices) => _buildPageButtonContainer(
      indices: indices,
      isHorizontal: false,
      isCollapsed: isCollapsed,
      expansionMode: expansionMode,
    );
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: _arrangedChildren(
            arrangement,
            buildGroup,
            const SizedBox(height: kElementVSpacing),
          ),
        ),
      ),
    );
  }
}

class const _ThemeSelector({
  required final NavBarPosition position,
  required final GradientAnimation gradientAnimation,
  required final bool showExpansionControl,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.appTheme;
    final expansionMode = ref.watch(
      appShellSettingsProvider.select((settings) => settings.navExpansionMode),
    );
    final isHorizontal =
        position == NavBarPosition.top || position == NavBarPosition.bottom;

    final isVert = !isHorizontal;
    return ClipRRect(
      borderRadius: BorderRadius.circular(theme.cornerRadius * 1.5),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedGradientBar(
            theme: theme,
            animationStyle: gradientAnimation,
            isVertical: isVert,
            width: isVert ? double.infinity : null,
            autoPauseWhenNotVisible: true,
            flipWaveForLeftVertical: position == NavBarPosition.left,
          ),
          if (showExpansionControl)
            Align(
              alignment: isVert ? Alignment.topCenter : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: SizedBox(
                  width: isVert ? double.infinity : 40,
                  height: 40,
                  child: GradientBarIconButton(
                    key: const ValueKey('nav-expansion-mode'),
                    tooltip:
                        'Navigation button style: ${expansionMode.displayName}',
                    onPressed: () => ref
                        .read(settingsProvider.notifier)
                        .set(SettingsKeys.navExpansionMode, expansionMode.next),
                    icon: switch (expansionMode) {
                      NavExpansionMode.automatic => Icons.dynamic_feed_rounded,
                      NavExpansionMode.expanded => Icons.unfold_more_rounded,
                      NavExpansionMode.collapsed => Icons.unfold_less_rounded,
                    },
                  ),
                ),
              ),
            ),
          Align(
            alignment: isVert ? Alignment.bottomCenter : Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: SizedBox(
                width: isVert ? double.infinity : 40,
                height: 40,
                child: NavigationThemeMenuButton(position: position),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class const _NavButton({
  super.key,
  required final NavItem item,
  required final bool isSelected,
  required final VoidCallback onTap,
  required final NavBarAppearance appearance,
  required final bool isHorizontal,
  required final bool isCollapsed,
  required final bool isLocked,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final textOnly = appearance == NavBarAppearance.textOnly;
    final showText = !isCollapsed && appearance != NavBarAppearance.iconOnly;
    final displayIcon = item.selectedIcon ?? item.icon;
    final tooltipText = isLocked
        ? '${item.tooltipLabel ?? item.label} (Locked during fetch)'
        : (isCollapsed ? (item.tooltipLabel ?? item.label) : '');

    Widget Function(BuildContext, Color, double)? iconBuilder;
    if (!isLocked) {
      if (item.iconBuilder != null) {
        iconBuilder = (context, color, size) => item.iconBuilder!(color, size);
      }
    }

    return AppNavigationButton(
      isSelected: isSelected,
      isEnabled: !isLocked,
      hasNotification: item.hasNotification,
      isHorizontal: isHorizontal,
      onTap: onTap,
      // Text-only buttons keep their icon mounted and shrink it away as the
      // label grows, so automatic expansion morphs instead of jumping.
      iconData: isLocked ? Icons.lock_rounded : displayIcon,
      hideIconWithLabel: textOnly,
      iconBuilder: iconBuilder,
      labelText: item.label,
      labelVisible: showText,
      labelFadeDuration: kNavButtonExpandAnimation,
      labelFadeCurve: kNavButtonExpandCurve,
      tooltipMessage: tooltipText.isEmpty ? null : tooltipText,
    );
  }
}
