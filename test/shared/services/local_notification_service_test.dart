import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/features/notifications/domain/models.dart';
import 'package:kabao/features/notifications/domain/reminder_rules.dart';
import 'package:kabao/shared/services/local_notification_service.dart';

import '../../helpers/recording_notification_gateway.dart';

AppNotification notification({
  ReminderType type = ReminderType.cardExpiry,
  String dedupeKey = 'expiry:c1:30',
  String title = '借记卡到期提醒',
  String body = '「工商银行」（**** 5678）的卡片有效期将于 2027/08/31 到期',
  DateTime? scheduledFor,
}) => AppNotification(
  id: 'n1',
  type: type,
  cardId: 'c1',
  dedupeKey: dedupeKey,
  title: title,
  body: body,
  createdAt: DateTime(2027, 6, 2),
  scheduledFor: scheduledFor,
);

void main() {
  group('初始化与降级', () {
    test('初始化成功且权限授予后才投递', () async {
      final gateway = RecordingGateway();
      final service = LocalNotificationService(gateway: gateway);
      await service.initialize();
      expect(gateway.initializeCalled, isTrue);

      await service.present(notification());
      expect(
        gateway.shown.single.id,
        LocalNotificationService.stableShadeId('expiry:c1:30'),
      );
      expect(gateway.shown.single.title, '借记卡到期提醒');
    });

    test('系统通知正文不写入卡号、银行名称或日期', () async {
      final gateway = RecordingGateway();
      final service = LocalNotificationService(gateway: gateway);
      await service.initialize();

      await service.present(notification());
      final body = gateway.shown.single.body;
      expect(body, isNot(contains('工商银行')));
      expect(body, isNot(contains('5678')));
      expect(body, isNot(contains('2027')));
      expect(body, '银行卡有效期即将到期，请打开卡包查看。');
    });

    test('三类提醒都使用不含敏感数据的系统正文', () async {
      final gateway = RecordingGateway();
      final service = LocalNotificationService(gateway: gateway);
      await service.initialize();

      await service.present(
        notification(
          type: ReminderType.uShieldExpiry,
          dedupeKey: 'ushield:c1:15',
        ),
      );
      await service.present(
        notification(
          type: ReminderType.documentExpiry,
          dedupeKey: 'docexpiry:c1:30',
        ),
      );

      expect(gateway.shown.map((entry) => entry.body), [
        'U 盾证书即将到期，请打开卡包查看。',
        '证件有效期限即将到期，请打开卡包查看。',
      ]);
    });

    test('并发初始化共享同一次平台初始化', () async {
      final gateway = RecordingGateway();
      final service = LocalNotificationService(gateway: gateway);
      await Future.wait([
        service.initialize(),
        service.initialize(),
        service.initialize(),
      ]);

      expect(gateway.initializeCalls, 1);
      expect(gateway.requestPermissionCalls, 1);
    });

    test('权限被拒绝时不投递、不抛错（应用内通知仍为准）', () async {
      final gateway = RecordingGateway(permissionGranted: false);
      final service = LocalNotificationService(gateway: gateway);
      await service.initialize();

      await service.present(notification());
      await service.schedule(notification(scheduledFor: DateTime(2028, 1, 1)));
      expect(gateway.shown, isEmpty);
      expect(gateway.scheduled, isEmpty);
    });

    test('系统设置重新开启权限后可恢复投递', () async {
      final gateway = RecordingGateway(permissionGranted: false)
        ..enabled = false;
      final service = LocalNotificationService(gateway: gateway);
      await service.initialize();
      await service.present(notification());
      expect(gateway.shown, isEmpty);

      gateway.enabled = true;
      await service.refreshPermission();
      await service.present(notification());
      expect(gateway.shown, hasLength(1));
    });

    test('平台初始化失败时静默降级，后续调用全部跳过', () async {
      final gateway = RecordingGateway(failInitialize: true);
      final service = LocalNotificationService(gateway: gateway);
      await service.initialize();

      await service.present(notification());
      expect(gateway.shown, isEmpty);
    });

    test('初始化临时失败后允许下一次重试', () async {
      final gateway = RecordingGateway(failInitialize: true);
      final service = LocalNotificationService(gateway: gateway);
      await service.initialize();

      gateway.failInitialize = false;
      await service.initialize();
      await service.present(notification());

      expect(gateway.initializeCalls, 1);
      expect(gateway.shown, hasLength(1));
    });

    test('网关抛错不会传播（横幅尽力而为）', () async {
      final gateway = RecordingGateway()..throwOnDeliver = true;
      final service = LocalNotificationService(gateway: gateway);
      await service.initialize();

      await service.present(notification());
      await service.schedule(notification(scheduledFor: DateTime(2028, 1, 1)));
      await service.cancel(notification());
    });
  });

  group('投递策略', () {
    test('未到期提醒按到期日当天 09:00 定时调度', () async {
      final gateway = RecordingGateway();
      final service = LocalNotificationService(gateway: gateway);
      await service.initialize();

      await service.schedule(
        notification(scheduledFor: DateTime(2027, 12, 31)),
        now: DateTime(2027, 6, 2),
      );
      final call = gateway.scheduled.single;
      expect(call.when, DateTime(2027, 12, 31, 9));
      expect(call.id, LocalNotificationService.stableShadeId('expiry:c1:30'));
      expect(gateway.shown, isEmpty);
    });

    test('已到期的预览回退为立即展示，不静默丢弃', () async {
      final gateway = RecordingGateway();
      final service = LocalNotificationService(gateway: gateway);
      await service.initialize();

      await service.schedule(
        notification(scheduledFor: DateTime(2026, 1, 1)),
        now: DateTime(2027, 6, 2),
      );
      expect(gateway.scheduled, isEmpty);
      expect(gateway.shown, isNotEmpty);
    });

    test('提醒日期当天的 09:00 前仍保持定时投递', () async {
      final gateway = RecordingGateway();
      final service = LocalNotificationService(gateway: gateway);
      await service.initialize();

      await service.schedule(
        notification(scheduledFor: DateTime(2027, 6, 2)),
        now: DateTime(2027, 6, 2, 8, 59),
      );

      expect(gateway.shown, isEmpty);
      expect(gateway.scheduled.single.when, DateTime(2027, 6, 2, 9));
    });

    test('相同去重键的重复调度覆盖同一 id（不堆叠）', () async {
      final gateway = RecordingGateway();
      final service = LocalNotificationService(gateway: gateway);
      await service.initialize();

      final n = notification(scheduledFor: DateTime(2027, 12, 31));
      await service.schedule(n, now: DateTime(2027, 6, 2));
      await service.schedule(n, now: DateTime(2027, 6, 2));
      expect(gateway.scheduled.map((c) => c.id).toSet().length, 1);
      expect(gateway.scheduled.length, 2); // 重挂是幂等的重复调用
    });
  });

  group('取消', () {
    test('删除应用内通知时取消对应横幅/闹钟', () async {
      final gateway = RecordingGateway();
      final service = LocalNotificationService(gateway: gateway);
      await service.initialize();

      await service.cancel(notification());
      expect(
        gateway.canceled.single,
        LocalNotificationService.stableShadeId('expiry:c1:30'),
      );
    });

    test('删除卡片时取消该卡全部可能的档位闹钟', () async {
      final gateway = RecordingGateway();
      final service = LocalNotificationService(gateway: gateway);
      await service.initialize();

      await service.cancelRemindersFor('c1');
      final expected = reminderDedupeKeysFor(
        'c1',
      ).map((k) => LocalNotificationService.stableShadeId(k)).toSet();
      expect(gateway.canceled.toSet(), expected);
      expect(gateway.canceled.length, expected.length);
    });

    test('未初始化时取消是安全空操作', () async {
      final gateway = RecordingGateway();
      final service = LocalNotificationService(gateway: gateway);
      await service.cancelRemindersFor('c1');
      expect(gateway.canceled, isEmpty);
    });

    test('权限被拒绝后仍可取消已有系统闹钟', () async {
      final gateway = RecordingGateway(permissionGranted: false);
      final service = LocalNotificationService(gateway: gateway);
      await service.initialize();

      await service.cancel(notification());
      await service.cancelAll();

      expect(gateway.canceled, [
        LocalNotificationService.stableShadeId('expiry:c1:30'),
      ]);
      expect(gateway.cancelAllCalls, 1);
    });
  });

  group('去重键枚举完整性', () {
    test('覆盖三类来源与全部档位且互不重复', () {
      final keys = reminderDedupeKeysFor('c1');
      expect(keys.toSet().length, keys.length);
      expect(
        keys,
        containsAll([
          'expiry:c1:90',
          'expiry:c1:0',
          'ushield:c1:15',
          'docexpiry:c1:30',
        ]),
      );
    });
  });
}
