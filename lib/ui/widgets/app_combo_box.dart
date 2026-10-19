import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import 'popup_menu_helpers.dart';

/// The app's combobox: themed input with the shared, padding-free popup menu.
/// Use [compact] and [selectedChild] for an icon-only selector.
class AppComboBox<T> extends FormField<T> {
  AppComboBox({
    super.key,
    super.initialValue,
    required this.items,
    required this.onChanged,
    this.theme,
    this.decoration = const InputDecoration(),
    this.style,
    this.hint,
    this.selectedChild,
    this.icon,
    this.isExpanded = true,
    this.compact = false,
    this.padding = EdgeInsets.zero,
    this.menuWidth,
    this.menuMaxHeight = kDropdownMenuMaxHeight,
    super.validator,
    super.onSaved,
    super.autovalidateMode,
  }) : super(
         enabled: onChanged != null && items.isNotEmpty,
         builder: (state) => (state as _AppComboBoxState<T>)._buildControl(),
       );

  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final AppThemeData? theme;
  final InputDecoration decoration;
  final TextStyle? style;
  final Widget? hint;
  final Widget? selectedChild;
  final Widget? icon;
  final bool isExpanded;
  final bool compact;
  final EdgeInsetsGeometry padding;
  final double? menuWidth;
  final double menuMaxHeight;

  @override
  FormFieldState<T> createState() => _AppComboBoxState<T>();
}

class _AppComboBoxState<T> extends FormFieldState<T> {
  @override
  void didUpdateWidget(covariant AppComboBox<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      setValue(widget.initialValue);
    }
  }

  final _focusNode = FocusNode();
  bool _focused = false;
  bool _hovered = false;
  bool _open = false;

  AppComboBox<T> get _combo => widget as AppComboBox<T>;
  AppThemeData get _theme =>
      _combo.theme ??
      Theme.of(context).extension<AppThemeData>() ??
      (Theme.of(context).brightness == Brightness.dark
          ? kDarkTheme
          : kLightTheme);

  Future<void> _openMenu() async {
    if (!_combo.enabled || _open) return;
    _focusNode.requestFocus();
    setState(() => _open = true);
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final width = (_combo.menuWidth ?? box.size.width).clamp(
      0.0,
      (overlay.size.width - 16).clamp(0.0, double.infinity),
    );
    final theme = _theme;
    final selected = await showAppMenu<T>(
      context: context,
      initialValue: value,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(origin.dx, origin.dy + box.size.height, width, 0),
        Offset.zero & overlay.size,
      ),
      color: theme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        side: BorderSide(color: theme.border),
      ),
      constraints: BoxConstraints(
        minWidth: width,
        maxWidth: width,
        maxHeight: _combo.menuMaxHeight,
      ),
      items: [
        for (final item in _combo.items)
          PopupMenuItem<T>(
            value: item.value,
            enabled: item.enabled,
            onTap: item.onTap,
            child: DefaultTextStyle.merge(
              style: _combo.style ?? TextStyle(color: theme.textPrimary),
              child: IconTheme.merge(
                data: IconThemeData(color: theme.textPrimary),
                child: item,
              ),
            ),
          ),
      ],
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (selected == null ||
        !_combo.enabled ||
        !_combo.items.any((item) => item.value == selected && item.enabled)) {
      return;
    }
    didChange(selected);
    _combo.onChanged?.call(selected);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Widget _buildControl() {
    final combo = _combo;
    final theme = _theme;
    final selected = combo.items.where((item) => item.value == value);
    final label =
        combo.selectedChild ??
        (selected.isEmpty ? combo.hint : selected.first.child) ??
        const SizedBox.shrink();
    final row = DefaultTextStyle.merge(
      style: combo.style ?? TextStyle(color: theme.textPrimary),
      child: Row(
        mainAxisSize: combo.isExpanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (combo.isExpanded) Expanded(child: label) else label,
          combo.icon ?? Icon(Icons.arrow_drop_down, color: theme.textSecondary),
        ],
      ),
    );
    return Semantics(
      button: true,
      enabled: combo.enabled,
      expanded: _open,
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowDown): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
              ActivateIntent(),
        },
        child: Actions(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _openMenu();
                return null;
              },
            ),
          },
          child: InkWell(
            focusNode: _focusNode,
            onFocusChange: (value) => setState(() => _focused = value),
            onHover: (value) => setState(() => _hovered = value),
            onTap: combo.enabled ? _openMenu : null,
            borderRadius: BorderRadius.circular(theme.cornerRadius),
            hoverColor: combo.compact ? theme.navItemHover : Colors.transparent,
            focusColor: combo.compact ? theme.navItemHover : Colors.transparent,
            child: combo.compact
                ? Padding(
                    padding: combo.padding,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: kIconSize),
                      child: row,
                    ),
                  )
                : InputDecorator(
                    isFocused: _focused || _open,
                    isHovering: _hovered,
                    isEmpty: value == null,
                    decoration: combo.decoration
                        .applyDefaults(Theme.of(context).inputDecorationTheme)
                        .copyWith(
                          enabled: combo.enabled,
                          isDense: combo.decoration.isDense ?? true,
                          errorText: errorText,
                        ),
                    child: row,
                  ),
          ),
        ),
      ),
    );
  }
}
