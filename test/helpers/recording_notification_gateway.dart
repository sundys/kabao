import 'package:kabao/shared/services/system_notification_gateway.dart';

/// 记录所有调用的假网关，用于离线验证投递策略。
final class RecordingGateway implements SystemNotificationGateway {
  RecordingGateway({
    this.permissionGranted = true,
    this.failInitialize = false,
  });

  final bool permissionGranted;
  bool failInitialize;
  bool enabled = true;
  bool initializeCalled = false;
  int initializeCalls = 0;
  int requestPermissionCalls = 0;
  bool throwOnDeliver = false;
  final shown = <({int id, String title, String body})>[];
  final scheduled = <({int id, String title, String body, DateTime when})>[];
  final canceled = <int>[];
  int cancelAllCalls = 0;

  @override
  Future<void> initialize() async {
    if (failInitialize) {
      throw StateError('platform unavailable');
    }
    initializeCalls++;
    initializeCalled = true;
  }

  @override
  Future<bool> requestPermission() async {
    requestPermissionCalls++;
    return permissionGranted;
  }

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> show(int id, String title, String body) async {
    if (throwOnDeliver) {
      throw StateError('shade refused');
    }
    shown.add((id: id, title: title, body: body));
  }

  @override
  Future<void> schedule(
    int id,
    String title,
    String body,
    DateTime when,
  ) async {
    if (throwOnDeliver) {
      throw StateError('shade refused');
    }
    scheduled.add((id: id, title: title, body: body, when: when));
  }

  @override
  Future<void> cancel(int id) async => canceled.add(id);

  @override
  Future<void> cancelAll() async => cancelAllCalls++;

  @override
  Future<void> openSettings() async {}
}
