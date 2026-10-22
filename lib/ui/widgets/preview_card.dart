library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/color_utils.dart';
import 'card_selection_glow.dart';
import 'settings_card_layout.dart';
import 'settings_card_inset.dart';

const _selectionCornerExtent = 48.0;

/// Uses settings-card row sizing with equal widths, retaining state when
/// resizing changes the number of columns. Card content is built outside the
/// layout callback; only inexpensive sizing wrappers change on resize.
class PreviewCardWrap extends StatelessWidget {
  const PreviewCardWrap({
    super.key,
    required this.children,
    this.spacing = 8,
    this.runSpacing = 8,
  }) : assert(spacing >= 0),
       assert(runSpacing >= 0);

  final List<Widget> children;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final width = availableWidth.isFinite
            ? settingsCardWidth(
                availableWidth: availableWidth,
                cardCount: children.length,
                spacing: spacing,
              )
            : kInteractionCardMaxWidth;
        final cards = [
          for (final child in children)
            SizedBox(
              key: child.key,
              width: width,
              child: RepaintBoundary(child: child),
            ),
        ];
        // Keep a flat child list rather than reparenting cards into new Rows:
        // Ink state and running preview animations survive column changes.
        return Wrap(spacing: spacing, runSpacing: runSpacing, children: cards);
      },
    );
  }
}

/// The compact preview surface shared by the theme menu and Settings cards.
class PreviewCard extends StatefulWidget {
  const PreviewCard({
    super.key,
    required this.name,
    required this.theme,
    required this.isSelected,
    required this.backgroundBuilder,
    this.recessedSelection = false,
    this.onTap,
    this.onDoubleTap,
    this.icon,
    this.height = 68,
    this.backgroundIconColor,
    this.foreground,
    this.tapKey,
  });

  final String name;
  final AppThemeData theme;
  final bool isSelected;

  /// Settings control selectors use a recessed selection instead of a glow.
  final bool recessedSelection;
  final Widget Function(BuildContext context, double backgroundRadius)
  backgroundBuilder;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final IconData? icon;
  final Color? backgroundIconColor;

  /// Interactive preview content above the card ink (for example a switch).
  final Widget? foreground;

  /// Null lets a menu grid provide the height.
  final double? height;
  final Key? tapKey;

  @override
  State<PreviewCard> createState() => _PreviewCardState();
}

class _PreviewCardState extends State<PreviewCard> {
  Timer? _minimumTimer;
  Timer? _timeoutTimer;
  TapUpDetails? _lastTap;
  bool _doubleTapReady = false;
  bool _tapUpReceived = false;
  bool _doubleTapPending = false;

  void _resetTapHistory() {
    _minimumTimer?.cancel();
    _timeoutTimer?.cancel();
    _lastTap = null;
    _doubleTapReady = false;
  }

  void _onTapUp(TapUpDetails details) {
    _tapUpReceived = true;
    final previous = _lastTap;
    _doubleTapPending =
        _doubleTapReady &&
        previous != null &&
        previous.kind == details.kind &&
        (previous.globalPosition - details.globalPosition).distance <=
            kDoubleTapSlop;
    _resetTapHistory();
    if (!_doubleTapPending) {
      _lastTap = details;
      _minimumTimer = Timer(kDoubleTapMinTime, () => _doubleTapReady = true);
      _timeoutTimer = Timer(kDoubleTapTimeout, _resetTapHistory);
    }
  }

  void _onTap() {
    // Keep InkWell's single-tap recognizer: selection and ink never wait for
    // a double-tap recognizer. Only two completed pointer taps can edit.
    final edit = _tapUpReceived && _doubleTapPending
        ? widget.onDoubleTap
        : null;
    if (!_tapUpReceived) _resetTapHistory(); // Keyboard activation is one tap.
    _tapUpReceived = false;
    _doubleTapPending = false;
    widget.onTap?.call();
    edit?.call();
  }

