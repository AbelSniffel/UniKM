import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../pages/settings_sections/settings_theme_editor.dart';
import 'app_dialog.dart';
import 'app_tab_bar.dart';
import 'custom_theme_actions.dart';
import 'popup_menu_helpers.dart';
import 'theme_preview_card.dart';
import 'theme_picker_actions.dart';

/// A small, keyboard-accessible theme picker anchored to the navigation bar.
class NavigationThemeMenuButton extends ConsumerStatefulWidget {
  const NavigationThemeMenuButton({
    super.key,
    required this.theme,
    required this.position,
  });

  final AppThemeData theme;
  final NavBarPosition position;

  @override
  ConsumerState<NavigationThemeMenuButton> createState() =>
      _NavigationThemeMenuButtonState();
}

class _NavigationThemeMenuButtonState
    extends ConsumerState<NavigationThemeMenuButton> {
  final _controller = MenuController();
  final _buttonFocus = FocusNode();

  @override
  void dispose() {
    _buttonFocus.dispose();
    super.dispose();
  }

  void _openEditor({AppThemeData? existing}) {
    // Capture the theme before closing the picker. Responsive navigation can
    // replace this button while the editor's route is still open.
    final theme = ref.read(effectiveThemeProvider);
    _controller.close();
    showAppDialog<void>(
      context: context,
      builder: (_) => ThemeEditorDialog(theme: theme, existingTheme: existing),
    );
  }

  void _deleteTheme(AppThemeData theme) {
    _controller.close();
    deleteCustomThemeWithConfirmation(context, ref, theme.id, theme.name);
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(themeProvider);
    final theme = widget.theme;
    return MenuAnchor(
      controller: _controller,
      animated: !MediaQuery.disableAnimationsOf(context),
      childFocusNode: _buttonFocus,
      consumeOutsideTap: true,
      useRootOverlay: true,
      reservedPadding: const EdgeInsets.all(8),
      alignmentOffset: switch (widget.position) {
        NavBarPosition.left || NavBarPosition.right => const Offset(8, 0),
        NavBarPosition.top || NavBarPosition.bottom => const Offset(0, 8),
      },
      style: appMenuStyle(
        theme,
        alignment: widget.position == NavBarPosition.left
            ? Alignment.topRight
            : Alignment.bottomLeft,
      ),
      menuChildren: [
        _ThemePicker(
          onSelected: (selected) =>
              ref.read(themeProvider.notifier).setTheme(selected),
          onCreate: () => _openEditor(),
          onEdit: (selected) => _openEditor(existing: selected),
          onDelete: _deleteTheme,
        ),
      ],
      builder: (context, controller, _) => Material(
        color: Colors.transparent,
        child: IconButton(
          focusNode: _buttonFocus,
          tooltip: 'Change theme',
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          style: IconButton.styleFrom(
            minimumSize: const Size(40, 40),
            padding: const EdgeInsets.all(8),
            foregroundColor: theme.textSecondary,
            hoverColor: theme.navItemHover,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(theme.cornerRadius * 1.5),
            ),
          ),
          icon: Icon(current.icon, size: 24),
        ),
      ),
    );
  }
}

class _ThemePicker extends ConsumerStatefulWidget {
  const _ThemePicker({
    required this.onSelected,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
  });

  final ValueChanged<AppThemeData> onSelected;
  final VoidCallback onCreate;
  final ValueChanged<AppThemeData> onEdit;
  final ValueChanged<AppThemeData> onDelete;

  @override
  ConsumerState<_ThemePicker> createState() => _ThemePickerState();
}

class _ThemePickerState extends ConsumerState<_ThemePicker> {
  final _scrollControllers = <int, ScrollController>{};
  final _scrollStorage = PageStorageBucket();

