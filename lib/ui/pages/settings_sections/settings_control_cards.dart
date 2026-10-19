import 'dart:ui' show ClipOp;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/app_providers.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/constants/app_constants.dart';
import '../../widgets/settings_card_inset.dart';
import '../../widgets/settings_card_indicator.dart';
import '../../widgets/settings_card_layout.dart';
import '../../widgets/popup_menu_helpers.dart';
import '../../widgets/toggle_switch.dart';

/// Uses full-width settings rows by default, or compact cards when enabled.
class SettingsControlWrap extends ConsumerWidget {
  const SettingsControlWrap({
    super.key,
    required this.children,
    this.minimumCardWidth = kInteractionCardMinWidth,
  });

  final List<Widget> children;
  final double minimumCardWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (children.isEmpty) return const SizedBox.shrink();
    final useCards = ref.watch(experimentalInteractionCardsProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final width = constraints.maxWidth;
        if (!width.isFinite) {
          return Wrap(spacing: gap, runSpacing: gap, children: children);
        }
        final cardWidth = useCards
            ? settingsCardWidth(
                availableWidth: width,
                cardCount: children.length,
                minimumCardWidth: minimumCardWidth,
                spacing: gap,
              )
            : width;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(width: cardWidth, child: child),
          ],
        );
      },
    );
  }
}

class SettingsChoice<T> {
  const SettingsChoice(this.value, this.label);

  final T value;
  final String label;
}

class SettingsToggleCard extends ConsumerWidget {
  const SettingsToggleCard({
    super.key,
    required this.theme,
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
    this.labelColor,
    this.indicatorStyle,
  });

  final AppThemeData theme;
  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? labelColor;

