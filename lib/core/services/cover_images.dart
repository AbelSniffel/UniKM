import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../database/database.dart';
import 'sync_entry_fingerprint.dart';

/// Covers live flat in `images/` beside the default database, named after the
/// game's normalized title, so games sharing a title share one file.
abstract final class CoverImages {
  static final _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  static final _edgeDashes = RegExp(r'^-+|-+$');

  /// The file name, without extension, for [title]'s cover: lowercase
  /// letters and digits joined by dashes. Empty when the title has none.
  static String stem(String title) {
    final slug = title
        .toLowerCase()
        .replaceAll(_separators, '-')
        .replaceAll(_edgeDashes, '');
    return slug.runes.length <= 80
        ? slug
        : String.fromCharCodes(slug.runes.take(80)).replaceAll(_edgeDashes, '');
  }

  /// `images/` beside the default database, created on demand. Keeping it
  /// next to the database lets the whole data folder be moved in one go.
  static Future<Directory> directory() async {
    final dir = Directory(
      p.join(p.dirname(await AppDatabase.getDatabasePath()), 'images'),
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Stores [bytes] as [title]'s cover in [dir]. An identical image already
  /// under the title's name is reused; a different one keeps its file and
  /// this image gets a short content hash appended. Never overwrites, so
  /// [created] tells whether the file is new.
  static Future<({File file, bool created})> store(
    Directory dir,
    String title,
    String extension,
    List<int> bytes,
  ) async {
    final hash = SyncEntryFingerprint.hashBytes(bytes);
    final ext = extension.isEmpty ? '.img' : extension.toLowerCase();
    final name = stem(title);
    final candidates = [
      if (name.isNotEmpty) ...[name, '$name-${hash.substring(0, 8)}'],
      hash,
    ];
    for (final candidate in candidates) {
      final file = File(p.join(dir.path, '$candidate$ext'));
      if (!await file.exists()) {
        await file.writeAsBytes(bytes, flush: true);
        return (file: file, created: true);
      }
      if (candidate == candidates.last ||
          SyncEntryFingerprint.hashBytes(await file.readAsBytes()) == hash) {
        return (file: file, created: false);
      }
    }
    throw StateError('unreachable');
  }

  static const _legacyFolders = ['steam', 'sync'];

  /// Moves covers out of the old `images/steam` (Steam app ID names) and
  /// `images/sync` (content hash names) folders into [root], renamed after
  /// their game, and points [db]'s games at them. Logical sync versions are
  /// kept, since the images themselves do not change.
  ///
  /// Other databases sharing the folder may still point at the old paths, so
  /// a missing old file is looked up in [root] by title or file name, and
  /// files no game here uses move to [root] unchanged.
  static Future<void> migrateLegacyFolders(
    AppDatabase db, {
    Directory? root,
  }) async {
    final dir = root ?? await directory();
    final legacy = {
      for (final name in _legacyFolders) p.normalize(p.join(dir.path, name)),
    };
    final games = db.games;
    final rows =
        await (db.selectOnly(games)
              ..addColumns([games.id, games.title, games.coverImage])
              ..where(games.coverImage.like('%images%')))
            .get();
    final updates = <int, String>{};
    final moved = <String>{};
    for (final row in rows) {
      final cover = row.read(games.coverImage)!;
      final old = SyncEntryFingerprint.coverFile(cover);
      if (!legacy.contains(p.normalize(old.parent.path))) continue;
      final title = row.read(games.title)!;
      final ext = p.extension(old.path);
      File? target;
      if (await old.exists()) {
        target = (await store(dir, title, ext, await old.readAsBytes())).file;
        moved.add(old.path);
      } else {
        for (final name in {'${stem(title)}$ext', p.basename(old.path)}) {
          final file = File(p.join(dir.path, name));
          if (await file.exists()) {
            target = file;
            break;
          }
        }
      }
      if (target != null) updates[row.read(games.id)!] = target.path;
    }

    if (updates.isNotEmpty) {
      await db.transaction(() async {
        final versions = await db.getSyncRecords();
        await db.batch((batch) {
          for (final MapEntry(key: id, value: path) in updates.entries) {
            batch.update(
              games,
              GamesCompanion(coverImage: Value(path)),
              where: (game) => game.id.equals(id),
            );
          }
        });
        await db.restoreSyncRecordVersions([
          for (final record in versions)
            if (updates.containsKey(record['id'])) record,
        ]);
      });
    }

    for (final path in moved) {
      await _tryDelete(File(path));
    }
    for (final path in legacy) {
      final folder = Directory(path);
      if (!await folder.exists()) continue;
      await for (final entity in folder.list(followLinks: false)) {
        if (entity is! File) continue;
        final target = File(p.join(dir.path, p.basename(entity.path)));
        if (!await target.exists()) {
          await entity.rename(target.path);
        } else if (SyncEntryFingerprint.hashBytes(await target.readAsBytes()) ==
            SyncEntryFingerprint.hashBytes(await entity.readAsBytes())) {
          await _tryDelete(entity);
        }
      }
      try {
        await folder.delete();
      } on FileSystemException {
        // Left in place while it still holds anything.
      }
    }
  }

  static Future<void> _tryDelete(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // A locked or already removed file only costs disk space.
    }
  }
}
