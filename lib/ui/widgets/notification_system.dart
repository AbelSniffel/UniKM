/// Toast notification system
/// Matches the original Python notification system with 7 types and 6 positions
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import 'tinted_card.dart';

/// Notification types
enum NotificationType { success, error, warning, info, update, download, steam }

/// How a notification's main action is drawn. [text] sits beside the
/// progress or under the message; the others fill the toast's width.
enum NotificationActionStyle { text, outlined, elevated }

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
    this.progressLabel,
    this.onTap,
    this.actionLabel,
    this.onAction,
    this.actionStyle = NotificationActionStyle.text,
    this.actionIcon,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.isDismissing = false,
    this.dismissible = true,
    this.autoDismiss,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final String message;
  final NotificationType type;
  final String? title;
  final double? progress;

  /// The large figure beside [progress], such as a count while fetching;
  /// without it the toast shows the percentage. Cleared with the progress.
  final String? progressLabel;
  final VoidCallback? onTap;
  final String? actionLabel;
  final VoidCallback? onAction;
  final NotificationActionStyle actionStyle;

  /// Draws a text action as this icon, with [actionLabel] as its
  /// accessibility label.
  final IconData? actionIcon;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final bool isDismissing;

  /// When false the user cannot close the notification; it stays until the
  /// task that owns it completes or dismisses it.
  final bool dismissible;

  /// When the scheduled auto-dismiss started and how long it lasts, for the
  /// toast's countdown line; null while the notification stays.
  final ({DateTime start, Duration length})? autoDismiss;

  AppNotification copyWith({
    String? message,
    NotificationType? type,
    String? title,
    double? progress,
    String? progressLabel,
    VoidCallback? onTap,
    String? actionLabel,
    VoidCallback? onAction,
    NotificationActionStyle? actionStyle,
    String? secondaryActionLabel,
    VoidCallback? onSecondaryAction,
    bool clearProgress = false,
    bool clearOnTap = false,
    bool clearAction = false,
    bool clearSecondaryAction = false,
    bool? isDismissing,
    bool? dismissible,
    ({DateTime start, Duration length})? autoDismiss,
    bool clearAutoDismiss = false,
  }) => AppNotification(
    id: id,
    message: message ?? this.message,
    type: type ?? this.type,
    title: title ?? this.title,
    progress: clearProgress ? null : (progress ?? this.progress),
    progressLabel: clearProgress ? null : (progressLabel ?? this.progressLabel),
    onTap: clearOnTap ? null : (onTap ?? this.onTap),
    actionLabel: clearAction ? null : (actionLabel ?? this.actionLabel),
    onAction: clearAction ? null : (onAction ?? this.onAction),
    actionStyle: clearAction
        ? NotificationActionStyle.text
        : (actionStyle ?? this.actionStyle),
    actionIcon: clearAction ? null : actionIcon,
    secondaryActionLabel: clearSecondaryAction
        ? null
        : (secondaryActionLabel ?? this.secondaryActionLabel),
    onSecondaryAction: clearSecondaryAction
        ? null
        : (onSecondaryAction ?? this.onSecondaryAction),
    isDismissing: isDismissing ?? this.isDismissing,
    dismissible: dismissible ?? this.dismissible,
    autoDismiss: clearAutoDismiss ? null : (autoDismiss ?? this.autoDismiss),
  );
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
    String? progressLabel,
    String? actionLabel,
    VoidCallback? onAction,
    NotificationActionStyle? actionStyle,
    String? secondaryActionLabel,
    VoidCallback? onSecondaryAction,
    bool clearProgress = false,
    bool clearAction = false,
    bool clearSecondaryAction = false,
    Duration? autoDismissAfter,
    bool? dismissible,
  }) => _manager._update(
    id,
    (notification) => notification.copyWith(
      message: message,
      type: type,
      title: title,
      progress: progress,
      progressLabel: progressLabel,
      actionLabel: actionLabel,
      onAction: onAction,
      actionStyle: actionStyle,
      secondaryActionLabel: secondaryActionLabel,
      onSecondaryAction: onSecondaryAction,
      clearProgress: clearProgress,
      clearAction: clearAction,
      clearSecondaryAction: clearSecondaryAction,
      dismissible: dismissible,
    ),
    autoDismissAfter: autoDismissAfter,
  );

  void setProgress(double progress) => update(progress: progress);

  void completeSuccess(String message, {String? title}) =>
      _complete(message, NotificationType.success, title: title);

  void completeError(String message, {String? title}) =>
      _complete(message, NotificationType.error, title: title);

  void _complete(String message, NotificationType type, {String? title}) {
    update(
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

  /// How far each paused auto-dismiss had run when it was paused.
  final Map<String, Duration> _pausedElapsed = <String, Duration>{};
  final _controller = StreamController<List<AppNotification>>.broadcast();

  bool _enabled = true;
  bool get enabled => _enabled;

  void setEnabled(bool enabled) {
    _enabled = enabled;
    if (!enabled) dismissAll();
  }

  Stream<List<AppNotification>> get notifications => _controller.stream;
  List<AppNotification> get currentNotifications => _notifications.toList();

  NotificationPosition _position = NotificationPosition.topRight;
  NotificationPosition get position => _position;

  void setPosition(NotificationPosition position) => _position = position;

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
    String? progressLabel,
    VoidCallback? onTap,
    String? actionLabel,
    VoidCallback? onAction,
    NotificationActionStyle? actionStyle,
    IconData? actionIcon,
    String? secondaryActionLabel,
    VoidCallback? onSecondaryAction,
    bool persistent = false,
    bool dedupe = true,
    bool dismissible = true,
    Duration? autoDismissAfter,
  }) {
    if (!_enabled) return NotificationHandle(this, 'disabled');

    final existing = dedupe
        ? _notifications
              .where((n) => n.message == message && n.type == type)
              .firstOrNull
        : null;
    if (existing != null) return NotificationHandle(this, existing.id);

    final dismissAfter = autoDismissAfter ?? defaultDuration(type);
    final autoDismisses =
        !persistent && progress == null && dismissAfter != Duration.zero;
    final notification = AppNotification(
      message: message,
      type: type,
      title: title,
      progress: progress,
      progressLabel: progressLabel,
      onTap: onTap,
      actionLabel: actionLabel,
      onAction: onAction,
      actionStyle: actionStyle ?? NotificationActionStyle.text,
      actionIcon: actionIcon,
      secondaryActionLabel: secondaryActionLabel,
      onSecondaryAction: onSecondaryAction,
      dismissible: dismissible,
      autoDismiss: autoDismisses
          ? (start: DateTime.now(), length: dismissAfter)
          : null,
    );

    _notifications.add(notification);
    _controller.add(_notifications.toList());

    if (autoDismisses) {
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
    String? progressLabel,
    String? actionLabel,
    VoidCallback? onAction,
    bool dismissible = true,
  }) => showHandle(
    message: message,
    type: type,
    title: title,
    progress: progress,
    progressLabel: progressLabel,
    actionLabel: actionLabel,
    onAction: onAction,
    persistent: true,
    dedupe: false,
    dismissible: dismissible,
  );

  /// Applies [change] to a shown notification. A new [autoDismissAfter]
  /// restarts its countdown once it no longer shows progress.
  void _update(
    String id,
    AppNotification Function(AppNotification) change, {
    Duration? autoDismissAfter,
  }) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index == -1) return;

    final changed = change(_notifications[index]);
    final reschedules =
        autoDismissAfter != null &&
        autoDismissAfter != Duration.zero &&
        changed.progress == null;
    _notifications[index] = autoDismissAfter == null
        ? changed
        : changed.copyWith(
            autoDismiss: reschedules
                ? (start: DateTime.now(), length: autoDismissAfter)
                : null,
            clearAutoDismiss: !reschedules,
          );
    _controller.add(_notifications.toList());

    // Reschedule auto-dismiss if requested and it's no longer a task.
    if (autoDismissAfter != null) {
      _dismissTimers[id]?.cancel();
      if (reschedules && _pausedElapsed.containsKey(id)) {
        // Still hovered: the new countdown starts when the pointer leaves.
        _pausedElapsed[id] = Duration.zero;
      } else if (reschedules) {
        _dismissTimers[id] = Timer(autoDismissAfter, () => dismiss(id));
      }
    }
  }

  /// Holds a notification's auto-dismiss, for example while it is hovered.
  void pauseAutoDismiss(String id) {
    final notification = _notifications.where((n) => n.id == id).firstOrNull;
    final schedule = notification?.autoDismiss;
    if (schedule == null ||
        notification!.isDismissing ||
        _pausedElapsed.containsKey(id)) {
      return;
    }
    _dismissTimers.remove(id)?.cancel();
    _pausedElapsed[id] = DateTime.now().difference(schedule.start);
  }

  /// Carries on a paused auto-dismiss for the time it had left.
  void resumeAutoDismiss(String id) {
    final elapsed = _pausedElapsed.remove(id);
    final index = _notifications.indexWhere((n) => n.id == id);
    if (elapsed == null || index == -1) return;
    final schedule = _notifications[index].autoDismiss;
    if (schedule == null) return;
    // Moving the start keeps the countdown line where it stopped.
    _notifications[index] = _notifications[index].copyWith(
      autoDismiss: (
        start: DateTime.now().subtract(elapsed),
        length: schedule.length,
      ),
    );
    _controller.add(_notifications.toList());
    final remaining = schedule.length - elapsed;
    _dismissTimers[id] = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () => dismiss(id),
    );
  }

  void dismiss(String id) {
    _dismissTimers.remove(id)?.cancel();
    _pausedElapsed.remove(id);
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
    for (final timer in [..._dismissTimers.values, ..._removeTimers.values]) {
      timer.cancel();
    }
    _dismissTimers.clear();
    _removeTimers.clear();
    _pausedElapsed.clear();
    _notifications.clear();
    _controller.add(_notifications.toList());
  }

  void success(String message, {String? title}) => showHandle(
    message: message,
    type: NotificationType.success,
    title: title,
  );

  void error(
    String message, {
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
    IconData? actionIcon,
  }) => showHandle(
    message: message,
    type: NotificationType.error,
    title: title,
    actionLabel: actionLabel,
    onAction: onAction,
    actionIcon: actionIcon,
  );

  void warning(String message, {String? title, Duration? autoDismissAfter}) =>
      showHandle(
        message: message,
        type: NotificationType.warning,
        title: title,
        autoDismissAfter: autoDismissAfter,
      );

  void info(String message, {String? title}) =>
      showHandle(message: message, title: title);

  void dispose() {
    dismissAll();
    _controller.close();
  }
}

