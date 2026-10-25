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

export 'app_dialog.dart';
import 'app_dialog.dart';

/// Global padding applied to all dialog content containers.
///
/// Defines a consistent inner spacing for both [Dialog]-based and
/// [AlertDialog]-based dialogs, replacing the per-dialog hardcoded values that
/// previously varied across the codebase.
const EdgeInsets kDialogContentPadding = EdgeInsets.symmetric(
  horizontal: 12,
  vertical: 12,
);

/// Standard vertical gap between elements within a dialog window.
///
/// Replaces all per-dialog [SizedBox] heights. Update this value to change
/// spacing uniformly across all dialogs.
const double kDialogSpacing = 12.0;

/// Shared width for compact confirmations and password prompts.
const double kCompactDialogWidth = 440.0;

ButtonStyle themedFilledButtonStyle(
  AppThemeData theme, {
  bool destructive = false,
}) {
  final backgroundColor = destructive ? theme.error : theme.primaryButton;
  final foregroundColor = theme.primaryButtonText;
  final disabledBackground = destructive
      ? backgroundColor.withValues(alpha: 0.18)
      : theme.primaryButtonDisabled;
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
    this.showCloseButton = false,
  });

  /// Optional leading icon. When null no icon or spacing is rendered.
  final IconData? icon;
  final String title;
  final AppThemeData theme;

  /// Defaults to [theme.accent].
  final Color? iconColor;

  /// Defaults to 28 when [showCloseButton] is true, else platform default.
  final double? iconSize;

  /// If true, adds a themed close `IconButton` at the trailing edge.
  final bool showCloseButton;

  @override
  Widget build(BuildContext context) {
    final effectiveSize = iconSize ?? (showCloseButton ? 28.0 : null);
    final effectiveColor = iconColor ?? theme.accent;

    final textWidget = Text(
      title,
      style: TextStyle(
        color: theme.textPrimary,
        fontSize: 18,
        fontWeight: showCloseButton ? FontWeight.w600 : FontWeight.w700,
      ),
      overflow: TextOverflow.ellipsis,
    );

    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon!, color: effectiveColor, size: effectiveSize),
          const SizedBox(width: 8),
        ],
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

/// Shared warning banner for destructive actions and security notices.
class DialogBanner extends StatelessWidget {
  const DialogBanner.warning({
    super.key,
    required this.message,
    required this.theme,
  });

  final String message;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: theme.baseAccent.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(theme.cornerRadius),
    ),
    child: Row(
      children: [
        Icon(Icons.warning_amber, color: theme.baseAccent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: theme.textSecondary, fontSize: 11),
          ),
        ),
      ],
    ),
  );
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

  /// When true the primary button uses the themed destructive style.
  final bool destructive;

  /// Size of the loading spinner. Defaults to 16.
  final double spinnerSize;

  @override
  Widget build(BuildContext context) {
    final effectiveShowCancel = showCancel || onCancel != null;
    final cancelButton = OutlinedButton(
      onPressed: isLoading ? null : (onCancel ?? () => Navigator.pop(context)),
      child: Text(cancelLabel),
    );

    final effectiveEnabled = !isLoading && isEnabled;

    final Widget spinnerWidget = AppCircularProgressIndicator(
      color: destructive ? theme.primaryButtonText : null,
      strokeWidth: theme.progressIndicatorStrokeWidth,
      size: spinnerSize,
    );

    final primaryButton = ElevatedButton.icon(
      onPressed: effectiveEnabled ? onConfirm : null,
      style: destructive
          ? themedFilledButtonStyle(theme, destructive: true)
          : null,
      icon: confirmIcon == null
          ? null
          : isLoading
          ? spinnerWidget
          : Icon(confirmIcon),
      label: Text(isLoading ? (loadingLabel ?? confirmLabel) : confirmLabel),
    );

    if (!effectiveShowCancel) {
      return SizedBox(width: double.infinity, child: primaryButton);
    }

    return Row(
      children: [
        Expanded(child: cancelButton),
        const SizedBox(width: kElementHSpacing),
        Expanded(child: primaryButton),
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
    this.theme,
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
    this.fullscreen = false,
  });

  final AppThemeData? theme;
  final bool fullscreen;

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

  @override
  Widget build(BuildContext context) {
    final theme =
        this.theme ?? Theme.of(context).extension<AppThemeData>() ?? kDarkTheme;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final effectiveMaxHeight = fullscreen
        ? screenHeight
        : maxHeight ?? (screenHeight * 0.85);

    final rows = <Widget>[];

    if (title != null) {
      rows.add(
        Container(
          padding: EdgeInsets.only(left: 6, right: 0),
          decoration: BoxDecoration(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: kElementHSpacing,
            children: [
              Expanded(child: title!),
              ...?titleActions,
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
            child: Wrap(
              spacing: kElementHSpacing,
              runSpacing: kElementVSpacing,
              alignment: WrapAlignment.end,
              children: actions!,
            ),
          ),
        );
      }
    }

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(theme.cornerRadius),
    );

    final dialogBox = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: fullscreen ? double.infinity : maxWidth,
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

    if (fullscreen) {
      return Dialog.fullscreen(
        backgroundColor: backgroundColor ?? theme.background,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(child: dialogBox),
              if (below != null)
                Padding(padding: const EdgeInsets.all(8), child: below!),
            ],
          ),
        ),
      );
    }

    // Extra content sits outside the styled surface in a transparent Dialog.
    return Dialog(
      backgroundColor: below != null
          ? Colors.transparent
          : backgroundColor ?? theme.background,
      shadowColor: below != null ? Colors.transparent : null,
      surfaceTintColor: below != null ? Colors.transparent : null,
      elevation: below != null ? 0 : null,
      shape: below != null ? null : shape,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: below == null
          ? dialogBox
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Material(
                    color: backgroundColor ?? theme.background,
                    shape: shape,
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
  bool showCancel = false,
  IconData? confirmIcon,
  bool destructive = false,
  IconData? titleIcon,
}) async {
  final result = await showAppDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => DialogInteractionScope(
      onPrimaryAction: () => Navigator.pop(ctx, true),
      onDismiss: () => Navigator.pop(ctx, false),
      child: ThemedAlertDialog(
        theme: theme,
        maxWidth: kCompactDialogWidth,
        title: DialogHeader(
          icon: titleIcon,
          iconColor: destructive && titleIcon != null ? theme.error : null,
          title: title,
          theme: theme,
        ),
        content: Text(message, style: TextStyle(color: theme.textSecondary)),
        actions: [
          DialogActionBar(
            theme: theme,
            onConfirm: () => Navigator.pop(ctx, true),
            showCancel: showCancel,
            onCancel: showCancel ? () => Navigator.pop(ctx, false) : null,
            cancelLabel: cancelLabel,
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
