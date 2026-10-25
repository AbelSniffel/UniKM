/// Toast notification system
/// Matches the original Python notification system with 7 types and 6 positions
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';

/// Notification types
enum NotificationType { success, error, warning, info, update, download, steam }

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
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.isDismissing = false,
    this.dismissible = true,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final String message;
  final NotificationType type;
  final String? title;
  final double? progress;
  final VoidCallback? onTap;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final bool isDismissing;

  /// When false the user cannot close the notification; it stays until the
  /// task that owns it completes or dismisses it.
  final bool dismissible;

  AppNotification copyWith({
    String? message,
    NotificationType? type,
    String? title,
    double? progress,
    VoidCallback? onTap,
    String? actionLabel,
    VoidCallback? onAction,
    String? secondaryActionLabel,
    VoidCallback? onSecondaryAction,
    bool clearProgress = false,
    bool clearOnTap = false,
    bool clearAction = false,
    bool clearSecondaryAction = false,
    bool? isDismissing,
    bool? dismissible,
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
      secondaryActionLabel: clearSecondaryAction
          ? null
          : (secondaryActionLabel ?? this.secondaryActionLabel),
      onSecondaryAction: clearSecondaryAction
          ? null
          : (onSecondaryAction ?? this.onSecondaryAction),
      isDismissing: isDismissing ?? this.isDismissing,
      dismissible: dismissible ?? this.dismissible,
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
    String? secondaryActionLabel,
    VoidCallback? onSecondaryAction,
    bool clearProgress = false,
    bool clearAction = false,
    bool clearSecondaryAction = false,
    Duration? autoDismissAfter,
    bool? dismissible,
  }) {
    _manager.update(
      id,
      message: message,
      type: type,
      title: title,
      progress: progress,
      actionLabel: actionLabel,
      onAction: onAction,
      secondaryActionLabel: secondaryActionLabel,
      onSecondaryAction: onSecondaryAction,
      clearProgress: clearProgress,
      clearAction: clearAction,
      clearSecondaryAction: clearSecondaryAction,
      autoDismissAfter: autoDismissAfter,
      dismissible: dismissible,
    );
  }

  void setProgress(double progress) => update(progress: progress);

  void completeSuccess(String message, {String? title}) =>
      _complete(message, NotificationType.success, title: title);

  void completeError(String message, {String? title}) =>
      _complete(message, NotificationType.error, title: title);

  void _complete(String message, NotificationType type, {String? title}) {
    _manager.update(
      id,
      message: message,
      type: type,
      title: title,
      clearProgress: true,
      clearAction: true,
      clearSecondaryAction: true,
      autoDismissAfter: NotificationManager.defaultDuration(type),
      dismissible: true,
    );
  }

  void dismiss() => _manager.dismiss(id);
}

/// Notification manager singleton
class NotificationManager {
  NotificationManager._();

  static final NotificationManager instance = NotificationManager._();

  static const Duration dismissAnimationDuration = Duration(milliseconds: 200);

  final _notifications = <AppNotification>[];
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

  /// Auto-hide delay; zero keeps update and progress/task notifications.
  static Duration defaultDuration(NotificationType type) => switch (type) {
    NotificationType.success ||
    NotificationType.info => const Duration(milliseconds: 5000),
    NotificationType.error => const Duration(milliseconds: 7000),
    NotificationType.warning => const Duration(milliseconds: 6000),
    NotificationType.update ||
    NotificationType.download ||
    NotificationType.steam => Duration.zero,
  };

