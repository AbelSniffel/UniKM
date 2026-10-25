/// Badge and chip builder helpers for GameCard.
///
/// All methods are static and take only the data they need ([AppThemeData] +
/// relevant [Game] fields) so they can live outside the card's widget state.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/constants/app_constants.dart';
import '../../core/constants/platform_patterns.dart';
import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import '../../shared/time/calendar_date.dart';
import '../../providers/app_providers.dart';
import '../widgets/app_progress_indicator.dart';
import 'game_card_painters.dart';
import 'platform_icon.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants (formerly static fields of _GameCardState)
// ─────────────────────────────────────────────────────────────────────────────

const double kBadgeHeight = 28.0;
const double kGameCardChipBackgroundAlpha = 0.80;
const double kPlatformBadgeHeight = 32.0;
const double kSelectionIndicatorSize = 20.0;
const EdgeInsets kSelectionIndicatorPadding = EdgeInsets.all(8.0);

// ─────────────────────────────────────────────────────────────────────────────
// GameCardBadges
// ─────────────────────────────────────────────────────────────────────────────

abstract final class GameCardBadges {
  static final NumberFormat _compactNumber = NumberFormat.compact();
  static final DateFormat _deadlineFormat = DateFormat('dd/MM/yyyy');

  // ── Primitive builders ────────────────────────────────────────────────────

  static BorderRadius chipBorderRadius(
    AppThemeData theme,
    double extent, {
    double multiplier = 1.0,
  }) {
    return BorderRadius.circular(
      math.min(theme.cornerRadius * multiplier, extent / 2),
    );
  }

