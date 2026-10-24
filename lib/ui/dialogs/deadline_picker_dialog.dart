library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/section_groupbox.dart';
import '../../core/settings/settings_model.dart';

const _deadlineExactDateFieldKey = ValueKey('deadline_exact_date_input');
const _deadlineDaysFieldKey = ValueKey('deadline_days_input');
// Date entry is reformatted on every keystroke; compile these once.
final _nonDigitPattern = RegExp(r'\D');
final _digitPattern = RegExp(r'\d');

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

DateTime _clampDate(DateTime value, DateTime firstDate, DateTime lastDate) {
  if (value.isBefore(firstDate)) {
    return firstDate;
  }
  if (value.isAfter(lastDate)) {
    return lastDate;
  }
  return value;
}

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

  void _syncExactDateFromSelectedDate() {
    final text = DateFormat('dd/MM/yyyy').format(_selectedDate);
    _exactDateController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  DateTime get _currentDateOnly => DateUtils.dateOnly(widget.currentDate);

  int _daysUntilFromCurrentDate(DateTime date) {
    // Count calendar days independently of daylight-saving time changes.
    return DateTime.utc(date.year, date.month, date.day)
        .difference(
          DateTime.utc(
            _currentDateOnly.year,
            _currentDateOnly.month,
            _currentDateOnly.day,
          ),
        )
        .inDays;
  }

  void _syncDayAmountFromSelectedDate() {
    final dayAmount = _daysUntilFromCurrentDate(_selectedDate);
    final text = dayAmount < 0 ? '' : '$dayAmount';
    _dayAmountController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _handleExactDateChanged(String value) {
    final digits = value.replaceAll(_nonDigitPattern, '');
    if (digits.isEmpty) {
      setState(() => _exactDateError = null);
      return;
    }

    final resolution = _resolveExactDateFromDigits(digits);
    if (resolution.error != null) {
      setState(() => _exactDateError = resolution.error);
      return;
    }
    if (resolution.date == null) {
      setState(() => _exactDateError = null);
      return;
    }

    setState(() {
      _exactDateError = null;
      _selectedDate = resolution.date!;
      _syncDayAmountFromSelectedDate();
    });
  }

  ({DateTime? date, String? error}) _resolveExactDateFromDigits(String digits) {
    var day = _selectedDate.day;
    var month = _selectedDate.month;
    var year = _selectedDate.year;

    if (digits.length >= 2) {
      day = int.parse(digits.substring(0, 2));
      if (day < 1 || day > 31) {
        return (date: null, error: 'Day must be between 01 and 31');
      }
    } else {
      return (date: null, error: null);
    }

    if (digits.length >= 4) {
      month = int.parse(digits.substring(2, 4));
      if (month < 1 || month > 12) {
        return (date: null, error: 'Month must be between 01 and 12');
      }
    }

    if (digits.length >= 8) {
      year = int.parse(digits.substring(4, 8));
    }

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
      setState(() {
        _dayAmountError = 'Day amount falls outside the allowed range';
      });
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
    final formattedDate = DateFormat('dd/MM/yyyy').format(_selectedDate);
    final textScale =
        MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 3).scale(14) /
        14;
    // Keep all six possible weeks visible with compact rows, allowing extra
    // room for larger text just as the Material calendar does.
    final calendarHeight =
        304.0 + (textScale > 1.3 ? 7 * (textScale - 1) * 8 : 0);

    return ThemedAlertDialog(
      theme: widget.theme,
      maxWidth: 460,
      title: DialogHeader(
        icon: Icons.schedule,
        title: 'Select Deadline',
        theme: widget.theme,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionGroupBox(
            title: 'Calendar',
            titleIcon: Icons.calendar_month_outlined,
            titleLocation: SectionTitleLocation.top,
            theme: widget.theme,
            headerCrossAxisAlignment: CrossAxisAlignment.center,
            stackTrailingWhenCompact: textScale > 1.3,
            headerBottomPadding: 0,
            trailing: Semantics(
              label: 'Selected deadline: $formattedDate',
              child: Container(
                key: const ValueKey('deadline-selected-date'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: widget.theme.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(
                    widget.theme.cornerRadius,
                  ),
                ),
                child: Text(
                  formattedDate,
                  style: TextStyle(
                    color: widget.theme.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            child: SizedBox(
              height: calendarHeight,
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
          ),
          const SizedBox(height: kDialogSpacing),
          SectionGroupBox(
            title: 'Quick Entry',
            titleIcon: Icons.edit_calendar_outlined,
            titleLocation: SectionTitleLocation.top,
            theme: widget.theme,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: _deadlineExactDateFieldKey,
                  controller: _exactDateController,
                  keyboardType: TextInputType.datetime,
                  inputFormatters: [_DeadlineDateInputFormatter()],
                  onChanged: _handleExactDateChanged,
                  style: TextStyle(color: widget.theme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Exact date',
                    hintText: 'dd/MM/yyyy',
                    errorText: _exactDateError,
                    prefixIcon: Icon(
                      Icons.edit_calendar_outlined,
                      color: widget.theme.textHint,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: _deadlineDaysFieldKey,
                  controller: _dayAmountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: _handleDayAmountChanged,
                  style: TextStyle(color: widget.theme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Expires in days',
                    hintText: 'Enter day amount',
                    errorText: _dayAmountError,
                    suffixText: 'days',
                    prefixIcon: Icon(
                      Icons.timelapse_outlined,
                      color: widget.theme.textHint,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
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
    if (digitCount <= 0) {
      return 0;
    }

    var seenDigits = 0;
    for (var index = 0; index < formatted.length; index++) {
      if (_digitPattern.hasMatch(formatted[index])) {
        seenDigits++;
        if (seenDigits == digitCount) {
          return index + 1;
        }
      }
    }
    return formatted.length;
  }
}
