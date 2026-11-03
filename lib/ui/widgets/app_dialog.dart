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

/// How dialogs open: as the library's game cards reveal. They close quickly
/// ([_AppDialogRoute.closeDuration]), leaving at once rather than lingering.
const _dialogAnimation = AnimationStyle(
  duration: Duration(milliseconds: 220),
  curve: Curves.easeOutCubic,
  reverseCurve: Curves.easeInCubic,
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
  // As [showDialog] builds its route, with a quicker close.
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  return navigator.push<T>(
    _AppDialogRoute<T>(
      context: context,
      builder: builder,
      barrierColor:
          DialogTheme.of(context).barrierColor ??
          Theme.of(context).dialogTheme.barrierColor ??
          Colors.black54,
      barrierDismissible: barrierDismissible,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : _dialogAnimation,
    ),
  );
}

/// A dialog that grows from 90% as its route fades it in, and closes faster
/// than it opens.
class _AppDialogRoute<T> extends DialogRoute<T> {
  _AppDialogRoute({
    required super.context,
    required super.builder,
    super.barrierColor,
    super.barrierDismissible,
    super.themes,
    super.traversalEdgeBehavior,
    super.animationStyle,
  });

  static const closeDuration = Duration(milliseconds: 160);
  static final _scale = Tween<double>(begin: 0.9, end: 1);

  CurvedAnimation? _curved;

  @override
  Duration get reverseTransitionDuration =>
      transitionDuration == Duration.zero ? Duration.zero : closeDuration;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (_curved?.parent != animation) {
      _curved?.dispose();
      _curved = CurvedAnimation(
        parent: animation,
        curve: _dialogAnimation.curve!,
        reverseCurve: _dialogAnimation.reverseCurve,
      );
    }
    return super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      ScaleTransition(scale: _scale.animate(_curved!), child: child),
    );
  }

  @override
  void dispose() {
    _curved?.dispose();
    super.dispose();
  }
}
