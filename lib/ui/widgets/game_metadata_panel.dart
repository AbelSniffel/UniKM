/// The Metadata block shared by the Game Editor and the Single Game page:
/// a heading, the game's dates and tiles for its Steam details.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import '../pages/settings_sections/settings_control_cards.dart';
import 'notification_system.dart';
import 'tinted_tiles.dart';

class GameMetadataPanel extends StatelessWidget {
  const GameMetadataPanel({
    super.key,
    required this.theme,
    required this.steam,
    this.headingTrailing,
    this.added,
    this.updated,
    this.cachedAt,
    this.developer,
    this.reviewScore,
    this.reviewCount,
    this.steamAppId = '',
  });

  final AppThemeData theme;

  /// Adds the Steam cache date, reviews and AppID.
  final bool steam;
  final String? headingTrailing;

  /// A game that is not saved yet has no Added or Updated date.
  final DateTime? added;
  final DateTime? updated;
  final DateTime? cachedAt;

  final String? developer;
  final int? reviewScore;
  final int? reviewCount;
  final String steamAppId;

  Widget _tile(IconData icon, String label, String value, [Widget? trailing]) =>
      TintedOptionTile(
        theme: theme,
        icon: icon,
        title: value,
        subtitle: label,
        trailing: trailing,
      );

  @override
  Widget build(BuildContext context) {
    final hasDates = added != null || steam;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        TintedHeading(
          theme: theme,
          title: 'Metadata',
          trailing: headingTrailing,
        ),
        if (hasDates)
          _DatesTile(
            theme: theme,
            added: added,
            updated: updated,
            steam: steam,
            cachedAt: cachedAt,
          ),
        SettingsControlWrap(
          minimumCardWidth: 220,
          children: [
            if (developer?.isNotEmpty == true)
              _tile(Icons.business_outlined, 'Developer', developer!),
            if (steam)
              reviewCount == null || reviewCount == 0
                  ? _tile(Icons.thumb_up_outlined, 'Reviews', 'No reviews')
                  : _tile(
                      Icons.thumb_up_outlined,
                      '${NumberFormat.compact().format(reviewCount)} reviews',
                      '${reviewScore ?? 0}% · '
                          '${Game.reviewRatingFor(reviewScore ?? 0)}',
                    ),
            if (steam)
              _tile(
                Icons.pin_outlined,
                'Steam AppID',
                steamAppId.isEmpty ? 'Not set' : steamAppId,
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  color: theme.textSecondary,
                  tooltip: 'Copy AppID',
                  onPressed: steamAppId.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: steamAppId));
                          NotificationManager.instance.success(
                            'Steam AppID copied to clipboard',
                          );
                        },
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The game's dates side by side, each as how long ago it was over the
/// date itself; hovering one shows its exact time. An update no later than
/// the add says Unchanged, and a game without Steam data says Not cached.
class _DatesTile extends StatelessWidget {
  const _DatesTile({
    required this.theme,
    required this.added,
    required this.updated,
    required this.steam,
    this.cachedAt,
  });

  final AppThemeData theme;
  final DateTime? added;
  final DateTime? updated;
  final bool steam;
  final DateTime? cachedAt;

  static final _day = DateFormat('d MMM yyyy');
  static final _exact = DateFormat('dd/MM/yyyy HH:mm');

  static String _ago(DateTime date) {
    final days = DateUtils.dateOnly(
      DateTime.now(),
    ).difference(DateUtils.dateOnly(date)).inDays;
    String plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'} ago';
    return switch (days) {
      <= 0 => 'Today',
      1 => 'Yesterday',
      < 30 => plural(days, 'day'),
      < 365 => plural(days ~/ 30, 'month'),
      _ => plural(days ~/ 365, 'year'),
    };
  }

  Widget _entry(IconData icon, String label, DateTime? date, String fallback) {
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Row(
          spacing: 6,
          children: [
            Icon(icon, color: theme.accent, size: 16),
            Flexible(
              child: Text(
                label,
                style: TextStyle(color: theme.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
        Text(
          date == null ? fallback : _ago(date),
          style: TextStyle(
            color: date == null ? theme.textSecondary : theme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (date != null)
          Text(
            _day.format(date),
            style: TextStyle(color: theme.textHint, fontSize: 12),
          ),
      ],
    );
    return Expanded(
      child: date == null
          ? column
          : Tooltip(message: _exact.format(date), child: column),
    );
  }

  @override
  Widget build(BuildContext context) {
    final added = this.added;
    final updated = this.updated;
    final divider = VerticalDivider(
      width: 20,
      color: theme.accent.withValues(alpha: 0.2),
    );
    final entries = [
      if (added != null) ...[
        _entry(Icons.add_circle_outline, 'Added', added, ''),
        _entry(
          Icons.edit_outlined,
          'Updated',
          updated != null &&
                  updated.isAfter(added.add(const Duration(minutes: 1)))
              ? updated
              : null,
          'Unchanged',
        ),
      ],
      if (steam) _entry(Icons.history, 'Cached', cachedAt, 'Not cached'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(theme.cornerRadius),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, entry) in entries.indexed) ...[
              if (index > 0) divider,
              entry,
            ],
          ],
        ),
      ),
    );
  }
}