  /// Optional override for live style previews.
  final SettingsCardIndicatorStyle? indicatorStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useCards = ref.watch(experimentalInteractionCardsProvider);
    final SettingsCardIndicatorStyle style = useCards
        ? (indicatorStyle ?? ref.watch(settingsCardIndicatorStyleProvider))
        : SettingsCardIndicatorStyle.switchControl;
    return Semantics(
      button: true,
      toggled: value,
      enabled: onChanged != null,
      label: label,
      value: onChanged == null
          ? 'Disabled'
          : value
          ? 'On'
          : 'Off',
      child: _SettingsControlCard(
        theme: theme,
        label: label,
        description: description,
        labelColor: labelColor,
        active: value,
        isToggle: true,
        indicatorStyle: style,
        enabled: onChanged != null,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: style != SettingsCardIndicatorStyle.switchControl
            ? const SizedBox.shrink()
            : ExcludeSemantics(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  // Switch animations can repaint without redrawing the card shading.
                  child: RepaintBoundary(
                    child: AppToggleSwitch(
                      value: value,
                      onChanged: onChanged,
                      theme: theme,
                      style: ref.watch(toggleStyleProvider),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// A whole-card action for status and management settings.
class SettingsActionCard extends StatelessWidget {
  const SettingsActionCard({
    super.key,
    required this.theme,
    required this.label,
    required this.actionLabel,
    required this.onTap,
    this.description,
    this.actionIcon,
    this.labelColor,
  });

  final AppThemeData theme;
  final String label;
  final String? description;
  final String actionLabel;
  final IconData? actionIcon;
  final Color? labelColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: '$label, $actionLabel',
      child: _SettingsControlCard(
        theme: theme,
        label: label,
        description: description,
        labelColor: labelColor,
        active: false,
        enabled: onTap != null,
        onTap: onTap,
        trailing: LayoutBuilder(
          builder: (context, constraints) {
            final showIcons = constraints.maxWidth >= 120;
            return Row(
              children: [
                if (showIcons && actionIcon != null) ...[
                  Icon(actionIcon, color: theme.accent, size: 18),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    actionLabel,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (showIcons) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: theme.textPrimary,
                    size: 18,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class SettingsChoiceCard<T> extends StatelessWidget {
  const SettingsChoiceCard({
    super.key,
    required this.theme,
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.description,
  });

  final AppThemeData theme;
  final String label;
  final String? description;

  final T value;
  final List<SettingsChoice<T>> choices;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = choices
        .where((choice) => choice.value == value)
        .firstOrNull;
    final selectedLabel = selected?.label ?? value.toString();
    final selectedChoice = Align(
      widthFactor: 1,
      heightFactor: 1,
      alignment: Alignment.centerRight,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selectedLabel,
              style: TextStyle(
                color: theme.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.arrow_drop_down, color: theme.textSecondary),
          ],
        ),
      ),
    );
    return Builder(
      builder: (cardContext) => Semantics(
        button: true,
        enabled: onChanged != null,
        label: label,
        value: selectedLabel,
        child: _SettingsControlCard(
          theme: theme,
          label: label,
          description: description,
          active: selected != null,
          enabled: onChanged != null,
          onTap: onChanged == null ? null : () => _openMenu(cardContext),
          trailing: selectedChoice,
        ),
      ),
    );
  }

  Future<void> _openMenu(BuildContext context) async {
    final card = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final origin = card.localToGlobal(Offset.zero);
    final useCards = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(experimentalInteractionCardsProvider);
    final menuWidth = useCards
        ? card.size.width
        : card.size.width.clamp(0.0, kInteractionCardMaxWidth);
    final selected = await showAppMenu<T>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          origin.dx + card.size.width - menuWidth,
          origin.dy + card.size.height,
          menuWidth,
          1,
        ),
        Offset.zero & overlay.size,
      ),
      color: theme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cornerRadius),
      ),
      constraints: BoxConstraints(minWidth: menuWidth),
      items: [
        for (final choice in choices)
          CheckedPopupMenuItem<T>(
            value: choice.value,
            checked: choice.value == value,
            child: Text(
              choice.label,
              style: TextStyle(color: theme.textPrimary),
            ),
          ),
      ],
    );
    if (selected != null && context.mounted) onChanged?.call(selected);
  }
}

class _SettingsControlCard extends ConsumerStatefulWidget {
  const _SettingsControlCard({
    required this.theme,
    required this.label,
    required this.description,
    required this.active,
    required this.enabled,
    required this.trailing,
    this.onTap,
    this.labelColor,
    this.isToggle = false,
    this.indicatorStyle = SettingsCardIndicatorStyle.switchControl,
  });

  final AppThemeData theme;
  final String label;
  final String? description;
  final bool active;
  final bool enabled;
  final Widget trailing;
  final bool isToggle;
  final SettingsCardIndicatorStyle indicatorStyle;
  final VoidCallback? onTap;
  final Color? labelColor;

  @override
  ConsumerState<_SettingsControlCard> createState() =>
      _SettingsControlCardState();
}

class _SettingsControlCardState extends ConsumerState<_SettingsControlCard> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    if (!ref.watch(experimentalInteractionCardsProvider)) {
      return _SettingsControlRow(
        theme: theme,
        label: widget.label,
        description: widget.description,
        labelColor: widget.labelColor,
        enabled: widget.enabled,
        onTap: widget.onTap,
        trailing: widget.trailing,
      );
    }
    final radius = BorderRadius.circular(theme.cornerRadius);
    final indicatorSize =
        widget.isToggle &&
            widget.indicatorStyle != SettingsCardIndicatorStyle.switchControl
        ? SettingsCardIndicator.size
        : null;
    final highlighted = widget.enabled && (_hovered || _pressed || _focused);
    final material = Material(
      animationDuration: const Duration(milliseconds: 140),
      color: theme.background.withValues(alpha: widget.enabled ? 0.65 : 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: !widget.enabled || indicatorSize != null
            ? BorderSide.none
            : BorderSide(
                color: highlighted ? theme.accent : theme.border,
                width: highlighted ? 1.5 : 1,
              ),
      ),
      child: InkWell(
        borderRadius: radius,
        mouseCursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onHover: widget.enabled
            ? (value) => setState(() => _hovered = value)
            : null,
        onHighlightChanged: widget.enabled
            ? (value) => setState(() => _pressed = value)
            : null,
        onFocusChange: widget.enabled
            ? (value) => setState(() => _focused = value)
            : null,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: widget.enabled ? 1 : 0.42,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) => ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: indicatorSize == null
                              ? 0
                              : (indicatorSize.height - 10).clamp(
                                  0.0,
                                  double.infinity,
                                ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      widget.label,
                                      overflow: TextOverflow.visible,
                                      style: TextStyle(
                                        color:
                                            widget.labelColor ??
                                            theme.textPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (indicatorSize != null)
                              SizedBox(width: indicatorSize.width)
                            else ...[
                              const SizedBox(width: 12),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: constraints.maxWidth * 0.65,
                                ),
                                child: widget.trailing,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (widget.description?.trim().isNotEmpty == true) ...[
                      Divider(height: 16, color: theme.border),
                      Text(
                        widget.description!,
                        style: TextStyle(
                          color: theme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final indicatorOverlay = indicatorSize == null
        ? null
        : CustomPaint(
            foregroundPainter: widget.enabled
                ? _SettingsIndicatorBorderPainter(
                    radius: theme.cornerRadius,
                    color: highlighted ? theme.accent : theme.border,
                    indicatorSize: indicatorSize,
                    omitIndicator:
                        widget.indicatorStyle ==
                            SettingsCardIndicatorStyle.retroSquare &&
                        (widget.active || !highlighted),
                  )
                : null,
            child: ExcludeSemantics(
              child: ClipRRect(
                borderRadius: radius,
                child: Align(
                  alignment: Alignment.topRight,
                  child: RepaintBoundary(
                    child: SettingsCardIndicator(
                      theme: theme,
                      value: widget.active,
                      enabled: widget.enabled,
                    ),
                  ),
                ),
              ),
            ),
          );
    return RepaintBoundary(
      child: SettingsCardInset(
        active: widget.active && widget.enabled,
        raisedWhenInactive: widget.isToggle && widget.enabled,
        surfaceColor: theme.background,
        borderRadius: theme.cornerRadius,
        overlay: indicatorOverlay == null
            ? null
            : RepaintBoundary(child: indicatorOverlay),
        shadeOverlay: !(widget.active && widget.enabled),
        child: RepaintBoundary(child: material),
      ),
    );
  }
}

/// OFF hover outlines cross the indicator without changing its geometry.
class _SettingsIndicatorBorderPainter extends CustomPainter {
  const _SettingsIndicatorBorderPainter({
    required this.radius,
    required this.color,
    required this.indicatorSize,
    required this.omitIndicator,
  });

  final double radius;
  final Color color;
  final Size indicatorSize;
  final bool omitIndicator;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).scaleRadii();
    canvas.save();
    if (omitIndicator) {
      canvas.clipRect(
        Rect.fromLTWH(
          size.width - indicatorSize.width,
          -1,
          indicatorSize.width + 1,
          indicatorSize.height + 1,
        ),
        clipOp: ClipOp.difference,
        doAntiAlias: false,
      );
    }
    canvas.drawRRect(
      outline.deflate(0.5),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SettingsIndicatorBorderPainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.color != color ||
      oldDelegate.indicatorSize != indicatorSize ||
      oldDelegate.omitIndicator != omitIndicator;
}

/// Legacy settings presentation: the entire row is clickable, with its control
/// at the right edge and no card border, fill, or selection glow.
class _SettingsControlRow extends StatelessWidget {
  const _SettingsControlRow({
    required this.theme,
    required this.label,
    required this.description,
    required this.enabled,
    required this.onTap,
    required this.trailing,
    required this.labelColor,
  });

  final AppThemeData theme;
  final String label;
  final String? description;
  final bool enabled;
  final VoidCallback? onTap;
  final Widget trailing;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      borderRadius: BorderRadius.circular(theme.cornerRadius),
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.forbidden,
      onTap: enabled ? onTap : null,
      hoverColor: theme.accent.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Opacity(
          opacity: enabled ? 1 : 0.42,
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              label,
                              style: TextStyle(
                                color: labelColor ?? theme.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (description?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 2),
                        Text(
                          description!,
                          style: TextStyle(
                            color: theme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.45,
                  ),
                  child: trailing,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
