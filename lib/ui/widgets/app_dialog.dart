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

/// How dialogs open and close: as the library's game cards reveal.
const _dialogAnimation = AnimationStyle(
  duration: Duration(milliseconds: 220),
  curve: Curves.easeOutCubic,
  reverseCurve: Curves.easeOutCubic,
);

/// Normal app dialogs retain Flutter's modal routing, popping in like the
/// library's game cards: fading in while growing from 90%. Only gallery
/// descendants are presented inline, within their own preview viewport.
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
    builder: (context) => _DialogPopIn(child: builder(context)),
    barrierDismissible: barrierDismissible,
    useRootNavigator: useRootNavigator,
    // The route fades the dialog and its backdrop; [_DialogPopIn] scales.
    animationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : _dialogAnimation,
  );
}

/// Grows a dialog from 90% with its route's animation, as it fades in.
class _DialogPopIn extends StatelessWidget {
  const _DialogPopIn({required this.child});

  final Widget child;

  static final _scale = Tween<double>(
    begin: 0.9,
    end: 1,
  ).chain(CurveTween(curve: _dialogAnimation.curve!));

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null) return child;
    return ScaleTransition(scale: animation.drive(_scale), child: child);
  }
}
