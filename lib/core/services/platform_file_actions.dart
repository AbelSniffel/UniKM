library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// What [PlatformFileActions.completeExport] does with a written export.
enum ExportHandoff {
  /// Written where the user chose; nothing more to do.
  none,

  /// Staged in the app's files and offered to the share sheet.
  share,

  /// Staged in the app's files, then saved where the user picks in the
  /// system's save dialog, which can write anywhere the user can.
  saveAs,
}

class const PlatformSaveTarget({
  required final File file,
  final ExportHandoff handoff = ExportHandoff.none,
});

class const PlatformFileActions._() {
  static bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;

  static bool get supportsDragAndDrop => !isMobilePlatform;

  static Future<PlatformSaveTarget?> prepareExportTarget({
    required String dialogTitle,
    required String fileName,
    required List<String> allowedExtensions,
  }) async {
    if (!isMobilePlatform) {
      final outputPath = await _selectDesktopSavePath(
        dialogTitle: dialogTitle,
        fileName: fileName,
        allowedExtensions: allowedExtensions,
      );

      if (outputPath == null || outputPath.isEmpty) return null;

      return PlatformSaveTarget(file: File(outputPath));
    }

    // A folder picked on Android is a path the app often cannot write to, so
    // the export is staged in the app's files and saved through the system's
    // save dialog once written.
    final outputPath = await createManagedFilePath(
      fileName: fileName,
      subdirectory: 'exports',
    );

    return PlatformSaveTarget(
      file: File(outputPath),
      handoff: Platform.isAndroid ? ExportHandoff.saveAs : ExportHandoff.share,
    );
  }

  static Future<String?> resolveDatabaseCreationPath({
    required String dialogTitle,
    required String fileName,
    required List<String> allowedExtensions,
  }) => isMobilePlatform
      ? createManagedFilePath(fileName: fileName, subdirectory: 'databases')
      : _selectDesktopSavePath(
          dialogTitle: dialogTitle,
          fileName: fileName,
          allowedExtensions: allowedExtensions,
        );

  static Future<String?> _selectDesktopSavePath({
    required String dialogTitle,
    required String fileName,
    required List<String> allowedExtensions,
  }) async {
    // FilePicker.saveFile writes bytes immediately. Select a location without
    // touching the destination until export or database creation has succeeded.
    final location = await file_selector.getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: [
        file_selector.XTypeGroup(
          label: dialogTitle,
          extensions: allowedExtensions,
        ),
      ],
    );
    final path = location?.path;
    return path == null || path.isEmpty ? null : path;
  }

  /// A path for [fileName] in the app's own `UniKM/[subdirectory]`, with a
  /// `_2`, `_3`… suffix when the name is taken.
  static Future<String> createManagedFilePath({
    required String fileName,
    String subdirectory = 'exports',
  }) async {
    final rootDirectory = await getApplicationDocumentsDirectory();
    final targetDirectory = await Directory(
      p.join(rootDirectory.path, 'UniKM', subdirectory),
    ).create(recursive: true);

    final baseName = p.basenameWithoutExtension(fileName);
    final extension = p.extension(fileName);
    var candidatePath = p.join(targetDirectory.path, fileName);
    var suffix = 2;

    while (await File(candidatePath).exists()) {
      candidatePath = p.join(
        targetDirectory.path,
        '${baseName}_$suffix$extension',
      );
      suffix++;
    }

    return candidatePath;
  }

  /// Hands a staged export on, as [PlatformSaveTarget.handoff] says. A
  /// shared one is kept unless the share is declined; a saved one leaves
  /// only the copy the user saved. False when the user backs out.
  static Future<bool> completeExport(
    PlatformSaveTarget target, {
    required String subject,
  }) async {
    switch (target.handoff) {
      case ExportHandoff.none:
        return true;
      case ExportHandoff.share:
        if (await _shareFile(target.file, subject)) return true;
        await _discard(target.file);
        return false;
      case ExportHandoff.saveAs:
        try {
          final saved = await FilePicker.saveFile(
            fileName: p.basename(target.file.path),
            bytes: await target.file.readAsBytes(),
            dialogTitle: subject,
          );
          return saved != null;
        } finally {
          await _discard(target.file);
        }
    }
  }

  static Future<void> _discard(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort cleanup only.
    }
  }

  static Future<bool> _shareFile(File file, String subject) async {
    final result = await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: subject),
    );
    return result.status == ShareResultStatus.success;
  }

  static Future<void> shareText(String text, {String? subject}) async =>
      await SharePlus.instance.share(ShareParams(text: text, subject: subject));

  static Future<bool> openDirectory(String directoryPath) async {
    if (Platform.isWindows) {
      // explorer.exe always exits with a non-zero code even on success, so
      // never check exitCode here — just launch and return true.
      await Process.run('explorer', [directoryPath]);
      return true;
    }

    if (Platform.isMacOS || Platform.isLinux) {
      final opener = Platform.isMacOS ? 'open' : 'xdg-open';
      return (await Process.run(opener, [directoryPath])).exitCode == 0;
    }

    final uri = Uri.directory(directoryPath);
    if (!await canLaunchUrl(uri)) return false;

    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
