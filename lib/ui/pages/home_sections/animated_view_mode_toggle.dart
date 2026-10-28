/// Game Library button that shows and switches the current grid/list view.
library;

import 'package:flutter/material.dart';

import '../../../core/services/platform_file_actions.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/popup_menu_helpers.dart';

class AnimatedViewModeToggle extends StatefulWidget {
  const AnimatedViewModeToggle({
    super.key,
    required this.theme,
    required this.isGridView,
    required this.selectedListViewMode,
    required this.onToggle,
    required this.onSelectListViewMode,
    required this.onSelectGridView,
  });

  final AppThemeData theme;
  final bool isGridView;
  final ListViewDensityMode selectedListViewMode;
  final VoidCallback onToggle;
  final VoidCallback onSelectGridView;
  final ValueChanged<ListViewDensityMode> onSelectListViewMode;

  @override
  State<AnimatedViewModeToggle> createState() => _AnimatedViewModeToggleState();
}

class _AnimatedViewModeToggleState extends State<AnimatedViewModeToggle> {
  void _handleTap() => widget.onToggle();

  Future<void> _showContextMenu(Offset globalPosition) async {
    final allowRegularListView = !PlatformFileActions.isMobilePlatform;
    final availableModes = [
      if (allowRegularListView) ListViewDensityMode.regular,
      ListViewDensityMode.slim,
    ];
    final action = await showAppMenu<String>(
      context: context,
      position: overlayMenuPosition(context, globalPosition & const Size(1, 1)),
      items: [
        CheckedPopupMenuItem<String>(
          value: GameListViewMode.grid.name,
          checked: widget.isGridView,
          child: const Text('Grid view'),
        ),
        for (final mode in availableModes)
          CheckedPopupMenuItem<String>(
            value: mode.name,
            checked: !widget.isGridView && widget.selectedListViewMode == mode,
            child: Text('${mode.displayName} list view'),
          ),
      ],
    );

    if (!mounted || action == null) return;

    if (action == GameListViewMode.grid.name) {
      widget.onSelectGridView();
      return;
    }

    final selectedMode = ListViewDensityMode.values.firstWhere(
      (mode) => mode.name == action,
      orElse: () => widget.selectedListViewMode,
    );

    if (widget.isGridView || selectedMode != widget.selectedListViewMode) {
      widget.onSelectListViewMode(selectedMode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentViewIcon = widget.isGridView ? Icons.apps : Icons.view_list;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => _showContextMenu(details.globalPosition),
      onLongPressStart: (details) => _showContextMenu(details.globalPosition),
      child: AppNavigationButton(
        theme: widget.theme,
        isSelected: false,
        isEnabled: true,
        isHorizontal: true,
        onTap: _handleTap,
        tooltipMessage: widget.isGridView
            ? 'Switch to list view'
            : 'Switch to grid view',
        iconBuilder: (context, color, size) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(scale: anim, child: child),
          ),
          child: Icon(
            currentViewIcon,
            key: ValueKey<IconData>(currentViewIcon),
            color: widget.theme.accent,
            size: size,
          ),
        ),
      ),
    );
  }
}
