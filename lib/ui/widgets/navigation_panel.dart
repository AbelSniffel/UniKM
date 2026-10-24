/// Navigation panel widget with configurable position and appearance
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
export '../../core/constants/app_constants.dart'
    show kNavigationPanelHorizontalExtent;
import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import 'animated_gradient_bar.dart';
import 'navigation_panel_overlay.dart';
import 'navigation_theme_menu.dart';

const kNavigationPanelCollapsedWidth = 64.0;
const kNavigationPanelExpandedWidth = 108.0;
const kNavigationPanelGradientHeight = 48.0;

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
class NavItem {
  const NavItem({
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.hasNotification = false,
    this.iconBuilder,
    this.tooltipLabel,
  });
  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final bool hasNotification;
  final String? tooltipLabel;

  /// When set, overrides all icon rendering with a custom widget builder.
  /// Takes the resolved icon [color] and [size] as arguments.
  final Widget Function(Color color, double size)? iconBuilder;
}

/// Navigation panel widget
class NavigationPanel extends ConsumerWidget {
  const NavigationPanel({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.theme,
    required this.position,
    required this.appearance,
    required this.gradientAnimation,
    this.forceCollapsed = false,
    this.lockedIndices = const {},
  });

  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final AppThemeData theme;
  final NavBarPosition position;
  final NavBarAppearance appearance;
  final GradientAnimation gradientAnimation;
  final bool forceCollapsed;
  final Set<int> lockedIndices;

  bool get _isHorizontal =>
      position == NavBarPosition.top || position == NavBarPosition.bottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectiveTheme = ref.watch(effectiveThemeProvider);
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
          child: NavigationPanelOverlayPaint(
            theme: effectiveTheme,
            isHorizontal: _isHorizontal,
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
    final isSplit =
        arrangement == NavButtonArrangement.split &&
        _trailingGroupIndices.isNotEmpty;
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
            Widget buildGroup(List<int> indices) => ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: items.isEmpty
                    ? 0
                    : groupSpace * indices.length / items.length,
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
              children: [
                if (arrangement != NavButtonArrangement.end) ...[
                  buildGroup(isSplit ? _leadingGroupIndices : _allGroupIndices),
                  const SizedBox(width: kElementHSpacing),
                ],
                Expanded(
                  child: _ThemeSelector(
                    theme: theme,
                    position: position,
                    gradientAnimation: gradientAnimation,
                    showExpansionControl: !forceCollapsed,
                  ),
                ),
                if (isSplit) ...[
                  const SizedBox(width: kElementHSpacing),
                  buildGroup(_trailingGroupIndices),
                ],
                if (arrangement == NavButtonArrangement.end) ...[
                  const SizedBox(width: kElementHSpacing),
                  buildGroup(_allGroupIndices),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  List<int> get _leadingGroupIndices {
    final limit = items.length < 2 ? items.length : 2;
    return [for (var i = 0; i < limit; i++) i];
  }

  List<int> get _allGroupIndices => [for (var i = 0; i < items.length; i++) i];

  List<int> get _trailingGroupIndices {
    if (items.length <= 2) {
      return const [];
    }
    return [for (var i = 2; i < items.length; i++) i];
  }

  Widget _buildPageButtonContainer({
    required List<int> indices,
    required bool isHorizontal,
    required bool isCollapsed,
    required NavExpansionMode expansionMode,
  }) {
    final buttonChildren = [
      for (var itemIndex = 0; itemIndex < indices.length; itemIndex++) ...[
        if (itemIndex > 0)
          isHorizontal ? const SizedBox(width: 4) : const SizedBox(height: 4),
        isHorizontal
            ? _buildIndexedNavButton(
                indices[itemIndex],
                true,
                isCollapsed,
                expansionMode,
              )
            : SizedBox(
                width: double.infinity,
                child: _buildIndexedNavButton(
                  indices[itemIndex],
                  false,
                  isCollapsed,
                  expansionMode,
                ),
              ),
      ],
    ];

    final content = Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(theme.cornerRadius * 1.5),
      ),
      child: isHorizontal
          ? Row(mainAxisSize: MainAxisSize.min, children: buttonChildren)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: buttonChildren,
            ),
    );

    if (isHorizontal) {
      return content;
    }

    return SizedBox(width: double.infinity, child: content);
  }

