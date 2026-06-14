/// Tag-row widget for GameCard.
///
/// Owns the per-card tag-fit measurement cache so those 4 state fields and 3
/// builder methods can be removed from [_GameCardState].
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import 'game_card_badges.dart';
import 'game_card_painters.dart';
import 'tag_width_cache.dart';

/// Animated tag row with built-in show/hide reveal and per-card layout cache.
///
/// Drop this directly into grid or list layouts in place of the old
/// `_buildAnimatedTagsRow` / `_buildTagsRow` / `_buildTagsRowForWidth` trio.
class GameCardTagsRow extends StatefulWidget {
  const GameCardTagsRow({
    super.key,
    required this.game,
    required this.theme,
    required this.isVisible,
    this.fixedMaxWidth,
    this.topSpacing = 0.0,
  });

  final Game game;
  final AppThemeData theme;
  final bool isVisible;

  /// When non-null (grid mode) skips the [LayoutBuilder] measurement pass.
  final double? fixedMaxWidth;

  /// Extra spacing above the tag row.
  final double topSpacing;

  @override
  State<GameCardTagsRow> createState() => _GameCardTagsRowState();
}

class _GameCardTagsRowState extends State<GameCardTagsRow> {
  // ── Per-card tag-fit cache (non-reactive, no setState needed) ─────────────
  String? _lastTagCacheKey;
  int _cachedTagBestCount = 0;
  double _cachedTagBestWidth = 0.0;
  bool _cachedTagCountFits = false;

  @override
  void didUpdateWidget(GameCardTagsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Invalidate if the game changes (different tag list).
    if (oldWidget.game.id != widget.game.id) {
      _lastTagCacheKey = null;
    }
  }

  // ── Tag row ───────────────────────────────────────────────────────────────

  Widget _buildTagsRow(BuildContext context) {
    final tagNames = widget.game.tags.map((t) => t.name).toList();
    if (tagNames.isEmpty) return const SizedBox.shrink();

    if (widget.fixedMaxWidth != null) {
      return _buildTagsRowForWidth(
        context,
        widget.fixedMaxWidth!,
        tagNames,
        MediaQuery.textScalerOf(context),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final rawWidth =
            constraints.hasBoundedWidth && constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final bucketedWidth = (rawWidth / 8).floorToDouble() * 8.0;
        return _buildTagsRowForWidth(context, bucketedWidth, tagNames, textScaler);
      },
    );
  }

  Widget _buildTagsRowForWidth(
    BuildContext context,
    double maxWidth,
    List<String> tagNames,
    TextScaler textScaler,
  ) {
    final textDirection = Directionality.of(context);
    final tagStyle = TextStyle(
      color: widget.theme.textPrimary,
      fontSize: 11,
      fontWeight: FontWeight.w300,
    );
    final countStyle = TextStyle(
      color: widget.theme.textPrimary,
      fontSize: 11,
      fontWeight: FontWeight.w300,
    );
    final baseTextStyle = DefaultTextStyle.of(context).style;
    final resolvedTagStyle = baseTextStyle.merge(tagStyle);
    final resolvedCountStyle = baseTextStyle.merge(countStyle);
    const chipPadding = EdgeInsets.symmetric(horizontal: 6, vertical: 3);
    const countPadding = EdgeInsets.symmetric(horizontal: 6, vertical: 3);
    const gap = 4.0;

    double measureChip(String text, TextStyle style, EdgeInsets padding) {
      return TagWidthCache.measureTextWidth(text, style, textDirection, textScaler)
          + padding.horizontal
          + 2.0;
    }

    final tagFingerprint = widget.game.tags.map((t) => t.id).join(',');
    final tagKey =
        '${maxWidth.toStringAsFixed(0)}:${textScaler.scale(1.0).toStringAsFixed(3)}:$tagFingerprint';

    int bestCount;
    double bestTagsWidth;
    bool countFits;

    if (tagKey == _lastTagCacheKey) {
      bestCount = _cachedTagBestCount;
      bestTagsWidth = _cachedTagBestWidth;
      countFits = _cachedTagCountFits;
    } else {
      final separatorWidth = TagWidthCache.measureTextWidth(
        ' · ',
        resolvedTagStyle,
        textDirection,
        textScaler,
      );

      final tagNameWidths = List<double>.generate(
        tagNames.length,
        (i) => TagWidthCache.measureTextWidth(tagNames[i], resolvedTagStyle, textDirection, textScaler),
        growable: false,
      );

      final countWidthCache = <int, double>{};
      double countChipWidthFor(int remaining) {
        return countWidthCache.putIfAbsent(
          remaining,
          () => measureChip('+$remaining', resolvedCountStyle, countPadding),
        );
      }

      bestCount = 0;
      double runningTextWidth = 0.0;
      bestTagsWidth = 0.0;
      for (var i = 0; i < tagNames.length; i++) {
        runningTextWidth += tagNameWidths[i];
        if (i > 0) runningTextWidth += separatorWidth;

        final visibleCount = i + 1;
        final remaining = tagNames.length - visibleCount;
        final tagsWidth = runningTextWidth + chipPadding.horizontal + 2.0;

        double trailingCountWidth = 0.0;
        if (remaining > 0) {
          trailingCountWidth = countChipWidthFor(remaining) + gap;
        }

        if (tagsWidth + trailingCountWidth <= maxWidth) {
          bestCount = visibleCount;
          bestTagsWidth = tagsWidth;
        } else {
          break;
        }
      }

      final remainingForFit = tagNames.length - bestCount;
      countFits = remainingForFit > 0
          ? (countChipWidthFor(remainingForFit) +
                  (bestTagsWidth > 0 ? bestTagsWidth + gap : 0.0) <=
              maxWidth)
          : false;

      _lastTagCacheKey = tagKey;
      _cachedTagBestCount = bestCount;
      _cachedTagBestWidth = bestTagsWidth;
      _cachedTagCountFits = countFits;
    }

    final showTagsText = bestCount > 0;
    final remainingCount = tagNames.length - bestCount;
    final displayTags = showTagsText ? tagNames.take(bestCount).join(' · ') : '';
    final displayCount = remainingCount > 0 ? '+$remainingCount' : '';
    final representativeTag = widget.game.tags.first;

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showTagsText)
            Flexible(
              fit: FlexFit.loose,
              child: buildTagChip(
                widget.theme,
                displayTags,
                padding: chipPadding,
                overrideBackground: representativeTag.isSteamTag
                    ? widget.theme.accent
                    : representativeTag.color,
                overrideTextColor: widget.theme.primaryButtonText,
              ),
            ),
          if (remainingCount > 0 && countFits) ...[
            if (showTagsText) const SizedBox(width: gap),
            buildTagChip(
              widget.theme,
              displayCount,
              padding: countPadding,
              weight: FontWeight.w600,
              overrideBackground: representativeTag.isSteamTag
                  ? widget.theme.accent.withValues(alpha: 0.92)
                  : representativeTag.color.withValues(alpha: 0.92),
              overrideTextColor: widget.theme.primaryButtonText,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // When hidden, avoid constructing the real widget at all to skip expensive
    // width measurement. Use a lightweight placeholder instead.
    final Widget childWidget = widget.isVisible
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.topSpacing > 0) SizedBox(height: widget.topSpacing),
              _buildTagsRow(context),
            ],
          )
        : const SizedBox.shrink();

    return VisibilityReveal(
      isVisible: widget.isVisible,
      axisAlignment: 1.0,
      alignment: Alignment.bottomLeft,
      child: childWidget,
    );
  }
}
