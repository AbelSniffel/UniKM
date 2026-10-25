library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class PlatformSaveTarget {
  const PlatformSaveTarget({
    required this.file,
    required this.shouldShareAfterWrite,
  });

  final File file;
  final bool shouldShareAfterWrite;
}

class PlatformFileActions {
  const PlatformFileActions._();

  static bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;

  static bool get supportsDragAndDrop => !isMobilePlatform;

  static Future<PlatformSaveTarget?> prepareExportTarget({
    required String dialogTitle,
    required String fileName,
    required List<String> allowedExtensions,
    String mobileSubdirectory = 'exports',
  }) async {
    if (!isMobilePlatform) {
      final outputPath = await _selectDesktopSavePath(
        dialogTitle: dialogTitle,
        fileName: fileName,
        allowedExtensions: allowedExtensions,
      );

      if (outputPath == null || outputPath.isEmpty) return null;

      return PlatformSaveTarget(
        file: File(outputPath),
        shouldShareAfterWrite: false,
      );
    }

    if (Platform.isAndroid) {
      final selectedDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: dialogTitle,
      );

      if (selectedDirectory == null || selectedDirectory.isEmpty) return null;

      final outputPath = await createUniquePathInDirectory(
        directoryPath: selectedDirectory,
        fileName: fileName,
      );

      return PlatformSaveTarget(
        file: File(outputPath),
        shouldShareAfterWrite: false,
      );
    }

    final outputPath = await createManagedFilePath(
      fileName: fileName,
      subdirectory: mobileSubdirectory,
    );

    return PlatformSaveTarget(
      file: File(outputPath),
      shouldShareAfterWrite: true,
    );
  }

  static Future<String?> resolveDatabaseCreationPath({
    required String dialogTitle,
    required String fileName,
    required List<String> allowedExtensions,
  }) async {
    if (!isMobilePlatform) {
      return _selectDesktopSavePath(
        dialogTitle: dialogTitle,
        fileName: fileName,
        allowedExtensions: allowedExtensions,
      );
    }

    return createManagedFilePath(fileName: fileName, subdirectory: 'databases');
  }

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

  static Future<String> createUniquePathInDirectory({
    required String directoryPath,
    required String fileName,
  }) async {
    final targetDirectory = Directory(directoryPath);
    if (!await targetDirectory.exists()) {
      await targetDirectory.create(recursive: true);
    }

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

  static Future<String> createManagedFilePath({
    required String fileName,
    String subdirectory = 'exports',
  }) async {
    final rootDirectory = await getApplicationDocumentsDirectory();
    final targetDirectoryPath = p.join(
      rootDirectory.path,
      'UniKM',
      subdirectory,
    );
    return createUniquePathInDirectory(
      directoryPath: targetDirectoryPath,
      fileName: fileName,
    );
  }

  /// Share staged exports when required; clean up only after a declined share.
  static Future<bool> completeExport(
    PlatformSaveTarget target, {
    required String subject,
  }) async {
    if (!target.shouldShareAfterWrite) return true;

    final shared = await shareFile(target.file, subject: subject);

    if (shared) return true;

    try {
      if (await target.file.exists()) await target.file.delete();
    } catch (_) {
      // Best effort cleanup only.
    }

    return false;
  }

  static Future<bool> shareFile(
    File file, {
    String? subject,
    String? text,
  }) async {
    final result = await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: subject, text: text),
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

    if (Platform.isMacOS) {
      final result = await Process.run('open', [directoryPath]);
      return result.exitCode == 0;
    }

    if (Platform.isLinux) {
      final result = await Process.run('xdg-open', [directoryPath]);
      return result.exitCode == 0;
    }

    final uri = Uri.directory(directoryPath);
    if (!await canLaunchUrl(uri)) return false;

    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
