/// Totals for the whole library: keys, types, deadlines and platforms.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import '../../providers/app_providers.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/segmented_bar.dart';
import '../widgets/tinted_tiles.dart';

Future<void> showLibraryStatsDialog(BuildContext context, List<Game> games) =>
    showAppDialog<void>(
      context: context,
      builder: (_) => LibraryStatsDialog(games: games),
    );

class LibraryStatsDialog extends ConsumerWidget {
  const LibraryStatsDialog({super.key, required this.games});

  final List<Game> games;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    int count(bool Function(Game game) test) => games.where(test).length;
    final unused = games.where((g) => !g.isUsed).toList();
    // Days left on each unused key's deadline; null without one.
    final daysLeft = [for (final game in unused) game.daysUntilDeadline];
    int due(bool Function(int days) test) =>
        daysLeft.where((days) => days != null && test(days)).length;
    final dueThisWeek = due((d) => d >= 0 && d <= 7);

    final platforms = <String, int>{};
    for (final game in games) {
      platforms.update(game.platform, (n) => n + 1, ifAbsent: () => 1);
    }
    final byPlatform = platforms.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    // Platforms take hues spread from the accent's, at its tone.
    final accent = HSLColor.fromColor(theme.accent);

    return ThemedAlertDialog(
      theme: theme,
      maxWidth: 480,
      title: DialogHeader(
        icon: Icons.bar_chart,
        title: 'Library Stats',
        theme: theme,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 20,
          children: [
            Row(
              spacing: 8,
              children: [
                for (final (label, value) in [
                  ('Keys', games.length),
                  ('Unused', unused.length),
                  ('Due in 7 days', dueThisWeek),
                ])
                  Expanded(child: _StatTile(theme, label, value)),
              ],
            ),
            _StatBar(theme, 'Keys', [
              (label: 'Unused', count: unused.length, color: theme.accent),
              (
                label: 'Used',
                count: games.length - unused.length,
                color: theme.textSecondary.withValues(alpha: 0.45),
              ),
            ]),
            _StatBar(theme, 'Type', [
              (
                label: 'Games',
                count: count((g) => !g.isDlc),
                color: theme.accent,
              ),
              (
                label: 'DLC',
                count: count((g) => g.isDlc),
                color: theme.secondary,
              ),
            ]),
            _StatBar(theme, 'Unused Key Deadlines', [
              (
                label: 'Expired',
                count: due((d) => d < 0),
                color: theme.secondary,
              ),
              (
                label: 'Within 7 days',
                count: dueThisWeek,
                color: theme.deadlineSoon,
              ),
              (
                label: 'Within 30 days',
                count: due((d) => d > 7 && d <= 30),
                color: theme.deadlineNormal,
              ),
              (
                label: 'Later',
                count: due((d) => d > 30),
                color: theme.deadlineNormal.withValues(alpha: 0.5),
              ),
              (
                label: 'No deadline',
                count: daysLeft.where((days) => days == null).length,
                color: theme.textSecondary.withValues(alpha: 0.3),
              ),
            ]),
            _StatBar(theme, 'Platforms', [
              for (final (i, MapEntry(:key, :value)) in byPlatform.indexed)
                (
                  label: key,
                  count: value,
                  color: accent
                      .withHue((accent.hue + i * 137.5) % 360)
                      .toColor(),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// A large number over its caption.
class _StatTile extends StatelessWidget {
  const _StatTile(this.theme, this.label, this.value);

  final AppThemeData theme;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    decoration: BoxDecoration(
      color: theme.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(theme.cornerRadius),
    ),
    // Narrow screens and large text shrink the tile's content to fit.
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        spacing: 2,
        children: [
          Text(
            '$value',
            style: TextStyle(
              color: theme.accent,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: TextStyle(color: theme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

/// A titled [SegmentedBar] over a legend with every count.
class _StatBar extends StatelessWidget {
  const _StatBar(this.theme, this.title, this.segments);

  final AppThemeData theme;
  final String title;
  final List<BarSegment> segments;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 8,
    children: [
      TintedHeading(
        theme: theme,
        title: title,
        trailing: '${segments.fold(0, (sum, s) => sum + s.count)}',
      ),
      SegmentedBar(theme: theme, segments: segments),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final segment in segments)
            TintedChip(
              theme: theme,
              color: segment.color,
              label: segment.label,
              value: '${segment.count}',
              faded: segment.count == 0,
            ),
        ],
      ),
    ],
  );
}
