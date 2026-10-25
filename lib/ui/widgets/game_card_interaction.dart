/// Pointer and selection interaction mixin for GameCard.
///
/// Owns all pointer-tracking fields and event handlers so they can be removed
/// from [_GameCardState].  Uses an abstract [cardGame] getter so this file
/// does not import game_card.dart, avoiding a circular dependency.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/game.dart';
import '../../providers/app_providers.dart';
import '../dialogs/game_editor_dialog.dart';
import '../widgets/notification_system.dart';

/// Mixin that adds pointer-tracking and selection-orchestration logic to any
/// [ConsumerState].  The host state must implement [cardGame].
mixin GameCardInteractionMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  /// The [Game] this card represents.  Implemented by [_GameCardState] as
  /// `widget.game`.
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
    if (ref.read(deviceSyncServiceProvider).isReceiverSyncInFlight) {
      NotificationManager.instance.warning(
        'Cannot edit games while device sync is in progress',
      );
      return;
    }
    if (ref.read(batchFetchProvider).isActive) {
      NotificationManager.instance.warning(
        'Cannot edit games while Steam data fetch is in progress',
      );
      return;
    }
    final allGames = ref.read(gamesProvider.select((s) => s.filteredGames));
    final selectedIds = ref.read(
      gamesProvider.select((s) => s.selectedGameIds),
    );

    final idsToPass =
        selectedIds.contains(cardGame.id) && selectedIds.length > 1
        ? [
            for (final game in allGames)
              if (selectedIds.contains(game.id)) game.id,
          ]
        : [cardGame.id];

    showGameEditorDialog(
      context,
      cardGame,
      gameIds: idsToPass,
      onViewedGame: (gameId) => markGameAsViewed(ref, gameId),
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

  // ── Internal ──────────────────────────────────────────────────────────────

  void _resetPrimaryPointerTracking() {
    _activePrimaryPointer = null;
    _primaryPointerDownPosition = null;
    _primaryPointerExceededSlop = false;
    _primaryPointerHandledByLongPress = false;
  }
}
