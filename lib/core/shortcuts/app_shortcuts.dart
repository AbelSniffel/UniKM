import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Intent to select all visible games in the list
class SelectAllGamesIntent extends Intent {
  const SelectAllGamesIntent();
}

/// Intent to deselect all currently selected games
class DeselectAllGamesIntent extends Intent {
  const DeselectAllGamesIntent();
}

/// Intent to delete currently selected games
class DeleteSelectionIntent extends Intent {
  const DeleteSelectionIntent();
}

/// Intent to copy currently selected games
class CopySelectionIntent extends Intent {
  const CopySelectionIntent();
}

/// Helper class to manage app-wide shortcuts
class AppShortcuts {
  /// Global shortcuts (always active unless overridden)
  static final Map<ShortcutActivator, Intent> global = {
    // Deselect all games / Clear search: Esc
    const SingleActivator(LogicalKeyboardKey.escape): const DeselectAllGamesIntent(),
  };

  /// Shortcuts active only when Game List has focus
  static final Map<ShortcutActivator, Intent> gameList = {
    // Select all visible games: Ctrl + A
    const SingleActivator(LogicalKeyboardKey.keyA, control: true): const SelectAllGamesIntent(),
    // Delete selected games: Delete
    const SingleActivator(LogicalKeyboardKey.delete): const DeleteSelectionIntent(),
    // Copy selected games: Ctrl + C
    const SingleActivator(LogicalKeyboardKey.keyC, control: true): const CopySelectionIntent(),
  };

  /// Combined defaults (legacy support if needed)
  static final Map<ShortcutActivator, Intent> defaults = {
    ...global,
    ...gameList,
  };
}
