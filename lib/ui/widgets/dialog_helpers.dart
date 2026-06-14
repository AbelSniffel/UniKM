/// Shared dialog building blocks — header, banner, action bar, etc.
///
/// Eliminates the repeated patterns found across all dialog files:
/// - Header Row with icon + title (± close button)
/// - Warning/info banner with colored background
/// - Cancel + primary action button pair with loading spinner
/// - Simple confirmation dialog
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import 'app_progress_indicator.dart';

/// Global padding applied to all dialog content containers.
///
/// Defines a consistent inner spacing for both [Dialog]-based and
/// [AlertDialog]-based dialogs, replacing the per-dialog hardcoded values that
/// previously varied across the codebase.
const EdgeInsets kDialogContentPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 12);

/// Standard vertical gap between elements within a dialog window.
///
/// Replaces all per-dialog [SizedBox] heights. Update this value to change
/// spacing uniformly across all dialogs.
const double kDialogSpacing = 12.0;

ButtonStyle themedFilledButtonStyle(
  AppThemeData theme, {
  bool destructive = false,
}) {
  final backgroundColor = destructive ? theme.error : theme.accent;
  final foregroundColor = destructive ? Colors.white : theme.primaryButtonText;
  final disabledBackground = Color.alphaBlend(
    theme.background.withValues(alpha: 0.4),
    backgroundColor.withValues(alpha: 0.5),
  );
  final disabledForeground = foregroundColor.withValues(alpha: 0.7);

  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return disabledBackground;
      }
      if (states.contains(WidgetState.pressed)) {
        return backgroundColor.withValues(alpha: 0.9);
      }
      return backgroundColor;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return disabledForeground;
      }
      return foregroundColor;
    }),
  );
}

class DialogInteractionScope extends StatelessWidget {
  const DialogInteractionScope({
    super.key,
    required this.child,
    this.onPrimaryAction,
    this.onDismiss,
    this.enableEscapeDismiss = true,
    this.enableEnterToPrimary = true,
  });

  final Widget child;
  final VoidCallback? onPrimaryAction;
  final VoidCallback? onDismiss;
  final bool enableEscapeDismiss;
  final bool enableEnterToPrimary;

  bool _shouldHandlePrimaryAction() {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) {
      return true;
    }

    final focusedWidget = focusedContext.widget;
    if (focusedWidget is EditableText) {
      final maxLines = focusedWidget.maxLines;
      if (maxLines == null || maxLines > 1) {
        return false;
      }
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (intent) {
              if (enableEscapeDismiss) {
                (onDismiss ?? () => Navigator.of(context).maybePop()).call();
              }
              return null;
            },
          ),
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              if (enableEnterToPrimary &&
                  onPrimaryAction != null &&
                  _shouldHandlePrimaryAction()) {
                onPrimaryAction!.call();
              }
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}

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
    this.icon,
    required this.title,
    required this.theme,
    this.iconColor,
    this.iconSize,
    this.spacing = 8,
    this.showCloseButton = false,
    this.titleStyle,
    this.trailing,
  });

  /// Optional leading icon. When null no icon or spacing is rendered.
  final IconData? icon;
  final String title;
  final AppThemeData theme;

  /// Defaults to [theme.accent].
  final Color? iconColor;

  /// Defaults to 28 when [showCloseButton] is true, else platform default.
  final double? iconSize;

  /// Gap between icon and title. Defaults to 8.
  final double spacing;

  /// If true, adds a themed close `IconButton` at the trailing edge.
  final bool showCloseButton;

  /// Override title text style. When null a sensible default is chosen:
  /// - With close button: 20 px, w500, [theme.textPrimary].
  /// - Without: 28 px, w600, [theme.textPrimary].
  final TextStyle? titleStyle;

  /// Optional widget rendered between the title and the close button.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final effectiveSize = iconSize ?? (showCloseButton ? 28.0 : null);
    final effectiveColor = iconColor ?? theme.accent;

    final textWidget = Text(
      title,
      style:
          titleStyle ??
          (showCloseButton
              ? TextStyle(
                  color: theme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                )
              : TextStyle(
                  color: theme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                )),
      overflow: TextOverflow.ellipsis,
    );

    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon!, color: effectiveColor, size: effectiveSize),
          SizedBox(width: spacing),
        ],
        Expanded(child: textWidget),
        ?trailing,
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
    super.iconSize,
    super.textColor,
    super.fontSize = 11,
    super.padding = const EdgeInsets.all(8),
    super.spacing = 8,
  }) : super(
         color: const Color(0xFF2196F3),
         icon: Icons.info_outline,
         showBorder: false,
       );

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

