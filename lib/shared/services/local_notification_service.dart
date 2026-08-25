import 'package:flutter/foundation.dart';

import '../../features/notifications/domain/models.dart';
import '../../features/notifications/domain/reminder_rules.dart';
import 'system_notification_gateway.dart';

/// Coordinates Android system notifications without making the system shade
/// the source of truth. Full notification content remains in the encrypted
/// in-app notification store; system banners use a generic body by design.
final class LocalNotificationService {
  LocalNotificationService({SystemNotificationGateway? gateway})
    : _gateway = gateway ?? AndroidNotificationGateway();

  static final LocalNotificationService instance = LocalNotificationService();

  final SystemNotificationGateway _gateway;
  Future<void>? _initialization;
  bool _ready = false;
  bool _permissionGranted = false;

  /// Initializes the local notification channel and requests Android 13+
  /// notification permission once per process.
  Future<void> initialize() {
    final current = _initialization;
    if (current != null) {
      return current;
    }
    late final Future<void> future;
    future = _initializeOnce().whenComplete(() {
      if (!_ready && identical(_initialization, future)) {
        // Permit a later unlock/resume to retry after a transient platform
        // channel failure (for example while the Android activity recreates).
        _initialization = null;
      }
    });
    _initialization = future;
    return future;
  }

  Future<void> _initializeOnce() async {
    try {
      await _gateway.initialize();
      _permissionGranted = await _gateway.requestPermission();
      _ready = true;
    } catch (_) {
      // In-app encrypted notifications remain available when the platform
      // plugin or permission is unavailable.
      _ready = false;
      _permissionGranted = false;
    }
  }

  /// Refreshes a permission changed outside the app, such as Android's app
  /// notification settings. No dialog is opened during this refresh.
  Future<void> refreshPermission() async {
    if (!_ready) {
      return;
    }
    try {
      _permissionGranted = await _gateway.isEnabled();
    } catch (_) {
      _permissionGranted = false;
    }
  }

  /// Shows a newly materialized reminder immediately when system delivery is
  /// enabled. The message intentionally omits sensitive record details.
  Future<bool> present(AppNotification notification) async {
    if (!_canDeliver) {
      return false;
    }
    try {
      await _gateway.show(
        stableShadeId(notification.dedupeKey),
        notification.title,
        _systemBody(notification),
      );
      return true;
    } catch (_) {
      // System delivery is best effort; the in-app notification is durable.
      return false;
    }
  }

  /// Schedules a reminder at 09:00 on its due date. Missed reminders are
  /// shown immediately by [schedule] so a powered-off device does not lose a
  /// reminder permanently.
  Future<bool> schedule(AppNotification notification, {DateTime? now}) async {
    if (!_canDeliver) {
      return false;
    }
    final current = now ?? DateTime.now();
    final dueAt = notification.scheduledFor;
    if (dueAt == null) {
      return present(notification);
    }
    final scheduledAt = DateTime(dueAt.year, dueAt.month, dueAt.day, 9);
    try {
      if (!scheduledAt.isAfter(current)) {
        await _gateway.show(
          stableShadeId(notification.dedupeKey),
          notification.title,
          _systemBody(notification),
        );
        return true;
      }
      await _gateway.schedule(
        stableShadeId(notification.dedupeKey),
        notification.title,
        _systemBody(notification),
        scheduledAt,
      );
      return true;
    } catch (_) {
      // A banner failure must never prevent the encrypted in-app reminder
      // from being created or displayed.
      return false;
    }
  }

  Future<void> cancel(AppNotification notification) async {
    if (!_ready) {
      return;
    }
    try {
      await _gateway.cancel(stableShadeId(notification.dedupeKey));
    } catch (_) {
      // Cancellation is best effort, just like delivery.
    }
  }

  Future<void> cancelRemindersFor(String cardId) async {
    if (!_ready) {
      return;
    }
    for (final key in reminderDedupeKeysFor(cardId)) {
      try {
        await _gateway.cancel(stableShadeId(key));
      } catch (_) {
        // Continue cancelling the remaining tiers.
      }
    }
  }

  Future<void> cancelAll() async {
    if (!_ready) {
      return;
    }
    try {
      await _gateway.cancelAll();
    } catch (_) {
      // Wipe must still continue if the platform plugin is unavailable.
    }
  }

  Future<void> openSettings() async {
    if (!_ready) {
      return;
    }
    try {
      await _gateway.openSettings();
    } catch (_) {
      // Settings navigation is optional; the in-app notification center is
      // unaffected when the platform does not expose it.
    }
  }

  bool get _canDeliver => _ready && _permissionGranted;

  // Avoid writing card numbers, document numbers, dates, or bank names into
  // Android's notification store and lock-screen preview.
  String _systemBody(AppNotification notification) =>
      switch (notification.type) {
        ReminderType.cardExpiry => '银行卡有效期即将到期，请打开卡包查看。',
        ReminderType.uShieldExpiry => 'U 盾证书即将到期，请打开卡包查看。',
        ReminderType.documentExpiry => '证件有效期限即将到期，请打开卡包查看。',
      };

  /// Stable, process-independent positive ID for Android AlarmManager.
  /// Dart's String.hashCode is intentionally not a persistence contract.
  @visibleForTesting
  static int stableShadeId(String value) {
    var hash = 0x811C9DC5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash == 0 ? 1 : hash;
  }
}
