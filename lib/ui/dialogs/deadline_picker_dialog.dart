library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/time/calendar_date.dart';
import '../widgets/dialog_helpers.dart';

const _deadlineExactDateFieldKey = ValueKey('deadline_exact_date_input');
const _deadlineDaysFieldKey = ValueKey('deadline_days_input');
// Date entry is reformatted on every keystroke; compile these once.
final _nonDigitPattern = RegExp(r'\D');
final _digitPattern = RegExp(r'\d');
final _dateFormat = DateFormat('dd/MM/yyyy');

Future<DateTime?> showDeadlinePickerDialog({
  required BuildContext context,
  required AppThemeData theme,
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  bool useRootNavigator = true,
  DateTime? currentDate,
}) {
  final today = DateUtils.dateOnly(currentDate ?? DateTime.now());
  final earliestDate = DateUtils.dateOnly(firstDate ?? today);
  final latestDate = DateUtils.dateOnly(lastDate ?? DateTime(9999, 12, 31));
  final fallbackDate = today.isBefore(earliestDate) ? earliestDate : today;
  final selectedDate = _clampDate(
    DateUtils.dateOnly(initialDate ?? fallbackDate),
    earliestDate,
    latestDate,
  );

  return showAppDialog<DateTime>(
    context: context,
    useRootNavigator: useRootNavigator,
    builder: (dialogContext) => _DeadlinePickerDialog(
      theme: theme,
      initialDate: selectedDate,
      firstDate: earliestDate,
      lastDate: latestDate,
      currentDate: today,
    ),
  );
}

DateTime _clampDate(DateTime value, DateTime firstDate, DateTime lastDate) =>
    value.isBefore(firstDate)
    ? firstDate
    : value.isAfter(lastDate)
    ? lastDate
    : value;

class _DeadlinePickerDialog extends StatefulWidget {
  const _DeadlinePickerDialog({
    required this.theme,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.currentDate,
  });

  final AppThemeData theme;
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime currentDate;

  @override
  State<_DeadlinePickerDialog> createState() => _DeadlinePickerDialogState();
}

class _DeadlinePickerDialogState extends State<_DeadlinePickerDialog> {
  late DateTime _selectedDate = widget.initialDate;
  late final TextEditingController _exactDateController =
      TextEditingController();
  late final TextEditingController _dayAmountController =
      TextEditingController();
  String? _exactDateError;
  String? _dayAmountError;

  @override
  void initState() {
    super.initState();
    _syncExactDateFromSelectedDate();
    _syncDayAmountFromSelectedDate();
  }

  @override
  void dispose() {
    _exactDateController.dispose();
    _dayAmountController.dispose();
    super.dispose();
  }

