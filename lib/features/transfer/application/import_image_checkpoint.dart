import 'dart:io';

/// Undo only image files changed by this import, alongside database rollback.
class ImportImageCheckpoint {
  Directory? _directory;
  final _originals = <String, String?>{};

  Future<void> copy(File source, File destination) async {
    if (!_originals.containsKey(destination.path)) {
      String? backup;
      if (await destination.exists()) {
        _directory ??= await Directory.systemTemp.createTemp(
          'unikm-import-images-',
        );
        backup = '${_directory!.path}/${_originals.length}';
        await destination.copy(backup);
      }
      _originals[destination.path] = backup;
    }
    await source.copy(destination.path);
  }

  Future<void> finish({required bool committed}) async {
    if (!committed) {
      for (final entry in _originals.entries.toList().reversed) {
        if (entry.value != null) {
          await File(entry.value!).copy(entry.key);
        } else {
          final file = File(entry.key);
          if (await file.exists()) await file.delete();
        }
      }
    }
    await _directory?.delete(recursive: true);
  }
}
