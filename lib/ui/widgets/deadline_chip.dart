import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../dialogs/deadline_picker_dialog.dart';
import 'app_action_button.dart';
import 'live_size_ink_ripple.dart';
import 'button_theme_sync.dart';
import '../../core/utils/format_utils.dart';

/// One compact control for enabling a deadline and choosing its date.
/// Turning it off keeps the last date available when enabled again.
class const DeadlineChip({
  super.key,
  required final bool hasDeadline,
  required final DateTime? date,
  required final ValueChanged<bool> onEnabledChanged,
  required final ValueChanged<DateTime> onDateChanged,
  final DateTime? firstDate,
}) extends StatelessWidget {
  Future<void> _chooseDate(BuildContext context) async {
    final selected = await showDeadlinePickerDialog(
      context: context,
      initialDate: date ?? DateTime.now(),
      firstDate: firstDate,
    );
    if (!context.mounted || selected == null) return;
    onDateChanged(selected);
    if (!hasDeadline) onEnabledChanged(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final label = date == null
        ? 'Select date'
        : dayMonthYearFormat.format(date!);
    final insetColor = theme.accent.withValues(alpha: 0.10);
    // Match the inset curve to the outer radius and its 4 px inset.
    final insetRadius = math.max(0.0, theme.cornerRadius - 4);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Semantics(
        toggled: hasDeadline,
        child: ButtonThemeSync(
          theme: theme,
          builder: (context, snapTheme) => OutlinedButton(
            key: const ValueKey('deadline-control'),
            onPressed: () => onEnabledChanged(!hasDeadline),
            style: AppActionButton.styleFor(context, selected: hasDeadline)
                .copyWith(
                  animationDuration: snapTheme ? Duration.zero : null,
                  // On, the date's box sits as far from the right edge as
                  // from the top and bottom.
                  padding: WidgetStatePropertyAll(
                    EdgeInsets.fromLTRB(10, 4, hasDeadline ? 4 : 10, 4),
                  ),
                  splashFactory: LiveSizeInkRipple.splashFactory,
                  foregroundBuilder: (context, states, label) =>
                      AppActionButton.withStatus(label!, selected: hasDeadline),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
