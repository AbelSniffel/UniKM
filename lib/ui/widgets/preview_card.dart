library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import 'settings_card_layout.dart';

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
    this.onTap,
    this.onDoubleTap,
    this.icon,
    this.height = defaultHeight,
    this.backgroundIconColor,
    this.foreground,
    this.tapKey,
    this.inlineLabel = false,
  });

  /// A card's height in Settings.
  static const double defaultHeight = 68;

  final String name;
  final AppThemeData theme;
  final bool isSelected;

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

  /// Shows the name as plain settings-card text centered on the left instead
  /// of in a chip in the bottom-left corner, for single-row cards whose preview
  /// sits beside it. Selection colors it like the selection border.
  final bool inlineLabel;

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
    const borderWidth = 1.0;
    final theme = widget.theme;
    final outerRadius = BorderRadius.circular(theme.cornerRadius);
    final innerRadius = math.max(0.0, theme.cornerRadius - borderWidth);
    final selected = widget.isSelected;
    final inline = widget.inlineLabel;
    final nameColor = selected ? theme.accent : theme.textPrimary;
    final name = Text(
      widget.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: nameColor,
        fontSize: inline ? null : 13,
        fontWeight: FontWeight.w600,
      ),
    );
    // On a preview the name and the selection dot sit in opposite corners.
    const labelInset = 2.0;
    final scrim = theme.background.withValues(alpha: 0.6);
    final dot = Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.background.withValues(alpha: 0.8),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(10)),
        border: Border.all(color: theme.border),
      ),
      child: Container(
        key: const ValueKey('preview-selection-check'),
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: theme.accent,
          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(8)),
        ),
      ),
    );
    final label = Container(
      key: const ValueKey('preview-card-label'),
      padding: inline
          ? EdgeInsets.zero
          : EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: inline
          ? null
          : BoxDecoration(
              color: scrim,
              // A selected card squares the top-left and bottom-right corners.
              borderRadius: selected
                  ? BorderRadius.only(
                      topRight: outerRadius.topRight,
                      bottomLeft: outerRadius.bottomLeft,
                    )
                  : outerRadius,
            ),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [Flexible(child: name)],
        ),
      ),
    );
    final selection = TweenAnimationBuilder<double>(
      tween: Tween(end: selected ? 1 : 0),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : kMediumAnimation,
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => t == 0
          ? const SizedBox.shrink()
          : _SelectionRing(theme: theme, t: t, gap: !inline),
    );
    final background = widget.backgroundBuilder(context, theme.cornerRadius);
    return Semantics(
      label: widget.name,
      button: widget.onTap != null,
      onTap: widget.onTap,
      selected: selected,
      child: SizedBox(
        width: 170,
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Compose the whole painted preview before clipping it. A
            // full-size background also covers the border's inner AA edge.
            ClipRRect(
              borderRadius: outerRadius,
              clipBehavior: Clip.antiAliasWithSaveLayer,
              child: background,
            ),
            Padding(
              padding: const EdgeInsets.all(borderWidth),
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
                              theme.surface.withValues(alpha: 0.25),
                        ),
                      ),
                    if (!inline)
                      Positioned(
                        left: labelInset,
                        right: labelInset + 24,
                        bottom: labelInset,
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: label,
                        ),
                      )
                    else
                      Positioned(
                        top: 0,
                        bottom: 0,
                        // Inline text keeps the settings-card text inset.
                        left: 12 - borderWidth,
                        right: 4,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: label,
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
                        onTapUp: widget.onDoubleTap == null ? null : _onTapUp,
                        onTapCancel: widget.onDoubleTap == null
                            ? null
                            : _resetTapHistory,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    ?widget.foreground,
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: outerRadius,
                    border: Border.all(color: theme.border, width: borderWidth),
                  ),
                ),
              ),
            ),
            // Above the card's border, clipped to the card's corner, so the dot
            // sits flush in it.
            if (!inline && selected)
              Positioned(
                top: 0,
                right: 0,
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      topRight: outerRadius.topRight,
                    ),
                    child: dot,
                  ),
                ),
              ),
            Positioned.fill(child: IgnorePointer(child: selection)),
          ],
        ),
      ),
    );
  }
}

/// The selected look: an accent ring over the card's edge. Previews keep
/// their own colours behind a thin [gap] in the panel colour; a plain style
/// card is tinted instead, like a chosen Tinted Tile.
class _SelectionRing extends StatelessWidget {
  const _SelectionRing({
    required this.theme,
    required this.t,
    required this.gap,
  });

  static const double width = 2;

  final AppThemeData theme;
  final double t;
  final bool gap;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const ValueKey('preview-selection-overlay'),
    decoration: BoxDecoration(
      color: gap ? null : theme.accent.withValues(alpha: 0.12 * t),
      border: Border.all(
        color: theme.accent.withValues(alpha: t),
        width: width,
      ),
      borderRadius: BorderRadius.circular(theme.cornerRadius),
    ),
    child: gap
        ? Padding(
            padding: const EdgeInsets.all(width),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: theme.surface.withValues(alpha: t),
                  width: width,
                ),
                borderRadius: BorderRadius.circular(
                  math.max(0.0, theme.cornerRadius - width),
                ),
              ),
            ),
          )
        : null,
  );
}

/// A single-row style choice at settings-card height: the name label sits on
/// the left and a live [preview] beside it, with the preview-card selection
/// look. Shared by the Control Styles and Settings Card Style groupboxes.
class StyleChoiceCard extends StatelessWidget {
  const StyleChoiceCard({
    super.key,
    required this.name,
    required this.theme,
    required this.isSelected,
    required this.onTap,
    required this.preview,
    this.previewAlignment = Alignment.centerRight,
  });

  /// Matches a settings card: one control row plus its vertical padding.
  static const double height = kElementHeight + 15;

  final String name;
  final AppThemeData theme;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget preview;

  /// [Alignment.topRight] places a corner preview flush with the card edge;
  /// other alignments keep the settings-card inset.
  final Alignment previewAlignment;

  @override
  Widget build(BuildContext context) {
    final inCorner = previewAlignment == Alignment.topRight;
    return PreviewCard(
      name: name,
      height: height,
      theme: theme,
      isSelected: isSelected,
      inlineLabel: true,
      onTap: onTap,
      backgroundBuilder: (_, _) =>
          ColoredBox(color: theme.background.withValues(alpha: 0.65)),
      foreground: Positioned.fill(
        child: Padding(
          padding: inCorner
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 12),
          child: Align(alignment: previewAlignment, child: preview),
        ),
      ),
    );
  }
}
