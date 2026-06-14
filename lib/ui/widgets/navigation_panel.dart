/// Navigation panel widget with configurable position and appearance
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import 'animated_gradient_bar.dart';
import 'badge.dart';
import 'hover_builder.dart';
import 'navigation_panel_overlay.dart';
import 'popup_menu_helpers.dart';

const kNavigationPanelCollapsedWidth = 56.0;
const kNavigationPanelExpandedWidth = 95.0;
const kNavigationPanelHorizontalExtent = 56.0;
const kNavigationPanelInnerGradientCollapsedWidth = 64.0;
const kNavigationPanelInnerGradientExpandedWidth = 108.0;
const kNavigationPanelInnerGradientExtent = 64.0;
const kNavigationPanelInnerGradientHorizontalRowHeight = 48.0;

/// Navigation item data
class NavItem {
  const NavItem({
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.badgeCount,
    this.iconBuilder,
  });
  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final int? badgeCount;

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
    final isCollapsed =
        forceCollapsed ||
        ref.watch(appShellSettingsProvider.select((s) => s.navBarCollapsed));
    final showCollapseButton = !forceCollapsed;
    final useInnerGradient = ref.watch(navPanelGradientBarProvider);
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
                    ? _buildHorizontal(
                        isCollapsed,
                        showCollapseButton,
                        useInnerGradient,
                        arrangement,
                      )
                    : _buildVertical(
                        isCollapsed,
                        showCollapseButton,
                        useInnerGradient,
                        arrangement,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontal(
    bool isCollapsed,
    bool showCollapseButton,
    bool useInnerGradient,
    NavButtonArrangement arrangement,
  ) {
    Widget buildGroup(List<int> indices) {
      if (useInnerGradient) {
        return _buildPageButtonContainer(
          indices: indices,
          isHorizontal: true,
          isCollapsed: isCollapsed,
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int k = 0; k < indices.length; k++) ...[
            if (k > 0) const SizedBox(width: 4),
            _buildIndexedNavButton(indices[k], true, isCollapsed),
          ],
        ],
      );
    }

    final effectiveArrangement =
        useInnerGradient && arrangement == NavButtonArrangement.center
        ? NavButtonArrangement.split
        : arrangement;
    final isSplit =
        effectiveArrangement == NavButtonArrangement.split &&
        _trailingGroupIndices.isNotEmpty;

    return SizedBox(
      height: useInnerGradient
          ? kNavigationPanelInnerGradientExtent
          : kNavigationPanelHorizontalExtent,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: useInnerGradient
              ? CrossAxisAlignment.stretch
              : CrossAxisAlignment.center,
          children: [
            if (showCollapseButton && !useInnerGradient)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _CollapseButton(
                  theme: theme,
                  isCollapsed: isCollapsed,
                  position: position,
                ),
              ),
            if (useInnerGradient) ...[
              if (effectiveArrangement != NavButtonArrangement.end) ...[
                buildGroup(isSplit ? _leadingGroupIndices : _allGroupIndices),
                const SizedBox(width: kElementHSpacing),
              ],
              Expanded(
                child: _ThemeSelector(
                  theme: theme,
                  position: position,
                  gradientAnimation: gradientAnimation,
                  alignToEdge: true,
                  isCollapsed: isCollapsed,
                  showCollapseButton: showCollapseButton,
                ),
              ),
              if (isSplit) ...[
                const SizedBox(width: kElementHSpacing),
                buildGroup(_trailingGroupIndices),
              ],
              if (effectiveArrangement == NavButtonArrangement.end) ...[
                const SizedBox(width: kElementHSpacing),
                buildGroup(_allGroupIndices),
              ],
            ] else ...[
              ...switch (effectiveArrangement) {
                NavButtonArrangement.start => [
                  buildGroup(_allGroupIndices),
                  const Spacer(),
                ],
                NavButtonArrangement.center => [
                  const Spacer(),
                  buildGroup(_allGroupIndices),
                  const Spacer(),
                ],
                NavButtonArrangement.split => [
                  buildGroup(isSplit ? _leadingGroupIndices : _allGroupIndices),
                  const Spacer(),
                  if (isSplit) buildGroup(_trailingGroupIndices),
                ],
                NavButtonArrangement.end => [
                  const Spacer(),
                  buildGroup(_allGroupIndices),
                ],
              },
              const SizedBox(width: 8),
              _ThemeSelector(
                theme: theme,
                position: position,
                isCollapsed: isCollapsed,
                alignToEdge:
                    !isSplit &&
                    effectiveArrangement != NavButtonArrangement.center,
              ),
            ],
          ],
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
  }) {
    final buttonChildren = [
      for (var itemIndex = 0; itemIndex < indices.length; itemIndex++) ...[
        if (itemIndex > 0)
          isHorizontal ? const SizedBox(width: 4) : const SizedBox(height: 4),
        isHorizontal
            ? _buildIndexedNavButton(indices[itemIndex], true, isCollapsed)
            : SizedBox(
                width: double.infinity,
                child: _buildIndexedNavButton(
                  indices[itemIndex],
                  false,
                  isCollapsed,
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
  ) {
    return _NavButton(
      key: ValueKey<String>('nav-button-${items[index].label}'),
      item: items[index],
      isSelected: index == selectedIndex,
      onTap: () => onItemSelected(index),
      theme: theme,
      appearance: appearance,
      isHorizontal: isHorizontal,
      isCollapsed: isCollapsed,
      isLocked: lockedIndices.contains(index),
    );
  }

  Widget _buildVertical(
    bool isCollapsed,
    bool showCollapseButton,
    bool useInnerGradient,
    NavButtonArrangement arrangement,
  ) {
    Widget buildGroup(List<int> indices) {
      if (useInnerGradient) {
        return _buildPageButtonContainer(
          indices: indices,
          isHorizontal: false,
          isCollapsed: isCollapsed,
        );
      }
      return SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int k = 0; k < indices.length; k++) ...[
              if (k > 0) const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: _buildIndexedNavButton(indices[k], false, isCollapsed),
              ),
            ],
          ],
        ),
      );
    }

    final effectiveArrangement =
        useInnerGradient && arrangement == NavButtonArrangement.center
        ? NavButtonArrangement.split
        : arrangement;
    final isSplit =
        effectiveArrangement == NavButtonArrangement.split &&
        _trailingGroupIndices.isNotEmpty;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            if (useInnerGradient) ...[
              if (effectiveArrangement != NavButtonArrangement.end) ...[
                buildGroup(isSplit ? _leadingGroupIndices : _allGroupIndices),
                const SizedBox(height: kElementVSpacing),
              ],
              Expanded(
                child: _ThemeSelector(
                  theme: theme,
                  position: position,
                  gradientAnimation: gradientAnimation,
                  isCollapsed: isCollapsed,
                  showCollapseButton: showCollapseButton,
                ),
              ),
              if (isSplit) ...[
                const SizedBox(height: kElementVSpacing),
                buildGroup(_trailingGroupIndices),
              ],
              if (effectiveArrangement == NavButtonArrangement.end) ...[
                const SizedBox(height: kElementVSpacing),
                buildGroup(_allGroupIndices),
              ],
            ] else ...[
              ...switch (effectiveArrangement) {
                NavButtonArrangement.start => [
                  buildGroup(_allGroupIndices),
                  const Spacer(),
                ],
                NavButtonArrangement.center => [
                  const Spacer(),
                  buildGroup(_allGroupIndices),
                  const Spacer(),
                ],
                NavButtonArrangement.split => [
                  buildGroup(isSplit ? _leadingGroupIndices : _allGroupIndices),
                  const Spacer(),
                  if (isSplit) buildGroup(_trailingGroupIndices),
                ],
                NavButtonArrangement.end => [
                  const Spacer(),
                  buildGroup(_allGroupIndices),
                ],
              },
              const SizedBox(height: kElementVSpacing),
              _ThemeSelector(
                theme: theme,
                position: position,
                isCollapsed: isCollapsed,
              ),
            ],
            if (showCollapseButton && !useInnerGradient) ...[
              const SizedBox(height: kElementVSpacing),
              SizedBox(
                width: double.infinity,
                child: _CollapseButton(
                  theme: theme,
                  isCollapsed: isCollapsed,
                  position: position,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Generic morphing icon button used by the nav bar collapse control and elsewhere.
class MorphingIconButton extends StatelessWidget {
  const MorphingIconButton({
    super.key,
    required this.theme,
    required this.toggled,
    required this.iconToggled,
    required this.iconUntoggled,
    required this.tooltipToggled,
    required this.tooltipUntoggled,
    required this.onTap,
    this.expandToParent = false,
  });

  final AppThemeData theme;
  final bool toggled;
  final IconData iconToggled;
  final IconData iconUntoggled;
  final String tooltipToggled;
  final String tooltipUntoggled;
  final VoidCallback onTap;
  final bool expandToParent;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: toggled ? tooltipToggled : tooltipUntoggled,
      child: HoverPressBuilder(
        onTap: onTap,
        builder: (context, hovered, _) {
          final decorated = AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hovered
                  ? theme.navItemHover
                  : theme.navItemHover.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(theme.cornerRadius * 1.5),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(scale: anim, child: child),
              ),
              child: Icon(
                toggled ? iconToggled : iconUntoggled,
                key: ValueKey<bool>(toggled),
                color: theme.textSecondary.withValues(
                  alpha: hovered ? 1.0 : 0.6,
                ),
              ),
            ),
          );

          if (!expandToParent) {
            return decorated;
          }

          return SizedBox.expand(child: decorated);
        },
      ),
    );
  }
}