  NotificationHandle showHandle({
    required String message,
    NotificationType type = NotificationType.info,
    String? title,
    double? progress,
    VoidCallback? onTap,
    String? actionLabel,
    VoidCallback? onAction,
    String? secondaryActionLabel,
    VoidCallback? onSecondaryAction,
    bool persistent = false,
    bool dedupe = true,
    bool dismissible = true,
    Duration? autoDismissAfter,
  }) {
    if (!_enabled) {
      return NotificationHandle(this, 'disabled');
    }

    final existing = dedupe
        ? _notifications
              .where((n) => n.message == message && n.type == type)
              .firstOrNull
        : null;
    if (existing != null) return NotificationHandle(this, existing.id);

    final notification = AppNotification(
      message: message,
      type: type,
      title: title,
      progress: progress,
      onTap: onTap,
      actionLabel: actionLabel,
      onAction: onAction,
      secondaryActionLabel: secondaryActionLabel,
      onSecondaryAction: onSecondaryAction,
      isDismissing: false,
      dismissible: dismissible,
    );

    _notifications.add(notification);
    _controller.add(_notifications.toList());

    final shouldAutoDismiss = !persistent && progress == null;
    final dismissAfter = autoDismissAfter ?? defaultDuration(type);
    if (shouldAutoDismiss && dismissAfter != Duration.zero) {
      _dismissTimers[notification.id]?.cancel();
      _dismissTimers[notification.id] = Timer(
        dismissAfter,
        () => dismiss(notification.id),
      );
    }

    return NotificationHandle(this, notification.id);
  }

  /// Start a sticky "task" notification that stays until completed.
  NotificationHandle beginTask(
    String message, {
    NotificationType type = NotificationType.info,
    String? title,
    double? progress,
    String? actionLabel,
    VoidCallback? onAction,
    bool dismissible = true,
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
      dismissible: dismissible,
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
    String? secondaryActionLabel,
    VoidCallback? onSecondaryAction,
    bool clearProgress = false,
    bool clearAction = false,
    bool clearSecondaryAction = false,
    Duration? autoDismissAfter,
    bool? dismissible,
  }) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index == -1) return;

    final updated = _notifications[index].copyWith(
      message: message,
      type: type,
      title: title,
      progress: progress,
      actionLabel: actionLabel,
      onAction: onAction,
      secondaryActionLabel: secondaryActionLabel,
      onSecondaryAction: onSecondaryAction,
      clearProgress: clearProgress,
      clearAction: clearAction,
      clearSecondaryAction: clearSecondaryAction,
      dismissible: dismissible,
    );
    _notifications[index] = updated;
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

    final index = _notifications.indexWhere((n) => n.id == id);
    if (index == -1 || _notifications[index].isDismissing) return;

    _notifications[index] = _notifications[index].copyWith(isDismissing: true);
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

  void success(String message, {String? title}) => showHandle(
    message: message,
    type: NotificationType.success,
    title: title,
  );

  void error(String message, {String? title}) =>
      showHandle(message: message, type: NotificationType.error, title: title);

  void warning(String message, {String? title, Duration? autoDismissAfter}) {
    showHandle(
      message: message,
      type: NotificationType.warning,
      title: title,
      autoDismissAfter: autoDismissAfter,
    );
  }

  void info(String message, {String? title}) =>
      showHandle(message: message, type: NotificationType.info, title: title);

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
              return NotificationToast(
                key: ValueKey(n.id),
                notification: n,
                theme: theme,
                onDismiss: () => NotificationManager.instance.dismiss(n.id),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  bool get _isTop => position.name.startsWith('top');
  bool get _isLeft => position.name.endsWith('Left');
  bool get _isRight => position.name.endsWith('Right');

  CrossAxisAlignment _getCrossAxisAlignment() {
    if (_isLeft) return CrossAxisAlignment.start;
    if (_isRight) return CrossAxisAlignment.end;
    return CrossAxisAlignment.center;
  }
}

