import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../dialogs/deadline_picker_dialog.dart';

/// One compact control for enabling a deadline and choosing its date.
/// Turning it off keeps the last date available when enabled again.
class DeadlineChip extends StatelessWidget {
  const DeadlineChip({
    super.key,
    required this.theme,
    required this.hasDeadline,
    required this.date,
    required this.onEnabledChanged,
    required this.onDateChanged,
    this.firstDate,
  });

  final AppThemeData theme;
  final bool hasDeadline;
  final DateTime? date;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<DateTime> onDateChanged;
  final DateTime? firstDate;

  static final _dateFormat = DateFormat('dd/MM/yyyy');

  Future<void> _chooseDate(BuildContext context) async {
    final selected = await showDeadlinePickerDialog(
      context: context,
      theme: theme,
      initialDate: date ?? DateTime.now(),
      firstDate: firstDate,
    );
    if (!context.mounted || selected == null) return;
    onDateChanged(selected);
    if (!hasDeadline) onEnabledChanged(true);
  }

  @override
  Widget build(BuildContext context) {
    final label = !hasDeadline
        ? 'Deadline'
        : date == null
        ? 'Select date'
        : _dateFormat.format(date!);
    final radius = BorderRadius.circular(theme.cornerRadius);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Material(
        color: hasDeadline
            ? theme.accent.withValues(alpha: 0.35)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: hasDeadline
                ? theme.accent.withValues(alpha: 0.5)
                : Colors.transparent,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: hasDeadline ? 'Disable deadline' : 'Enable deadline',
              child: Semantics(
                label: 'Deadline enabled',
                toggled: hasDeadline,
                child: InkWell(
                  key: const ValueKey('deadline-toggle'),
                  onTap: () => onEnabledChanged(!hasDeadline),
                  child: SizedBox(
                    width: 36,
                    height: kOptionChipHeight,
                    child: Icon(
                      hasDeadline
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 20,
                      color: hasDeadline
                          ? theme.accent
                          : theme.accent.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ),
            Flexible(
              child: Tooltip(
                message: hasDeadline && date != null
                    ? 'Change deadline: $label'
                    : 'Choose deadline date',
                child: InkWell(
                  key: const ValueKey('deadline-date'),
                  onTap: () => _chooseDate(context),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: SizedBox(
                      height: kOptionChipHeight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
