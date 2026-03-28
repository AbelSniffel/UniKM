/// Navigation panel widget with configurable position and appearance
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import 'badge.dart';
import 'hover_builder.dart';

const kNavigationPanelCollapsedWidth = 56.0;
const kNavigationPanelExpandedWidth = 95.0;

/// Navigation item data
class NavItem {
  const NavItem({
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.badgeCount,
    this.pulsate = false,
  });
  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final int? badgeCount;
  /// When true, the nav icon pulsates to signal an active notification.
  final bool pulsate;
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
    this.lockedIndices = const {},
  });

  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final AppThemeData theme;
  final NavBarPosition position;
  final NavBarAppearance appearance;
  final GradientAnimation gradientAnimation;
  final Set<int> lockedIndices;

  bool get _isHorizontal =>
      position == NavBarPosition.top || position == NavBarPosition.bottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCollapsed = ref.watch(
      appShellSettingsProvider.select((s) => s.navBarCollapsed),
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.navBackground,
        boxShadow: [
          BoxShadow(
            color: theme.border.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: _isHorizontal ? MainAxisSize.min : MainAxisSize.max,
        children: [
          _isHorizontal
              ? _buildHorizontal(ref, isCollapsed)
              : _buildVertical(ref, isCollapsed),
        ],
      ),
    );
  }

  Widget _buildHorizontal(WidgetRef ref, bool isCollapsed) {
    final centerButtons = ref.watch(navBarCenterButtonsProvider);
    final alignToEdge = _isHorizontal && !centerButtons;

    // When `centerButtons` is true the whole group (nav buttons plus a
    // hidden spacer for the theme selector) is centered; otherwise it sits
    // flush to the left.  The collapse button and visible theme selector
    // remain pinned to the edges in either state.
    final group = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildNavButtonsRow(isCollapsed),
        _buildControlsRow(isCollapsed, alignToEdge: alignToEdge),
      ],
    );

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedAlign(
            alignment:
                centerButtons ? Alignment.center : Alignment.centerLeft,
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeInOutCubicEmphasized,
            child: group,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: _CollapseButton(
                theme: theme,
                isCollapsed: isCollapsed,
                position: position,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _ThemeSelector(
                theme: theme,
                position: position,
                isCollapsed: isCollapsed,
                alignToEdge: alignToEdge,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButtonsRow(bool isCollapsed) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Invisible placeholder for the anchored collapse button so the
        // horizontal layout reserves space and nav buttons do not overlap it.
        Visibility(
          visible: false,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _CollapseButton(
              theme: theme,
              isCollapsed: isCollapsed,
              position: position,
            ),
          ),
        ),
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _NavButton(
              items[i],
              i == selectedIndex,
              () => onItemSelected(i),
              theme,
              appearance,
              true,
              isCollapsed,
              lockedIndices.contains(i),
            ),
          ),
      ],
    );
  }

  Widget _buildControlsRow(bool isCollapsed, {required bool alignToEdge}) {
    // hidden theme selector used solely to reserve space when the nav
    // buttons animate between left/center alignment.
    return Visibility(
      visible: false,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: _ThemeSelector(
        theme: theme,
        position: position,
        isCollapsed: isCollapsed,
        alignToEdge: alignToEdge,
      ),
    );
  }

  Widget _buildVertical(WidgetRef ref, bool isCollapsed) {
    return Expanded(
      child: Column(
        children: [
          const SizedBox(height: 8),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: SizedBox(
                width: double.infinity,
                child: _NavButton(
                  items[i],
                  i == selectedIndex,
                  () => onItemSelected(i),
                  theme,
                  appearance,
                  false,
                  isCollapsed,
                  lockedIndices.contains(i),
                ),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(8),
            child: _ThemeSelector(
              theme: theme,
              position: position,
              isCollapsed: isCollapsed,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: _CollapseButton(
              theme: theme,
              isCollapsed: isCollapsed,
              position: position,
            ),
          ),
        ],
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
    this.size = 20,
  });

  final AppThemeData theme;
  final bool toggled;
  final IconData iconToggled;
  final IconData iconUntoggled;
  final String tooltipToggled;
  final String tooltipUntoggled;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: toggled ? tooltipToggled : tooltipUntoggled,
      child: HoverPressBuilder(
        onTap: onTap,
        builder: (context, hovered, _) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: hovered ? theme.navItemHover : theme.navItemHover.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(theme.cornerRadius),
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
            ),
          ),
        ),
      ),
    );
  }
}

