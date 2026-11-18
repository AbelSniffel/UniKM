/// Pointer and selection interaction mixin for the library cards ([GameTile]).
///
/// Owns all pointer-tracking fields, event handlers and the context menu.
/// Uses an abstract [cardGame] getter, the card's game.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/game.dart';
import '../../providers/app_providers.dart';
import 'game_selection_actions.dart';
import 'popup_menu_helpers.dart';

/// Mixin that adds pointer-tracking and selection-orchestration logic to any
/// [ConsumerState].  The host state must implement [cardGame].
mixin GameCardInteractionMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  /// The [Game] this card represents.
  Game get cardGame;
  bool get dragSelectionHandledByParent => false;
  static const double _dragStartSlop = 6.0;

  // ── Pointer tracking state ─────────────────────────────────────────────────

  PointerDeviceKind _lastPointerKind = PointerDeviceKind.mouse;
  int? _activePrimaryPointer;
  Offset? _primaryPointerDownPosition;
  bool _primaryPointerExceededSlop = false;
  bool _primaryPointerHandledByLongPress = false;

  // ── Keyboard modifier helpers ─────────────────────────────────────────────

  bool get isCtrlPressed =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  bool get isShiftPressed => HardwareKeyboard.instance.isShiftPressed;

  /// Makes this card the anchor for the next range selection.
  void _markLastSelected() =>
      ref.read(lastSelectedGameIdProvider.notifier).set(cardGame.id);

  // ── Tap / double-tap / long-press ─────────────────────────────────────────

  void handleTap() {
    final notifier = ref.read(gamesProvider.notifier);
    final selectedIds = ref.read(
      gamesProvider.select((s) => s.selectedGameIds),
    );
    final lastId = ref.read(lastSelectedGameIdProvider);
    final isMultiSelectModeEnabled = ref.read(selectionMultiSelectModeProvider);

    final ctrlDown = isCtrlPressed || isMultiSelectModeEnabled;
    final shiftDown = isShiftPressed;

    if (shiftDown && lastId != null) {
      notifier.selectRange(lastId, cardGame.id);
    } else if (ctrlDown) {
      notifier.toggleGameSelection(cardGame.id);
      _markLastSelected();
    } else {
      if (!selectedIds.contains(cardGame.id) || selectedIds.length != 1) {
        notifier.clearSelection();
        notifier.selectGame(cardGame.id);
      }
      _markLastSelected();
    }
  }

  void handleDoubleTap() {
    final allGames = ref.read(gamesProvider.select((s) => s.filteredGames));
    final selectedIds = ref.read(
      gamesProvider.select((s) => s.selectedGameIds),
    );
    // A double-tap inside a multi-selection opens all of it.
    final targets = selectedIds.contains(cardGame.id) && selectedIds.length > 1
        ? [
            for (final game in allGames)
              if (selectedIds.contains(game.id)) game,
          ]
        : [cardGame];
    GameSelectionActions.openDetails(
      context,
      ref,
      targets: targets,
      initialGame: cardGame,
    );
  }

  void handleLongPress() {
    if (_lastPointerKind != PointerDeviceKind.touch) return;
    if (ref.read(dragSelectionProvider).isActive) return;

    _primaryPointerHandledByLongPress = true;
    ref.read(gamesProvider.notifier).toggleGameSelection(cardGame.id);
    _markLastSelected();
  }

  // ── Drag-selection ────────────────────────────────────────────────────────

  void handleDragSelectionEvent(PointerEvent event) {
    if (dragSelectionHandledByParent) return;
    if (event.kind != PointerDeviceKind.mouse) return;
    if ((event.buttons & kPrimaryMouseButton) == 0) return;

    final dragState = ref.read(dragSelectionProvider);
    if (!dragState.isActive) return;
    if (dragState.visitedIds.contains(cardGame.id)) return;

    final notifier = ref.read(gamesProvider.notifier);
    final selectedIds = ref.read(
      gamesProvider.select((s) => s.selectedGameIds),
    );

    if (isShiftPressed || isCtrlPressed) {
      notifier.toggleGameSelection(cardGame.id);
    } else {
      final mode =
          dragState.mode ??
          (selectedIds.contains(cardGame.id)
              ? DragSelectionMode.deselect
              : DragSelectionMode.select);
      if (dragState.mode == null) {
        ref.read(dragSelectionProvider.notifier).setMode(mode);
      }

      if (mode == DragSelectionMode.select) {
        notifier.selectGame(cardGame.id);
      } else {
        notifier.deselectGame(cardGame.id);
      }
    }

    ref.read(dragSelectionProvider.notifier).markVisited(cardGame.id);
    _markLastSelected();
  }

  // ── Pointer event handlers ────────────────────────────────────────────────

  void handlePointerDown(PointerDownEvent event) {
    _lastPointerKind = event.kind;
    if (event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kSecondaryMouseButton) != 0) {
      return;
    }
    if ((event.buttons & kPrimaryButton) == 0) return;

    _activePrimaryPointer = event.pointer;
    _primaryPointerDownPosition = event.position;
    _primaryPointerExceededSlop = false;
    _primaryPointerHandledByLongPress = false;
  }

  void handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePrimaryPointer) return;
    final downPosition = _primaryPointerDownPosition;
    if (downPosition == null) return;

    if (!_primaryPointerExceededSlop &&
        (event.position - downPosition).distance > _dragStartSlop) {
      _primaryPointerExceededSlop = true;

      if (!dragSelectionHandledByParent &&
          event.kind == PointerDeviceKind.mouse &&
          (isCtrlPressed || ref.read(selectionMultiSelectModeProvider))) {
        if (!ref.read(dragSelectionProvider).isActive) {
          ref.read(dragSelectionProvider.notifier).start();
          handleDragSelectionEvent(event);
        }
      }
    }
  }

  void handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _activePrimaryPointer) return;
    final shouldHandleTap =
        !_primaryPointerExceededSlop && !_primaryPointerHandledByLongPress;
    _resetPrimaryPointerTracking();
    if (shouldHandleTap) handleTap();
  }

  void handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePrimaryPointer) return;
    _resetPrimaryPointerTracking();
  }

  // ── Context menu ──────────────────────────────────────────────────────────

  /// The games a menu choice acts on: the selection, if it holds this card.
  List<Game> _targetGames() =>
      ref.read(gamesProvider).selectedGameIds.contains(cardGame.id)
      ? ref.read(selectedGamesProvider)
      : [cardGame];

  void showContextMenu(Offset position) {
    final selectedIds = ref.read(
      gamesProvider.select((s) => s.selectedGameIds),
    );
    if (!selectedIds.contains(cardGame.id)) {
      ref.read(gamesProvider.notifier).clearSelection();
      ref.read(gamesProvider.notifier).selectGame(cardGame.id);
      ref.read(lastSelectedGameIdProvider.notifier).set(cardGame.id);
    }

    final theme = ref.read(themeProvider);
    final game = cardGame;
    final targetGames = _targetGames();
    final count = targetGames.length;
    final suffix = count > 1 ? ' ($count)' : '';
    final isFetching = ref.read(batchFetchProvider).isActive;
    final hasSteamTargets = targetGames.any((g) => g.platform == 'Steam');

    // Items with a [lockedLabel] are disabled while a Steam fetch runs.
    Widget item(
      IconData icon,
      String label,
      VoidCallback onPressed, {
      Color? iconColor,
      Color? color,
      String? lockedLabel,
    }) {
      final enabled = lockedLabel == null || !isFetching;
      return appMenuItem(
        theme,
        leading: Icon(
          enabled ? icon : Icons.lock_rounded,
          size: 18,
          color: enabled ? iconColor : theme.textHint,
        ),
        color: enabled ? color : null,
        // The menu runs its choice a frame after closing.
        onPressed: enabled
            ? () {
                if (context.mounted) onPressed();
              }
            : null,
        child: Text(enabled ? '$label$suffix' : '$lockedLabel (Locked)$suffix'),
      );
    }

    showAppContextMenu(
      context: context,
      theme: theme,
      position: position,
      menuChildren: [
        item(
          Icons.copy_all,
          'Copy',
          () => GameSelectionActions.showCopyDialog(context, ref, targetGames),
        ),
        appMenuDivider(theme),
        item(
          Icons.edit_outlined,
          'Game Editor',
          handleDoubleTap,
          lockedLabel: 'Game Editor',
        ),
        if (hasSteamTargets) ...[
          item(
            Icons.open_in_new,
            'Open Steam Page',
            () => GameSelectionActions.openSteamPages(ref, targetGames),
          ),
          item(
            Icons.cloud_download,
            'Fetch Steam Data',
            () =>
                GameSelectionActions.fetchSteamData(context, ref, targetGames),
            iconColor: theme.accent,
            lockedLabel: 'Fetch Steam Data',
          ),
        ],
        appMenuDivider(theme),
        item(
          game.isUsed ? Icons.radio_button_unchecked : Icons.check_circle,
          game.isUsed ? 'Mark as Unused' : 'Mark as Used',
          () => GameSelectionActions.toggleUsed(ref, targetGames, !game.isUsed),
          lockedLabel: 'Mark as Used/Unused',
        ),
        appMenuDivider(theme),
        item(
          Icons.delete_outline,
          'Delete',
          () => GameSelectionActions.deleteGames(
            context,
            ref,
            theme,
            targetGames,
          ),
          color: theme.error,
          lockedLabel: 'Delete',
        ),
      ],
    );
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _resetPrimaryPointerTracking() {
    _activePrimaryPointer = null;
    _primaryPointerDownPosition = null;
    _primaryPointerExceededSlop = false;
    _primaryPointerHandledByLongPress = false;
  }
}
