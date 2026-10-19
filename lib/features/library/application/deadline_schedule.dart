import '../../../models/game.dart';
import '../../../shared/time/calendar_date.dart';

/// Calendar-date reminders, grouped to keep the native schedule bounded by
/// dates rather than games. Android resolves each date to 09:00 local time.
List<Map<String, Object>> buildDeadlineSchedule(
  List<Game> games,
  DateTime now,
) {
  final groups = <String, ({DateTime day, int kind, List<String> names})>{};
  for (final game in games) {
    if (!game.hasDeadline || game.deadlineDate == null) continue;
    final deadline = calendarDay(game.deadlineDate!);
    for (final (offset, kind) in [(-7, 1003), (0, 1002), (1, 1001)]) {
      final day = deadline.add(Duration(days: offset));
      final localTime = DateTime(day.year, day.month, day.day, 9);
      if (!localTime.isAfter(now)) continue;
      final key = '${day.toIso8601String()}:$kind';
      final group = groups.putIfAbsent(
        key,
        () => (day: day, kind: kind, names: []),
      );
      group.names.add(game.title);
    }
  }
  final sorted = groups.values.toList()
    ..sort((a, b) {
      final date = a.day.compareTo(b.day);
      return date != 0 ? date : a.kind.compareTo(b.kind);
    });
  return sorted
      .map((group) {
        final count = group.names.length;
        final state = switch (group.kind) {
          1001 => 'Expired',
          1002 => 'Due Today',
          _ => 'Expiring Soon',
        };
        final names = group.names.take(7).join(', ');
        return <String, Object>{
          'date': group.day.toIso8601String().substring(0, 10),
          'id': group.kind,
          'title': count == 1 ? 'Key $state' : '$count Keys $state',
          'body': count > 7 ? '$names +${count - 7} more' : names,
        };
      })
      .toList(growable: false);
}
