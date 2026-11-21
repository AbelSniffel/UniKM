import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// Intent to select all visible games in the list
class const SelectAllGamesIntent() extends Intent;

/// Intent to deselect all currently selected games
class const DeselectAllGamesIntent() extends Intent;

/// Intent to delete currently selected games
class const DeleteSelectionIntent() extends Intent;

/// Intent to copy currently selected games
class const CopySelectionIntent() extends Intent;

/// Helper class to manage app-wide shortcuts
class AppShortcuts {
  /// Global shortcuts (always active unless overridden)
  static final Map<ShortcutActivator, Intent> global = {
    // Deselect all games / Clear search: Esc
    const SingleActivator(LogicalKeyboardKey.escape):
        const DeselectAllGamesIntent(),
  };

  /// Shortcuts active only when Game List has focus
  static final Map<ShortcutActivator, Intent> gameList = {
    // Select all visible games: Ctrl + A
    const SingleActivator(LogicalKeyboardKey.keyA, control: true):
        const SelectAllGamesIntent(),
    // Delete selected games: Delete
    const SingleActivator(LogicalKeyboardKey.delete):
        const DeleteSelectionIntent(),
    // Copy selected games: Ctrl + C
    const SingleActivator(LogicalKeyboardKey.keyC, control: true):
        const CopySelectionIntent(),
  };
}
