import 'package:flutter/material.dart';

import '../../core/services/steam_service.dart';
import '../../core/theme/app_theme.dart';
import 'popup_menu_helpers.dart';

/// Lookup details anchored to the header, using the theme icon menu's motion.
class SteamLookupInfoMenu extends StatefulWidget {
  const SteamLookupInfoMenu({
    super.key,
    required this.theme,
    required this.searchedTitle,
    required this.result,
  });

  final AppThemeData theme;
  final String searchedTitle;
  final SteamSearchResult result;

  @override
  State<SteamLookupInfoMenu> createState() => _SteamLookupInfoMenuState();
}

class _SteamLookupInfoMenuState extends State<SteamLookupInfoMenu> {
  final _controller = MenuController();
  final _buttonFocus = FocusNode();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _buttonFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Size _menuSize(BuildContext context) =>
      anchoredMenuSize(MediaQuery.of(context), const Size(320, 420));

  Widget _section({
    required IconData icon,
    required String label,
    required Widget child,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20, color: widget.theme.accent),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: widget.theme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 4),
            child,
          ],
        ),
      ),
    ],
  );

  Widget _badge(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: widget.theme.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
    ),
    child: Text(
      label,
      style: TextStyle(color: widget.theme.accent, fontSize: 12),
    ),
  );

  Widget _details(BuildContext context) {
    final theme = widget.theme;
    final size = _menuSize(context);
    final result = widget.result;
    final matchService = result.searchSource;
    final otherSearches = result.searchSourcesTried
        .where((source) => source != matchService)
        .toList();
    final valueStyle = TextStyle(
      color: theme.textPrimary,
      fontWeight: FontWeight.w600,
    );

    return SizedBox(
      width: size.width,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: size.height),
        child: SingleChildScrollView(
          controller: _scrollController,
          primary: false,
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Lookup Details',
                style: TextStyle(
                  color: theme.accent,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              _section(
                icon: Icons.search,
                label: 'Searched title',
                child: Text(widget.searchedTitle, style: valueStyle),
              ),
              Divider(height: 24, color: theme.border),
              if (matchService != null) ...[
                _section(
                  icon: Icons.travel_explore,
                  label: 'Match service',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 6,
                    children: [
                      Text(matchService.label, style: valueStyle),
                      if (matchService == SteamSearchSource.community)
                        _badge('Fallback match'),
                    ],
                  ),
                ),
              ] else
                _section(
                  icon: Icons.cloud_outlined,
                  label: 'Fetch services',
                  child: Text(
                    'Service details were not recorded for this result. Fetch fresh data to see them.',
                    style: TextStyle(color: theme.textSecondary, fontSize: 12),
                  ),
                ),
              if (otherSearches.isNotEmpty) ...[
                const SizedBox(height: 14),
                _section(
                  icon: Icons.manage_search,
                  label: 'Also searched',
                  child: Text(
                    otherSearches.map((source) => source.label).join(', '),
                    style: TextStyle(color: theme.textPrimary),
                  ),
                ),
              ],
              if (result.dataSources.isNotEmpty) ...[
                const SizedBox(height: 14),
                _section(
                  icon: Icons.cloud_done_outlined,
                  label: 'Data supplied by',
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final source in result.dataSources)
                        _badge(source.label),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return MenuAnchor(
      controller: _controller,
      animated: !MediaQuery.disableAnimationsOf(context),
      childFocusNode: _buttonFocus,
      consumeOutsideTap: true,
      useRootOverlay: true,
      reservedPadding: const EdgeInsets.all(8),
      alignmentOffset: Offset(
        Directionality.of(context) == TextDirection.ltr
            ? -_menuSize(context).width
            : 0,
        8,
      ),
      style: appMenuStyle(theme),
      menuChildren: [_details(context)],
      builder: (context, controller, _) => IconButton(
        focusNode: _buttonFocus,
        tooltip: 'Lookup details',
        style: theme.compactIconButtonStyle,
        icon: Icon(Icons.info_outline, color: theme.accent, size: 26),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
