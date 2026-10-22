import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../dialogs/deadline_picker_dialog.dart';
import 'app_action_button.dart';
import 'live_size_ink_ripple.dart';
import 'button_theme_sync.dart';

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
    final label = date == null ? 'Select date' : _dateFormat.format(date!);
    final insetColor = Color.alphaBlend(
      theme.accent.withValues(alpha: 0.10),
      theme.inputBackground,
    );
    // Match the inset curve to the outer radius and its 4 px inset.
    final insetCornerMultiplier = theme.cornerRadius == 0
        ? 0.0
        : ((theme.cornerRadius - 4) / theme.cornerRadius).clamp(0.0, 1.0);
    final insetRadius = theme.cornerRadius * insetCornerMultiplier;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Semantics(
        toggled: hasDeadline,
        child: ButtonThemeSync(
          theme: theme,
          builder: (context, snapTheme) => OutlinedButton(
            key: const ValueKey('deadline-control'),
            onPressed: () => onEnabledChanged(!hasDeadline),
            style: AppActionButton.styleFor(theme, selected: hasDeadline)
                .copyWith(
                  animationDuration: snapTheme ? Duration.zero : null,
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.fromLTRB(10, 4, 10, 4),
                  ),
                  splashFactory: LiveSizeInkRipple.splashFactory,
                ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Tooltip(
                    message: hasDeadline
                        ? 'Disable deadline'
                        : 'Enable deadline',
                    child: const Text(
                      'Deadline',
                      key: ValueKey('deadline-toggle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                SizedBox(width: hasDeadline ? 6 : 0),
                Flexible(
                  flex: hasDeadline ? 2 : 0,
                  child: Align(
                    widthFactor: hasDeadline ? 1 : 0,
                    heightFactor: 1,
                    child: Visibility(
                      visible: hasDeadline,
                      maintainState: true,
                      maintainSize: true,
                      maintainAnimation: true,
                      child: Tooltip(
                        message: date != null
                            ? 'Change deadline: $label'
                            : 'Choose deadline date',
                        child: Material(
                          color: insetColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(insetRadius),
                          ),
                          child: InkWell(
                            key: const ValueKey('deadline-date'),
                            onTap: () => _chooseDate(context),
                            borderRadius: BorderRadius.circular(insetRadius),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 24),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: theme.textPrimary),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                AppButtonSelectionIndicator(
                  selected: hasDeadline,
                  theme: theme,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
