/// Service that fires deadline reminders as in-app toasts and OS notifications.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/game.dart';
import '../../providers/games_providers.dart';
import '../../providers/settings_providers.dart';
import '../../ui/widgets/notification_system.dart';

// =============================================================================
// DEADLINE NOTIFICATION SERVICE
// =============================================================================

// Fixed OS notification IDs so grouped notifications replace the previous one.
const int _osIdExpired = 1001;
const int _osIdSoon = 1002;
const int _osIdTest = 9998;

/// Singleton service that checks game deadlines and fires reminders.
///
/// Fires:
/// - In-app toasts via [NotificationManager] (all platforms).
/// - OS-level desktop notifications (Linux/macOS via flutter_local_notifications,
///   Windows via native WinRT PowerShell toast).
///
/// Games are grouped — one notification for all expired games and one for all
/// soon-expiring games, rather than one notification per game.
///
/// The timer runs once every 24 hours so users receive at most one notification
/// batch per day. An immediate check is also performed at app startup.
class DeadlineNotificationService {
  DeadlineNotificationService._();

  static final DeadlineNotificationService instance =
      DeadlineNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Games that have already received an OS notification today.
  final Set<int> _notifiedGameIds = {};

  /// Periodic (24 h) check timer.
  Timer? _periodicTimer;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Initialise the local notifications plugin.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Windows uses native WinRT toasts via PowerShell — no plugin init needed.
      if (!Platform.isWindows) {
        final settings = InitializationSettings(
          linux: const LinuxInitializationSettings(
            defaultActionName: 'Open UniKM',
          ),
          macOS: const DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        );
        await _plugin.initialize(settings);
      }
      _initialized = true;
    } catch (_) {
      _initialized = true;
    }
  }

  // ---------------------------------------------------------------------------
  // Deadline check
  // ---------------------------------------------------------------------------

  /// Checks [games] for deadlines and fires grouped notifications.
  Future<void> checkDeadlines(List<Game> games, {required bool enabled}) async {
    if (!enabled) return;

    final expired =
        games.where((g) => g.hasDeadline && g.isExpired).toList();
    final soon = games
        .where((g) => g.hasDeadline && g.isDeadlineSoon && !g.isExpired)
        .toList();

    // In-app toasts (always shown when games are found).
    if (expired.isNotEmpty) {
      final count = expired.length;
      NotificationManager.instance.warning(
        count == 1
            ? '"${expired[0].title}" key deadline has already passed!'
            : '$count key deadlines have already passed: ${_nameList(expired)}',
        title: count == 1 ? 'Key Expired' : '$count Keys Expired',
      );
    }

    if (soon.isNotEmpty) {
      final count = soon.length;
      NotificationManager.instance.warning(
        count == 1
            ? '"${soon[0].title}" expires in ${_dayLabel(soon[0].daysUntilDeadline ?? 0)}.'
            : '$count keys expiring soon: ${_nameList(soon)}',
        title: count == 1 ? 'Key Expiring Soon' : '$count Keys Expiring Soon',
      );
    }

    // OS notifications (once per game per day, grouped).
    final newExpired =
        expired.where((g) => !_notifiedGameIds.contains(g.id)).toList();
    final newSoon =
        soon.where((g) => !_notifiedGameIds.contains(g.id)).toList();

    if (newExpired.isNotEmpty) {
      for (final g in newExpired) {
        _notifiedGameIds.add(g.id);
      }
      final count = newExpired.length;
      await _showOsNotification(
        id: _osIdExpired,
        title: count == 1 ? 'Key Expired' : '$count Keys Expired',
        body: count == 1
            ? '${newExpired[0].title} — deadline has already passed!'
            : '${_nameList(newExpired)} — deadlines have passed.',
      );
    }

    if (newSoon.isNotEmpty) {
      for (final g in newSoon) {
        _notifiedGameIds.add(g.id);
      }
      final count = newSoon.length;
      await _showOsNotification(
        id: _osIdSoon,
        title: count == 1 ? 'Key Expiring Soon' : '$count Keys Expiring Soon',
        body: count == 1
            ? '${newSoon[0].title} — expires in ${_dayLabel(newSoon[0].daysUntilDeadline ?? 0)}.'
            : '${_nameList(newSoon)} — expiring soon.',
      );
    }
  }

  /// Reads current state from [ref] and runs a deadline check.
  Future<void> runCheck(WidgetRef ref) async {
    try {
      final games = ref.read(allGamesProvider);
      final enabled = ref.read(notificationsSettingsProvider).deadlineReminders;
      await checkDeadlines(games, enabled: enabled);
    } catch (_) {}
  }

  /// Clears deduplication, runs an immediate check, then restarts the 24 h timer.
  ///
  /// Use from dev tools or after a database switch.
  Future<void> triggerAndRestart(WidgetRef ref) async {
    resetSession();
    await runCheck(ref);
    startPeriodicCheck(ref);
  }

  // ---------------------------------------------------------------------------
  // Periodic scheduling
  // ---------------------------------------------------------------------------

  /// Starts a 24-hour timer. Resets the dedup set before each tick.
  void startPeriodicCheck(WidgetRef ref) {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(hours: 24), (_) {
      _notifiedGameIds.clear();
      runCheck(ref);
    });
  }

  /// Cancels the periodic timer.
  void stopPeriodicCheck() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Clears the per-day dedup set (e.g. after a database switch).
  void resetSession() {
    _notifiedGameIds.clear();
  }

  // ---------------------------------------------------------------------------
  // Dev-tools helpers
  // ---------------------------------------------------------------------------

  /// Send a test OS notification to verify the integration is working.
  Future<void> sendTestOsNotification() async {
    await _showOsNotification(
      id: _osIdTest,
      title: 'UniKM Test Notification',
      body: 'OS-level notifications are working correctly.',
      bypassFocusCheck: true,
    );
  }

  // ---------------------------------------------------------------------------
  // OS notification dispatch
  // ---------------------------------------------------------------------------

  Future<void> _showOsNotification({
    required int id,
    required String title,
    required String body,
    bool bypassFocusCheck = false,
  }) async {
    if (!_initialized) return;

    // Skip OS notifications while the app window is focused — in-app toasts
    // are already visible to the user and provide the same information.
    try {
      if (!bypassFocusCheck && await windowManager.isFocused()) return;
    } catch (_) {
      // window_manager unavailable (e.g. on a platform without a window) —
      // fall through and show the notification anyway.
    }

    try {
      if (Platform.isWindows) {
        await _showWindowsToast(title: title, body: body);
      } else if (Platform.isLinux || Platform.isMacOS) {
        await _showPluginNotification(id: id, title: title, body: body);
      }
    } catch (_) {}
  }

  /// Windows 10/11 toast via WinRT loaded through PowerShell.
  Future<void> _showWindowsToast({
    required String title,
    required String body,
  }) async {
    final safeTitle = title.replaceAll("'", ' ').replaceAll('\n', ' ');
    final safeBody  = body .replaceAll("'", ' ').replaceAll('\n', ' ');

    final script =
        "[Windows.UI.Notifications.ToastNotificationManager,"
        "Windows.UI.Notifications,ContentType=WindowsRuntime]|Out-Null;"
        "[Windows.Data.Xml.Dom.XmlDocument,"
        "Windows.Data.Xml.Dom.XmlDocument,ContentType=WindowsRuntime]|Out-Null;"
        r"$xml=[Windows.UI.Notifications.ToastNotificationManager]::"
        "GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02);"
        r"$n=$xml.GetElementsByTagName('text');"
        "\$n.Item(0).InnerText='$safeTitle';"
        "\$n.Item(1).InnerText='$safeBody';"
        r"$t=[Windows.UI.Notifications.ToastNotification]::new($xml);"
        "[Windows.UI.Notifications.ToastNotificationManager]::"
        r"CreateToastNotifier('UniKM').Show($t);";

    await Process.run(
      'powershell',
      ['-WindowStyle', 'Hidden', '-NonInteractive', '-Command', script],
    );
  }

  /// Linux/macOS notification via flutter_local_notifications plugin.
  Future<void> _showPluginNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const details = NotificationDetails(
      linux: LinuxNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );
    await _plugin.show(id, title, body, details);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _dayLabel(int days) => days == 1 ? '1 day' : '$days days';

  String _nameList(List<Game> games) {
    const max = 3;
    final shown = games.take(max).map((g) => g.title).join(', ');
    if (games.length <= max) return shown;
    return '$shown +${games.length - max} more';
  }
}
