/// Opens a game's Steam store page.
library;

import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../ui/widgets/notification_system.dart';

/// Opens [appId]'s store page in the browser, or a store search for [title]
/// without one, and reports a failure as an error notification.
Future<void> openSteamPage({
  required String appId,
  required String title,
}) async {
  try {
    await launchUrl(
      Uri.parse(steamPageUrl(appId: appId, title: title)),
      mode: LaunchMode.externalApplication,
    );
  } catch (e) {
    NotificationManager.instance.error('Failed to open Steam page: $e');
  }
}
