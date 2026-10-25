/// Service that fires deadline reminders as in-app toasts and OS notifications.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/game.dart';
import '../../features/library/application/deadline_schedule.dart';
import '../../shared/platform/android_deadline_scheduler.dart';
import '../../providers/games_providers.dart';
import '../../providers/settings_providers.dart';
import '../../ui/widgets/notification_system.dart';

// =============================================================================
// DEADLINE NOTIFICATION SERVICE
// =============================================================================

// Fixed OS notification IDs so grouped notifications replace the previous one.
const int _osIdExpired = 1001;
const int _osIdToday = 1002;
const int _osIdSoon = 1003;
const int _osIdTest = 9998;
const int _osIdFetchProgress = 1004;
const int _maxNotificationNames = 7;
const Duration _deadlineToastDuration = Duration(seconds: 10);

/// Singleton service that checks game deadlines and fires reminders.
///
/// Fires:
/// - In-app toasts via [NotificationManager] (all platforms).
/// - OS-level desktop notifications (Linux/macOS via flutter_local_notifications,
///   Windows via native WinRT PowerShell toast).
///
/// Games are grouped by deadline state — expired, due today, and expiring soon
/// — rather than showing one notification per game.
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
        const darwin = DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );
        const settings = InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          linux: LinuxInitializationSettings(defaultActionName: 'Open UniKM'),
          macOS: darwin,
          iOS: darwin,
        );
        await _plugin.initialize(settings: settings);

        // Request the runtime notification permission on Android 13+ and iOS.
        if (Platform.isAndroid) {
          await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission();
        } else if (Platform.isIOS) {
          await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: false, sound: false);
        }
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

    final groups = [
      (
        games.where((g) => g.hasDeadline && g.isExpired).toList(),
        _osIdExpired,
        'Expired',
        'Expired',
      ),
      (
        games.where((g) => g.daysUntilDeadline == 0).toList(),
        _osIdToday,
        'Due Today',
        'Expiring Today',
      ),
      (
        games.where(_isDueSoon).toList(),
        _osIdSoon,
        'Expiring Soon',
        'Expiring Soon',
      ),
    ];
    String title(int count, String state) =>
        count == 1 ? 'Key $state' : '$count Keys $state';

    // Show all in-app groups before dispatching any OS notifications.
    for (final (entries, _, state, _) in groups) {
      if (entries.isEmpty) continue;
      NotificationManager.instance.warning(
        _notificationNameList(entries),
        title: title(entries.length, state),
        autoDismissAfter: _deadlineToastDuration,
      );
    }

    // Capture all pending groups before awaiting OS dispatch, preserving the
    // per-check snapshot and once-per-game deduplication across async calls.
    final pending = [
      for (final (entries, id, _, state) in groups)
        (
          entries.where((g) => !_notifiedGameIds.contains(g.id)).toList(),
          id,
          state,
        ),
    ];
    for (final (entries, id, state) in pending) {
      if (entries.isEmpty) continue;
      _notifiedGameIds.addAll(entries.map((g) => g.id));
      await _showOsNotification(
        id: id,
        title: title(entries.length, state),
        body: _notificationNameList(entries),
      );
    }
  }

  Future<void> updateSchedule(List<Game> games, {required bool enabled}) async {
    if (!Platform.isAndroid) return;
    await AndroidDeadlineScheduler.replace(
      enabled ? buildDeadlineSchedule(games, DateTime.now()) : const [],
    );
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

  /// Clears the per-day dedup set (e.g. after a database switch).
  void resetSession() => _notifiedGameIds.clear();

  // ---------------------------------------------------------------------------
  // Dev-tools helpers
  // ---------------------------------------------------------------------------

  /// Send a test OS notification to verify the integration is working.
  Future<void> sendTestOsNotification() => _showOsNotification(
    id: _osIdTest,
    title: 'UniKM Test Notification',
    body: 'OS-level notifications are working correctly.',
    bypassFocusCheck: true,
  );

  /// Simulates deadline notifications for expired, due today, and expiring soon games.
  Future<void> simulateDeadlineNotifications(WidgetRef ref) async {
    final now = DateTime.now();
    DateTime daysAgo(int days) => now.subtract(Duration(days: days));
    Game sample(
      int id,
      String title,
      String key,
      int added,
      int updated,
      DateTime deadline,
    ) => Game(
      id: id,
      title: title,
      gameKey: key,
      platform: 'Steam',
      dateAdded: daysAgo(added),
      updatedAt: daysAgo(updated),
      hasDeadline: true,
      deadlineDate: deadline,
    );

    await checkDeadlines([
      sample(-1001, 'Expired Simulation', 'SIM-EXPIRED', 30, 30, daysAgo(1)),
      sample(
        -1002,
        'Due Today Simulation',
        'SIM-TODAY',
        5,
        2,
        DateTime(now.year, now.month, now.day, 23, 59),
      ),
      sample(-1003, 'Expiring Soon Simulation', 'SIM-SOON', 2, 1, daysAgo(-3)),
    ], enabled: true);
  }

  // ---------------------------------------------------------------------------
  // Steam fetch-progress notifications (mobile only)
  // ---------------------------------------------------------------------------

  /// Show or update a progress notification on Android/iOS while a Steam batch
  /// fetch is running in the background. No-ops on other platforms.
  Future<void> showFetchProgressNotification({
    required int completed,
    required int total,
    required String? currentTitle,
  }) async {
    if (!_initialized) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      if (await windowManager.isFocused()) return;
    } catch (_) {}
    final title = currentTitle ?? '';
    try {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'unikm_fetch_progress',
          'Steam Data Fetch',
          channelDescription:
              'Progress for Steam data fetch operations running in the background',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          showProgress: total > 0,
          maxProgress: total,
          progress: completed,
          onlyAlertOnce: true,
          showWhen: false,
          playSound: false,
          enableVibration: false,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: false,
        ),
      );
      await _plugin.show(
        id: _osIdFetchProgress,
        title: 'Fetching Steam Data',
        body: total > 0
            ? '$completed / $total${title.isNotEmpty ? ' — $title' : ''}'
            : 'Starting...',
        notificationDetails: details,
      );
    } catch (_) {}
  }

  /// Dismiss the fetch-progress OS notification (mobile only).
  Future<void> clearFetchProgressNotification() async {
    if (!_initialized) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _plugin.cancel(id: _osIdFetchProgress);
    } catch (_) {}
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
      // window_manager unavailable on mobile — use lifecycle state instead.
      if (!bypassFocusCheck && (Platform.isAndroid || Platform.isIOS)) {
        final state = WidgetsBinding.instance.lifecycleState;
        if (state == AppLifecycleState.resumed) return;
      }
    }

    try {
      if (Platform.isWindows) {
        await _showWindowsToast(title: title, body: body);
      } else if (Platform.isLinux ||
          Platform.isMacOS ||
          Platform.isAndroid ||
          Platform.isIOS) {
        await _showPluginNotification(id: id, title: title, body: body);
      }
    } catch (_) {}
  }

  /// Windows 10/11 toast via WinRT loaded through PowerShell.
  Future<void> _showWindowsToast({
    required String title,
    required String body,
  }) async {
    String safe(String text) => text.replaceAll("'", ' ').replaceAll('\n', ' ');
    final safeTitle = safe(title);
    final safeBody = safe(body);

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

    await Process.run('powershell', [
      '-WindowStyle',
      'Hidden',
      '-NonInteractive',
      '-Command',
      script,
    ]);
  }

  /// Linux/macOS/Android/iOS notification via flutter_local_notifications plugin.
  Future<void> _showPluginNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'unikm_deadlines',
        'Deadline Alerts',
        channelDescription: 'Notifications for approaching game key deadlines',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: false,
      ),
      linux: LinuxNotificationDetails(),
      macOS: DarwinNotificationDetails(),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  bool _isDueSoon(Game game) => switch (game.daysUntilDeadline) {
    final days? => days > 0 && days <= 7,
    null => false,
  };

  /// Up to [_maxNotificationNames] titles, then a count of the rest.
  String _notificationNameList(List<Game> games) {
    final names = games.take(_maxNotificationNames).map((game) => game.title);
    final remaining = games.length - _maxNotificationNames;
    return remaining <= 0
        ? names.join(', ')
        : '${names.join(', ')} +$remaining more';
  }
}
