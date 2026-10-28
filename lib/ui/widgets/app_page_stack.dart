import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/constants/app_constants.dart';
import 'app_progress_indicator.dart';

/// Prepares pages once per database session. Hidden pages retain fields
/// and scroll positions, but cannot paint, receive focus, or run tickers.
/// Riverpod also pauses hidden consumers through TickerMode.
class AppPageStack extends StatefulWidget {
  const AppPageStack({
    super.key,
    required this.index,
    required this.children,
    this.preload = true,
  }) : assert(index >= 0 && index < children.length);

  /// Prepare all pages behind a loading screen, one page per frame.
  /// Disable for callers that explicitly need lazy mounting.
  final bool preload;
  final int index;
  final List<Widget> children;

  @override
  State<AppPageStack> createState() => _AppPageStackState();
}

class _AppPageStackState extends State<AppPageStack>
    with SingleTickerProviderStateMixin {
  final _visited = <int>{};
  int? _outgoing;
  bool _preloading = false;
  bool _preloadScheduled = false;
  late final _controller = AnimationController(
    vsync: this,
    duration: kPageTransition,
    value: 1,
  )..addStatusListener(_onStatus);
  late final _fade = _controller.drive(CurveTween(curve: kPageTransitionCurve));
  late final _reverseFade = ReverseAnimation(_fade);

  @override
  void initState() {
    super.initState();
    _visited.add(widget.index);
    _preloading = widget.preload;
    if (_preloading) _schedulePreload();
  }

  void _schedulePreload() {
    if (_preloadScheduled) return;
    _preloadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadScheduled = false;
      if (!mounted || !_preloading) return;
      final next = Iterable<int>.generate(
        widget.children.length,
      ).where((index) => !_visited.contains(index)).firstOrNull;
      setState(() {
        if (next == null) {
          // The last page has now completed its first build and layout.
          _preloading = false;
        } else {
          _visited.add(next);
        }
      });
      if (_preloading) _schedulePreload();
    });
  }

  @override
  void didUpdateWidget(AppPageStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.removeWhere((index) => index >= widget.children.length);
    _visited.add(widget.index);
    if (widget.preload != oldWidget.preload) {
      _preloading = widget.preload;
      if (_preloading) _schedulePreload();
    }
    if (widget.index != oldWidget.index) {
      _outgoing = oldWidget.index < widget.children.length
          ? oldWidget.index
          : null;
      if (MediaQuery.disableAnimationsOf(context)) {
        _outgoing = null;
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _outgoing = null;
      _controller.value = 1;
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _outgoing != null) {
      setState(() => _outgoing = null);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: Stack(
      fit: StackFit.expand,
      children: [
        // Paint the incoming page on top; stable keys retain every page's state
        // even when a user reverses direction before a fade has completed.
        for (final index in [
          ..._visited.where((index) => index != widget.index),
          widget.index,
        ])
          Offstage(
            key: ValueKey(index),
            offstage: index != widget.index && index != _outgoing,
            child: TickerMode(
              enabled: !_preloading && index == widget.index,
              child: ExcludeSemantics(
                excluding: _preloading || index != widget.index,
                child: ExcludeFocus(
                  excluding: _preloading || index != widget.index,
                  child: IgnorePointer(
                    ignoring: _preloading || index != widget.index,
                    child: FadeTransition(
                      opacity: index == widget.index
                          ? _fade
                          : index == _outgoing
                          ? _reverseFade
                          : const AlwaysStoppedAnimation(1),
                      child: RepaintBoundary(
                        child: _RetainedPageLayout(
                          visible: index == widget.index || index == _outgoing,
                          child: _RetainedPageEnvironment(
                            active: index == widget.index || index == _outgoing,
                            child: widget.children[index],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_preloading)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppCircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Preparing pages…'),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Pause the whole page environment, not just provider watches and layout.
/// Window metrics bypass render constraints through MediaQuery, while responsive
/// parent configuration can also rebuild a hidden page. Retain both alongside
/// inherited themes and catch up atomically before the page becomes visible.
class _RetainedPageEnvironment extends StatefulWidget {
  const _RetainedPageEnvironment({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_RetainedPageEnvironment> createState() =>
      _RetainedPageEnvironmentState();
}

class _RetainedPageEnvironmentState extends State<_RetainedPageEnvironment> {
  CapturedThemes? _themes;
  late Widget _wrapped;

  void _capture() {
    _themes = InheritedTheme.capture(from: context, to: null);
    _wrapped = _themes!.wrap(
      MediaQuery(data: MediaQuery.of(context), child: widget.child),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe at this small boundary, not inside each hidden control.
    Theme.of(context);
    IconTheme.of(context);
    DefaultTextStyle.of(context);
    MediaQuery.of(context);
    if (widget.active || _themes == null) _capture();
  }

  @override
  void didUpdateWidget(_RetainedPageEnvironment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active &&
        (!oldWidget.active || widget.child != oldWidget.child)) {
      _capture();
    }
  }

  @override
  Widget build(BuildContext context) => _wrapped;
}

/// Offstage suppresses painting, but still lays out its child when the shell
/// changes size. Preserve hidden-page constraints during ribbon/nav animations;
/// first layout still runs for preloading, and showing a page catches up before
/// paint. This also avoids rebuilding hidden LayoutBuilders on every frame.
class _RetainedPageLayout extends SingleChildRenderObjectWidget {
  const _RetainedPageLayout({required this.visible, required super.child});

  final bool visible;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRetainedPageLayout(visible);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRetainedPageLayout renderObject,
  ) => renderObject.visible = visible;
}

class _RenderRetainedPageLayout extends RenderProxyBox {
  _RenderRetainedPageLayout(this._visible);

  bool _visible;
  BoxConstraints? _lastVisibleConstraints;

  set visible(bool value) {
    if (_visible == value) return;
    _visible = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    if (_visible || _lastVisibleConstraints == null) {
      _lastVisibleConstraints = constraints;
    }
    child?.layout(_lastVisibleConstraints!, parentUsesSize: true);
    size = constraints.constrain(child?.size ?? Size.zero);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
    child?.getDryLayout(
          _visible ? constraints : _lastVisibleConstraints ?? constraints,
        ) ??
        Size.zero,
  );
}
