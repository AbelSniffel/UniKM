import 'package:flutter/widgets.dart';

/// Owns the text fields shared by new-game drafts and the existing-game editor.
/// Reusing controllers when navigating games also retains one disposal owner.
class GameEditorFields {
  final title = TextEditingController();
  final gameKey = TextEditingController();
  final notes = TextEditingController();
  final coverImage = TextEditingController();

  void load({
    required String title,
    required String gameKey,
    required String notes,
    required String coverImage,
  }) {
    this.title.text = title;
    this.gameKey.text = gameKey;
    this.notes.text = notes;
    this.coverImage.text = coverImage;
  }

  void clear() {
    for (final field in [title, gameKey, notes, coverImage]) {
      field.clear();
    }
  }

  void dispose() {
    for (final field in [title, gameKey, notes, coverImage]) {
      field.dispose();
    }
  }
}