  @override
  void dispose() {
    _resetTapHistory();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderWidth = widget.recessedSelection ? 1.0 : 2.0;
    final outerRadius = BorderRadius.circular(widget.theme.cornerRadius);
    final innerRadius = math.max(0.0, widget.theme.cornerRadius - borderWidth);
    final secondary = Theme.of(context).colorScheme.secondary;
    return Semantics(
      label: widget.name,
      button: widget.onTap != null,
      onTap: widget.onTap,
      selected: widget.isSelected,
      child: SizedBox(
        width: 170,
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            _selectionSurface(
              Stack(
                fit: StackFit.expand,
                children: [
                  // Compose the whole painted preview before clipping it. A
                  // full-size background also covers the border's inner AA edge.
                  ClipRRect(
                    borderRadius: outerRadius,
                    clipBehavior: Clip.antiAliasWithSaveLayer,
                    child: widget.backgroundBuilder(
                      context,
                      widget.theme.cornerRadius,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(borderWidth),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(innerRadius),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (widget.icon != null)
                            Positioned(
                              right: 2,
                              bottom: 0,
                              child: Icon(
                                widget.icon,
                                size: widget.height == null ? 32 : 45,
                                color:
                                    widget.backgroundIconColor ??
                                    widget.theme.surface.withValues(
                                      alpha: 0.25,
                                    ),
                              ),
                            ),
                          Positioned(
                            top: 4,
                            left: 4,
                            right: widget.isSelected
                                ? _selectionCornerExtent - 6
                                : 4,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  borderRadius: outerRadius,
                                ),
                                child: ExcludeSemantics(
                                  child: Text(
                                    widget.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // The live clip above controls every splash, including one
                          // already running when a selected theme changes the corners.
                          Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              key: widget.tapKey,
                              excludeFromSemantics: true,
                              onTap: widget.onTap == null ? null : _onTap,
                              onTapUp: widget.onDoubleTap == null
                                  ? null
                                  : _onTapUp,
                              onTapCancel: widget.onDoubleTap == null
                                  ? null
                                  : _resetTapHistory,
                              child: const SizedBox.expand(),
                            ),
                          ),
                          if (widget.foreground != null) widget.foreground!,
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: outerRadius,
                          border: Border.all(
                            color:
                                widget.isSelected && !widget.recessedSelection
                                ? widget.theme.accent
                                : widget.theme.border,
                            width: borderWidth,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.isSelected)
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: ClipPath(
                      clipper: _SelectionCornerClipper(
                        widget.theme.cornerRadius,
                      ),
                      child: DecoratedBox(
                        key: const ValueKey('preview-selection-badge'),
                        decoration: BoxDecoration(color: secondary),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6, right: 6),
                            child: Icon(
                              Icons.check,
                              size: 20,
                              color: contrastColor(secondary),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _selectionSurface(Widget child) {
    if (widget.recessedSelection) {
      return SettingsCardInset(
        active: widget.isSelected,
        borderRadius: widget.theme.cornerRadius,
        surfaceColor: widget.theme.background,
        child: child,
      );
    }
    return CardSelectionGlow(
      selected: widget.isSelected,
      color: widget.theme.accent,
      borderRadius: widget.theme.cornerRadius,
      child: child,
    );
  }
}

/// A filled upper-right corner, clipped to the card's live rounded outline.
/// The check remains upright and does not take part in hit testing.
class _SelectionCornerClipper extends CustomClipper<Path> {
  const _SelectionCornerClipper(this.radius);

  final double radius;

  @override
  Path getClip(Size size) {
    final extent = math.min(
      _selectionCornerExtent,
      math.min(size.width, size.height),
    );
    final triangle = Path()
      ..moveTo(size.width - extent, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, extent)
      ..close();
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    return Path.combine(PathOperation.intersect, triangle, outline);
  }

  @override
  bool shouldReclip(_SelectionCornerClipper oldClipper) =>
      oldClipper.radius != radius;
}
