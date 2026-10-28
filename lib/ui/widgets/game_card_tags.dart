/// Lightweight, content-sized tag badges for grid and list game cards.
library;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/color_utils.dart';
import '../../models/game.dart';
import 'game_card_badges.dart';
import 'game_card_painters.dart';
import 'tag_width_cache.dart';

class GameCardTagsRow extends StatefulWidget {
  const GameCardTagsRow({
    super.key,
    required this.game,
    required this.theme,
    required this.isVisible,
    this.fixedMaxWidth,
    this.topSpacing = 0,
  });

  final Game game;
  final AppThemeData theme;
  final bool isVisible;
  final double? fixedMaxWidth;
  final double topSpacing;

  @override
  State<GameCardTagsRow> createState() => _GameCardTagsRowState();
}

class _GameCardTagsRowState extends State<GameCardTagsRow> {
  static const _padding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);
  static const _gap = 4.0;

  List<String> _names = const [];
  String _tooltip = '';
  (double, TextStyle, TextScaler, TextDirection, Locale?)? _layoutKey;
  String _label = '';
  String _count = '';

  @override
  void initState() {
    super.initState();
    _updateTags();
  }

  @override
  void didUpdateWidget(GameCardTagsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.game.tags, widget.game.tags) &&
        !const ListEquality<Tag>().equals(
          oldWidget.game.tags,
          widget.game.tags,
        )) {
      _updateTags();
    }
  }

  void _updateTags() {
    _names = widget.game.tags.map((tag) => tag.name).toList(growable: false);
    _tooltip = _names.join('\n');
    _layoutKey = null;
  }

  void _fit(
    double width,
    TextStyle style,
    TextScaler scaler,
    TextDirection direction,
    Locale? locale,
  ) {
    final key = (width, style, scaler, direction, locale);
    if (key == _layoutKey) return;
    _layoutKey = key;
    double measure(String text) => TagWidthCache.measureTextWidth(
      text,
      style,
      direction,
      scaler,
      locale: locale,
    );
    final separatorWidth = measure(' · ');
    double countWidth(int count) => measure('+$count') + _padding.horizontal;
    var bestCount = 0;
    var textWidth = 0.0;
    for (var i = 0; i < _names.length; i++) {
      textWidth += measure(_names[i]) + (i == 0 ? 0 : separatorWidth);
      final labelWidth = textWidth + _padding.horizontal;
      // Once the prefix alone exceeds the width, no later prefix can fit.
      // Do not stop just because the count badge doesn't fit: a final small
      // tag may fit while removing the count badge altogether.
      if (labelWidth > width) break;
      final remaining = _names.length - i - 1;
      if (labelWidth + (remaining == 0 ? 0 : _gap + countWidth(remaining)) <=
          width) {
        bestCount = i + 1;
      }
    }
    _label = _names.take(bestCount).join(' · ');
    _count = bestCount == _names.length ? '' : '+${_names.length - bestCount}';
  }

  Widget _badge(String text, TextStyle style, Color color) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: kGameCardChipBackgroundAlpha),
      borderRadius: GameCardBadges.chipBorderRadius(widget.theme, kBadgeHeight),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kBadgeHeight),
      child: Padding(
        padding: _padding,
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          child: Text(
            text,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ),
  );

  Widget _row(BuildContext context, double width) {
    final firstTag = widget.game.tags.first;
    final color = firstTag.isSteamTag
        ? widget.theme.accent
        : widget.theme.secondary;
    // Measured with a fixed colour, so a colour-only theme change keeps the
    // cached layout; drawn in whichever of black or white reads on the fill.
    final measureStyle = DefaultTextStyle.of(context).style.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );
    final style = measureStyle.copyWith(color: contrastColor(color));
    _fit(
      width,
      measureStyle,
      MediaQuery.textScalerOf(context),
      Directionality.of(context),
      Localizations.maybeLocaleOf(context),
    );
    return Tooltip(
      message: _tooltip,
      // Mouse hover can reveal the full list; leave touch long-press to the card.
      triggerMode: TooltipTriggerMode.manual,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_label.isNotEmpty)
              Flexible(child: _badge(_label, style, color)),
            if (_count.isNotEmpty) ...[
              if (_label.isNotEmpty) const SizedBox(width: _gap),
              if (_label.isNotEmpty)
                _badge(_count, style, color)
              else
                Flexible(child: _badge(_count, style, color)),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child = const SizedBox.shrink();
    // Hidden rows never construct badges or measure text. Cache tag data across
    // ordinary rebuilds, and layout across color-only theme changes.
    if (widget.isVisible && _names.isNotEmpty) {
      final row = widget.fixedMaxWidth == null
          ? LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.hasBoundedWidth
                    ? constraints.maxWidth
                    : MediaQuery.sizeOf(context).width;
                return _row(context, (width / 8).floorToDouble() * 8);
              },
            )
          : _row(context, widget.fixedMaxWidth!);
      child = Padding(
        padding: EdgeInsets.only(top: widget.topSpacing),
        child: row,
      );
    }
    return VisibilityReveal(
      isVisible: widget.isVisible,
      axisAlignment: 1,
      alignment: Alignment.bottomLeft,
      child: child,
    );
  }
}