/// Individual notification toast. Its keyed state retains the entry animation
/// and drag position when other notifications are dismissed or updated.
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
  double _dragOffset = 0.0;

  bool get _isMobileTarget {
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  }

  @override
  Widget build(BuildContext context) {
    final notification = widget.notification;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = math.min(380.0, math.max(0.0, viewportWidth - 32));
    final useSizeCollapse = !_isMobileTarget;
    final dismissOffset = _isMobileTarget
        ? const Offset(0.05, 0)
        : const Offset(0.2, 0);
    final child = Align(
      alignment: Alignment.topCenter,
      heightFactor: notification.isDismissing && useSizeCollapse ? 0 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Transform.translate(
          offset: Offset(_dragOffset, 0),
          child: AnimatedOpacity(
            duration: NotificationManager.dismissAnimationDuration,
            opacity: notification.isDismissing ? 0 : 1,
            curve: Curves.easeIn,
            child: AnimatedSlide(
              duration: NotificationManager.dismissAnimationDuration,
              offset: notification.isDismissing ? dismissOffset : Offset.zero,
              curve: Curves.easeIn,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 200),
                builder: (context, value, child) => FractionalTranslation(
                  translation: Offset(
                    0.3 * (1 - Curves.easeOut.transform(value)),
                    0,
                  ),
                  child: Opacity(opacity: value, child: child),
                ),
                child: GestureDetector(
                  onTap: () {
                    notification.onTap?.call();
                    if (notification.dismissible) widget.onDismiss();
                  },
                  onHorizontalDragUpdate: (details) {
                    if (notification.dismissible &&
                        !notification.isDismissing) {
                      setState(() {
                        _dragOffset = (_dragOffset + details.delta.dx).clamp(
                          0.0,
                          double.infinity,
                        );
                      });
                    }
                  },
                  onHorizontalDragEnd: (details) {
                    if (notification.dismissible && _dragOffset >= 40.0) {
                      widget.onDismiss();
                    } else {
                      setState(() => _dragOffset = 0.0);
                    }
                  },
                  child: _buildSurface(maxWidth),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Mobile sizes change immediately. A zero-duration AnimatedSize can notify
    // its render object during layout when a progress/action row is added.
    return useSizeCollapse
        ? AnimatedSize(
            duration: NotificationManager.dismissAnimationDuration,
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: child,
          )
        : child;
  }

  Widget _buildSurface(double maxWidth) {
    final theme = widget.theme;
    final notification = widget.notification;
    final radius = BorderRadius.circular(theme.cornerRadius);
    return Container(
      constraints: BoxConstraints(
        maxWidth: maxWidth,
        minWidth: maxWidth >= 280 ? 280 : 0,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          _getTypeColor().withValues(alpha: 0.10),
          theme.background,
        ).withValues(alpha: 0.95),
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: theme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 56,
            child: ColoredBox(
              color: _getTypeColor().withValues(alpha: 0.55),
              child: Center(
                child: Icon(_getTypeIcon(), color: Colors.white, size: 28),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 56),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
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
                      if (notification.dismissible)
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            size: 18,
                            color: theme.textHint,
                          ),
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
                _buildFooter(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final notification = widget.notification;
    final actions = [
      for (final (label, onPressed) in [
        (notification.actionLabel, notification.onAction),
        if (notification.progress == null)
          (notification.secondaryActionLabel, notification.onSecondaryAction),
      ])
        if (label != null && onPressed != null)
          TextButton(onPressed: onPressed, child: Text(label)),
    ];
    final progress = notification.progress;
    if (progress == null && actions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: progress == null
          ? Align(
              alignment: Alignment.centerRight,
              child: Wrap(spacing: 6, children: actions),
            )
          : Row(
              children: [
                Expanded(
                  child: AppLinearProgressBar(
                    theme: widget.theme,
                    value: progress,
                    label: '${(progress.clamp(0.0, 1.0) * 100).round()}%',
                  ),
                ),
                if (actions.isNotEmpty) const SizedBox(width: kElementHSpacing),
                ...actions,
              ],
            ),
    );
  }

  IconData _getTypeIcon() => switch (widget.notification.type) {
    NotificationType.success => Icons.check_circle_outline,
    NotificationType.error => Icons.error,
    NotificationType.warning => Icons.warning_amber_outlined,
    NotificationType.info => Icons.info_outline,
    NotificationType.update => Icons.update,
    NotificationType.download => Icons.download,
    NotificationType.steam => Icons.cloud_download,
  };

  Color _getTypeColor() => switch (widget.notification.type) {
    NotificationType.success => widget.theme.success,
    NotificationType.error => widget.theme.error,
    NotificationType.warning => widget.theme.warning,
    _ => widget.theme.accent,
  };
}