  Widget _buildIndexedNavButton(
    int index,
    bool isHorizontal,
    bool isCollapsed,
    NavExpansionMode expansionMode,
  ) {
    return _NavButton(
      key: ValueKey<String>('nav-button-${items[index].label}'),
      item: items[index],
      isSelected: index == selectedIndex,
      onTap: () => onItemSelected(index),
      theme: theme,
      appearance: appearance,
      isHorizontal: isHorizontal,
      isCollapsed:
          isCollapsed ||
          (expansionMode == NavExpansionMode.automatic &&
              index != selectedIndex),
      isLocked: lockedIndices.contains(index),
    );
  }

  Widget _buildVertical(
    bool isCollapsed,
    NavButtonArrangement arrangement,
    NavExpansionMode expansionMode,
  ) {
    final isSplit =
        arrangement == NavButtonArrangement.split &&
        _trailingGroupIndices.isNotEmpty;
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
          children: [
            if (arrangement != NavButtonArrangement.end) ...[
              buildGroup(isSplit ? _leadingGroupIndices : _allGroupIndices),
              const SizedBox(height: kElementVSpacing),
            ],
            Expanded(
              child: _ThemeSelector(
                theme: theme,
                position: position,
                gradientAnimation: gradientAnimation,
                showExpansionControl: !forceCollapsed,
              ),
            ),
            if (isSplit) ...[
              const SizedBox(height: kElementVSpacing),
              buildGroup(_trailingGroupIndices),
            ],
            if (arrangement == NavButtonArrangement.end) ...[
              const SizedBox(height: kElementVSpacing),
              buildGroup(_allGroupIndices),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThemeSelector extends ConsumerWidget {
  const _ThemeSelector({
    required this.theme,
    required this.position,
    required this.gradientAnimation,
    required this.showExpansionControl,
  });
  final AppThemeData theme;
  final NavBarPosition position;
  final GradientAnimation gradientAnimation;
  final bool showExpansionControl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            height: kNavigationPanelGradientHeight,
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
                  child: Material(
                    color: Colors.transparent,
                    child: IconButton(
                      key: const ValueKey('nav-expansion-mode'),
                      tooltip:
                          'Navigation button style: ${expansionMode.displayName}',
                      onPressed: () => ref
                          .read(settingsProvider.notifier)
                          .setSetting(
                            SettingsKeys.navExpansionMode,
                            expansionMode.next,
                          ),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(40, 40),
                        padding: const EdgeInsets.all(8),
                        foregroundColor: theme.textSecondary,
                        hoverColor: theme.navItemHover,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            theme.cornerRadius * 1.5,
                          ),
                        ),
                      ),
                      icon: Icon(switch (expansionMode) {
                        NavExpansionMode.automatic =>
                          Icons.dynamic_feed_rounded,
                        NavExpansionMode.expanded => Icons.unfold_more_rounded,
                        NavExpansionMode.collapsed => Icons.unfold_less_rounded,
                      }, size: 24),
                    ),
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
                child: NavigationThemeMenuButton(
                  theme: theme,
                  position: position,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    super.key,
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.theme,
    required this.appearance,
    required this.isHorizontal,
    required this.isCollapsed,
    required this.isLocked,
  });

  final NavItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final AppThemeData theme;
  final NavBarAppearance appearance;
  final bool isHorizontal;
  final bool isCollapsed;
  final bool isLocked;

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
      theme: theme,
      variant: AppNavigationButtonVariant.navigation,
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
