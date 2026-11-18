/// What the library cards' chips show, and the chip widgets the cover editor
/// shows too.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/theme/app_theme.dart';
import '../../core/utils/color_utils.dart';
import '../../models/game.dart';
import '../../shared/time/calendar_date.dart';
import '../../core/utils/format_utils.dart';

const double kBadgeHeight = 28.0;
const double kGameCardChipBackgroundAlpha = 0.875;
const double kPlatformBadgeHeight = 32.0;
const double kSelectionIndicatorSize = 20.0;

abstract final class GameCardBadges {
  static final NumberFormat _compactNumber = NumberFormat.compact();

  /// Whether [game] still shows its NEW chip: added within a day and not
  /// yet [viewed].
  static bool showsNew(Game game, {required bool viewed}) {
    if (viewed) return false;
    final age = DateTime.now().difference(game.dateAdded);
    return !age.isNegative && age <= const Duration(days: 1);
  }

  // ── Primitive builders ────────────────────────────────────────────────────

  static BorderRadius chipBorderRadius(
    AppThemeData theme,
    double extent, {
    double multiplier = 1.0,
  }) => BorderRadius.circular(
    math.min(theme.cornerRadius * multiplier, extent / 2),
  );

  /// What a rating chip shows: its tooltip, fill and icon.
  static ({String tooltip, Color fill, IconData icon}) ratingInfo(
    AppThemeData theme,
    Game game,
  ) {
    final reviewCount = game.reviewCount;
    return (
      tooltip: reviewCount == 0
          ? 'No Reviews'
          : '${game.reviewScore}% · ${game.reviewRating} · ${_compactNumber.format(reviewCount)}',
      fill: game.reviewColorFor(negativeColor: theme.secondary),
      icon: _ratingIconFor(game.reviewScore, reviewCount),
    );
  }

  /// What a deadline badge shows: its colour, its text (none when it shows
  /// only its icon, more than two weeks away), tooltip and icon.
  static ({
    Color color,
    String text,
    bool iconOnly,
    String tooltip,
    IconData icon,
  })
  deadlineInfo(AppThemeData theme, DateTime? deadlineDate) {
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
        : dayMonthYearFormat.format(deadlineDate);
    final (color, text) = switch (daysLeft) {
      < 0 => (theme.secondary, 'Expired'),
      <= 3 => (theme.deadlineUrgent, dueText),
      <= 7 => (theme.deadlineSoon, dueText),
      <= 14 => (theme.deadlineNormal, dueText),
      _ => (theme.deadlineNormal, date ?? 'Deadline'),
    };
    return (
      color: color,
      text: text,
      iconOnly: daysLeft > 14,
      tooltip: date == null
          ? text
          : isExpired
          ? 'Expired ${daysLeft == -1 ? '1 day' : '${-daysLeft} days'} ago · $date'
          : daysLeft == 0
          ? 'Due today · $date'
          : 'Due in $daysLeft days · $date',
      icon: isExpired ? Icons.event_busy : Icons.schedule,
    );
  }

  /// Deadline badge [kBadgeHeight] tall. Deadlines more than two weeks away
  /// show only the status icon.
  static Widget deadlineBadge(AppThemeData theme, DateTime? deadlineDate) {
    final (:color, :text, :iconOnly, tooltip: tooltipMessage, icon: iconData) =
        deadlineInfo(theme, deadlineDate);
    final badgeColor = color.withValues(alpha: kGameCardChipBackgroundAlpha);
    final foreground = contrastColor(color);
    final icon = Icon(iconData, color: foreground, size: 18.0);

    // Its parents give it loose widths, so it wraps its row by itself.
    return Tooltip(
      message: tooltipMessage,
      child: Container(
        padding: iconOnly
            ? null
            : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        constraints: iconOnly
            ? const BoxConstraints.tightFor(
                width: kBadgeHeight,
                height: kBadgeHeight,
              )
            : const BoxConstraints(minHeight: kBadgeHeight),
        alignment: iconOnly ? Alignment.center : null,
        decoration: BoxDecoration(
          color: badgeColor,
          borderRadius: chipBorderRadius(theme, kBadgeHeight),
        ),
        child: iconOnly
            ? icon
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  const SizedBox(width: 6),
                  Text(
                    text,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// The DLC chip, as tall as the stacked rating chip.
  static Widget dlcChip(AppThemeData theme) => Container(
    key: const ValueKey('dlc-chip'),
    height: 26,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: theme.accent.withValues(alpha: 0.95),
      borderRadius: chipBorderRadius(theme, 20.0),
    ),
    child: Text(
      'DLC',
      style: TextStyle(
        color: theme.primaryButtonText,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        decoration: TextDecoration.none,
      ),
    ),
  );

  static IconData _ratingIconFor(int score, int reviewCount) {
    if (reviewCount == 0) return Icons.help_outline_rounded;
    if (score >= 95) return Icons.auto_awesome_rounded;
    if (score >= 90) return Icons.thumb_up_alt_rounded;
    if (score >= 75) return Icons.thumb_up_rounded;
    if (score >= 60) return Icons.thumbs_up_down_rounded;
    if (score >= 40) return Icons.thumb_down_alt_rounded;
    return Icons.thumb_down_rounded;
  }
}