  static void _setText(TextEditingController controller, String text) =>
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );

  void _syncExactDateFromSelectedDate() =>
      _setText(_exactDateController, _dateFormat.format(_selectedDate));

  DateTime get _currentDateOnly => DateUtils.dateOnly(widget.currentDate);

  void _syncDayAmountFromSelectedDate() {
    final dayAmount = calendarDaysUntil(_selectedDate, _currentDateOnly);
    _setText(_dayAmountController, dayAmount < 0 ? '' : '$dayAmount');
  }

  void _handleExactDateChanged(String value) {
    final digits = value.replaceAll(_nonDigitPattern, '');
    final resolution = digits.isEmpty
        ? (date: null, error: null)
        : _resolveExactDateFromDigits(digits);
    setState(() {
      _exactDateError = resolution.error;
      if (resolution.date case final date?) {
        _selectedDate = date;
        _syncDayAmountFromSelectedDate();
      }
    });
  }

  /// The date typed so far; null with no error while it is still incomplete.
  ({DateTime? date, String? error}) _resolveExactDateFromDigits(String digits) {
    if (digits.length < 2) return (date: null, error: null);
    final day = int.parse(digits.substring(0, 2));
    var month = _selectedDate.month;
    var year = _selectedDate.year;
    if (day < 1 || day > 31) {
      return (date: null, error: 'Day must be between 01 and 31');
    }

    if (digits.length >= 4) {
      month = int.parse(digits.substring(2, 4));
      if (month < 1 || month > 12) {
        return (date: null, error: 'Month must be between 01 and 12');
      }
    }

    if (digits.length >= 8) year = int.parse(digits.substring(4, 8));

    final candidate = DateTime(year, month, day);
    if (candidate.year != year ||
        candidate.month != month ||
        candidate.day != day) {
      return (date: null, error: 'Date is invalid');
    }

    if (candidate.isBefore(widget.firstDate) ||
        candidate.isAfter(widget.lastDate)) {
      return (date: null, error: 'Date falls outside the allowed range');
    }

    return (date: DateUtils.dateOnly(candidate), error: null);
  }

  void _handleDayAmountChanged(String value) {
    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) {
      setState(() => _dayAmountError = null);
      return;
    }

    final parsedDays = int.tryParse(trimmedValue);
    if (parsedDays == null) {
      setState(() => _dayAmountError = 'Enter a whole number of days');
      return;
    }

    final computedDate = DateTime(
      _currentDateOnly.year,
      _currentDateOnly.month,
      _currentDateOnly.day + parsedDays,
    );

    if (computedDate.isBefore(widget.firstDate) ||
        computedDate.isAfter(widget.lastDate)) {
      setState(
        () => _dayAmountError = 'Day amount falls outside the allowed range',
      );
      return;
    }

    setState(() {
      _dayAmountError = null;
      _selectedDate = computedDate;
      _exactDateError = null;
      _syncExactDateFromSelectedDate();
    });
  }

  void _setSelectedDate(DateTime date) {
    setState(() {
      _selectedDate = DateUtils.dateOnly(date);
      _exactDateError = null;
      _dayAmountError = null;
      _syncExactDateFromSelectedDate();
      _syncDayAmountFromSelectedDate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final textScale =
        MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 3).scale(14) /
        14;
    // Keep all six possible weeks visible with compact rows, allowing extra
    // room for larger text just as the Material calendar does.
    final calendarHeight =
        304.0 + (textScale > 1.3 ? 7 * (textScale - 1) * 8 : 0);
    final exactDate = TextField(
      key: _deadlineExactDateFieldKey,
      controller: _exactDateController,
      keyboardType: TextInputType.datetime,
      inputFormatters: [_DeadlineDateInputFormatter()],
      onChanged: _handleExactDateChanged,
      style: TextStyle(color: theme.textPrimary),
      decoration: InputDecoration(
        labelText: 'Exact date',
        hintText: 'dd/MM/yyyy',
        errorText: _exactDateError,
        errorMaxLines: 2,
        prefixIcon: Icon(
          Icons.edit_calendar_outlined,
          color: theme.textHint,
          size: 18,
        ),
      ),
    );
    final dayAmount = TextField(
      key: _deadlineDaysFieldKey,
      controller: _dayAmountController,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: _handleDayAmountChanged,
      style: TextStyle(color: theme.textPrimary),
      decoration: InputDecoration(
        labelText: 'Expires in',
        hintText: 'Days',
        errorText: _dayAmountError,
        errorMaxLines: 2,
        suffixText: 'days',
        prefixIcon: Icon(
          Icons.timelapse_outlined,
          color: theme.textHint,
          size: 18,
        ),
      ),
    );

    return ThemedAlertDialog(
      theme: theme,
      maxWidth: 460,
      title: DialogHeader(
        icon: Icons.schedule,
        title: 'Select Deadline',
        theme: theme,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          _SelectedDateCard(
            theme: theme,
            date: _selectedDate,
            daysLeft: calendarDaysUntil(_selectedDate, _currentDateOnly),
          ),
          Container(
            key: const ValueKey('deadline-calendar-panel'),
            height: calendarHeight,
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(theme.cornerRadius),
              border: Border.all(color: theme.border),
            ),
            child: DatePickerTheme(
              data: DatePickerTheme.of(
                context,
              ).copyWith(todayBorder: BorderSide.none),
              child: CalendarDatePicker(
                key: ValueKey(
                  'deadline_calendar_${_selectedDate.year}_${_selectedDate.month}_${_selectedDate.day}',
                ),
                initialDate: _selectedDate,
                firstDate: widget.firstDate,
                lastDate: widget.lastDate,
                currentDate: widget.currentDate,
                onDateChanged: _setSelectedDate,
              ),
            ),
          ),
          // Side by side when both fit, stacked on narrow screens.
          LayoutBuilder(
            builder: (context, constraints) =>
                constraints.maxWidth / textScale >= 360
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 12,
                    children: [
                      Expanded(child: exactDate),
                      Expanded(child: dayAmount),
                    ],
                  )
                : Column(spacing: 12, children: [exactDate, dayAmount]),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_selectedDate),
          child: const Text('Set deadline'),
        ),
      ],
    );
  }
}

/// The chosen date, tinted by how soon it is due like the game card badges,
/// with the days left as large as the stats tiles' numbers.
class _SelectedDateCard extends StatelessWidget {
  const _SelectedDateCard({
    required this.theme,
    required this.date,
    required this.daysLeft,
  });

  final AppThemeData theme;
  final DateTime date;
  final int daysLeft;

  @override
  Widget build(BuildContext context) {
    final color = switch (daysLeft) {
      < 0 => theme.secondary,
      <= 7 => theme.deadlineSoon,
      _ => theme.deadlineNormal,
    };
    final formatted = _dateFormat.format(date);
    return Semantics(
      label: 'Selected deadline: $formatted',
      liveRegion: true,
      child: Container(
        key: const ValueKey('deadline-selected-date'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(theme.cornerRadius),
        ),
        child: Row(
          spacing: 14,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(theme.cornerRadius),
              ),
              child: Icon(Icons.event, color: color, size: 26),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    formatted,
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    DateFormat.EEEE().format(date),
                    style: TextStyle(color: theme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${daysLeft.abs()}',
                  style: TextStyle(
                    color: color,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(switch (daysLeft) {
                  0 => 'today',
                  1 => 'day left',
                  -1 => 'day ago',
                  < 0 => 'days ago',
                  _ => 'days left',
                }, style: TextStyle(color: theme.textSecondary, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeadlineDateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(_nonDigitPattern, '');
    final truncatedDigits = digits.length > 8 ? digits.substring(0, 8) : digits;
    final formatted = _formatDigits(truncatedDigits);
    final digitsBeforeSelection = _countDigitsBeforeSelection(newValue);
    final selectionIndex = _selectionIndexForDigits(
      formatted,
      digitsBeforeSelection.clamp(0, truncatedDigits.length),
    );

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: selectionIndex),
    );
  }

  static String _formatDigits(String digits) {
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      buffer.write(digits[index]);
      if ((index == 1 || index == 3) && index != digits.length - 1) {
        buffer.write('/');
      }
    }
    return buffer.toString();
  }

  static int _countDigitsBeforeSelection(TextEditingValue value) {
    final end = value.selection.end.clamp(0, value.text.length);
    return value.text.substring(0, end).replaceAll(_nonDigitPattern, '').length;
  }

  static int _selectionIndexForDigits(String formatted, int digitCount) {
    if (digitCount <= 0) return 0;

    var seenDigits = 0;
    for (var index = 0; index < formatted.length; index++) {
      if (_digitPattern.hasMatch(formatted[index])) {
        seenDigits++;
        if (seenDigits == digitCount) return index + 1;
      }
    }
    return formatted.length;
  }
}
