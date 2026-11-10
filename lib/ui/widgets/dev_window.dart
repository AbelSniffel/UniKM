import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/deadline_notification_service.dart';
import '../../core/settings/settings_model.dart';
import '../../providers/app_providers.dart';
import '../../app/application/update_controller.dart';
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

  static void _close() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  static void toggle(BuildContext context) {
    if (_overlayEntry != null) return _close();
    _overlayEntry = OverlayEntry(
      builder: (context) => const DevWindowOverlay(onClose: _close),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  @override
  ConsumerState<DevWindowOverlay> createState() => _DevWindowOverlayState();
}

class _DevWindowOverlayState extends ConsumerState<DevWindowOverlay> {
  static NotificationHandle? _fetchPreviewHandle;
  static int _fetchPreviewStep = 0;

  final _position = ValueNotifier(const Offset(100, 100));

  /// Where the title row was grabbed, from the panel's corner.
  Offset? _grab;
  int _tab = 0;

  static const _fetchPreviewStates = [
    ('Portal 2', 0.18),
    ('Half-Life 2', 0.42),
    ('Left 4 Dead 2', 0.71),
    ('Team Fortress 2', 0.94),
  ];

  bool get _hasActiveFetchPreview {
    final handle = _fetchPreviewHandle;
    if (handle == null) return false;
    return NotificationManager.instance.currentNotifications.any(
      (notification) => notification.id == handle.id,
    );
  }

  void _showOrAdvanceFetchPreview() {
    final count = _fetchPreviewStates.length;
    final step = _fetchPreviewStep % count;
    final (title, progress) = _fetchPreviewStates[step];
    const message = 'Fetching Steam data';
    final progressLabel = '${step + 1}/$count';
    if (!_hasActiveFetchPreview) {
      _fetchPreviewHandle = NotificationManager.instance.beginTask(
        message,
        type: NotificationType.steam,
        title: title,
        progress: progress,
        progressLabel: progressLabel,
        actionLabel: 'Cancel',
        onAction: _clearFetchPreview,
      );
    } else {
      _fetchPreviewHandle!.update(
        message: message,
        title: title,
        progress: progress,
        progressLabel: progressLabel,
        actionLabel: 'Cancel',
        onAction: _clearFetchPreview,
      );
    }

    _fetchPreviewStep = (step + 1) % count;
    setState(() {});
  }

  void _clearFetchPreview() {
    _fetchPreviewHandle?.dismiss();
    _fetchPreviewHandle = null;
    _fetchPreviewStep = 0;
    if (mounted) setState(() {});
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

  /// Runs a firewall action and reports its outcome.
  Future<void> _firewallAction(
    Future<bool> Function(DeviceSyncNotifier sync) run,
    String failure, {
    String? success,
    String? command,
  }) async {
    if (await run(ref.read(deviceSyncProvider.notifier))) {
      if (success != null) NotificationManager.instance.success(success);
    } else if (mounted) {
      // The copy button copies only the command to run manually.
      NotificationManager.instance.error(
        command == null
            ? failure
            : '$failure You may need to run this command manually:\n$command',
        actionLabel: command == null ? null : 'Copy command',
        actionIcon: Icons.copy,
        onAction: command == null
            ? null
            : () => Clipboard.setData(ClipboardData(text: command)),
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
    final showId =
        (settings[SettingsKeys.showGameDetailsSkmId] as bool?) ??
        DefaultSettings.showGameDetailsSkmId;
    final showSyncDeviceId = ref.watch(showSyncDeviceIdProvider);
    final showSyncStatus = ref.watch(showSyncStatusProvider);
    final showSeasonal = ref.watch(showSeasonalPatternsProvider);
    // Plain outlined buttons in the app theme's style.
    Widget action(String label, IconData icon, VoidCallback? onTap) =>
        OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(label),
        );
    // A small label over its actions, which wrap at their own widths.
    Widget section(String title, List<Widget> actions) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelMedium!.copyWith(
            color: theme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        Wrap(spacing: 6, runSpacing: 6, children: actions),
      ],
    );
    Widget settingToggle(String label, IconData icon, String key, bool value) =>
        AppActionButton(
          label: label,
          icon: icon,
          theme: theme,
          onTap: () => ref.read(settingsProvider.notifier).set(key, !value),
          selected: value,
        );

    final content = switch (_tab) {
      0 => [
        section('Send test', [
          action('In-app preview', Icons.notifications_outlined, () {
            for (final (type, title) in const [
              (NotificationType.info, 'Info'),
              (NotificationType.warning, 'Warning'),
              (NotificationType.error, 'Error'),
            ]) {
              NotificationManager.instance.showHandle(
                message: 'Test ${type.name} notification from Dev Tools.',
                type: type,
                title: title,
              );
            }
          }),
          action(
            'OS notification',
            Icons.desktop_windows_outlined,
            DeadlineNotificationService.instance.sendTestOsNotification,
          ),
        ]),
        section('Deadlines', [
          action('Simulate alerts', Icons.timelapse, () async {
            await DeadlineNotificationService.instance
                .simulateDeadlineNotifications(ref);
            NotificationManager.instance.info(
              'Deadline notifications simulated',
            );
          }),
          action(
            'Run check',
            Icons.timer_outlined,
            () => DeadlineNotificationService.instance.triggerAndRestart(ref),
          ),
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
          settingToggle(
            'Device ID',
            Icons.fingerprint,
            SettingsKeys.showSyncDeviceId,
            showSyncDeviceId,
          ),
          settingToggle(
            'Sync status',
            Icons.info_outline,
            SettingsKeys.showSyncStatus,
            showSyncStatus,
          ),
          settingToggle(
            'SKM-ID',
            Icons.tag,
            SettingsKeys.showGameDetailsSkmId,
            showId,
          ),
          settingToggle(
            'Seasonal patterns',
            Icons.celebration_outlined,
            SettingsKeys.showSeasonalPatterns,
            showSeasonal,
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
              () => _firewallAction(
                (sync) => sync.openWindowsFirewallAllowedApps(),
                'Could not open Windows Firewall Allowed Apps.',
              ),
            ),
            action(
              'Advanced rules',
              Icons.admin_panel_settings_outlined,
              () => _firewallAction(
                (sync) => sync.openWindowsFirewallAdvancedSettings(),
                'Could not open Windows Firewall Advanced Settings.',
              ),
            ),
          ]),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux)
          section('Linux firewall', [
            action(
              'Grant access',
              Icons.shield_outlined,
              () => _firewallAction(
                (sync) => sync.grantFirewallAccess(),
                'Could not add firewall rules.',
                command: 'sudo ufw allow 45871/udp && sudo ufw allow 45872/tcp',
                success:
                    'Firewall rules added for UniKM (ufw/firewalld/iptables).',
              ),
            ),
            action(
              'Clear access',
              Icons.shield_outlined,
              () => _firewallAction(
                (sync) => sync.clearLinuxFirewallAccess(),
                'Could not remove firewall rules.',
                command:
                    'sudo ufw delete allow 45871/udp && sudo ufw delete allow 45872/tcp',
                success: 'Firewall rules removed for UniKM.',
              ),
            ),
          ]),
        section('Dialogs', [
          Tooltip(
            message: 'Shortcut: Ctrl+Alt+G',
            child: action('Open dialog gallery', Icons.grid_view_rounded, () {
              final navigatorContext = context;
              widget.onClose();
              showDialogGallery(navigatorContext);
            }),
          ),
        ]),
      ],
    };

    return Positioned.fill(
      child: RepaintBoundary(
        // Moving only re-positions the panel; its content stays cached.
        child: CustomSingleChildLayout(
          delegate: _PanelLayout(_position),
          child: RepaintBoundary(
            child: Material(
              key: const ValueKey('dev-tools-panel'),
              // The app's main background, like the pages behind it.
              color: theme.background,
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
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // One tinted header: the title bar to drag by, and the
                    // tabs under it.
                    ColoredBox(
                      color: theme.accent.withValues(alpha: 0.12),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 4, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _dragHandle(theme),
                            AppTabBar(
                              theme: theme,
                              selectedIndex: _tab,
                              onChanged: (index) =>
                                  setState(() => _tab = index),
                              tabs: const [
                                AppTab('Notifications'),
                                AppTab('Updates'),
                                AppTab('Tools'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Flexible(
                      child: AppTabTransition(
                        index: _tab,
                        child: SingleChildScrollView(
                          key: ValueKey('dev-tools-tab-$_tab'),
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: 10,
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
    );
  }

  /// The title row, which drags the panel by the point it was grabbed at.
  Widget _dragHandle(AppThemeData theme) => MouseRegion(
    cursor: SystemMouseCursors.move,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onPanStart: (details) =>
          _grab = details.localPosition + const Offset(8, 0),
      onPanUpdate: (details) {
        final grab = _grab;
        if (grab == null) return;
        // Absolute pointer tracking keeps events between frames; the layout
        // keeps the panel on screen.
        final overlay = context.findRenderObject()! as RenderBox;
        _position.value = overlay.globalToLocal(details.globalPosition) - grab;
      },
      onPanEnd: (_) => _grab = null,
      onPanCancel: () => _grab = null,
      child: SizedBox(
        height: 36,
        child: Row(
          spacing: 5,
          children: [
            Icon(Icons.tune, color: theme.accent),
            Expanded(
              child: Text(
                'Dev Tools',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            // Always measured while Dev Tools is open.
            AppFpsCounter(theme: theme),
            IconButton(
              tooltip: 'Close Dev Tools',
              onPressed: widget.onClose,
              icon: Icon(Icons.close, color: theme.textSecondary),
              style: IconButton.styleFrom(
                minimumSize: const Size.square(28),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Places the panel at its dragged position, kept 12 px inside the window
/// at whatever height its tab gives it.
class _PanelLayout extends SingleChildLayoutDelegate {
  _PanelLayout(this.position) : super(relayout: position);

  static const _margin = 12.0;
  final ValueListenable<Offset> position;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width = math.min(360.0, constraints.maxWidth - _margin * 2);
    return BoxConstraints(
      minWidth: math.max(0, width),
      maxWidth: math.max(0, width),
      maxHeight: math.max(
        0,
        math.min(440.0, constraints.maxHeight - _margin * 2),
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    position.value.dx.clamp(
      _margin,
      math.max(_margin, size.width - childSize.width - _margin),
    ),
    position.value.dy.clamp(
      _margin,
      math.max(_margin, size.height - childSize.height - _margin),
    ),
  );

  @override
  bool shouldRelayout(_PanelLayout oldDelegate) =>
      position != oldDelegate.position;
}
