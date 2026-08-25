import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Platform boundary for notification-shade (system banner) notifications.
/// Keeping it an interface allows the delivery logic to be unit tested
/// without a device or platform channel.
abstract interface class SystemNotificationGateway {
  /// Prepares the plugin (channel + icon). Must run before any other call.
  Future<void> initialize();

  /// Requests Android 13+ POST_NOTIFICATIONS or reads the platform's current
  /// notification-enabled state on older Android versions.
  Future<bool> requestPermission();

  /// Reads the current system notification switch without prompting.
  Future<bool> isEnabled();

  /// Posts a banner immediately.
  Future<void> show(int id, String title, String body);

  /// Arms a system alarm that posts the banner at [when] (local wall clock).
  /// Re-arming the same [id] replaces the previous alarm.
  Future<void> schedule(int id, String title, String body, DateTime when);

  /// Removes a posted banner and disarms its pending alarm (no-op if absent).
  Future<void> cancel(int id);

  /// Removes every notification and pending alarm owned by this app.
  Future<void> cancelAll();

  /// Opens this app's Android notification settings.
  Future<void> openSettings();
}

/// Android implementation backed by flutter_local_notifications.
final class AndroidNotificationGateway implements SystemNotificationGateway {
  AndroidNotificationGateway();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const MethodChannel _timezoneChannel = MethodChannel(
    'com.sundys.kabao/device_timezone',
  );

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      '到期提醒',
      channelDescription: '卡片有效期与 U 盾证书到期提醒',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: 'ic_stat_reminder',
    ),
  );

  @override
  Future<void> initialize() async {
    tzdata.initializeTimeZones();
    await _setDeviceTimeZone();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_reminder'),
      ),
    );
  }

  Future<void> _setDeviceTimeZone() async {
    try {
      final name = await _timezoneChannel.invokeMethod<String>(
        'getTimeZoneName',
      );
      if (name != null && name.isNotEmpty) {
        tz.setLocalLocation(tz.getLocation(name));
      }
    } catch (_) {
      // Keep the package default (UTC) if the platform channel is unavailable.
      // Android production builds provide the channel from MainActivity.
    }
  }

  @override
  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    // Android 13+ returns a permission result. Older Android versions do not
    // expose a runtime permission request and may return null, so fall back to
    // the channel/app-level enabled state instead of disabling delivery.
    final requested = await android?.requestNotificationsPermission();
    if (requested != null) {
      return requested;
    }
    return await android?.areNotificationsEnabled() ?? false;
  }

  @override
  Future<bool> isEnabled() async =>
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled() ??
      false;

  @override
  Future<void> show(int id, String title, String body) => _plugin.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: _details,
  );

  @override
  Future<void> schedule(int id, String title, String body, DateTime when) =>
      _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        // The device timezone is loaded during initialize(). Constructing the
        // wall-clock time in tz.local keeps 09:00 local on every Android zone.
        scheduledDate: tz.TZDateTime(
          tz.local,
          when.year,
          when.month,
          when.day,
          when.hour,
          when.minute,
          when.second,
        ),
        notificationDetails: _details,
        // Inexact on purpose: no exact-alarm permission is requested. Banners
        // may shift within the system's idle-window budget; every app resume
        // re-arms the alarms as a corrective pass.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<void> openSettings() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.openAppNotificationSettings();
  }
}