/// A primary action button with an optional secondary dismiss action.
///
/// Works both as `AlertDialog.actions` children and as a standalone `Row`.
///
/// ```dart
/// DialogActionBar(
///   theme: theme,
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
    this.showCancel = false,
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
    final effectiveShowCancel = showCancel || onCancel != null;
    final cancelButton = TextButton(
      onPressed: isLoading ? null : (onCancel ?? () => Navigator.pop(context)),
      child: Text(cancelLabel),
    );

    final effectiveEnabled = !isLoading && isEnabled;

    final Widget spinnerWidget = SizedBox(
      width: spinnerSize,
      height: spinnerSize,
      child: AppCircularProgressIndicator(
        color: destructive ? Colors.white : null,
        strokeWidth: theme.progressIndicatorStrokeWidth,
      ),
    );

    final primaryButton = confirmIcon != null
        ? ElevatedButton.icon(
            onPressed: effectiveEnabled ? onConfirm : null,
            style: themedFilledButtonStyle(theme, destructive: destructive),
            icon: isLoading ? spinnerWidget : Icon(confirmIcon),
            label: Text(
              isLoading ? (loadingLabel ?? confirmLabel) : confirmLabel,
            ),
          )
        : destructive
        ? ElevatedButton(
            onPressed: effectiveEnabled ? onConfirm : null,
            style: themedFilledButtonStyle(theme, destructive: true),
            child: Text(
              isLoading ? (loadingLabel ?? confirmLabel) : confirmLabel,
            ),
          )
        : OutlinedButton(
            onPressed: effectiveEnabled ? onConfirm : null,
            child: Text(
              isLoading ? (loadingLabel ?? confirmLabel) : confirmLabel,
            ),
          );

    if (!effectiveShowCancel) {
      return SizedBox(width: double.infinity, child: primaryButton);
    }

    final orderedButtons = cancelOnRight
        ? <Widget>[primaryButton, cancelButton]
        : <Widget>[cancelButton, primaryButton];

    return Row(
      children: [
        for (int index = 0; index < orderedButtons.length; index++) ...[
          if (index > 0) const SizedBox(width: kElementHSpacing),
          Expanded(child: orderedButtons[index]),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ThemedAlertDialog
// ---------------------------------------------------------------------------

/// A themed [Dialog] that lays out title / content / actions as a manual
/// [Column] separated by [SizedBox] gaps.
///
/// A single [padding] governs all four sides of the dialog's inner area, so
/// spacing can be adjusted in one place. Vertical gaps between the three rows
/// are controlled by [spacing].
///
/// The dialog is constrained to [maxWidth] (default 600) and [maxHeight]
/// (default 85 % of the screen height). When content exceeds the max height the
/// content area becomes scrollable automatically.
///
/// Defaults:
/// - `backgroundColor` → [AppThemeData.surface]
/// - `padding` → [kDialogContentPadding]
/// - `spacing` → `12.0`
/// - `maxWidth` → `600.0`
/// - `maxHeight` → 85 % of screen height
/// - `shape` → [RoundedRectangleBorder] using [AppThemeData.cornerRadius]
///
/// Override [backgroundColor] when a dialog intentionally uses the page
/// background colour instead of the elevated surface colour.
class ThemedAlertDialog extends StatelessWidget {
  const ThemedAlertDialog({
    super.key,
    required this.theme,
    this.title,
    this.content,
    this.body,
    this.actions,
    this.below,
    this.showCloseButton = true,
    this.titleActions,
    this.backgroundColor,
    this.padding = kDialogContentPadding,
    this.spacing = 8.0,
    this.maxWidth = 600.0,
    this.maxHeight,
    this.shape,
    this.insetPadding = const EdgeInsets.symmetric(horizontal: 14.0, vertical: 16.0),
  });

  final AppThemeData theme;

  /// The dialog background colour. Defaults to [AppThemeData.surface].
  final Color? backgroundColor;

  final Widget? title;
  final Widget? content;

  /// A non-scrollable flexible widget placed below [content] and above [actions].
  /// Expands to fill the remaining height. Use this for widgets such as [TabBarView]
  /// that manage their own scrolling. When provided, the dialog fills [maxHeight].
  final Widget? body;

  final List<Widget>? actions;

  /// An optional widget rendered below the dialog box (outside the Material
  /// surface). When provided the outer dialog becomes transparent so the
  /// dialog box and this widget can sit in a Column together.
  final Widget? below;

  final bool showCloseButton;

  /// Optional icon buttons inserted between the title and the close button.
  final List<Widget>? titleActions;

  /// Uniform padding applied to all four sides of the dialog content area.
  /// Defaults to [kDialogContentPadding].
  final EdgeInsetsGeometry padding;

  /// Vertical gap inserted between title → content and content → actions rows.
  final double spacing;

  /// Maximum dialog width. Defaults to 600.
  final double maxWidth;

  /// Maximum dialog height. When null defaults to 85 % of the screen height.
  final double? maxHeight;

  final ShapeBorder? shape;
  final EdgeInsets insetPadding;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final effectiveMaxHeight = maxHeight ?? (screenHeight * 0.85);

    final rows = <Widget>[];

    if (title != null) {
      rows.add(
        Container(
          padding: EdgeInsets.only(left: 6, right: 0),
          decoration: BoxDecoration(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: title!),
              if (titleActions != null) ...titleActions!,
              if (showCloseButton) ...[
                IconButton(
                  icon: Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (content != null) {
      if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
      rows.add(Flexible(child: SingleChildScrollView(child: content!)));
    }

    if (body != null) {
      if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
      rows.add(Expanded(child: body!));
    }

    if (actions != null && actions!.isNotEmpty) {
      if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
      if (actions!.length == 1) {
        rows.add(SizedBox(width: double.infinity, child: actions!.first));
      } else if (actions!.length == 2) {
        rows.add(
          Row(
            children: [
              Expanded(child: actions![0]),
              const SizedBox(width: kElementHSpacing),
              Expanded(child: actions![1]),
            ],
          ),
        );
      } else {
        rows.add(
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < actions!.length; i++) ...[
                  if (i > 0) const SizedBox(width: kElementHSpacing),
                  actions![i],
                ],
              ],
            ),
          ),
        );
      }
    }

    final effectiveShape =
        shape ??
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(theme.cornerRadius),
        );

    final dialogBox = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth,
        maxHeight: effectiveMaxHeight,
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: body != null ? MainAxisSize.max : MainAxisSize.min,
          children: rows,
        ),
      ),
    );

    // When a `below` widget is provided, render a transparent outer Dialog
    // that holds both the styled dialog box and the below widget in a Column,
    // so the below widget appears outside (beneath) the dialog surface.
    if (below != null) {
      return Dialog(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: insetPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Material(
                color: backgroundColor ?? theme.background,
                shape: effectiveShape,
                elevation: 6,
                clipBehavior: Clip.antiAlias,
                child: dialogBox,
              ),
            ),
            const SizedBox(height: 8),
            below!,
          ],
        ),
      );
    }

    return Dialog(
      backgroundColor: backgroundColor ?? theme.background,
      shape: effectiveShape,
      insetPadding: insetPadding,
      child: dialogBox,
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
    barrierDismissible: true,
    builder: (ctx) => DialogInteractionScope(
      onPrimaryAction: () => Navigator.pop(ctx, true),
      onDismiss: () => Navigator.pop(ctx, false),
      child: ThemedAlertDialog(
      theme: theme,

      title: DialogHeader(title: title, theme: theme),
      content: Text(message, style: TextStyle(color: theme.textSecondary)),
      actions: [
        DialogActionBar(
          theme: theme,
          onConfirm: () => Navigator.pop(ctx, true),
          confirmLabel: confirmLabel,
          confirmIcon: confirmIcon,
          destructive: destructive,
        ),
      ],
      ),
  ),
  );
  return result ?? false;
}
