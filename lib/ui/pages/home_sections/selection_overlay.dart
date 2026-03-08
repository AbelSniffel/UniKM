/// Selection overlay bar shown at the bottom when games are selected
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../dialogs/steam_lookup_dialog.dart';
import '../../widgets/notification_system.dart';
import '../../widgets/navigation_panel.dart';
import '../../dialogs/game_details_dialog.dart';
import '../../dialogs/copy_actions_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

/// Helper to construct the selection overlay widget
Widget buildSelectionOverlay(
  BuildContext context,
  WidgetRef ref,
  AppThemeData theme,
  Set<int> selectedGameIds,
) {
  return SelectionOverlay(
    theme: theme,
    selectedGameIds: selectedGameIds,
  );
}

/// Collapsible selection overlay bar
class SelectionOverlay extends ConsumerWidget {
  const SelectionOverlay({
    super.key,
    required this.theme,
    required this.selectedGameIds,
  });

  final AppThemeData theme;
  final Set<int> selectedGameIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCollapsed = ref.watch(selectionBarCollapsedProvider);
    final allUsed = ref.watch(selectedGamesAllUsedProvider);
    
    final selectedCount = selectedGameIds.length;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    void openDetails() {
      // Build list of ids similar to GameCard._handleDoubleTap logic
      final allGames = ref.read(gamesProvider.select((s) => s.filteredGames));
      final ids = selectedGameIds.isNotEmpty
          ? (selectedGameIds.length > 1
              ? allGames
                  .where((g) => selectedGameIds.contains(g.id))
                  .map((g) => g.id)
                  .toList()
              : [selectedGameIds.first])
          : <int>[];
      if (ids.isEmpty) {
        NotificationManager.instance.info('No games selected');
        return;
      }
      showDialog(
        context: context,
        builder: (ctx) => GameDetailsDialog(initialGameId: ids.first, gameIds: ids),
      );
    }

    void showCopyDialog() {
      final selectedGames = ref.read(selectedGamesProvider);
      if (selectedGames.isEmpty) {
        NotificationManager.instance.info('No games selected');
        return;
      }
      showDialog(
        context: context,
        builder: (ctx) => CopyActionsDialog(targets: selectedGames),
      );
    }

    Future<void> openSteamPage() async {
      final selectedGames = ref.read(selectedSteamGamesProvider);
      if (selectedGames.isEmpty) {
        NotificationManager.instance.info('No Steam games selected');
        return;
      }
      for (final game in selectedGames) {
        final title = game.title;
        final appId = game.steamAppId;
        final Uri url = appId.isNotEmpty
            ? Uri.parse('https://store.steampowered.com/app/$appId')
            : Uri.parse(
                'https://store.steampowered.com/search/?term=${Uri.encodeComponent(title)}',
              );

        try {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        } catch (e) {
          NotificationManager.instance.error(
            'Failed to open Steam page for $title',
          );
        }
      }

      if (selectedGames.length == 1) {
        NotificationManager.instance.info(
          'Opened Steam page for ${selectedGames.first.title}',
        );
      } else {
        NotificationManager.instance.info(
          'Opened Steam pages for ${selectedGames.length} games',
        );
      }
    }