class _CollapseButton extends ConsumerWidget {
  const _CollapseButton({
    required this.theme,
    required this.isCollapsed,
    required this.position,
    this.expandToParent = false,
  });
  final AppThemeData theme;
  final bool isCollapsed;
  final NavBarPosition position;
  final bool expandToParent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRightPanel = position == NavBarPosition.right;
    return MorphingIconButton(
      theme: theme,
      toggled: isCollapsed,
      iconToggled: isRightPanel ? Icons.chevron_left : Icons.chevron_right,
      iconUntoggled: isRightPanel ? Icons.chevron_right : Icons.chevron_left,
      tooltipToggled: 'Expand navigation',
      tooltipUntoggled: 'Collapse navigation',
      expandToParent: expandToParent,
      onTap: () => ref
          .read(settingsProvider.notifier)
          .setSetting(SettingsKeys.navBarCollapsed, !isCollapsed),
    );
  }
}

class _ThemeSelector extends ConsumerStatefulWidget {
  const _ThemeSelector({
    required this.theme,
    required this.position,
    this.isCollapsed = false,
    this.alignToEdge = false,
    this.gradientAnimation,
    this.showCollapseButton = false,
  });
  final AppThemeData theme;
  final NavBarPosition position;
  final bool isCollapsed;
  final bool alignToEdge;
  final bool showCollapseButton;
  final GradientAnimation? gradientAnimation;

