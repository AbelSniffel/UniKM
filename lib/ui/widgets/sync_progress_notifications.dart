library;

import '../../core/models/device_sync_models.dart';
import 'notification_system.dart';

/// Shows one progress notification per device sync transfer. The user cannot
/// dismiss it while the transfer runs; once it finishes the notification shows
/// the outcome and starts its normal auto-dismiss timer.
class SyncProgressNotifications {
  final Map<String, NotificationHandle> _handles = {};

  void handle(SyncEvent event) {
    if (event is! SyncProgressEvent) return;
    final id = event.transferId;
    if (event.finished || event.failed) {
      final handle = _handles.remove(id);
      if (handle == null) return;
      if (event.failed) {
        handle.completeError(event.message, title: event.title);
      } else {
        handle.completeSuccess(event.message, title: event.title);
      }
      return;
    }
    final handle = _handles[id];
    if (handle == null) {
      _handles[id] = NotificationManager.instance.beginTask(
        event.message,
        type: NotificationType.download,
        title: event.title,
        progress: event.progress,
        dismissible: false,
      );
    } else {
      handle.update(
        message: event.message,
        title: event.title,
        progress: event.progress,
      );
    }
  }

  /// Ends every open notification, e.g. when the app shell goes away.
  void dispose() {
    for (final handle in _handles.values) {
      handle.dismiss();
    }
    _handles.clear();
  }
}
