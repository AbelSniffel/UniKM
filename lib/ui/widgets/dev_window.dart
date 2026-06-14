import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/deadline_notification_service.dart';
import '../../core/settings/settings_model.dart';
import '../../providers/app_providers.dart';
import '../pages/update_page.dart';
import '../../core/constants/app_constants.dart';
import 'app_fps_counter.dart';
import 'notification_system.dart';

class DevWindowOverlay extends ConsumerStatefulWidget {
  const DevWindowOverlay({super.key, required this.onClose});
  final VoidCallback onClose;

  static OverlayEntry? _overlayEntry;

  static void toggle(BuildContext context) {
    if (_overlayEntry != null) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    } else {
      _overlayEntry = OverlayEntry(
        builder: (context) => DevWindowOverlay(
          onClose: () {
            _overlayEntry?.remove();
            _overlayEntry = null;
          },
        ),
      );
      Overlay.of(context).insert(_overlayEntry!);
    }
  }

  @override
  ConsumerState<DevWindowOverlay> createState() => _DevWindowOverlayState();
}

class _DevWindowOverlayState extends ConsumerState<DevWindowOverlay> {
  static NotificationHandle? _fetchPreviewHandle;
  static int _fetchPreviewStep = 0;

  Offset position = const Offset(100, 100);

  static const List<({String title, String message, double progress})>
  _fetchPreviewStates = [
    (title: 'Portal 2', message: 'Fetching Steam data (1/4)', progress: 0.18),
    (
      title: 'Half-Life 2',
      message: 'Fetching Steam data (2/4)',
      progress: 0.42,
    ),
    (
      title: 'Left 4 Dead 2',
      message: 'Fetching Steam data (3/4)',
      progress: 0.71,
    ),
    (
      title: 'Team Fortress 2',
      message: 'Fetching Steam data (4/4)',
      progress: 0.94,
    ),
  ];

  bool get _hasActiveFetchPreview {
    final handle = _fetchPreviewHandle;
    if (handle == null) return false;
    return NotificationManager.instance.currentNotifications.any(
      (notification) => notification.id == handle.id,
    );
  }

  void _showOrAdvanceFetchPreview() {
    final nextState =
        _fetchPreviewStates[_fetchPreviewStep % _fetchPreviewStates.length];

    if (!_hasActiveFetchPreview) {
      _fetchPreviewHandle = NotificationManager.instance.beginTask(
        nextState.message,
        type: NotificationType.steam,
        title: nextState.title,
        progress: nextState.progress,
        actionLabel: 'Cancel',
        onAction: _clearFetchPreview,
      );
    } else {
      _fetchPreviewHandle!.update(
        message: nextState.message,
        title: nextState.title,
        progress: nextState.progress,
        actionLabel: 'Cancel',
        onAction: _clearFetchPreview,
      );
    }

    _fetchPreviewStep = (_fetchPreviewStep + 1) % _fetchPreviewStates.length;
    setState(() {});
  }

