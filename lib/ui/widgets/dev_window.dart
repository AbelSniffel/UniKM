import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/deadline_notification_service.dart';
import '../../core/settings/settings_model.dart';
import '../../providers/app_providers.dart';
import '../pages/update_page.dart';
import '../dialogs/dialog_gallery.dart';
import '../../core/theme/app_theme.dart';
import 'app_action_button.dart';
import 'app_fps_counter.dart';
import 'app_tab_bar.dart';
import 'notification_system.dart';
import 'update_status_icons.dart';

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

  final _position = ValueNotifier(const Offset(100, 100));
  Offset? _dragOffset;
  int _tab = 0;

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
      NotificationManager.instance.warning('No selected games were updated');
      return;
    }

    NotificationManager.instance.success(
      'Cleared Steam data on $cleared selected game${cleared == 1 ? '' : 's'}',
    );
  }

  Future<void> _openWindowsFirewallAllowedApps() async {
    final launched = await ref
        .read(deviceSyncProvider.notifier)
        .openWindowsFirewallAllowedApps();
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

  Future<void> _grantLinuxFirewallAccess() async {
    final granted = await ref
        .read(deviceSyncProvider.notifier)
        .grantLinuxFirewallAccess();
    if (granted) {
      NotificationManager.instance.success(
        'Firewall rules added for UniKM (ufw/firewalld/iptables).',
      );
    } else if (mounted) {
      NotificationManager.instance.error(
        'Could not add firewall rules. You may need to run this command manually:\n'
        'sudo ufw allow 45871/udp && sudo ufw allow 45872/tcp',
      );
    }
  }

  Future<void> _clearLinuxFirewallAccess() async {
    final cleared = await ref
        .read(deviceSyncProvider.notifier)
        .clearLinuxFirewallAccess();
    if (cleared) {
      NotificationManager.instance.success('Firewall rules removed for UniKM.');
    } else if (mounted) {
      NotificationManager.instance.error(
        'Could not remove firewall rules. You may need to run this command manually:\n'
        'sudo ufw delete allow 45871/udp && sudo ufw delete allow 45872/tcp',
      );
    }
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final selectedGames = ref.watch(selectedGamesProvider);
    final batchFetchActive = ref.watch(
      batchFetchProvider.select((state) => state.isActive),
    );
    final settings = ref.watch(settingsProvider);
    final showFps =
        (settings[SettingsKeys.showFpsCounter] as bool?) ??
        DefaultSettings.showFpsCounter;
    final showId =
        (settings[SettingsKeys.showGameDetailsSkmId] as bool?) ??
        DefaultSettings.showGameDetailsSkmId;
    final showSyncDeviceId = ref.watch(showSyncDeviceIdProvider);
    final viewport = MediaQuery.sizeOf(context);
    final width = math.min(380.0, math.max(0.0, viewport.width - 24));
    final height = math.min(400.0, math.max(0.0, viewport.height - 24));
    Offset clampPosition(Offset position) => Offset(
      position.dx.clamp(12.0, math.max(12.0, viewport.width - width - 12)),
      position.dy.clamp(12.0, math.max(12.0, viewport.height - height - 12)),
    );

    Widget action(
      String label,
      IconData icon,
      VoidCallback? onTap, {
      bool? selected,
    }) => AppActionButton(
      label: label,
      icon: icon,
      theme: theme,
      onTap: onTap,
      selected: selected,
      expandLabel: true,
    );
    Widget section(String title, List<Widget> actions) =>
        _DevSection(title: title, theme: theme, children: actions);

    final content = switch (_tab) {
      0 => [
        section('Notifications', [
          action('In-app preview', Icons.notifications_outlined, () {
            final notifications = NotificationManager.instance;
            notifications.info(
              'Test info notification from Dev Tools.',
              title: 'Info',
            );
            notifications.warning(
              'Test warning notification from Dev Tools.',
              title: 'Warning',
            );
            notifications.error(
              'Test error notification from Dev Tools.',
              title: 'Error',
            );
          }),
          action(
            'OS notification',
            Icons.desktop_windows_outlined,
            () => DeadlineNotificationService.instance.sendTestOsNotification(),
          ),
        ]),
        section('Deadlines', [
          action(
            'Run check',
            Icons.timer_outlined,
            () => DeadlineNotificationService.instance.triggerAndRestart(ref),
          ),
          action('Simulate alerts', Icons.timelapse, () async {
            await DeadlineNotificationService.instance
                .simulateDeadlineNotifications(ref);
            NotificationManager.instance.info(
              'Deadline notifications simulated',
            );
          }),
        ]),
        section('Steam fetch', [
          action(
            _hasActiveFetchPreview ? 'Advance preview' : 'Show preview',
            Icons.cloud_download_outlined,
            _showOrAdvanceFetchPreview,
          ),
          action(
            'Clear preview',
            Icons.close,
            _hasActiveFetchPreview ? _clearFetchPreview : null,
          ),
        ]),
        section('Dialogs', [
          action('Open dialog gallery', Icons.grid_view_rounded, () {
            final navigatorContext = context;
            widget.onClose();
            showDialogGallery(navigatorContext);
          }),
        ]),
      ],
      1 => [
        section('Update service', [
          action('Check for updates', Icons.refresh, () {
            ref.read(updateProvider.notifier).checkForUpdates();
            NotificationManager.instance.info('Checking for updates');
          }),
          action(
            'Clear state',
            UpdateStatusIcons.idle,
            () => ref.read(updateProvider.notifier).clearUpdate(),
          ),
        ]),
        section('Preview update states', [
          for (final preview in [
            (UpdatePreviewState.idle, 'Idle', UpdateStatusIcons.idle),
            (
              UpdatePreviewState.checking,
              'Checking',
              UpdateStatusIcons.checking,
            ),
            (
              UpdatePreviewState.upToDate,
              'Up to date',
              UpdateStatusIcons.upToDate,
            ),
            (
              UpdatePreviewState.updateAvailable,
              'Available',
              UpdateStatusIcons.available,
            ),
            (
              UpdatePreviewState.downloading,
              'Downloading',
              UpdateStatusIcons.downloading,
            ),
            (
              UpdatePreviewState.downloaded,
              'Downloaded',
              UpdateStatusIcons.downloaded,
            ),
            (UpdatePreviewState.error, 'Error', UpdateStatusIcons.error),
          ])
            action(
              preview.$2,
              preview.$3,
              () => ref.read(updateProvider.notifier).previewState(preview.$1),
            ),
        ]),
      ],
      _ => [
        section('Display', [
          action(
            'Device ID',
            Icons.fingerprint,
            () => ref
                .read(settingsProvider.notifier)
                .setSetting(SettingsKeys.showSyncDeviceId, !showSyncDeviceId),
            selected: showSyncDeviceId,
          ),
          action(
            'FPS counter',
            Icons.speed,
            () => ref
                .read(settingsProvider.notifier)
                .setSetting(SettingsKeys.showFpsCounter, !showFps),
            selected: showFps,
          ),
          action(
            'SKM-ID',
            Icons.tag,
            () => ref
                .read(settingsProvider.notifier)
                .setSetting(SettingsKeys.showGameDetailsSkmId, !showId),
            selected: showId,
          ),
        ]),
        section('Library · ${selectedGames.length} selected', [
          action(
            'Clear Steam data',
            Icons.delete_outline,
            selectedGames.isEmpty || batchFetchActive
                ? null
                : _clearSelectedSteamData,
          ),
        ]),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows)
          section('Windows firewall', [
            action(
              'Allowed apps',
              Icons.shield_outlined,
              _openWindowsFirewallAllowedApps,
            ),
            action(
              'Advanced rules',
              Icons.admin_panel_settings_outlined,
              _openWindowsFirewallAdvancedRules,
            ),
          ]),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux)
          section('Linux firewall', [
            action(
              'Grant access',
              Icons.shield_outlined,
              _grantLinuxFirewallAccess,
            ),
            action(
              'Clear access',
              Icons.shield_outlined,
              _clearLinuxFirewallAccess,
            ),
          ]),
      ],
    };

    return Positioned.fill(
      child: RepaintBoundary(
        child: Align(
          alignment: Alignment.topLeft,
          child: ValueListenableBuilder<Offset>(
            valueListenable: _position,
            builder: (context, position, child) => Transform.translate(
              offset: clampPosition(position),
              child: child,
            ),
            child: RepaintBoundary(
              child: SizedBox(
                width: width,
                height: height,
                child: Material(
                  key: const ValueKey('dev-tools-panel'),
                  color: theme.surface,
                  elevation: 12,
                  shadowColor: Colors.black.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(theme.cornerRadius),
                    side: BorderSide(color: theme.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: DefaultTextStyle(
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium!.copyWith(color: theme.textPrimary),
                    child: Column(
                      children: [
                        MouseRegion(
                          cursor: SystemMouseCursors.move,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            dragStartBehavior: DragStartBehavior.down,
                            onPanStart: (details) {
                              _dragOffset =
                                  details.globalPosition -
                                  clampPosition(_position.value);
                            },
                            onPanUpdate: (details) {
                              final dragOffset = _dragOffset;
                              if (dragOffset == null) return;
                              // Absolute pointer tracking keeps events between frames.
                              // Only the translation rebuilds; the panel stays cached.
                              _position.value = clampPosition(
                                details.globalPosition - dragOffset,
                              );
                            },
                            onPanEnd: (_) => _dragOffset = null,
                            onPanCancel: () => _dragOffset = null,
                            child: Container(
                              color: theme.accent.withValues(alpha: 0.12),
                              padding: const EdgeInsets.fromLTRB(12, 5, 5, 5),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.tune,
                                    size: 18,
                                    color: theme.accent,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Dev Tools',
                                      style: TextStyle(
                                        color: theme.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (showFps) AppFpsCounter(theme: theme),
                                  IconButton(
                                    tooltip: 'Close Dev Tools',
                                    onPressed: widget.onClose,
                                    icon: Icon(
                                      Icons.close,
                                      size: 18,
                                      color: theme.textSecondary,
                                    ),
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size.square(30),
                                      padding: const EdgeInsets.all(4),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: AppTabBar(
                            theme: theme,
                            selectedIndex: _tab,
                            onChanged: (index) => setState(() => _tab = index),
                            tabs: const [
                              AppTab('Previews'),
                              AppTab('Updates'),
                              AppTab('Tools'),
                            ],
                          ),
                        ),
                        Expanded(
                          child: AppTabTransition(
                            index: _tab,
                            child: SingleChildScrollView(
                              key: ValueKey('dev-tools-tab-$_tab'),
                              padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: content,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DevSection extends StatelessWidget {
  const _DevSection({
    required this.title,
    required this.theme,
    required this.children,
  });
  final String title;
  final AppThemeData theme;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelMedium!.copyWith(
              color: theme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                constraints.maxWidth >= 320 &&
                    MediaQuery.textScalerOf(context).scale(14) <= 17
                ? 2
                : 1;
            final width = (constraints.maxWidth - 6 * (columns - 1)) / columns;
            return Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final child in children)
                  SizedBox(width: width, child: child),
              ],
            );
          },
        ),
      ],
    ),
  );
}
