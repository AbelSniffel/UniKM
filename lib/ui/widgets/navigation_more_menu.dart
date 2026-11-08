/// The navigation panel's More menu: the library view and Updates.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/application/update_controller.dart';
import '../../core/services/platform_file_actions.dart';
import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import 'app_progress_indicator.dart';
import 'popup_menu_helpers.dart';

/// Where a navigation panel menu opens: beside a side panel, and past the
/// edge of a top or bottom one.
({Alignment alignment, Offset offset}) navigationMenuPlacement(
  NavBarPosition position,
) => (
  alignment: position == NavBarPosition.left
      ? Alignment.topRight
      : Alignment.bottomLeft,
  offset: switch (position) {
    NavBarPosition.left || NavBarPosition.right => const Offset(8, 0),
    NavBarPosition.top || NavBarPosition.bottom => const Offset(0, 8),
  },
);

/// The meatball button that ends the navigation panel's last button group.
/// It carries the Updates dot.
class NavigationMoreMenuButton extends ConsumerStatefulWidget {
  const NavigationMoreMenuButton({
    super.key,
    required this.theme,
    required this.position,
  });

  final AppThemeData theme;
  final NavBarPosition position;

  @override
  ConsumerState<NavigationMoreMenuButton> createState() =>
      _NavigationMoreMenuButtonState();
}

class _NavigationMoreMenuButtonState
    extends ConsumerState<NavigationMoreMenuButton> {
  final _menu = MenuController();
  final _focusNode = FocusNode(skipTraversal: true);

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    if (_menu.isOpen) return _menu.close();
    // Focus lets Escape close the menu again.
    _focusNode.requestFocus();
    _menu.open();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final grid = ref.watch(viewModeProvider) == GameListViewMode.grid;
    final density = resolveListViewDensityMode(
      slimListView: ref.watch(
        gameCardSettingsProvider.select((s) => s.slimListView),
      ),
    );
    final updateDot = ref.watch(
      pageNotificationsProvider.select((s) => s.contains(NavItem.updates)),
    );
    final placement = navigationMenuPlacement(widget.position);
    return AppMenuAnchor(
      theme: theme,
      controller: _menu,
      childFocusNode: _focusNode,
      alignment: placement.alignment,
      alignmentOffset: placement.offset,
      menuChildren: [
        appMenuItem(
          theme,
          selected: grid,
          leading: const Icon(Icons.apps, size: 18),
          onPressed: () => ref
              .read(viewModeProvider.notifier)
              .setViewMode(GameListViewMode.grid),
          child: const Text('Grid view'),
        ),
        for (final mode in [
          if (!PlatformFileActions.isMobilePlatform)
            ListViewDensityMode.regular,
          ListViewDensityMode.slim,
        ])
          appMenuItem(
            theme,
            selected: !grid && density == mode,
            leading: Icon(
              mode == ListViewDensityMode.slim
                  ? Icons.view_headline
                  : Icons.view_list,
              size: 18,
            ),
            onPressed: () => ref.read(settingsProvider.notifier).setMany({
              ...listViewDensityModeSettings(mode),
              SettingsKeys.gameListViewMode: GameListViewMode.list,
            }),
            child: Text('${mode.displayName} list view'),
          ),
        appMenuDivider(theme),
        appMenuItem(
          theme,
          leading: _UpdateIcon(theme: theme),
          onPressed: () =>
              ref.read(updateDialogOpenProvider.notifier).set(true),
          child: const Text('Updates'),
        ),
      ],
      builder: (context, controller, _) => Focus(
        focusNode: _focusNode,
        child: Semantics(
          expanded: controller.isOpen,
          child: AppNavigationButton(
            key: const ValueKey('nav-more-menu'),
            theme: theme,
            isSelected: false,
            isEnabled: true,
            isHorizontal:
                widget.position == NavBarPosition.top ||
                widget.position == NavBarPosition.bottom,
            onTap: _toggleMenu,
            iconData: Icons.more_horiz_rounded,
            labelVisible: false,
            hasNotification: updateDot,
            tooltipMessage: 'More',
          ),
        ),
      ),
    );
  }
}

/// Updates' state: a spinner while checking or downloading, and the accent
/// while an update waits. It watches only while the menu is open.
class _UpdateIcon extends ConsumerWidget {
  const _UpdateIcon({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (:busy, :ready) = ref.watch(
      updateProvider.select(
        (s) => (
          busy: s.isChecking || s.isDownloading,
          ready: s.downloadedFilePath != null,
        ),
      ),
    );
    final available = ref.watch(
      pageNotificationsProvider.select((s) => s.contains(NavItem.updates)),
    );
    if (busy) return const AppCircularProgressIndicator.icon(size: 18);
    return Icon(
      ready ? Icons.file_download_done : Icons.download_rounded,
      size: 18,
      color: ready || available ? theme.accent : null,
    );
  }
}
