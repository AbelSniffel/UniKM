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
  final _menu = MenuController();

  /// The control's own width, taken as the menu opens.
  double? _menuWidth;

  AppComboBox<T> get _combo => widget as AppComboBox<T>;
  AppThemeData get _theme =>
      _combo.theme ??
      Theme.of(context).extension<AppThemeData>() ??
      (Theme.of(context).brightness == Brightness.dark
          ? kDarkTheme
          : kLightTheme);

  void _openMenu() {
    if (!_combo.enabled) return;
    if (_menu.isOpen) return _menu.close();
    _focusNode.requestFocus();
    final box = context.findRenderObject()! as RenderBox;
    setState(() => _menuWidth = _combo.menuWidth ?? box.size.width);
    // Opens once the width has rebuilt into the menu.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_menu.isOpen) _menu.open();
    });
  }

  void _select(DropdownMenuItem<T> item) {
    item.onTap?.call();
    didChange(item.value);
    _combo.onChanged?.call(item.value);
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
    return AppMenuAnchor(
      theme: theme,
      controller: _menu,
      childFocusNode: _focusNode,
      onOpen: () => setState(() => _open = true),
      onClose: () => setState(() => _open = false),
      width: _menuWidth,
      maxHeight: combo.menuMaxHeight,
      menuChildren: [
        for (final item in combo.items)
          appMenuItem(
            theme,
            selected: item.value == value,
            onPressed: item.enabled ? () => _select(item) : null,
            child: item,
          ),
      ],
      builder: (context, controller, _) => _buildField(theme, row),
    );
  }

  Widget _buildField(AppThemeData theme, Widget row) {
    final combo = _combo;
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