/// Shows notifications above [child], the app's navigator, so they stay
/// readable and usable over a dialog and its backdrop.
class NotificationHost extends StatelessWidget {
  const NotificationHost({super.key, required this.theme, required this.child});

  final AppThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) => _NotificationHostStack(
    children: [
      child,
      NotificationOverlay(
        theme: theme,
        position: NotificationManager.instance.position,
      ),
    ],
  );
}

/// The widget inspector picks the smallest widget under the pointer from
/// every layer, so a toast always lost to the page beneath it. In debug
/// builds, while the inspector selects, the page is hidden from its search
/// where the pointer is over the notifications.
class _NotificationHostStack extends Stack {
  const _NotificationHostStack({required super.children})
    : super(fit: StackFit.expand);

  @override
  RenderStack createRenderObject(BuildContext context) =>
      _RenderNotificationHostStack(textDirection: Directionality.of(context));
}

class _RenderNotificationHostStack extends RenderStack {
  _RenderNotificationHostStack({super.textDirection})
    : super(fit: StackFit.expand);

  /// The last pointer position, which the inspector selects at.
  Offset? _pointer;

  void _trackPointer(PointerEvent event) => _pointer = event.position;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    if (kDebugMode) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_trackPointer);
    }
  }

  @override
  void detach() {
    if (kDebugMode) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_trackPointer);
    }
    super.detach();
  }

  bool get _pointerOverNotifications {
    final pointer = _pointer;
    final notifications = lastChild;
    if (pointer == null || notifications == null || childCount < 2) {
      return false;
    }
    final data = notifications.parentData! as StackParentData;
    // Without notifications the overlay is an unpositioned empty box.
    return data.isPositioned &&
        (data.offset & notifications.size).contains(globalToLocal(pointer));
  }

  @override
  List<DiagnosticsNode> debugDescribeChildren() {
    final children = super.debugDescribeChildren();
    if (!WidgetsBinding.instance.debugShowWidgetInspectorOverride ||
        !_pointerOverNotifications) {
      return children;
    }
    return [
      firstChild!.toDiagnosticsNode(
        name: 'page under the notifications',
        style: DiagnosticsTreeStyle.offstage,
      ),
      ...children.skip(1),
    ];
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

  /// How many notifications show at once; newer ones wait their turn.
  static const maxVisible = 8;

  // Without notifications this is an empty box rather than a Positioned.
  @override
  Widget build(BuildContext context) => StreamBuilder<List<AppNotification>>(
    stream: NotificationManager.instance.notifications,
    initialData: const [],
    builder: (context, snapshot) {
      final notifications = snapshot.data ?? [];
      if (notifications.isEmpty) return const SizedBox.shrink();

      final isTop = position.name.startsWith('top');
      final isLeft = position.name.endsWith('Left');
      final isRight = position.name.endsWith('Right');
      return Positioned(
        top: isTop ? 16 : null,
        bottom: isTop ? null : 16,
        left: isLeft ? 16 : null,
        right: isRight ? 16 : null,
        // A full stack on a short window scrolls instead of overflowing.
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.max(0, MediaQuery.sizeOf(context).height - 32),
          ),
          child: SingleChildScrollView(
            reverse: !isTop,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: isLeft
                  ? CrossAxisAlignment.start
                  : isRight
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.center,
              children: [
                for (final n in notifications.take(maxVisible))
                  NotificationToast(
                    key: ValueKey(n.id),
                    notification: n,
                    theme: theme,
                    onDismiss: () => NotificationManager.instance.dismiss(n.id),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
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

class _NotificationToastState extends State<NotificationToast>
    with SingleTickerProviderStateMixin {
  Offset _drag = Offset.zero;

  /// The axis a swipe locks onto with its first movement.
  Axis? _axis;

  /// The way a swipe threw the toast, for its exit; a tap exits rightwards.
  Offset _exitDirection = const Offset(1, 0);

  /// Runs the countdown line while an auto-dismiss is scheduled.
  late final _countdown = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void didUpdateWidget(NotificationToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notification.autoDismiss != widget.notification.autoDismiss) {
      _startCountdown();
    }
  }

  @override
  void dispose() {
    _countdown.dispose();
    super.dispose();
  }

  void _startCountdown() {
    final schedule = widget.notification.autoDismiss;
    if (schedule == null) {
      _countdown.stop();
      return;
    }
    final elapsed = DateTime.now().difference(schedule.start);
    _countdown
      ..duration = schedule.length
      ..value = elapsed.inMicroseconds / schedule.length.inMicroseconds
      ..forward();
  }

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
    final dismissOffset = _exitDirection * (_isMobileTarget ? 0.05 : 0.2);
    final child = Align(
      alignment: Alignment.topCenter,
      heightFactor: notification.isDismissing && useSizeCollapse ? 0 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Transform.translate(
          offset: _drag,
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
                  // Swiping in any direction, along whichever axis it
                  // starts on, dismisses; a short one springs back.
                  // From the touch, so the first update carries the
                  // movement that started the swipe.
                  dragStartBehavior: DragStartBehavior.down,
                  onPanStart: (_) => _axis = null,
                  onPanUpdate: (details) {
                    if (!notification.dismissible ||
                        notification.isDismissing) {
                      return;
                    }
                    final delta = details.delta;
                    _axis ??= delta.dx.abs() >= delta.dy.abs()
                        ? Axis.horizontal
                        : Axis.vertical;
                    setState(
                      () => _drag += _axis == Axis.horizontal
                          ? Offset(delta.dx, 0)
                          : Offset(0, delta.dy),
                    );
                  },
                  onPanEnd: (details) {
                    if (notification.dismissible && _drag.distance >= 40.0) {
                      // Locked to one axis, so this points along it.
                      setState(
                        () => _exitDirection = Offset(
                          _drag.dx.sign,
                          _drag.dy.sign,
                        ),
                      );
                      widget.onDismiss();
                    } else {
                      setState(() => _drag = Offset.zero);
                    }
                  },
                  // Hovering holds the countdown and the auto-dismiss.
                  child: MouseRegion(
                    onEnter: (_) {
                      _countdown.stop();
                      NotificationManager.instance.pauseAutoDismiss(
                        notification.id,
                      );
                    },
                    onExit: (_) {
                      if (notification.autoDismiss != null) {
                        _countdown.forward();
                      }
                      NotificationManager.instance.resumeAutoDismiss(
                        notification.id,
                      );
                    },
                    child: _buildSurface(maxWidth),
                  ),
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

  /// The update dialog's status card, floating: the type's icon (a spinner
  /// while it shows progress) beside the title, or the type, over the
  /// message, with the progress figure at the end. Progress and actions run
  /// across the card under them, and a countdown line runs along the bottom
  /// while it is set to close by itself.
  Widget _buildSurface(double maxWidth) {
    final theme = widget.theme;
    final notification = widget.notification;
    final color = _getTypeColor();
    final progress = notification.progress?.clamp(0.0, 1.0);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth,
        minWidth: maxWidth >= 280 ? 280 : 0,
      ),
      child: TintedCard(
        theme: theme,
        size: TintedCardSize.large,
        liveRegion: true,
        color: color,
        icon: _getTypeIcon(),
        // Spins while the task runs; the bar and figure show how far it is.
        busy: progress != null,
        title: notification.title ?? _typeLabel,
        subtitle: notification.message,
        figure: progress == null
            ? null
            : notification.progressLabel ?? '${(progress * 100).round()}%',
        backdrop: theme.surface,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.isDark ? 0.35 : 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
        bottomEdge: notification.autoDismiss == null
            ? null
            : RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _countdown,
                  builder: (context, _) => Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FractionallySizedBox(
                      widthFactor: 1 - _countdown.value,
                      child: ColoredBox(
                        color: color,
                        child: const SizedBox(height: 3),
                      ),
                    ),
                  ),
                ),
              ),
        children: _buildActions(progress),
      ),
    );
  }

  String get _typeLabel => switch (widget.notification.type) {
    NotificationType.success => 'Done',
    NotificationType.error => 'Error',
    NotificationType.warning => 'Warning',
    NotificationType.info => 'Info',
    NotificationType.update => 'Update',
    NotificationType.download => 'Download',
    NotificationType.steam => 'Steam',
  };

  /// Across the card: any progress filling a row with the actions at its
  /// end; otherwise text actions at the end and an outlined or elevated main
  /// action at full width.
  List<Widget> _buildActions(double? progress) {
    final notification = widget.notification;
    final text = notification.actionStyle == NotificationActionStyle.text;
    final label = notification.actionLabel;
    final onPressed = notification.onAction;
    final button = text || label == null || onPressed == null
        ? null
        : switch (notification.actionStyle) {
            NotificationActionStyle.outlined => OutlinedButton(
              onPressed: onPressed,
              child: Text(label),
            ),
            _ => ElevatedButton(onPressed: onPressed, child: Text(label)),
          };
    final textActions = [
      for (final (label, onPressed, icon) in [
        if (text) (label, onPressed, notification.actionIcon),
        if (progress == null)
          (
            notification.secondaryActionLabel,
            notification.onSecondaryAction,
            null,
          ),
      ])
        if (label != null && onPressed != null)
          if (icon != null)
            // No tooltip: toasts sit above the navigator, outside any
            // Overlay, where a tooltip throws.
            IconButton(
              onPressed: onPressed,
              icon: Icon(icon, semanticLabel: label),
            )
          else
            OutlinedButton(onPressed: onPressed, child: Text(label)),
    ];
    if (progress != null) {
      return [
        Row(
          spacing: kElementHSpacing,
          children: [
            Expanded(
              child: AppLinearProgressBar(theme: widget.theme, value: progress),
            ),
            ...textActions,
            ?button,
          ],
        ),
      ];
    }
    return [
      if (textActions.isNotEmpty)
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Wrap(spacing: 6, children: textActions),
        ),
      ?button,
    ];
  }

  IconData _getTypeIcon() => switch (widget.notification.type) {
    NotificationType.success => Icons.check_circle_outline,
    NotificationType.error => Icons.error_outline,
    NotificationType.warning => Icons.warning_amber_outlined,
    NotificationType.info => Icons.info_outline,
    NotificationType.update => Icons.update,
    NotificationType.download => Icons.download,
    NotificationType.steam => Icons.cloud_download_outlined,
  };

  Color _getTypeColor() => switch (widget.notification.type) {
    NotificationType.success => widget.theme.success,
    NotificationType.error => widget.theme.error,
    NotificationType.warning => widget.theme.warning,
    _ => widget.theme.accent,
  };
}