    /// Creates an action button used in both the collapsed (compact) and
    /// expanded (full) selection bar.  When [label] is provided the button
    /// renders with text beside the icon; otherwise only the icon is shown and
    /// a tooltip will be displayed on hover.
    Widget actionButton({
      required IconData icon,
      required String tooltip,
      required VoidCallback onTap,
      String? label,
      Color? foreground,
      bool isDestructive = false,
    }) {
        // icon color may be overridden while the button styling always uses
      // the primary text color for consistency.
      final iconColor = foreground ?? theme.primaryButtonText;
      final styleColor = theme.primaryButtonText;

      // constants used by both compact and expanded styles
      const double fillAlpha = 0.05;
      const double overlayAlpha = 0.15;
      const double destructivePressedAlpha = 0.90;
      const double borderAlpha = 0.30;

      Color fillColor(Set<WidgetState> states) {
        if (isDestructive) {
          // destructive buttons use the normal fill color by default and
          // switch to the error color only while pressed.
          return states.contains(WidgetState.pressed)
              ? theme.error
              : styleColor.withValues(alpha: fillAlpha);
        }
        return styleColor.withValues(alpha: fillAlpha);
      }

      Color? overlayColorFor(Set<WidgetState> states) {
        if (isDestructive) {
          if (states.contains(WidgetState.pressed)) {
            return theme.error.withValues(alpha: destructivePressedAlpha);
          }
          return null;
        }
        return styleColor.withValues(alpha: overlayAlpha);
      }

      // reusable widget-state properties
      final backgroundColor = WidgetStateProperty.resolveWith(fillColor);
      final overlayColor = WidgetStateProperty.resolveWith(overlayColorFor);
      final side = WidgetStateProperty.all(
        BorderSide(color: styleColor.withValues(alpha: borderAlpha)),
      );

      // helper to compute the static fill color for non-material widgets (compact)
      final compactFill = fillColor(<WidgetState>{});
      final compactOverlay = overlayColorFor({WidgetState.pressed});

      if (label != null && label.isNotEmpty) {
        // expanded mode: text button with icon
        return TextButton.icon(
          onPressed: onTap,
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.all(styleColor),
            backgroundColor: backgroundColor,
            overlayColor: overlayColor,
            padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(theme.cornerRadius)),
            ),
            side: side,
          ),
          icon: Icon(icon, size: 18, color: iconColor),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        );
      } else {
        // compact mode: icon only with tooltip
        return Tooltip(
          message: tooltip,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(theme.cornerRadius),
              // use the computed overlay colour rather than the default white ripple
              highlightColor: compactOverlay,
              splashColor: compactOverlay,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: compactFill,
                  borderRadius: BorderRadius.circular(theme.cornerRadius),
                  border: Border.all(color: styleColor.withValues(alpha: borderAlpha)),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
            ),
          ),
        );
      }
    }

    // Collapsed view — compact icon-only actions + count
    if (isCollapsed) {
      // Determine whether selected games are all "used" to toggle the icon/action
      return Container(
        margin: EdgeInsets.zero,
        padding: EdgeInsets.only(
          left: 8,
          right: 8,
          top: 6,
          bottom: 6 + bottomInset,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.primary.withValues(alpha: 0.95),
              theme.primary.withValues(alpha: 0.95),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Left-aligned: collapse button + selection count
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, right: 6),
                    child: MorphingIconButton(
                      theme: theme,
                      toggled: isCollapsed,
                      iconToggled: Icons.more_vert,
                      iconUntoggled: Icons.menu,
                      tooltipToggled: 'Expand Selection Bar',
                      tooltipUntoggled: 'Collapse Selection Bar',
                      onTap: () => ref.read(settingsProvider.notifier).setSetting(SettingsKeys.selectionBarCollapsed, !isCollapsed),
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(theme.cornerRadius),
                    ),
                    child: Text(
                      '$selectedCount selected',
                      style: TextStyle(
                        color: theme.primaryButtonText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Centered: compact action buttons (icons only)
            Align(
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  actionButton(
                    icon: Icons.info_outline,
                    tooltip: 'View Details',
                    onTap: openDetails,
                  ),
                  const SizedBox(width: 8),
                  actionButton(
                    icon: Icons.copy_all,
                    tooltip: 'Copy',
                    onTap: showCopyDialog,
                  ),
                  const SizedBox(width: 8),
                  actionButton(
                    icon: Icons.open_in_new,
                    tooltip: 'Open Steam Page',
                    onTap: openSteamPage,
                  ),
                  const SizedBox(width: 8),
                  actionButton(
                    icon: allUsed ? Icons.check_box : Icons.check_box_outline_blank,
                    tooltip: allUsed ? 'Mark Unused' : 'Mark Used',
                    onTap: () async {
                      await ref.read(gamesProvider.notifier).setGamesUsed(selectedGameIds.toList(), !allUsed);
                      NotificationManager.instance.success('${selectedGameIds.length} ${!allUsed ? 'marked as used' : 'marked as unused'}');
                    },
                  ),
                  const SizedBox(width: 8),
                  actionButton(
                    icon: Icons.cloud_download,
                    tooltip: 'Fetch',
                    foreground: ref.read(batchFetchProvider).isActive
                        ? theme.textSecondary.withValues(alpha: 0.4)
                        : null,
                    onTap: () async {
                      final selectedGames = ref.read(selectedSteamGamesProvider);
                      if (selectedGames.isEmpty) {
                        NotificationManager.instance.info('No Steam games selected');
                        return;
                      }
                      if (ref.read(batchFetchProvider).isActive) {
                        NotificationManager.instance.info('A fetch is already in progress');
                        return;
                      }
                      await performSteamBatchLookup(context, selectedGames);
                    },
                  ),
                  const SizedBox(width: 8),
                  actionButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Delete',
                    isDestructive: true,
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            backgroundColor: theme.background,
                            title: Text('Delete ${selectedGameIds.length} games?', style: TextStyle(color: theme.textPrimary)),
                            content: const Text('This action cannot be undone.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                              ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: theme.error), child: const Text('Delete')),
                            ],
                          );
                        },
                      );

                      if (confirmed == true) {
                        await ref.read(gamesProvider.notifier).deleteGames(selectedGameIds.toList());
                        NotificationManager.instance.success('Deleted ${selectedGameIds.length} games');
                      }
                    },
                  ),
                ],
              ),
            ),

            // Right-aligned: clear selection
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => ref.read(gamesProvider.notifier).clearSelection(),
                    constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                    icon: Icon(Icons.close, color: theme.primaryButtonText),
                    tooltip: 'Clear Selection',
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Full view
    return Container(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 6,
        bottom: 6 + bottomInset,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.primary.withValues(alpha: 0.95),
            theme.primary.withValues(alpha: 0.95),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Left-aligned: collapse button + selection count
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 6),
                  child: MorphingIconButton(
                    theme: theme,
                    toggled: isCollapsed,
                    iconToggled: Icons.more_vert,
                    iconUntoggled: Icons.menu,
                    tooltipToggled: 'Expand Selection Bar',
                    tooltipUntoggled: 'Collapse Selection Bar',
                    onTap: () => ref.read(settingsProvider.notifier).setSetting(SettingsKeys.selectionBarCollapsed, !isCollapsed),
                  ),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(theme.cornerRadius),
                  ),
                  child: Text(
                    '$selectedCount selected',
                    style: TextStyle(
                      color: theme.primaryButtonText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),

          // Centered: non-destructive actions
          Align(
            alignment: Alignment.center,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  actionButton(
                    icon: Icons.info_outline,
                    tooltip: 'View Details',
                    label: 'View Details',
                    onTap: openDetails,
                  ),
                  const SizedBox(width: 8),
                  actionButton(
                    icon: Icons.copy_all,
                    tooltip: 'Copy',
                    label: 'Copy',
                    onTap: showCopyDialog,
                  ),
                  const SizedBox(width: 8),
                  actionButton(
                    icon: Icons.open_in_new,
                    tooltip: 'Open Steam Page',
                    label: 'Open Steam Page',
                    onTap: openSteamPage,
                  ),
                  const SizedBox(width: 8),
                  actionButton(
                    icon: allUsed ? Icons.check_box : Icons.check_box_outline_blank,
                    tooltip: allUsed ? 'Mark Unused' : 'Mark Used',
                    label: allUsed ? 'Mark Unused' : 'Mark Used',
                    onTap: () async {
                      await ref.read(gamesProvider.notifier).setGamesUsed(selectedGameIds.toList(), !allUsed);
                      NotificationManager.instance.success('${selectedGameIds.length} ${!allUsed ? 'marked as used' : 'marked as unused'}');
                    },
                  ),

                  const SizedBox(width: 8),
                  actionButton(
                    icon: Icons.cloud_download,
                    tooltip: 'Fetch',
                    label: 'Fetch',
                    onTap: () async {
                      final selectedGames = ref.read(selectedSteamGamesProvider);
                      if (selectedGames.isEmpty) {
                        NotificationManager.instance.info('No Steam games selected');
                        return;
                      }
                      if (ref.read(batchFetchProvider).isActive) {
                        NotificationManager.instance.info('A fetch is already in progress');
                        return;
                      }
                      await performSteamBatchLookup(context, selectedGames);
                    },
                  ),

                  const SizedBox(width: 8),
                  // delete remains compact even in expanded view; it no longer has a label
                  actionButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Delete',
                    isDestructive: true,
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            backgroundColor: theme.background,
                            title: Text('Delete ${selectedGameIds.length} games?'),
                            content: const Text('This action cannot be undone.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.error,
                                ),
                                child: const Text('Delete'),
                              ),
                            ],
                          );
                        },
                      );

                      if (confirmed == true) {
                        await ref
                            .read(gamesProvider.notifier)
                            .deleteGames(selectedGameIds.toList());
                        NotificationManager.instance.success(
                          'Deleted ${selectedGameIds.length} games',
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          // Right-aligned: only close button now that delete has moved
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () =>
                      ref.read(gamesProvider.notifier).clearSelection(),
                  constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                  icon: Icon(Icons.close, color: theme.primaryButtonText),
                  tooltip: 'Clear Selection',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
