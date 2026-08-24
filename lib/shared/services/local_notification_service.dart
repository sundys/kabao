import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../features/notifications/domain/models.dart';

/// Presents system banner notifications with graceful degradation: when the
/// platform refuses (permission denied, unsupported), the in-app notification
/// center still holds every message.
final class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _permissionGranted = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    try {
      await _plugin.initialize(settings: settings);
      _permissionGranted =
          await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
      _initialized = true;
    } catch (_) {
      // Banners are optional; the in-app center remains the source of truth.
      _permissionGranted = false;
    }
  }

  /// Fire-and-forget banner for freshly created reminders. Never throws.
  Future<void> present(AppNotification notification) async {
    if (!_initialized || !_permissionGranted) {
      return;
    }
    try {
      await _plugin.show(
        id: notification.dedupeKey.hashCode & 0x7FFFFFFF,
        title: notification.title,
        body: notification.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'reminders',
            '到期提醒',
            channelDescription: '卡片有效期与 U 盾证书到期提醒',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
    } catch (_) {
      // Ignore: banners are best-effort.
    }
  }
}