  static Widget squareIconBadge(
    AppThemeData theme, {
    required String tooltip,
    required Color color,
    required Widget icon,
    required double size,
    String? semanticsLabel,
    BorderRadius? borderRadius,
  }) {
    Widget content = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius ?? chipBorderRadius(theme, size),
      ),
      child: icon,
    );

    if (semanticsLabel != null) {
      content = Semantics(label: semanticsLabel, child: content);
    }

    return Tooltip(message: tooltip, child: content);
  }

  static Widget pillBadge(
    AppThemeData theme, {
    required String tooltip,
    required Color color,
    required Widget child,
    BorderRadius? borderRadius,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    double? minHeight,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        alignment: Alignment.center,
        padding: padding,
        constraints: minHeight != null
            ? BoxConstraints.tightFor(height: minHeight)
            : null,
        decoration: BoxDecoration(
          color: color,
          borderRadius:
              borderRadius ??
              chipBorderRadius(theme, minHeight ?? kBadgeHeight),
        ),
        child: child,
      ),
    );
  }

  // ── Fetch-status helpers ──────────────────────────────────────────────────

  static FetchStatusVisual fetchStatusVisual(
    AppThemeData theme,
    GameFetchStatus status, {
    required double iconSize,
    bool compactProcessingSpinner = false,
  }) {
    switch (status) {
      case GameFetchStatus.waiting:
        return FetchStatusVisual(
          color: theme.secondary,
          tooltip: 'Queued for fetch',
          icon: Icon(Icons.schedule, color: Colors.white, size: iconSize),
        );
      case GameFetchStatus.processing:
        final spinnerSize = compactProcessingSpinner
            ? (iconSize - 3.0).clamp(10.0, iconSize)
            : iconSize;
        return FetchStatusVisual(
          color: theme.background,
          tooltip: 'Fetching from Steam',
          icon: AppCircularProgressIndicator(size: spinnerSize),
        );
      case GameFetchStatus.done:
        return FetchStatusVisual(
          color: Colors.green,
          tooltip: 'Fetch completed',
          icon: Icon(Icons.check, color: Colors.white, size: iconSize),
        );
      case GameFetchStatus.error:
        return FetchStatusVisual(
          color: theme.secondary,
          tooltip: 'Fetch failed',
          icon: Icon(
            Icons.error,
            color: theme.primaryButtonText,
            size: iconSize,
          ),
        );
    }
  }

  // ── Concrete badge builders ───────────────────────────────────────────────

  static Widget platformBadge(
    AppThemeData theme,
    Game game, {
    BorderRadius? borderRadius,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    double? minHeight,
  }) {
    return platformBadgeForType(
      theme,
      platform: game.platformEnum,
      platformLabel: game.platform,
      borderRadius: borderRadius,
      padding: padding,
      minHeight: minHeight,
    );
  }

  static Widget platformBadgeForType(
    AppThemeData theme, {
    required GamePlatform platform,
    String? platformLabel,
    BorderRadius? borderRadius,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    double? minHeight,
  }) {
    platformLabel ??= platform.displayName;
    final double iconSize = platformIconSizeFor(platform, minHeight: minHeight);
    final chipColor = theme.baseSecondary.withValues(
      alpha: kGameCardChipBackgroundAlpha,
    );
    final bool iconOnly = minHeight != null;

    if (iconOnly) {
      return squareIconBadge(
        theme,
        tooltip: platformLabel,
        color: chipColor,
        size: minHeight,
        semanticsLabel: platformLabel,
        borderRadius: chipBorderRadius(theme, minHeight),
        icon: PlatformIcon(
          platform: platform,
          size: iconSize,
          color: theme.primaryButtonText,
        ),
      );
    }

    return pillBadge(
      theme,
      tooltip: platformLabel,
      color: chipColor,
      borderRadius: borderRadius,
      padding: padding,
      minHeight: minHeight,
      child: Semantics(
        label: platformLabel,
        child: PlatformIcon(
          platform: platform,
          size: iconSize,
          color: theme.accent,
        ),
      ),
    );
  }

  static Widget ratingBadge(
    AppThemeData theme,
    Game game, {
    BorderRadius? borderRadius,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    double? minHeight,
  }) {
    final reviewCount = game.reviewCount;
    final ratingText = reviewCount == 0
        ? 'No Reviews'
        : '${game.reviewScore}% · ${game.reviewRating} · ${_compactNumber.format(reviewCount)}';

    return pillBadge(
      theme,
      tooltip: ratingText,
      color: game
          .reviewColorFor(negativeColor: theme.secondary)
          .withValues(alpha: 0.95),
      borderRadius: borderRadius,
      padding: padding,
      minHeight: minHeight,
      child: Icon(
        _ratingIconFor(game.reviewScore, game.reviewCount),
        color: Colors.white,
        size: 18.0,
      ),
    );
  }

  static Widget deadlineBadge(
    AppThemeData theme,
    DateTime? deadlineDate, {
    BorderRadius? borderRadius,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    bool showIcon = false,
    double? minHeight,
    bool forceIconOnly = false,
  }) {
    final daysLeft = deadlineDate == null
        ? 0
        : calendarDaysUntil(
            DateUtils.dateOnly(deadlineDate),
            DateUtils.dateOnly(DateTime.now()),
          );
    final isExpired = daysLeft < 0;
    final isUrgent = daysLeft <= 3 && !isExpired;
    final isSoon = daysLeft <= 7 && !isExpired && !isUrgent;
    final isDueSoon = daysLeft <= 14 && !isExpired;
    final dueText = daysLeft == 0 ? 'Today' : '$daysLeft days';
    final iconOnly = forceIconOnly || (!isExpired && !isDueSoon);
    const iconSize = 18.0;

    Color badgeColor;
    String text;

    if (isExpired) {
      badgeColor = theme.secondary;
      text = 'Expired';
    } else if (isUrgent) {
      badgeColor = theme.deadlineUrgent;
      text = dueText;
    } else if (isSoon) {
      badgeColor = theme.deadlineSoon;
      text = dueText;
    } else {
      badgeColor = theme.deadlineNormal;
      final date = deadlineDate;
      text = isDueSoon
          ? dueText
          : date != null
          ? _deadlineFormat.format(date)
          : 'Deadline';
    }

    badgeColor = badgeColor.withValues(alpha: kGameCardChipBackgroundAlpha);

    final String tooltipMessage;
    if (isExpired) {
      if (deadlineDate == null) {
        tooltipMessage = 'Expired';
      } else {
        final daysAgo = daysLeft.abs();
        final agoText = daysAgo == 0
            ? 'today'
            : daysAgo == 1
            ? '1 day ago'
            : '$daysAgo days ago';
        tooltipMessage =
            'Expired $agoText · ${_deadlineFormat.format(deadlineDate)}';
      }
    } else if (deadlineDate == null) {
      tooltipMessage = text;
    } else if (daysLeft == 0) {
      tooltipMessage = 'Due today · ${_deadlineFormat.format(deadlineDate)}';
    } else {
      tooltipMessage =
          'Due in $daysLeft days · ${_deadlineFormat.format(deadlineDate)}';
    }

    if (iconOnly && minHeight != null) {
      return squareIconBadge(
        theme,
        tooltip: tooltipMessage,
        color: badgeColor,
        size: minHeight,
        borderRadius: chipBorderRadius(theme, minHeight),
        icon: _deadlineStatusIcon(isExpired, size: iconSize),
      );
    }

    return Tooltip(
      message: tooltipMessage,
      child: IntrinsicWidth(
        child: Container(
          alignment: Alignment.center,
          padding: padding,
          constraints: minHeight != null
              ? BoxConstraints(minHeight: minHeight)
              : null,
          decoration: BoxDecoration(
            color: badgeColor,
            borderRadius:
                borderRadius ??
                chipBorderRadius(theme, minHeight ?? kBadgeHeight),
          ),
          child: iconOnly
              ? _deadlineStatusIcon(isExpired, size: iconSize)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showIcon) ...[
                      _deadlineStatusIcon(isExpired, size: iconSize),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  static Widget titleChip(AppThemeData theme, String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.background.withValues(alpha: 0.75),
        borderRadius: chipBorderRadius(theme, kBadgeHeight),
      ),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  static Widget slimFetchStatusBadge(
    AppThemeData theme,
    Game game,
    GameFetchStatus status, {
    required double minHeight,
  }) {
    final iconSize = platformIconSizeFor(
      game.platformEnum,
      minHeight: minHeight,
    );
    final visual = fetchStatusVisual(
      theme,
      status,
      iconSize: iconSize,
      compactProcessingSpinner: true,
    );

    return squareIconBadge(
      theme,
      tooltip: visual.tooltip,
      color: visual.color,
      size: minHeight,
      icon: AnimatedSwitcher(
        duration: kVeryFastAnimation,
        transitionBuilder: (child, anim) => ScaleTransition(
          scale: anim,
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: SizedBox(
          key: ValueKey(status),
          width: iconSize,
          height: iconSize,
          child: Center(child: visual.icon),
        ),
      ),
    );
  }

  static Widget slimSelectionBadge(
    AppThemeData theme,
    Game game, {
    required double minHeight,
  }) {
    final iconSize = platformIconSizeFor(
      game.platformEnum,
      minHeight: minHeight,
    );
    return squareIconBadge(
      theme,
      tooltip: 'Selected',
      color: theme.accent,
      size: minHeight,
      icon: Icon(Icons.check, color: Colors.white, size: iconSize),
    );
  }

  // ── Top-right chip cluster ────────────────────────────────────────────────

  static Widget topRightChips(
    AppThemeData theme,
    Game game, {
    required bool showPlatform,
    required bool showRatings,
    EdgeInsets padding = const EdgeInsets.symmetric(
      horizontal: 5.0,
      vertical: 5.0,
    ),
  }) {
    final bool showRatingChip = showRatings && game.reviewCount > 0;
    if (!showRatingChip && !showPlatform) return const SizedBox.shrink();

    final Widget content = showPlatform
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              platformBadge(
                theme,
                game,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                minHeight: kPlatformBadgeHeight,
              ),
              if (showRatingChip)
                _animatedRatingChip(
                  theme,
                  game,
                  borderRadius: chipBorderRadius(theme, 20.0),
                  topPadding: 4,
                ),
            ],
          )
        : _animatedRatingChip(
            theme,
            game,
            borderRadius: chipBorderRadius(theme, kBadgeHeight),
            minHeight: kBadgeHeight,
          );

    return Padding(padding: padding, child: content);
  }

  // ── Slim trailing chips ───────────────────────────────────────────────────

  static Widget slimTrailingChips(
    AppThemeData theme,
    Game game, {
    required bool showDeadline,
    required bool showRating,
    required bool showPlatform,
    required GameFetchStatus? fetchStatus,
    required bool isSelected,
  }) {
    final baseChips = <Widget>[
      if (showDeadline)
        deadlineBadge(
          theme,
          game.deadlineDate,
          borderRadius: chipBorderRadius(theme, kBadgeHeight),
          showIcon: true,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          minHeight: kBadgeHeight,
          forceIconOnly: true,
        ),
      if (showRating)
        ratingBadge(
          theme,
          game,
          borderRadius: chipBorderRadius(theme, kBadgeHeight),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          minHeight: kBadgeHeight,
        ),
      if (showPlatform) platformBadge(theme, game, minHeight: kBadgeHeight),
    ];

    final hasExtraChips = fetchStatus != null || isSelected;
    if (baseChips.isEmpty && !hasExtraChips) return const SizedBox.shrink();

    final extraChips = <Widget>[
      if (fetchStatus != null)
        slimFetchStatusBadge(theme, game, fetchStatus, minHeight: kBadgeHeight),
      if (isSelected) slimSelectionBadge(theme, game, minHeight: kBadgeHeight),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < baseChips.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          baseChips[i],
        ],
        if (hasExtraChips && baseChips.isNotEmpty) const SizedBox(width: 6),
        ClipRect(
          child: AnimatedSize(
            duration: kFastAnimation,
            curve: Curves.easeInOutCubic,
            alignment: Alignment.centerRight,
            child: hasExtraChips
                ? RepaintBoundary(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < extraChips.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          extraChips[i],
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  static Widget _deadlineStatusIcon(bool isExpired, {double size = 18.0}) {
    return Icon(
      isExpired ? Icons.event_busy : Icons.schedule,
      color: Colors.white,
      size: size,
    );
  }

  static IconData _ratingIconFor(int score, int reviewCount) {
    if (reviewCount == 0) return Icons.help_outline_rounded;
    if (score >= 95) return Icons.auto_awesome_rounded;
    if (score >= 90) return Icons.thumb_up_alt_rounded;
    if (score >= 75) return Icons.thumb_up_rounded;
    if (score >= 60) return Icons.thumbs_up_down_rounded;
    if (score >= 40) return Icons.thumb_down_alt_rounded;
    return Icons.thumb_down_rounded;
  }

  static Widget _animatedRatingChip(
    AppThemeData theme,
    Game game, {
    required BorderRadius borderRadius,
    double? minHeight,
    double topPadding = 0,
  }) {
    Widget rating = ratingBadge(
      theme,
      game,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      borderRadius: borderRadius,
      minHeight: minHeight,
    );

    if (topPadding > 0) {
      rating = Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: rating,
      );
    }

    return VisibilityReveal(
      isVisible: true,
      axisAlignment: -1.0,
      alignment: Alignment.topCenter,
      child: rating,
    );
  }
}
