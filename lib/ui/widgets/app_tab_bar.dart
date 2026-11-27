import 'package:material_ui/material_ui.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/surface_depth.dart';

class const AppTab(final String label, {final IconData? icon});

/// A connected pill with rounded outer ends and square internal edges.
/// Existing tab views keep their controller; standalone panels use an index.
class const AppTabBar({
  super.key,
  required final List<AppTab> tabs,
  final TabController? controller,
  final int selectedIndex = 0,
  final ValueChanged<int>? onChanged,
}) extends StatelessWidget {
  this
    : assert(tabs.length > 0),
      assert(controller != null || onChanged != null),
      assert(controller == null || controller.length == tabs.length),
      assert(selectedIndex >= 0 && selectedIndex < tabs.length);

  @override
  Widget build(BuildContext context) {
    if (controller case final controller?) {
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) => _buildTabs(context, controller.index),
      );
    }
    return _buildTabs(context, selectedIndex);
  }

  Widget _buildTabs(BuildContext context, int selected) {
    final theme = context.appTheme;
    final radius = Radius.circular(theme.cornerRadius * 1.25);
    final labelStyle = Theme.of(context).textTheme.labelLarge!
        .copyWith(fontWeight: FontWeight.bold);
    Widget buildRow(bool showIcons) => FocusTraversalGroup(
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < tabs.length; index++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: index == selected,
                  label: tabs[index].label,
                  excludeSemantics: true,
                  onTap: () => _select(context, index),
                  child: AppTabSurface(
                    selected: index == selected,
                    borderRadius: _radiusFor(index, radius, context),
                    onTap: () => _select(context, index),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    builder: (context, color) => Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (showIcons && tabs[index].icon != null) ...[
                          Icon(tabs[index].icon, size: 16, color: color),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            tabs[index].label,
                            textAlign: TextAlign.center,
                            style: labelStyle.copyWith(color: color),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    // Each variant is built once, so a width change only picks one.
    final rows = <bool, Widget>{};
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.all(radius),
        boxShadow: [SurfaceDepth.shadow(isDark: theme.isDark)],
      ),
      child: Material(
        // A new corner radius applies at once, as it does to the shadow.
        animationDuration: Duration.zero,
        color: theme.tabUnselected,
        borderRadius: BorderRadius.all(radius),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showIcons =
                constraints.maxWidth / tabs.length >= 105 &&
                MediaQuery.textScalerOf(context).scale(14) <= 17;
            return rows[showIcons] ??= buildRow(showIcons);
          },
        ),
      ),
    );
  }

  void _select(BuildContext context, int index) {
    if (controller case final controller?) {
      if (MediaQuery.disableAnimationsOf(context)) {
        controller.index = index;
      } else {
        controller.animateTo(
          index,
          duration: kTabTransition,
          curve: kTabTransitionCurve,
        );
      }
    }
    onChanged?.call(index);
  }

  /// Only the outer ends of the joined tabs have rounded corners.
  BorderRadius _radiusFor(int index, Radius radius, BuildContext context) =>
      BorderRadiusDirectional.horizontal(
        start: index == 0 ? radius : Radius.zero,
        end: index == tabs.length - 1 ? radius : Radius.zero,
      ).resolve(Directionality.of(context));
}

/// One tab's surface: the unselected tab fill easing into the selected one
/// (with the text color) as [selected] changes, the tab's depth gradient, and
/// its hover, splash and press highlights. [builder] gets the text color.
class const AppTabSurface({
  super.key,
  required final bool selected,
  required final BorderRadius borderRadius,
  required final VoidCallback? onTap,
  required final Widget Function(BuildContext context, Color color) builder,
  final EdgeInsetsGeometry padding = EdgeInsets.zero,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: selected ? 1 : 0, end: selected ? 1 : 0),
      duration: context.motion(kTabTransition),
      curve: kTabTransitionCurve,
      builder: (context, amount, _) {
        final background = Color.lerp(
          theme.tabUnselected,
          theme.tabSelected,
          amount,
        )!;
        final color = onTap == null
            ? theme.primaryButtonDisabledText
            : Color.lerp(theme.textSecondary, theme.primaryButtonText, amount)!;
        return Material(
          color: background,
          animationDuration: Duration.zero,
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              gradient: SurfaceDepth.gradient(background),
            ),
            child: InkWell(
              borderRadius: borderRadius,
              hoverColor: theme.navItemHover,
              splashColor: theme.navItemHover,
              highlightColor: theme.tabSelected,
              onTap: onTap,
              child: Padding(padding: padding, child: builder(context, color)),
            ),
          ),
        );
      },
    );
  }
}