  @override
  ConsumerState<_ThemeSelector> createState() => _ThemeSelectorState();
}

class _ThemeSelectorState extends ConsumerState<_ThemeSelector> {
  final GlobalKey _themeButtonKey = GlobalKey();

  PopupMenuItem<AppThemeData> _buildSectionHeader(String label) {
    return PopupMenuItem<AppThemeData>(
      enabled: false,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        label,
        style: TextStyle(
          color: widget.theme.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.45,
        ),
      ),
    );
  }

  PopupMenuItem<AppThemeData> _buildThemeOption(
    AppThemeData themeData,
    AppThemeData current,
  ) {
    return PopupMenuItem<AppThemeData>(
      value: themeData,
      height: 40,
      padding: EdgeInsets.zero,
      child: _ThemeMenuItem(
        data: themeData,
        selected: current.id == themeData.id,
        theme: widget.theme,
      ),
    );
  }

  List<PopupMenuEntry<AppThemeData>> _buildThemeSection({
    required List<AppThemeData> themes,
    required AppThemeData current,
  }) {
    return [
      for (final themeData in themes) _buildThemeOption(themeData, current),
    ];
  }

  RelativeRect _menuPosition() {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final buttonContext = _themeButtonKey.currentContext ?? context;
    final button = buttonContext.findRenderObject() as RenderBox;

    final buttonRect = Rect.fromPoints(
      button.localToGlobal(Offset.zero, ancestor: overlay),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero),
        ancestor: overlay,
      ),
    );

    final offset = switch (widget.position) {
      NavBarPosition.left => const Offset(8, 0),
      NavBarPosition.right => const Offset(-8, 0),
      NavBarPosition.top =>
        widget.alignToEdge ? const Offset(-8, 8) : const Offset(0, 8),
      NavBarPosition.bottom =>
        widget.alignToEdge ? const Offset(-8, -8) : const Offset(0, -8),
    };

    return RelativeRect.fromRect(
      buttonRect.shift(offset),
      Offset.zero & overlay.size,
    );
  }

  Future<void> _openMenu() async {
    ref.read(customThemesJsonProvider);
    final notifier = ref.read(themeProvider.notifier);
    final allThemes = notifier.getAllThemes();
    final current = ref.read(themeProvider);

    final builtInIds = kBuiltInThemes.map((t) => t.id).toSet();
    final builtInThemes = allThemes
        .where((t) => builtInIds.contains(t.id))
        .toList();
    final customThemes = allThemes
        .where((t) => !builtInIds.contains(t.id))
        .toList();

    final List<PopupMenuEntry<AppThemeData>> menuItems = [
      PopupMenuItem<AppThemeData>(
        enabled: false,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          'Theme Menu',
          style: TextStyle(
            color: widget.theme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      PopupMenuDivider(height: 1, color: widget.theme.border),
      _buildSectionHeader('Built-in Themes'),
      ..._buildThemeSection(themes: builtInThemes, current: current),
      if (customThemes.isNotEmpty) ...[
        PopupMenuDivider(height: 1, color: widget.theme.border),
        _buildSectionHeader('Custom Themes'),
        ..._buildThemeSection(themes: customThemes, current: current),
      ],
    ];

    final selected = await showAppMenu<AppThemeData>(
      context: context,
      position: _menuPosition(),
      initialValue: allThemes.firstWhere(
        (themeData) => themeData.id == current.id,
        orElse: () => current,
      ),
      constraints: BoxConstraints.tightFor(width: 180),
      popUpAnimationStyle: AnimationStyle.noAnimation,
      items: menuItems,
    );

    if (selected != null && mounted) {
      notifier.setTheme(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(themeProvider);
    final isHorizontal =
        widget.position == NavBarPosition.top ||
        widget.position == NavBarPosition.bottom;
    final icon = Icon(current.icon, color: widget.theme.accent);

    if (widget.gradientAnimation != null) {
      final isVert = !isHorizontal;
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.theme.cornerRadius * 1.5),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedGradientBar(
              theme: widget.theme,
              animationStyle: widget.gradientAnimation!,
              isVertical: isVert,
              height: kNavigationPanelInnerGradientHorizontalRowHeight,
              width: isVert ? double.infinity : null,
              autoPauseWhenNotVisible: true,
              flipWaveForLeftVertical: widget.position == NavBarPosition.left,
            ),
            if (widget.showCollapseButton)
              Align(
                alignment: isVert ? Alignment.topCenter : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: SizedBox(
                    width: isVert ? double.infinity : 40,
                    height: 40,
                    child: _CollapseButton(
                      theme: widget.theme,
                      isCollapsed: widget.isCollapsed,
                      position: widget.position,
                      expandToParent: true,
                    ),
                  ),
                ),
              ),
            Align(
              alignment: isVert
                  ? Alignment.bottomCenter
                  : Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: SizedBox(
                  key: _themeButtonKey,
                  width: isVert ? double.infinity : 40,
                  height: 40,
                  child: Tooltip(
                    message: 'Change theme',
                    child: HoverPressBuilder(
                      onTap: _openMenu,
                      builder: (context, hovered, _) => AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.all(8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: hovered
                              ? widget.theme.navItemHover
                              : widget.theme.navItemHover.withValues(alpha: 0),
                          borderRadius: BorderRadius.circular(
                            widget.theme.cornerRadius * 1.5,
                          ),
                        ),
                        child: Icon(
                          current.icon,
                          color: widget.theme.textSecondary.withValues(
                            alpha: hovered ? 1.0 : 0.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Tooltip(
      message: 'Change theme',
      child: HoverPressBuilder(
        onTap: _openMenu,
        builder: (context, hovered, _) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: isHorizontal || widget.isCollapsed ? 8 : 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: hovered
                ? widget.theme.navItemHover
                : widget.theme.navItemHover.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(
              widget.theme.cornerRadius * 1.5,
            ),
          ),
          child: isHorizontal
              ? icon
              : SizedBox(
                  width: double.infinity,
                  child: Center(child: icon),
                ),
        ),
      ),
    );
  }
}

class _ThemeMenuItem extends StatelessWidget {
  const _ThemeMenuItem({
    required this.data,
    required this.selected,
    required this.theme,
  });
  final AppThemeData data;
  final bool selected;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        children: [
          Icon(
            data.icon,
            size: 16,
            color: selected ? theme.accent : theme.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              data.name,
              style: TextStyle(
                color: selected ? theme.textPrimary : theme.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 46,
            height: 20,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [data.background, data.accent, data.secondary],
              ),
              borderRadius: BorderRadius.circular(theme.cornerRadius),
              border: Border.all(color: theme.border, width: 0.5),
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
    final showIcon = isCollapsed || appearance != NavBarAppearance.textOnly;
    final showText = !isCollapsed && appearance != NavBarAppearance.iconOnly;
    final displayIcon = item.selectedIcon ?? item.icon;
    final tooltipText = isLocked
        ? '${item.label} (Locked during fetch)'
        : (isCollapsed ? item.label : '');

    Widget Function(BuildContext, Color, double)? iconBuilder;
    if (showIcon && !isLocked) {
      if (item.iconBuilder != null) {
        iconBuilder = (context, color, size) => item.iconBuilder!(color, size);
      }
    }

    Widget button = AppNavigationButton(
      theme: theme,
      variant: AppNavigationButtonVariant.navigation,
      isSelected: isSelected,
      isEnabled: !isLocked,
      isHorizontal: isHorizontal,
      onTap: onTap,
      iconData: showIcon ? (isLocked ? Icons.lock_rounded : displayIcon) : null,
      iconBuilder: iconBuilder,
      labelText: item.label,
      labelVisible: showText,
      labelFadeDuration: kNavButtonExpandAnimation,
      labelFadeCurve: kNavButtonExpandCurve,
      tooltipMessage: tooltipText.isEmpty ? null : tooltipText,
    );

    if (item.badgeCount != null && item.badgeCount! > 0 && !isLocked) {
      button = button.withCountBadge(
        item.badgeCount!,
        theme: theme,
        fit: StackFit.passthrough,
      );
    }
    return button;
  }
}
