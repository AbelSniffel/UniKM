/// Toast notification system
/// Matches the original Python notification system with 7 types and 6 positions
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_theme.dart';

/// Notification types
enum NotificationType {
  success,
  error,
  warning,
  info,
  update,
  download,
  steam,
}

/// Notification positions
enum NotificationPosition {
  topLeft,
  topCenter,
  topRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

/// Notification data
class AppNotification {
  AppNotification({
    String? id,
    required this.message,
    required this.type,
    this.title,
    this.progress,
    this.onTap,
    this.actionLabel,
    this.onAction,
    this.isDismissing = false,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final String message;
  final NotificationType type;
  final String? title;
  final double? progress;
  final VoidCallback? onTap;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isDismissing;

  AppNotification copyWith({
    String? message,
    NotificationType? type,
    String? title,
    double? progress,
    VoidCallback? onTap,
    String? actionLabel,
    VoidCallback? onAction,
    bool clearProgress = false,
    bool clearOnTap = false,
    bool clearAction = false,
    bool? isDismissing,
  }) {
    return AppNotification(
      id: id,
      message: message ?? this.message,
      type: type ?? this.type,
      title: title ?? this.title,
      progress: clearProgress ? null : (progress ?? this.progress),
      onTap: clearOnTap ? null : (onTap ?? this.onTap),
      actionLabel: clearAction ? null : (actionLabel ?? this.actionLabel),
      onAction: clearAction ? null : (onAction ?? this.onAction),
      isDismissing: isDismissing ?? this.isDismissing,
    );
  }
}

/// Handle for a notification that can be updated/dismissed.
class NotificationHandle {
  NotificationHandle(this._manager, this.id);

  final NotificationManager _manager;
  final String id;

  void update({
    String? message,
    NotificationType? type,
    String? title,
    double? progress,
    String? actionLabel,
    VoidCallback? onAction,
    bool clearProgress = false,
    bool clearAction = false,
    Duration? autoDismissAfter,
  }) {
    _manager.update(
      id,
      message: message,
      type: type,
      title: title,
      progress: progress,
      actionLabel: actionLabel,
      onAction: onAction,
      clearProgress: clearProgress,
      clearAction: clearAction,
      autoDismissAfter: autoDismissAfter,
    );
  }

  void setProgress(double progress) {
    update(progress: progress);
  }

  void completeSuccess(String message, {String? title}) {
    _manager.update(
      id,
      message: message,
      type: NotificationType.success,
      title: title,
      clearProgress: true,
      autoDismissAfter: NotificationManager.defaultDuration(NotificationType.success),
    );
  }

  void completeError(String message, {String? title}) {
    _manager.update(
      id,
      message: message,
      type: NotificationType.error,
      title: title,
      clearProgress: true,
      autoDismissAfter: NotificationManager.defaultDuration(NotificationType.error),
    );
  }

  void dismiss() {
    _manager.dismiss(id);
  }
}

/// Notification manager singleton
class NotificationManager {
  NotificationManager._();
  
  static final NotificationManager instance = NotificationManager._();

  static const Duration dismissAnimationDuration = Duration(milliseconds: 200);
  
  final _notifications = Queue<AppNotification>();
  final Map<String, Timer> _dismissTimers = <String, Timer>{};
  final Map<String, Timer> _removeTimers = <String, Timer>{};
  final _controller = StreamController<List<AppNotification>>.broadcast();

  bool _enabled = true;
  bool get enabled => _enabled;

  void setEnabled(bool enabled) {
    _enabled = enabled;
    if (!enabled) {
      dismissAll();
    }
  }
  
  Stream<List<AppNotification>> get notifications => _controller.stream;
  List<AppNotification> get currentNotifications => _notifications.toList();
  
  NotificationPosition _position = NotificationPosition.topRight;
  NotificationPosition get position => _position;
  
  void setPosition(NotificationPosition position) {
    _position = position;
  }

  static Duration defaultDuration(NotificationType type) {
    // Match UniKM-Sonnet defaults.
    switch (type) {
      case NotificationType.success:
        return const Duration(milliseconds: 5000);
      case NotificationType.error:
        return const Duration(milliseconds: 7000);
      case NotificationType.warning:
        return const Duration(milliseconds: 6000);
      case NotificationType.info:
        return const Duration(milliseconds: 5000);
      case NotificationType.update:
        return Duration.zero; // No auto-hide
      case NotificationType.download:
        return Duration.zero; // Progress/task
      case NotificationType.steam:
        return Duration.zero; // Progress/task
    }
  }

  NotificationHandle showHandle({
    required String message,
    NotificationType type = NotificationType.info,
    String? title,
    double? progress,
    VoidCallback? onTap,
    String? actionLabel,
    VoidCallback? onAction,
    bool persistent = false,
    bool dedupe = true,
    Duration? autoDismissAfter,
  }) {
    if (!_enabled) {
      return NotificationHandle(this, 'disabled');
    }

    if (dedupe && _notifications.any((n) => n.message == message && n.type == type)) {
      final existing = _notifications.firstWhere((n) => n.message == message && n.type == type);
      return NotificationHandle(this, existing.id);
    }

    final notification = AppNotification(
      message: message,
      type: type,
      title: title,
      progress: progress,
      onTap: onTap,
      actionLabel: actionLabel,
      onAction: onAction,
      isDismissing: false,
    );

    _notifications.add(notification);
    _controller.add(_notifications.toList());

    final shouldAutoDismiss = !persistent && progress == null;
    final dismissAfter = autoDismissAfter ?? defaultDuration(type);
    if (shouldAutoDismiss && dismissAfter != Duration.zero) {
      _dismissTimers[notification.id]?.cancel();
      _dismissTimers[notification.id] = Timer(dismissAfter, () => dismiss(notification.id));
    }

    return NotificationHandle(this, notification.id);
  }
  
  void show({
    required String message,
    NotificationType type = NotificationType.info,
    String? title,
    double? progress,
    VoidCallback? onTap,
  }) {
    showHandle(
      message: message,
      type: type,
      title: title,
      progress: progress,
      onTap: onTap,
    );
  }

  /// Start a sticky "task" notification that stays until completed.
  NotificationHandle beginTask(
    String message, {
    NotificationType type = NotificationType.info,
    String? title,
    double? progress,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return showHandle(
      message: message,
      type: type,
      title: title,
      progress: progress,
      actionLabel: actionLabel,
      onAction: onAction,
      persistent: true,
      dedupe: false,
    );
  }

  void update(
    String id, {
    String? message,
    NotificationType? type,
    String? title,
    double? progress,
    String? actionLabel,
    VoidCallback? onAction,
    bool clearProgress = false,
    bool clearAction = false,
    Duration? autoDismissAfter,
  }) {
    final list = _notifications.toList(growable: false);
    final index = list.indexWhere((n) => n.id == id);
    if (index == -1) return;

    final old = list[index];
    final updated = AppNotification(
      id: id,
      message: message ?? old.message,
      type: type ?? old.type,
      title: title ?? old.title,
      progress: clearProgress ? null : (progress ?? old.progress),
      onTap: old.onTap,
      actionLabel: clearAction ? null : (actionLabel ?? old.actionLabel),
      onAction: clearAction ? null : (onAction ?? old.onAction),
      isDismissing: old.isDismissing,
    );

    _notifications
      ..clear()
      ..addAll(list.take(index))
      ..add(updated)
      ..addAll(list.skip(index + 1));

    _controller.add(_notifications.toList());

    // Reschedule auto-dismiss if requested and it's no longer a task.
    if (autoDismissAfter != null) {
      _dismissTimers[id]?.cancel();
      if (autoDismissAfter != Duration.zero && updated.progress == null) {
        _dismissTimers[id] = Timer(autoDismissAfter, () => dismiss(id));
      }
    }
  }
  
  void dismiss(String id) {
    _dismissTimers.remove(id)?.cancel();
    if (_removeTimers.containsKey(id)) return;

    final list = _notifications.toList(growable: false);
    final index = list.indexWhere((n) => n.id == id);
    if (index == -1) return;

    final old = list[index];
    if (old.isDismissing) return;

    final updated = old.copyWith(isDismissing: true);
    _notifications
      ..clear()
      ..addAll(list.take(index))
      ..add(updated)
      ..addAll(list.skip(index + 1));
    _controller.add(_notifications.toList());

    _removeTimers[id] = Timer(dismissAnimationDuration, () {
      _removeTimers.remove(id)?.cancel();
      _notifications.removeWhere((n) => n.id == id);
      _controller.add(_notifications.toList());
    });
  }
  
  void dismissAll() {
    for (final t in _dismissTimers.values) {
      t.cancel();
    }
    _dismissTimers.clear();
    for (final t in _removeTimers.values) {
      t.cancel();
    }
    _removeTimers.clear();
    _notifications.clear();
    _controller.add(_notifications.toList());
  }
  
  void success(String message, {String? title}) {
    showHandle(message: message, type: NotificationType.success, title: title);
  }
  
  void error(String message, {String? title}) {
    showHandle(message: message, type: NotificationType.error, title: title);
  }
  
  void warning(String message, {String? title}) {
    showHandle(message: message, type: NotificationType.warning, title: title);
  }
  
  void info(String message, {String? title}) {
    showHandle(message: message, type: NotificationType.info, title: title);
  }
  
  void dispose() {
    dismissAll();
    _controller.close();
  }
}

/// Notification overlay widget
class NotificationOverlay extends StatelessWidget {
  const NotificationOverlay({
    super.key,
    required this.theme,
    this.position = NotificationPosition.topRight,
  });

  final AppThemeData theme;
  final NotificationPosition position;

  @override
  Widget build(BuildContext context) {
    // Simplified overlay - just returns empty positioned widget if no notifications
    return StreamBuilder<List<AppNotification>>(
      stream: NotificationManager.instance.notifications,
      initialData: const [],
      builder: (context, snapshot) {
        final notifications = snapshot.data ?? [];
        
        if (notifications.isEmpty) {
          return const SizedBox.shrink();
        }
        
        return Positioned(
          top: _isTop ? 16 : null,
          bottom: _isTop ? null : 16,
          left: _isLeft ? 16 : null,
          right: _isRight ? 16 : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: _getCrossAxisAlignment(),
            children: notifications.take(5).map((n) {
              return Padding(
                // Stable key so Flutter preserves the NotificationToast state
                // (including its entry animation) when the list shifts after
                // another toast is dismissed.
                key: ValueKey(n.id),
                padding: const EdgeInsets.only(bottom: 8),
                child: NotificationToast(
                  notification: n,
                  theme: theme,
                  onDismiss: () => NotificationManager.instance.dismiss(n.id),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  bool get _isTop => position == NotificationPosition.topLeft ||
      position == NotificationPosition.topCenter ||
      position == NotificationPosition.topRight;

  bool get _isLeft => position == NotificationPosition.topLeft ||
      position == NotificationPosition.bottomLeft;

  bool get _isRight => position == NotificationPosition.topRight ||
      position == NotificationPosition.bottomRight;

  CrossAxisAlignment _getCrossAxisAlignment() {
    if (_isLeft) return CrossAxisAlignment.start;
    if (_isRight) return CrossAxisAlignment.end;
    return CrossAxisAlignment.center;
  }
}

/// Individual notification toast widget.
///
/// Implemented as a [StatefulWidget] so that Flutter preserves this widget's
/// subtree state (including the [flutter_animate] [Animate] state that drives
/// the entry animation) when the notification list shifts after a toast above
/// this one is dismissed.  Without this, every rebuild would replay the slide-
/// in animation on the topmost remaining notification.
class NotificationToast extends StatefulWidget {
  const NotificationToast({
    super.key,
    required this.notification,
    required this.theme,
    required this.onDismiss,
  });

  final AppNotification notification;
  final AppThemeData theme;
  final VoidCallback onDismiss;

  @override
  State<NotificationToast> createState() => _NotificationToastState();
}

class _NotificationToastState extends State<NotificationToast> {
  @override
  Widget build(BuildContext context) {
    final notification = widget.notification;
    final theme = widget.theme;
    return AnimatedOpacity(
      duration: NotificationManager.dismissAnimationDuration,
      opacity: notification.isDismissing ? 0 : 1,
      curve: Curves.easeIn,
      child: AnimatedSlide(
        duration: NotificationManager.dismissAnimationDuration,
        offset: notification.isDismissing ? const Offset(0.2, 0) : Offset.zero,
        curve: Curves.easeIn,
        child: GestureDetector(
          onTap: () {
            notification.onTap?.call();
            widget.onDismiss();
          },
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360, minWidth: 280),
            decoration: BoxDecoration(
              color: theme.surfaceElevated,
              borderRadius: BorderRadius.circular(theme.cornerRadius),
              border: Border.all(color: _getTypeColor().withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _buildIcon(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (notification.title != null)
                              Text(
                                notification.title!,
                                style: TextStyle(
                                  color: theme.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            Text(
                              notification.message,
                              style: TextStyle(
                                color: notification.title != null 
                                    ? theme.textSecondary 
                                    : theme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, size: 18, color: theme.textHint),
                        onPressed: widget.onDismiss,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                      ),
                    ],
                  ),
                ),
                if (notification.actionLabel != null &&
                    notification.onAction != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: notification.onAction,
                        child: Text(notification.actionLabel!),
                      ),
                    ),
                  ),
                if (notification.progress != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                notification.title ?? 'Processing',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_progressPercent(notification.progress)}%',
                              style: TextStyle(
                                color: theme.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: notification.progress,
                            minHeight: 6,
                            backgroundColor: theme.surfaceElevated.withValues(alpha: 0.6),
                            valueColor: AlwaysStoppedAnimation(_getTypeColor()),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ).animate()
          .fadeIn(duration: const Duration(milliseconds: 200))
          .slideX(
            begin: 0.3,
            end: 0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          ),
      ),
    );
  }

  Widget _buildIcon() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _getTypeColor().withValues(alpha: 0.2),
        border: Border.all(color: _getTypeColor().withValues(alpha: 0.35)),
        shape: BoxShape.circle,
      ),
      child: Icon(
        _getTypeIcon(),
        color: _getTypeColor(),
        size: 20,
      ),
    );
  }

  int _progressPercent(double? value) {
    if (value == null) return 0;
    final clamped = value.clamp(0.0, 1.0);
    return (clamped * 100).round();
  }

  IconData _getTypeIcon() {
    switch (widget.notification.type) {
      case NotificationType.success:
        return Icons.check_circle_outline;
      case NotificationType.error:
        return Icons.error_outline;
      case NotificationType.warning:
        return Icons.warning_amber_outlined;
      case NotificationType.info:
        return Icons.info_outline;
      case NotificationType.update:
        return Icons.update;
      case NotificationType.download:
        return Icons.download;
      case NotificationType.steam:
        return Icons.cloud_download;
    }
  }

  Color _getTypeColor() {
    switch (widget.notification.type) {
      case NotificationType.success:
        return widget.theme.success;
      case NotificationType.error:
        return widget.theme.error;
      case NotificationType.warning:
        return widget.theme.warning;
      case NotificationType.info:
        return widget.theme.accent;
      case NotificationType.update:
        return widget.theme.accent;
      case NotificationType.download:
        return widget.theme.accent;
      case NotificationType.steam:
        return widget.theme.accent;
    }
  }
}