class _CollapseButton extends ConsumerWidget {
  const _CollapseButton({
    required this.theme,
    required this.isCollapsed,
    required this.position,
  });
  final AppThemeData theme;
  final bool isCollapsed;
  final NavBarPosition position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MorphingIconButton(
      theme: theme,
      toggled: isCollapsed,
      iconToggled: Icons.chevron_right,
      iconUntoggled: Icons.chevron_left,
      tooltipToggled: 'Expand navigation',
      tooltipUntoggled: 'Collapse navigation',
      onTap: () => ref.read(settingsProvider.notifier).setSetting(SettingsKeys.navBarCollapsed, !isCollapsed),
    );
  }
}

class _ThemeSelector extends ConsumerStatefulWidget {
  const _ThemeSelector({
    required this.theme,
    required this.position,
    this.isCollapsed = false,
    this.alignToEdge = false,
  });
  final AppThemeData theme;
  final NavBarPosition position;
  final bool isCollapsed;
  final bool alignToEdge;

  @override
  ConsumerState<_ThemeSelector> createState() => _ThemeSelectorState();
}

class _ThemeSelectorState extends ConsumerState<_ThemeSelector> {
  RelativeRect _menuPosition() {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final button = context.findRenderObject() as RenderBox;

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

    final selected = await showMenu<AppThemeData>(
      context: context,
      position: _menuPosition(),
      color: widget.theme.surface,
      elevation: 10,
      constraints: const BoxConstraints(maxWidth: 250),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
        side: BorderSide(color: widget.theme.border),
      ),
      items: [
        PopupMenuItem<AppThemeData>(
          enabled: false,
          height: 28,
          child: Text(
            'Select Theme',
            style: TextStyle(
              color: widget.theme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (final t in allThemes)
          PopupMenuItem<AppThemeData>(
            value: t,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: _ThemeMenuItem(
              data: t,
              selected: current.id == t.id,
              theme: widget.theme,
            ),
          ),
      ],
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
    final icon = Icon(current.icon, color: widget.theme.accent, size: 24);

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
            borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
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
    return Row(
      children: [
        Icon(
          data.icon,
          size: 18,
          color: selected ? theme.accent : theme.textSecondary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            data.name,
            style: TextStyle(
              color: selected ? theme.textPrimary : theme.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
        Container(
          width: 40,
          height: 16,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [data.background, data.primary, data.accent],
            ),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: theme.border, width: 0.5),
          ),
        ),
        if (selected) ...[
          const SizedBox(width: 8),
          Icon(Icons.check, size: 16, color: theme.accent),
        ],
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton(
    this.item,
    this.isSelected,
    this.onTap,
    this.theme,
    this.appearance,
    this.isHorizontal,
    this.isCollapsed,
    this.isLocked,
  );
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

    Widget button = AppNavigationButton(
      theme: theme,
      variant: AppNavigationButtonVariant.navigation,
      isSelected: isSelected,
      isEnabled: !isLocked,
      isHorizontal: isHorizontal,
      onTap: onTap,
      iconData: showIcon ? (isLocked ? Icons.lock_rounded : displayIcon) : null,
      iconBuilder: showIcon && item.pulsate && !isLocked
          ? (context, color, size) => Icon(
              displayIcon,
              color: color,
              size: size,
            ).animate(
              onPlay: (controller) => controller.repeat(reverse: true),
            ).custom(
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeInOutQuad,
              builder: (context, value, _) => Icon(
                displayIcon,
                color: Color.lerp(color, theme.primary, value),
                size: size,
              ),
            )
          : null,
      labelText: showText ? item.label : null,
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
