import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Snap Material's implicit colors on theme changes, retaining its normal
/// interaction animations on subsequent frames and keeping button state mounted.
class ButtonThemeSync extends StatefulWidget {
  const ButtonThemeSync({
    super.key,
    required this.theme,
    required this.builder,
  });

  final AppThemeData theme;
  final Widget Function(BuildContext context, bool snapTheme) builder;

  @override
  State<ButtonThemeSync> createState() => _ButtonThemeSyncState();
}

class _ButtonThemeSyncState extends State<ButtonThemeSync> {
  ThemeData? _materialTheme;
  bool _snapTheme = false;
  bool _restoreQueued = false;

  void _snapColors() {
    _snapTheme = true;
    if (_restoreQueued) return;
    _restoreQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreQueued = false;
      if (mounted) setState(() => _snapTheme = false);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context);
    if (_materialTheme != null && !identical(theme, _materialTheme)) {
      _snapColors();
    }
    _materialTheme = theme;
  }

  @override
  void didUpdateWidget(ButtonThemeSync oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.theme != widget.theme) _snapColors();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _snapTheme);
}
