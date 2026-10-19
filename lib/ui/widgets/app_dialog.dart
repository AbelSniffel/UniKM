import 'package:flutter/material.dart';

import '../../core/services/database_file_info.dart';
import '../../core/services/steam_service.dart';

typedef DialogPreviewPresenter = Future<T?> Function<T>(WidgetBuilder builder);

/// The gallery captures real dialog builders, rather than maintaining copies.
/// Its scope also supplies fixtures for dialogs that normally read local files.
class AppDialogPreviewScope extends InheritedWidget {
  const AppDialogPreviewScope({
    super.key,
    required this.present,
    required this.databaseFiles,
    required this.steamCachedAt,
    this.steamResult,
    required super.child,
  });

  final DialogPreviewPresenter present;
  final Map<String, DatabaseFileInfo> databaseFiles;
  final SteamSearchResult? steamResult;
  final DateTime steamCachedAt;

  // Non-listening access is intentional: some dialogs read fixtures in initState.
  static AppDialogPreviewScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppDialogPreviewScope>();

  @override
  bool updateShouldNotify(AppDialogPreviewScope oldWidget) => false;
}

/// Normal app dialogs retain Flutter's modal routing. Only gallery descendants
/// are presented inline, within their own preview viewport.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) {
  final preview = AppDialogPreviewScope.maybeOf(context);
  if (preview != null) return preview.present<T>(builder);
  return showDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    useRootNavigator: useRootNavigator,
  );
}
