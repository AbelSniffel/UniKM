import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/deadline_notification_service.dart';
import '../../core/settings/settings_model.dart';
import '../../providers/app_providers.dart';
import '../pages/update_page.dart';
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
  Offset position = const Offset(100, 100);

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final showFpsCounter = ref.watch(
      settingsProvider.select(
        (s) =>
            (s[SettingsKeys.showFpsCounter] as bool?) ??
            DefaultSettings.showFpsCounter,
      ),
    );

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: Material(
        color: Colors.transparent,
        elevation: 8,
        child: Container(
          width: 380,
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(theme.cornerRadius),
            border: Border.all(color: theme.accent, width: 1.5),
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
                    color: theme.accent.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(theme.cornerRadius)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.developer_mode, size: 16, color: theme.accent),
                      const SizedBox(width: 8),
                      Text(
                        'Dev Tools',
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      _CloseButton(
                        onPressed: widget.onClose,
                        theme: theme,
                      ),
                    ],
                  ),
                ),
              ),

              //  Body
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
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
                            label: 'In-App Toast',
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
                    _DevButton(
                      label: 'Deadline Check + Restart Timer',
                      icon: Icons.timer_outlined,
                      theme: theme,
                      onPressed: () => DeadlineNotificationService.instance
                          .triggerAndRestart(ref),
                    ),

                    const SizedBox(height: 12),

                    //  DISPLAY
                    _SectionHeader(
                      label: 'Display',
                      icon: Icons.display_settings_outlined,
                      theme: theme,
                    ),
                    const SizedBox(height: 6),
                    _DevButton(
                      label: showFpsCounter
                          ? 'Hide FPS Counter'
                          : 'Show FPS Counter',
                      icon: showFpsCounter ? Icons.speed : Icons.speed_outlined,
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
            fontSize: 10,
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
    final effectiveColor = theme.accent as Color;
    return SizedBox(
      height: 32,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          side: BorderSide(color: effectiveColor.withValues(alpha: 0.4)),
          foregroundColor: effectiveColor,
          backgroundColor: effectiveColor.withValues(alpha: 0.07),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.cornerRadius as double),
          ),
        ),
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      ),
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
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        side: BorderSide(color: effectiveColor.withValues(alpha: 0.35)),
        foregroundColor: effectiveColor,
        backgroundColor: effectiveColor.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(theme.cornerRadius as double),
        ),
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
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
          child: Icon(
            Icons.close,
            size: 18,
            color: widget.theme.textPrimary,
          ),
        ),
      ),
    );
  }
}
