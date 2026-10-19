/// Compare calendar dates independently of daylight-saving offset changes.
DateTime calendarDay(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

int calendarDaysUntil(DateTime deadline, DateTime now) =>
    calendarDay(deadline).difference(calendarDay(now)).inDays;
