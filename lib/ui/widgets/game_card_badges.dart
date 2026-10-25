/// Badge and chip builder helpers for GameCard.
///
/// All methods are static and take only the data they need ([AppThemeData] +
/// relevant [Game] fields) so they can live outside the card's widget state.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/constants/app_constants.dart';
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
  }) => BorderRadius.circular(
    math.min(theme.cornerRadius * multiplier, extent / 2),
  );

  static Widget squareIconBadge(
    AppThemeData theme, {
    required String tooltip,
    required Color color,
    required Widget icon,
    required double size,
    String? semanticsLabel,
  }) {
    Widget content = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: chipBorderRadius(theme, size),
      ),
      child: icon,
    );

    if (semanticsLabel != null) {
      content = Semantics(label: semanticsLabel, child: content);
    }

    return Tooltip(message: tooltip, child: content);
  }

  // ── Fetch-status helpers ──────────────────────────────────────────────────

  static FetchStatusVisual fetchStatusVisual(
    AppThemeData theme,
    GameFetchStatus status, {
    required double iconSize,
    bool compactProcessingSpinner = false,
  }) => switch (status) {
    GameFetchStatus.waiting => (
      color: theme.secondary,
      tooltip: 'Queued for fetch',
      icon: Icon(Icons.schedule, color: Colors.white, size: iconSize),
    ),
    GameFetchStatus.processing => (
      color: theme.background,
      tooltip: 'Fetching from Steam',
      icon: AppCircularProgressIndicator(
        size: compactProcessingSpinner
            ? (iconSize - 3.0).clamp(10.0, iconSize)
            : iconSize,
      ),
    ),
    GameFetchStatus.done => (
      color: Colors.green,
      tooltip: 'Fetch completed',
      icon: Icon(Icons.check, color: Colors.white, size: iconSize),
    ),
    GameFetchStatus.error => (
      color: theme.secondary,
      tooltip: 'Fetch failed',
      icon: Icon(Icons.error, color: theme.primaryButtonText, size: iconSize),
    ),
  };

  /// The status icon, scaled and faded in when [status] changes.
  static Widget fetchStatusIcon(
    FetchStatusVisual visual,
    GameFetchStatus status,
    double size,
  ) => AnimatedSwitcher(
    duration: kVeryFastAnimation,
    transitionBuilder: (child, anim) => ScaleTransition(
      scale: anim,
      child: FadeTransition(opacity: anim, child: child),
    ),
    child: SizedBox(
      key: ValueKey(status),
      width: size,
      height: size,
      child: Center(child: visual.icon),
    ),
  );

  // ── Concrete badge builders ───────────────────────────────────────────────

  /// Square platform icon badge of [size].
  static Widget platformBadge(AppThemeData theme, Game game, double size) {
    final platform = game.platformEnum;
    return squareIconBadge(
      theme,
      tooltip: game.platform,
      color: theme.baseSecondary.withValues(
        alpha: kGameCardChipBackgroundAlpha,
      ),
      size: size,
      semanticsLabel: game.platform,
      icon: PlatformIcon(
        platform: platform,
        size: platformIconSizeFor(platform, minHeight: size),
        color: theme.primaryButtonText,
      ),
    );
  }

  static Widget ratingBadge(
    AppThemeData theme,
    Game game, {
    required EdgeInsets padding,
    BorderRadius? borderRadius,
    double? minHeight,
  }) {
    final reviewCount = game.reviewCount;
    final ratingText = reviewCount == 0
        ? 'No Reviews'
        : '${game.reviewScore}% · ${game.reviewRating} · ${_compactNumber.format(reviewCount)}';

    return Tooltip(
      message: ratingText,
      child: Container(
        alignment: Alignment.center,
        padding: padding,
        constraints: minHeight != null
            ? BoxConstraints.tightFor(height: minHeight)
            : null,
        decoration: BoxDecoration(
          color: game
              .reviewColorFor(negativeColor: theme.secondary)
              .withValues(alpha: 0.95),
          borderRadius:
              borderRadius ??
              chipBorderRadius(theme, minHeight ?? kBadgeHeight),
        ),
        child: Icon(
          _ratingIconFor(game.reviewScore, reviewCount),
          color: Colors.white,
          size: 18.0,
        ),
      ),
    );
  }

  /// Deadline badge [kBadgeHeight] tall. Deadlines more than two weeks away
  /// (or every deadline with [forceIconOnly]) show only the status icon.
  static Widget deadlineBadge(
    AppThemeData theme,
    DateTime? deadlineDate, {
    bool forceIconOnly = false,
  }) {
    final daysLeft = deadlineDate == null
        ? 0
        : calendarDaysUntil(
            DateUtils.dateOnly(deadlineDate),
            DateUtils.dateOnly(DateTime.now()),
          );
    final isExpired = daysLeft < 0;
    final dueText = daysLeft == 0 ? 'Today' : '$daysLeft days';
    final date = deadlineDate == null
        ? null
        : _deadlineFormat.format(deadlineDate);
    final (color, text) = switch (daysLeft) {
      < 0 => (theme.secondary, 'Expired'),
      <= 3 => (theme.deadlineUrgent, dueText),
      <= 7 => (theme.deadlineSoon, dueText),
      <= 14 => (theme.deadlineNormal, dueText),
      _ => (theme.deadlineNormal, date ?? 'Deadline'),
    };
    final badgeColor = color.withValues(alpha: kGameCardChipBackgroundAlpha);
    final tooltipMessage = date == null
        ? text
        : isExpired
        ? 'Expired ${daysLeft == -1 ? '1 day' : '${-daysLeft} days'} ago · $date'
        : daysLeft == 0
        ? 'Due today · $date'
        : 'Due in $daysLeft days · $date';
    final icon = Icon(
      isExpired ? Icons.event_busy : Icons.schedule,
      color: Colors.white,
      size: 18.0,
    );

    if (forceIconOnly || daysLeft > 14) {
      return squareIconBadge(
        theme,
        tooltip: tooltipMessage,
        color: badgeColor,
        size: kBadgeHeight,
        icon: icon,
      );
    }

    return Tooltip(
      message: tooltipMessage,
      child: IntrinsicWidth(
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          constraints: const BoxConstraints(minHeight: kBadgeHeight),
          decoration: BoxDecoration(
            color: badgeColor,
            borderRadius: chipBorderRadius(theme, kBadgeHeight),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(width: 6),
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

  static Widget titleChip(AppThemeData theme, String title) => Container(
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
            children: [
              platformBadge(theme, game, kPlatformBadgeHeight),
              if (showRatingChip)
                _animatedRatingChip(
                  theme,
                  game,
                  borderRadius: chipBorderRadius(theme, 20.0),
                  topPadding: 4,
                ),
            ],
          )
        : _animatedRatingChip(theme, game, minHeight: kBadgeHeight);

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
        deadlineBadge(theme, game.deadlineDate, forceIconOnly: true),
      if (showRating)
        ratingBadge(
          theme,
          game,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          minHeight: kBadgeHeight,
        ),
      if (showPlatform) platformBadge(theme, game, kBadgeHeight),
    ];

    final hasExtraChips = fetchStatus != null || isSelected;
    if (baseChips.isEmpty && !hasExtraChips) return const SizedBox.shrink();

    final iconSize = platformIconSizeFor(
      game.platformEnum,
      minHeight: kBadgeHeight,
    );
    final extraChips = <Widget>[
      if (fetchStatus != null)
        _slimFetchStatusBadge(theme, fetchStatus, iconSize),
      if (isSelected)
        squareIconBadge(
          theme,
          tooltip: 'Selected',
          color: theme.accent,
          size: kBadgeHeight,
          icon: Icon(Icons.check, color: Colors.white, size: iconSize),
        ),
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

  static Widget _slimFetchStatusBadge(
    AppThemeData theme,
    GameFetchStatus status,
    double iconSize,
  ) {
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
      size: kBadgeHeight,
      icon: fetchStatusIcon(visual, status, iconSize),
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
    BorderRadius? borderRadius,
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