  void _clearFetchPreview() {
    _fetchPreviewHandle?.dismiss();
    _fetchPreviewHandle = null;
    _fetchPreviewStep = 0;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _clearSelectedSteamData() async {
    final selectedGames = ref.read(selectedGamesProvider);
    if (selectedGames.isEmpty) {
      NotificationManager.instance.info('No games selected');
      return;
    }

    final cleared = await ref
        .read(gamesProvider.notifier)
        .clearSteamMetadata(
          selectedGames.map((game) => game.id).toList(growable: false),
        );

    if (cleared == 0) {
      NotificationManager.instance.warning(
        'No selected games were updated',
      );
      return;
    }

    NotificationManager.instance.success(
      'Cleared Steam data on $cleared selected game${cleared == 1 ? '' : 's'}',
    );
  }

  Future<void> _openWindowsFirewallAllowedApps() async {
    final launched =
        await ref.read(deviceSyncProvider.notifier).openWindowsFirewallAllowedApps();
    if (!launched && mounted) {
      NotificationManager.instance.error(
        'Could not open Windows Firewall Allowed Apps.',
      );
    }
  }

  Future<void> _openWindowsFirewallAdvancedRules() async {
    final launched = await ref
        .read(deviceSyncProvider.notifier)
        .openWindowsFirewallAdvancedSettings();
    if (!launched && mounted) {
      NotificationManager.instance.error(
        'Could not open Windows Firewall Advanced Settings.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final selectedGames = ref.watch(selectedGamesProvider);
    final batchFetchActive = ref.watch(
      batchFetchProvider.select((state) => state.isActive),
    );
    final showFpsCounter = ref.watch(
      settingsProvider.select(
        (s) =>
            (s[SettingsKeys.showFpsCounter] as bool?) ??
            DefaultSettings.showFpsCounter,
      ),
    );
    final showGameDetailsSkmId = ref.watch(
      settingsProvider.select(
        (s) =>
            (s[SettingsKeys.showGameDetailsSkmId] as bool?) ??
            DefaultSettings.showGameDetailsSkmId,
      ),
    );

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 365,
          decoration: BoxDecoration(
            color: theme.surface.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(theme.cornerRadius),
            boxShadow: [
              BoxShadow(
                color: theme.accent.withValues(alpha: 0.30),
                blurRadius: 8,
                spreadRadius: 3,
                offset: const Offset(0, 0),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              //  Drag handle / header
              GestureDetector(
                onPanUpdate: (d) => setState(() => position += d.delta),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.accent.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(theme.cornerRadius),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.developer_mode, size: 18, color: theme.accent),
                      const SizedBox(width: kElementHSpacing),
                      Text(
                        'Dev Tools',
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      if (showFpsCounter) ...[
                        AppFpsCounter(
                          theme: theme,
                          style: TextStyle(
                            color: theme.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: kElementHSpacing),
                      ],
                      _CloseButton(onPressed: widget.onClose, theme: theme),
                    ],
                  ),
                ),
              ),

              //  Body
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    //  UPDATES
                    _SectionHeader(
                      label: 'Updates',
                      icon: Icons.system_update,
                      theme: theme,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _DevButton(
                            label: 'Check',
                            icon: Icons.refresh,
                            theme: theme,
                            onPressed: () {
                              ref
                                  .read(updateProvider.notifier)
                                  .checkForUpdates();
                              NotificationManager.instance.info(
                                'Checking for updates',
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _DevButton(
                            label: 'Clear State',
                            icon: Icons.clear_all,
                            theme: theme,
                            onPressed: () =>
                                ref.read(updateProvider.notifier).clearUpdate(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _CompactDevButton(
                          label: 'Idle',
                          theme: theme,
                          onPressed: () => ref
                              .read(updateProvider.notifier)
                              .previewState(UpdatePreviewState.idle),
                        ),
                        _CompactDevButton(
                          label: 'Checking',
                          theme: theme,
                          onPressed: () => ref
                              .read(updateProvider.notifier)
                              .previewState(UpdatePreviewState.checking),
                        ),
                        _CompactDevButton(
                          label: 'Up To Date',
                          theme: theme,
                          onPressed: () => ref
                              .read(updateProvider.notifier)
                              .previewState(UpdatePreviewState.upToDate),
                        ),
                        _CompactDevButton(
                          label: 'Available',
                          theme: theme,
                          onPressed: () => ref
                              .read(updateProvider.notifier)
                              .previewState(UpdatePreviewState.updateAvailable),
                        ),
                        _CompactDevButton(
                          label: 'Downloading',
                          theme: theme,
                          onPressed: () => ref
                              .read(updateProvider.notifier)
                              .previewState(UpdatePreviewState.downloading),
                        ),
                        _CompactDevButton(
                          label: 'Downloaded',
                          theme: theme,
                          onPressed: () => ref
                              .read(updateProvider.notifier)
                              .previewState(UpdatePreviewState.downloaded),
                        ),
                        _CompactDevButton(
                          label: 'Error',
                          theme: theme,
                          onPressed: () => ref
                              .read(updateProvider.notifier)
                              .previewState(UpdatePreviewState.error),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    //  NOTIFICATIONS
                    _SectionHeader(
                      label: 'Notifications',
                      icon: Icons.notifications_outlined,
                      theme: theme,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _DevButton(
                            label: 'In-App Notification',
                            icon: Icons.message_outlined,
                            theme: theme,
                            onPressed: () => NotificationManager.instance.info(
                              'Test in-app notification from Dev Tools.',
                              title: 'Dev Test',
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _DevButton(
                            label: 'OS Notify',
                            icon: Icons.desktop_windows_outlined,
                            theme: theme,
                            onPressed: () => DeadlineNotificationService
                                .instance
                                .sendTestOsNotification(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _DevButton(
                            label: 'Run Deadline Check',
                            icon: Icons.timer_outlined,
                            theme: theme,
                            onPressed: () => DeadlineNotificationService
                                .instance
                                .triggerAndRestart(ref),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _DevButton(
                            label: 'Deadline Sim',
                            icon: Icons.timelapse,
                            theme: theme,
                            onPressed: () async {
                              await DeadlineNotificationService.instance
                                  .simulateDeadlineNotifications(ref);
                              NotificationManager.instance.info(
                                'Deadline notifications simulated',
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _DevButton(
                            label: _hasActiveFetchPreview
                                ? 'Advance Fetch Preview'
                                : 'Show Fetch Preview',
                            icon: Icons.cloud_download_outlined,
                            theme: theme,
                            onPressed: _showOrAdvanceFetchPreview,
                          ),
                        ),
                      ],
                    ),

                    if (isWindows) ...[
                      const SizedBox(height: 12),

                      //  SYNC
                      _SectionHeader(
                        label: 'Firewall',
                        icon: Icons.shield_outlined,
                        theme: theme,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _DevButton(
                              label: 'Allowed Apps',
                              icon: Icons.shield_outlined,
                              theme: theme,
                              onPressed: _openWindowsFirewallAllowedApps,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _DevButton(
                              label: 'Advanced Rules',
                              icon: Icons.admin_panel_settings_outlined,
                              theme: theme,
                              onPressed: _openWindowsFirewallAdvancedRules,
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 12),

                    //  LIBRARY
                    _SectionHeader(
                      label: 'Library',
                      icon: Icons.video_library_outlined,
                      theme: theme,
                    ),
                    const SizedBox(height: 6),
                    _DevButton(
                      label: selectedGames.isEmpty
                          ? 'Clear Selected Steam Data'
                          : 'Clear Steam Data (${selectedGames.length})',
                      icon: Icons.delete_outline,
                      theme: theme,
                      onPressed: selectedGames.isEmpty || batchFetchActive
                          ? null
                          : _clearSelectedSteamData,
                    ),

                    const SizedBox(height: 12),

                    //  DISPLAY
                    _SectionHeader(
                      label: 'Display',
                      icon: Icons.display_settings_outlined,
                      theme: theme,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _DevButton(
                            label: showFpsCounter
                                ? 'Hide FPS'
                                : 'Show FPS',
                            icon: showFpsCounter
                                ? Icons.speed
                                : Icons.speed_outlined,
                            theme: theme,
                            onPressed: () {
                              ref
                                  .read(settingsProvider.notifier)
                                  .setSetting(
                                    SettingsKeys.showFpsCounter,
                                    !showFpsCounter,
                                  );
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _DevButton(
                            label: showGameDetailsSkmId
                                ? 'Hide SKM-ID'
                                : 'Show SKM-ID',
                            icon: showGameDetailsSkmId
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            theme: theme,
                            onPressed: () {
                              ref
                                  .read(settingsProvider.notifier)
                                  .setSetting(
                                    SettingsKeys.showGameDetailsSkmId,
                                    !showGameDetailsSkmId,
                                  );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Helper widgets
// =============================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.icon,
    required this.theme,
  });

  final String label;
  final IconData icon;
  final dynamic theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: theme.textSecondary),
        const SizedBox(width: 5),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: theme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(child: Divider(height: 1, color: theme.border)),
      ],
    );
  }
}

class _DevButton extends StatelessWidget {
  const _DevButton({
    required this.label,
    required this.icon,
    required this.theme,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final dynamic theme;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _CompactDevButton extends StatelessWidget {
  const _CompactDevButton({
    required this.label,
    required this.theme,
    required this.onPressed,
  });

  final String label;
  final dynamic theme;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = theme.accent as Color;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: effectiveColor.withValues(alpha: 0.35)),
        foregroundColor: effectiveColor,
        backgroundColor: effectiveColor.withValues(alpha: 0.05),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

// simple close button with hover effect
class _CloseButton extends StatefulWidget {
  const _CloseButton({required this.onPressed, required this.theme});

  final VoidCallback onPressed;
  final dynamic theme;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hovering = false;

  void _onHover(bool hovering) {
    if (_hovering != hovering) {
      setState(() {
        _hovering = hovering;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _hovering
        ? (widget.theme.accent as Color).withValues(alpha: 0.15)
        : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => _onHover(true),
      onExit: (_) => _onHover(false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.close, size: 20, color: widget.theme.textPrimary),
        ),
      ),
    );
  }
}