  @override
  void dispose() {
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(customThemesJsonProvider);
    final theme = ref.watch(effectiveThemeProvider);
    final current = ref.watch(themeProvider);
    final builtInIds = ref.watch(builtInThemeIdsProvider);
    final builtInOverlay = ref.watch(navPanelOverlayStyleSettingProvider);
    final selectedTab = ref.watch(navigationThemeMenuTabProvider);
    final custom = ref
        .read(themeProvider.notifier)
        .getAllThemes()
        .where((data) => !builtInIds.contains(data.id))
        .toList();
    final themes = selectedTab == 0 ? kBuiltInThemes : custom;
    final canManageCurrent =
        selectedTab == 1 && !builtInIds.contains(current.id);
    final media = MediaQuery.of(context);
    final width = math.min(
      296.0,
      media.size.width - media.padding.horizontal - 16,
    );
    final columns = width >= 260 && media.textScaler.scale(13) <= 20 ? 2 : 1;
    final tileHeight = math.max(16.0, media.textScaler.scale(13) * 1.4) + 30;
    final rows = (themes.length / columns).ceil();
    final contentHeight = rows * tileHeight + math.max(0, rows - 1) * 6 + 6;
    final gridHeight = themes.isEmpty ? 104.0 : math.min(224.0, contentHeight);
    final tabLabelStyle = Theme.of(
      context,
    ).textTheme.labelLarge!.copyWith(fontWeight: FontWeight.bold);
    final tabHeight = ['Default', 'Custom']
        .map((label) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: tabLabelStyle),
            textDirection: Directionality.of(context),
            textScaler: media.textScaler,
          )..layout(maxWidth: (width - 20) / 2 - 16);
          final height = painter.height + 20;
          painter.dispose();
          return height;
        })
        .reduce(math.max);
    final footerHeight = math.max(36.0, media.textScaler.scale(13) * 1.5 + 16);
    // Outer padding and spacing above and below the grid.
    const verticalSpacing = 20.0 + 8 + 8;
    final height = math.min(
      gridHeight + tabHeight + footerHeight + verticalSpacing,
      media.size.height -
          media.padding.vertical -
          media.viewInsets.vertical -
          16,
    );

    // Lay out the list at its destination size throughout the height animation.
    // Changing the viewport on each frame would clamp bottom-aligned scrolling.
    final viewportHeight = height - tabHeight - footerHeight - verticalSpacing;
    // Tabs and grid at the destination height, above the footer row.
    final panelHeight = height - footerHeight - 20 - 8;
    final activeIndex = themes.indexWhere((data) => data.id == current.id);
    final scrollController = _scrollControllers.putIfAbsent(
      selectedTab,
      () => ScrollController(
        initialScrollOffset: activeIndex < 0
            ? 0
            : ((activeIndex ~/ columns) * (tileHeight + 6)).clamp(
                0.0,
                math.max(0.0, contentHeight - viewportHeight),
              ),
      ),
    );

    return Focus(
      autofocus: true,
      child: AnimatedContainer(
        key: const ValueKey('navigation-theme-picker'),
        duration: media.disableAnimations ? Duration.zero : kTabTransition,
        curve: kTabTransitionCurve,
        width: width,
        height: height,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: width,
            maxWidth: width,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The tabs and grid keep their destination layout while the
                  // menu resizes; the footer below follows the animated edge.
                  Expanded(
                    child: ClipRect(
                      clipper: const _BottomEdgeClipper(),
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minHeight: panelHeight,
                        maxHeight: panelHeight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppTabBar(
                              theme: theme,
                              tabs: const [AppTab('Default'), AppTab('Custom')],
                              selectedIndex: selectedTab,
                              onChanged: ref
                                  .read(navigationThemeMenuTabProvider.notifier)
                                  .setIndex,
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: AppTabTransition(
                                index: selectedTab,
                                child: themes.isEmpty
                                    ? Center(
                                        child: Text(
                                          'No custom themes yet.\nCreate one from your current colors.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: theme.textSecondary,
                                            fontSize: 13,
                                          ),
                                        ),
                                      )
                                    : PageStorage(
                                        bucket: _scrollStorage,
                                        child: Scrollbar(
                                          controller: scrollController,
                                          child: GridView.builder(
                                            key: PageStorageKey(
                                              'navigation-theme-grid-$selectedTab',
                                            ),
                                            controller: scrollController,
                                            padding: const EdgeInsets.all(3),
                                            gridDelegate:
                                                SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount: columns,
                                                  mainAxisExtent: tileHeight,
                                                  mainAxisSpacing: 6,
                                                  crossAxisSpacing: 6,
                                                ),
                                            itemCount: themes.length,
                                            itemBuilder: (context, index) {
                                              final data = themes[index];
                                              final builtIn = builtInIds
                                                  .contains(data.id);
                                              return ThemePreviewCard(
                                                key: ValueKey(data.id),
                                                tapKey: ValueKey(
                                                  'navigation-theme-${data.id}',
                                                ),
                                                height: null,
                                                data: data,
                                                preview: builtIn
                                                    ? data.copyWith(
                                                        navPanelOverlayStyle:
                                                            builtInOverlay,
                                                      )
                                                    : data,
                                                selected: data.id == current.id,
                                                theme: theme,
                                                onTap: () =>
                                                    widget.onSelected(data),
                                                onDoubleTap: builtIn
                                                    ? null
                                                    : () => widget.onEdit(data),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ThemePickerActions(
                    theme: theme,
                    onCreate: widget.onCreate,
                    // Edit and Delete act on the active custom theme, on the
                    // Custom tab only.
                    onEdit: canManageCurrent
                        ? () => widget.onEdit(current)
                        : null,
                    onDelete: canManageCurrent
                        ? () => widget.onDelete(current)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Clips only below the bottom edge, so the content's shadows still show at
/// the sides and top while the footer covers what lies beneath.
class _BottomEdgeClipper extends CustomClipper<Rect> {
  const _BottomEdgeClipper();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-size.width, -size.height, size.width * 2, size.height);

  @override
  bool shouldReclip(_BottomEdgeClipper oldClipper) => false;
}
