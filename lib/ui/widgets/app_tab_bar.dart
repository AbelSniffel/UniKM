import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/button_group_shape.dart';
import '../../core/theme/surface_depth.dart';

class AppTab {
  const AppTab(this.label, {this.icon});

  final String label;
  final IconData? icon;
}

/// A connected pill with rounded outer ends and square internal edges.
/// Existing tab views keep their controller; standalone panels use an index.
class AppTabBar extends StatelessWidget {
  const AppTabBar({
    super.key,
    required this.theme,
    required this.tabs,
    this.controller,
    this.selectedIndex = 0,
    this.onChanged,
  }) : assert(tabs.length > 0),
       assert(controller != null || onChanged != null),
       assert(controller == null || controller.length == tabs.length),
       assert(selectedIndex >= 0 && selectedIndex < tabs.length);

  final AppThemeData theme;
  final List<AppTab> tabs;
  final TabController? controller;
  final int selectedIndex;
  final ValueChanged<int>? onChanged;

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
    final radius = Radius.circular(theme.cornerRadius * 1.25);
    final labelStyle = Theme.of(
      context,
    ).textTheme.labelLarge!.copyWith(fontWeight: FontWeight.bold);
    final restColor = Color.alphaBlend(
      theme.accent.withValues(alpha: 0.45),
      theme.navBackground,
    );
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : kTabTransition;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.all(radius),
        boxShadow: [SurfaceDepth.shadow(isDark: theme.isDark)],
      ),
      child: Material(
        color: restColor,
        borderRadius: BorderRadius.all(radius),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showIcons =
                constraints.maxWidth / tabs.length >= 105 &&
                MediaQuery.textScalerOf(context).scale(14) <= 17;
            return FocusTraversalGroup(
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
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(
                              begin: index == selected ? 1 : 0,
                              end: index == selected ? 1 : 0,
                            ),
                            duration: duration,
                            curve: kTabTransitionCurve,
                            builder: (context, amount, _) {
                              final background = Color.lerp(
                                restColor,
                                theme.tabSelected,
                                amount,
                              )!;
                              return Material(
                                color: background,
                                animationDuration: Duration.zero,
                                borderRadius: _radiusFor(
                                  index,
                                  radius,
                                  context,
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Ink(
                                  decoration: BoxDecoration(
                                    gradient: SurfaceDepth.gradient(background),
                                  ),
                                  child: InkWell(
                                    borderRadius: _radiusFor(
                                      index,
                                      radius,
                                      context,
                                    ),
                                    hoverColor: theme.navItemHover,
                                    splashColor: theme.navItemHover,
                                    highlightColor: theme.tabSelected,
                                    onTap: () => _select(context, index),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          if (showIcons &&
                                              tabs[index].icon != null) ...[
                                            Icon(
                                              tabs[index].icon,
                                              size: 16,
                                              color: Color.lerp(
                                                theme.textSecondary,
                                                theme.accent,
                                                amount,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                          ],
                                          Flexible(
                                            child: Text(
                                              tabs[index].label,
                                              textAlign: TextAlign.center,
                                              style: labelStyle.copyWith(
                                                color: Color.lerp(
                                                  theme.textSecondary,
                                                  theme.textPrimary,
                                                  amount,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
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

  BorderRadius _radiusFor(int index, Radius radius, BuildContext context) {
    return buttonGroupBorderRadius(
      index: index,
      count: tabs.length,
      radius: radius.x,
      textDirection: Directionality.of(context),
    );
  }
}

/// Reveals index-driven tab content without retaining stale controls or adding
/// an outgoing child's height to panels that size themselves to their content.
class AppTabTransition extends StatefulWidget {
  const AppTabTransition({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<AppTabTransition> createState() => _AppTabTransitionState();
}

class _AppTabTransitionState extends State<AppTabTransition>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: kTabTransition,
    value: 1,
  );
  late final _animation = _controller.drive(
    CurveTween(curve: kTabTransitionCurve),
  );

  @override
  void didUpdateWidget(covariant AppTabTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && _controller.value != 1) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _animation, child: widget.child);
}

/// Controller-driven tabs use the same stationary fade as index-driven panels.
/// Visited pages retain their fields and scroll position while hidden.
class AppTabView extends StatefulWidget {
  const AppTabView({
    super.key,
    required this.controller,
    required this.children,
  }) : assert(controller.length == children.length);

  final TabController controller;
  final List<Widget> children;

  @override
  State<AppTabView> createState() => _AppTabViewState();
}

class _AppTabViewState extends State<AppTabView> {
  late int _index;
  final _visited = <int>{};
  double _dragDistance = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.controller.index;
    _visited.add(_index);
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant AppTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
      _visited.clear();
    }
    _index = widget.controller.index;
    _visited.add(_index);
    _visited.removeWhere((index) => index >= widget.children.length);
  }

  void _onChanged() {
    if (_index == widget.controller.index) return;
    setState(() {
      _index = widget.controller.index;
      _visited.add(_index);
    });
  }

  void _onSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragDistance.abs() < 48 && velocity.abs() < 300) return;
    final movement = velocity.abs() >= 300 ? velocity : _dragDistance;
    final direction = Directionality.of(context) == TextDirection.ltr ? 1 : -1;
    final next = (_index + (movement < 0 ? direction : -direction)).clamp(
      0,
      widget.children.length - 1,
    );
    widget.controller.index = next;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onHorizontalDragStart: (_) => _dragDistance = 0,
    onHorizontalDragUpdate: (details) => _dragDistance += details.delta.dx,
    onHorizontalDragEnd: _onSwipe,
    child: ClipRect(
      child: AppTabTransition(
        index: _index,
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (var index = 0; index < widget.children.length; index++)
              if (_visited.contains(index))
                Offstage(
                  key: ValueKey(index),
                  offstage: index != _index,
                  child: TickerMode(
                    enabled: index == _index,
                    child: ExcludeFocus(
                      excluding: index != _index,
                      child: widget.children[index],
                    ),
                  ),
                ),
          ],
        ),
      ),
    ),
  );
}
