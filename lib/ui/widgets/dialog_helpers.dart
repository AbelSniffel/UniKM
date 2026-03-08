/// Shared dialog building blocks — header, banner, action bar, etc.
///
/// Eliminates the repeated patterns found across all dialog files:
/// - Header Row with icon + title (± close button)
/// - Warning/info banner with colored background
/// - Cancel + primary action button pair with loading spinner
/// - Simple confirmation dialog
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// DialogHeader
// ---------------------------------------------------------------------------

/// A row containing [icon] + [title], optionally with a close button.
///
/// Two layout variants:
/// - **AlertDialog title** (default): compact icon + title row.
/// - **Custom Dialog header**: larger icon (28), bold 20 px title, close button.
///
/// ```dart
/// AlertDialog(
///   title: DialogHeader(icon: Icons.lock, title: 'Enable Encryption', theme: theme),
/// )
/// ```
class DialogHeader extends StatelessWidget {
  const DialogHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.theme,
    this.iconColor,
    this.iconSize,
    this.spacing = 12,
    this.showCloseButton = false,
    this.titleStyle,
  });

  final IconData icon;
  final String title;
  final AppThemeData theme;

  /// Defaults to [theme.accent].
  final Color? iconColor;

  /// Defaults to 28 when [showCloseButton] is true, else platform default.
  final double? iconSize;

  /// Gap between icon and title. Defaults to 12.
  final double spacing;

  /// If true, adds a themed close `IconButton` at the trailing edge.
  final bool showCloseButton;

  /// Override title text style. When null a sensible default is chosen:
  /// - With close button: 20 px bold, [theme.textPrimary].
  /// - Without: inherits from context (AlertDialog title style).
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final effectiveSize = iconSize ?? (showCloseButton ? 28.0 : null);
    final effectiveColor = iconColor ?? theme.accent;

    final textWidget = Text(
      title,
      style: titleStyle ??
          (showCloseButton
              ? TextStyle(
                  color: theme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                )
              : TextStyle(color: theme.textPrimary)),
      overflow: TextOverflow.ellipsis,
    );

    return Row(
      children: [
        Icon(icon, color: effectiveColor, size: effectiveSize),
        SizedBox(width: spacing),
        Expanded(child: textWidget),
        if (showCloseButton)
          IconButton(
            icon: Icon(Icons.close, color: theme.textSecondary),
            onPressed: () => Navigator.pop(context),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// DialogBanner
// ---------------------------------------------------------------------------

/// A colored container with icon + message, used for warnings and info tips.
///
/// ```dart
/// DialogBanner.warning(
///   theme: theme,
///   message: 'This action cannot be undone.',
/// )
/// ```
class DialogBanner extends StatelessWidget {
  const DialogBanner({
    super.key,
    required this.color,
    required this.icon,
    required this.message,
    required this.theme,
    this.iconSize,
    this.textColor,
    this.fontSize = 13,
    this.padding = const EdgeInsets.all(12),
    this.spacing = 12,
    this.showBorder = true,
  });

  /// Amber-coloured warning banner with [Icons.warning_amber].
  const factory DialogBanner.warning({
    Key? key,
    required AppThemeData theme,
    required String message,
    double? iconSize,
    Color? textColor,
    double fontSize,
    EdgeInsets padding,
    double spacing,
  }) = _WarningBanner;

  /// Orange-coloured caution banner with [Icons.warning].
  const factory DialogBanner.caution({
    Key? key,
    required AppThemeData theme,
    required String message,
    double? iconSize,
    Color? textColor,
    double fontSize,
    EdgeInsets padding,
    double spacing,
  }) = _CautionBanner;

  /// Red danger banner with [Icons.warning].
  const factory DialogBanner.danger({
    Key? key,
    required AppThemeData theme,
    required String message,
    double? iconSize,
    Color? textColor,
    double fontSize,
    EdgeInsets padding,
    double spacing,
  }) = _DangerBanner;

  /// Info banner with [Icons.info_outline] using the theme accent.
  const factory DialogBanner.info({
    Key? key,
    required AppThemeData theme,
    required String message,
    double? iconSize,
    Color? textColor,
    double fontSize,
    EdgeInsets padding,
    double spacing,
  }) = _InfoBanner;

  final Color color;
  final IconData icon;
  final String message;
  final AppThemeData theme;
  final double? iconSize;
  final Color? textColor;
  final double fontSize;
  final EdgeInsets padding;
  final double spacing;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        border: showBorder
            ? Border.all(color: color.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: iconSize),
          SizedBox(width: spacing),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: textColor ?? theme.textPrimary,
                fontSize: fontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends DialogBanner {
  const _WarningBanner({
    super.key,
    required super.theme,
    required super.message,
    super.iconSize,
    super.textColor,
    super.fontSize = 13,
    super.padding = const EdgeInsets.all(12),
    super.spacing = 12,
  }) : super(color: Colors.amber, icon: Icons.warning_amber);
}

class _CautionBanner extends DialogBanner {
  const _CautionBanner({
    super.key,
    required super.theme,
    required super.message,
    super.iconSize,
    super.textColor,
    super.fontSize = 12,
    super.padding = const EdgeInsets.all(12),
    super.spacing = 8,
  }) : super(color: Colors.orange, icon: Icons.warning);
}

class _DangerBanner extends DialogBanner {
  const _DangerBanner({
    super.key,
    required super.theme,
    required super.message,
    super.iconSize,
    super.textColor,
    super.fontSize = 12,
    super.padding = const EdgeInsets.all(12),
    super.spacing = 8,
  }) : super(color: Colors.red, icon: Icons.warning);
}

class _InfoBanner extends DialogBanner {
  const _InfoBanner({
    super.key,
    required super.theme,
    required super.message,
    super.iconSize = 16,
    super.textColor,
    super.fontSize = 11,
    super.padding = const EdgeInsets.all(8),
    super.spacing = 8,
  }) : super(color: const Color(0xFF2196F3), icon: Icons.info_outline, showBorder: false);

  @override
  Widget build(BuildContext context) {
    // Info banner uses theme accent for color instead of fixed blue.
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.baseAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(theme.cornerRadius),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.baseAccent, size: iconSize),
          SizedBox(width: spacing),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: textColor ?? theme.textSecondary,
                fontSize: fontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// DialogActionBar
// ---------------------------------------------------------------------------

/// A Cancel + Primary action button pair with optional loading spinner.
///
/// Works both as `AlertDialog.actions` children and as a standalone `Row`.
///
/// ```dart
/// DialogActionBar(
///   theme: theme,
///   onCancel: () => Navigator.pop(context),
///   onConfirm: _submit,
///   confirmIcon: Icons.lock,
///   confirmLabel: 'Enable Encryption',
///   isLoading: _isLoading,
/// )
/// ```
class DialogActionBar extends StatelessWidget {
  const DialogActionBar({
    super.key,
    required this.theme,
    required this.onConfirm,
    this.onCancel,
    this.showCancel = true,
    this.cancelLabel = 'Cancel',
    this.confirmIcon,
    this.confirmLabel = 'Confirm',
    this.loadingLabel,
    this.isLoading = false,
    this.isEnabled = true,
    this.destructive = false,
    this.cancelOnRight = false,
    this.spinnerSize = 16,
  });

  final AppThemeData theme;

  /// Called when Cancel is pressed. If null, pops the current route.
  final VoidCallback? onCancel;

  /// Whether to show the cancel button.
  final bool showCancel;

  /// Called when the primary button is pressed.
  final VoidCallback? onConfirm;

  final String cancelLabel;
  final IconData? confirmIcon;
  final String confirmLabel;

  /// Label shown while [isLoading] is true. Falls back to [confirmLabel].
  final String? loadingLabel;

  final bool isLoading;

  /// Extra disable condition (ANDed with !isLoading).
  final bool isEnabled;

  /// When true the primary button uses a red destructive style.
  final bool destructive;

  /// When true, places the cancel button on the right of the primary action.
  final bool cancelOnRight;

  /// Size of the loading spinner. Defaults to 16.
  final double spinnerSize;

  @override
  Widget build(BuildContext context) {
    final cancelButton = TextButton(
      onPressed: isLoading ? null : (onCancel ?? () => Navigator.pop(context)),
      child: Text(cancelLabel),
    );

    final effectiveEnabled = !isLoading && isEnabled;

    final Widget spinnerWidget = SizedBox(
      width: spinnerSize,
      height: spinnerSize,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: destructive ? Colors.white : null,
      ),
    );

    final primaryButton = confirmIcon != null
        ? ElevatedButton.icon(
            onPressed: effectiveEnabled ? onConfirm : null,
            icon: isLoading ? spinnerWidget : Icon(confirmIcon),
            label: Text(
              isLoading ? (loadingLabel ?? confirmLabel) : confirmLabel,
            ),
          )
        : OutlinedButton(
            onPressed: effectiveEnabled ? onConfirm : null,
            style: destructive
                ? OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  )
                : null,
            child: Text(
              isLoading ? (loadingLabel ?? confirmLabel) : confirmLabel,
            ),
          );

    final children = !showCancel
      ? <Widget>[primaryButton]
      : cancelOnRight
        ? <Widget>[primaryButton, const SizedBox(width: 8), cancelButton]
        : <Widget>[cancelButton, const SizedBox(width: 8), primaryButton];

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

// ---------------------------------------------------------------------------
// showConfirmDialog
// ---------------------------------------------------------------------------

/// Shows a simple themed confirmation dialog that returns `true` or `false`.
///
/// ```dart
/// final ok = await showConfirmDialog(
///   context: context,
///   theme: theme,
///   title: 'Delete items?',
///   message: 'This action cannot be undone.',
///   confirmLabel: 'Delete',
///   destructive: true,
/// );
/// ```
Future<bool> showConfirmDialog({
  required BuildContext context,
  required AppThemeData theme,
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  IconData? confirmIcon,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: theme.background,
      title: Text(title, style: TextStyle(color: theme.textPrimary)),
      content: Text(message, style: TextStyle(color: theme.textSecondary)),
      actions: [
        DialogActionBar(
          theme: theme,
          onCancel: () => Navigator.pop(ctx, false),
          onConfirm: () => Navigator.pop(ctx, true),
          cancelLabel: cancelLabel,
          confirmLabel: confirmLabel,
          confirmIcon: confirmIcon,
          destructive: destructive,
        ),
      ],
    ),
  );
  return result ?? false;
}
