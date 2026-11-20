library;

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';

/// A pairing code to compare by eye: large digits in two groups of three on
/// a faint box, rounded like the cards that sit 12 px inside a dialog.
class const PairCodeDisplay({super.key, required final String code})
    extends StatelessWidget {
  static const double _letterSpacing = 6;

  /// "123456" reads as "123-456"; other lengths are shown as they are.
  String get grouped =>
      code.length == 6 ? '${code.substring(0, 3)}-${code.substring(3)}' : code;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        // Untinted, so the warning beside it is the one that stands out.
        color: theme.textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(theme.cornerRadius),
      ),
      // Letter spacing also follows the last digit, so the same space before
      // the first keeps the code centred.
      child: Padding(
        padding: const EdgeInsets.only(left: _letterSpacing),
        child: Text(
          grouped,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: theme.textPrimary,
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: _letterSpacing,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
