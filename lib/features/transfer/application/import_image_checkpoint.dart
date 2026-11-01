import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/services/cover_images.dart';

/// Undo only image files added by this import, alongside database rollback.
/// Covers are never overwritten, so only new files need removing.
class ImportImageCheckpoint {
  final _added = <String>[];

  /// Stores [source] as [title]'s cover in [dir] (see [CoverImages.store]).
  Future<File> store(File source, Directory dir, String title) async {
    final (:file, :created) = await CoverImages.store(
      dir,
      title,
      p.extension(source.path),
      await source.readAsBytes(),
    );
    if (created) _added.add(file.path);
    return file;
  }

  Future<void> finish({required bool committed}) async {
    if (committed) return;
    for (final path in _added.reversed) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }
}
