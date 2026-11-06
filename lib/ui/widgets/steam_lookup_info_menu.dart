import 'package:flutter/material.dart';

import '../../core/services/steam_service.dart';
import '../../core/theme/app_theme.dart';
import 'popup_menu_helpers.dart';

/// Lookup details anchored to the header, using the theme icon menu's motion.
class SteamLookupInfoMenu extends StatelessWidget {
  const SteamLookupInfoMenu({
    super.key,
    required this.theme,
    required this.searchedTitle,
    required this.result,
  });

  final AppThemeData theme;
  final String searchedTitle;
  final SteamSearchResult result;

  Widget _section({
    required IconData icon,
    required String label,
    required Widget child,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20, color: theme.accent),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: theme.textSecondary, fontSize: 12),
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
      color: theme.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(theme.cornerRadius),
    ),
    child: Text(label, style: TextStyle(color: theme.accent, fontSize: 12)),
  );

  Widget _details(Size size, ScrollController scrollController) {
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
          controller: scrollController,
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
                child: Text(searchedTitle, style: valueStyle),
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
  Widget build(BuildContext context) => AnchoredPanelMenu(
    theme: theme,
    maxSize: const Size(320, 420),
    panel: _details,
    button: (focusNode, toggle) => IconButton(
      focusNode: focusNode,
      tooltip: 'Lookup details',
      style: theme.compactIconButtonStyle,
      icon: Icon(Icons.info_outline, color: theme.accent, size: 26),
      onPressed: toggle,
    ),
  );
}