/// Slides index-driven tab content like [TabBarView]: the previous tab slides
/// out while the next slides in. Unlike [TabBarView] it sizes to the current
/// tab, so the outgoing tab keeps its own height without adding to the panel.
/// Fixed-height tab views use [AppTabView].
class const AppTabTransition({
  super.key,
  required final int index,
  required final Widget child,

  /// False fades the new content in place, for page-like section switches.
  final bool slide = true,
}) extends StatefulWidget {
  @override
  State<AppTabTransition> createState() => _AppTabTransitionState();
}

class _AppTabTransitionState extends State<AppTabTransition> {
  // 1 when the next tab enters from the end side, -1 from the start side.
  double _side = 1;
  final _heights = <Key, double>{};
  // The child built this frame; every other switcher child is sliding out,
  // even one returning to an index that is still leaving.
  Widget? _current;

  @override
  void didUpdateWidget(covariant AppTabTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == oldWidget.index) return;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    _side = (widget.index > oldWidget.index) != rtl ? 1 : -1;
    // Only the current tab sizes the panel, so remember the outgoing height.
    if (context.findRenderObject() case final RenderBox box when box.hasSize) {
      _heights[ValueKey(oldWidget.index)] = box.size.height;
    }
  }

  Widget _transition(Widget child, Animation<double> animation) {
    final incoming = identical(child, _current);
    // A tab coming back while it still slides out is never mounted twice, so
    // its controllers stay attached to a single copy.
    if (!incoming && child.key == ValueKey(widget.index)) {
      return const SizedBox.shrink();
    }
    final position = animation.drive(
      Tween(begin: Offset(incoming ? _side : -_side, 0), end: Offset.zero),
    );
    final slide = SlideTransition(position: position, child: child);
    if (incoming) return slide;
    return SizedBox(
      height: _heights[child.key],
      child: IgnorePointer(child: ExcludeSemantics(child: slide)),
    );
  }

  // Clip only while a tab slides out, so selection glows and shadows that
  // reach past the panel edge stay visible at rest. Toggling the clip keeps
  // the tab mounted.
  Widget _layout(Widget? current, List<Widget> previous) => ClipRect(
    clipBehavior: previous.isEmpty ? Clip.none : Clip.hardEdge,
    child: Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        for (final child in previous)
          Positioned(left: 0, right: 0, top: 0, child: child),
        ?current,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final duration = context.motion(kTabTransition);
    if (!widget.slide) {
      // Page-like sections fade in alone, so no second copy is ever mounted.
      return AnimatedSwitcher(
        duration: duration,
        switchInCurve: kTabTransitionCurve,
        layoutBuilder: (current, _) => current!,
        child: _current = KeyedSubtree(
          key: ValueKey(widget.index),
          child: widget.child,
        ),
      );
    }
    // Slide across the full available width, even when a tab's content is
    // narrower, so the slide distance and clip never cut that content off.
    final child = _current = KeyedSubtree(
      key: ValueKey(widget.index),
      child: Align(
        alignment: AlignmentDirectional.topStart,
        heightFactor: 1,
        child: widget.child,
      ),
    );
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: kTabTransitionCurve,
      // Mirrors the incoming curve so both tabs stay edge to edge.
      switchOutCurve: kTabTransitionCurve.flipped,
      // A fresh closure makes the switcher re-wrap the outgoing tab, which
      // was built as the incoming one, with its outgoing transition.
      transitionBuilder: (child, animation) => _transition(child, animation),
      layoutBuilder: _layout,
      child: child,
    );
  }
}

/// Controller-driven tabs use Flutter's native [TabBarView] slide and swipe.
/// Visited pages retain their fields and scroll position while hidden.
class const AppTabView({
  super.key,
  required final TabController controller,
  required final List<Widget> children,
}) extends StatelessWidget {
  this : assert(controller.length == children.length);

  @override
  Widget build(BuildContext context) {
    // TabBarView always animates with the controller's duration, so reduced
    // motion swaps pages directly instead.
    if (MediaQuery.disableAnimationsOf(context)) {
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) =>
            IndexedStack(index: controller.index, children: children),
      );
    }
    return TabBarView(
      controller: controller,
      children: [for (final child in children) _KeepAlive(child: child)],
    );
  }
}

class const _KeepAlive({required final Widget child}) extends StatefulWidget {
  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
