import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/core/security/secure_store.dart';
import 'package:kabao/features/auth/logic/auth_controller.dart';
import 'package:kabao/features/settings/logic/lock_timeout_controller.dart';
import 'package:kabao/features/settings/presentation/pages/settings_page.dart';

import '../../helpers/in_memory_secure_store.dart';

void main() {
  const storageKey = 'kabao.settings.lockTimeout';

  group('LockTimeout', () {
    test('六个档位的时长与文案', () {
      expect(LockTimeout.values, hasLength(6));
      expect(LockTimeout.values.map((t) => t.label).toList(), [
        '立即',
        '30秒',
        '1分钟',
        '2分钟',
        '5分钟',
        '10分钟',
      ]);
      expect(LockTimeout.immediate.duration, Duration.zero);
      expect(LockTimeout.seconds30.duration, const Duration(seconds: 30));
      expect(LockTimeout.minutes1.duration, const Duration(minutes: 1));
      expect(LockTimeout.minutes2.duration, const Duration(minutes: 2));
      expect(LockTimeout.minutes5.duration, const Duration(minutes: 5));
      expect(LockTimeout.minutes10.duration, const Duration(minutes: 10));
    });

    test('无法识别的持久化值回落到默认档位而非更长超时', () {
      expect(LockTimeout.fromName(null), LockTimeout.fallback);
      expect(LockTimeout.fromName(''), LockTimeout.fallback);
      expect(LockTimeout.fromName('minutes99'), LockTimeout.fallback);
      expect(LockTimeout.fallback, LockTimeout.seconds30);
      expect(LockTimeout.fromName('minutes5'), LockTimeout.minutes5);
    });
  });

  group('LockTimeoutController', () {
    ProviderContainer containerWith(SecureStore store) {
      final container = ProviderContainer(
        overrides: [secureStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('未设置过时读到默认档位', () async {
      final container = containerWith(InMemorySecureStore());
      expect(
        await container.read(lockTimeoutProvider.future),
        LockTimeout.fallback,
      );
    });

    test('选择后写入安全存储，重建仍保持选中状态', () async {
      final store = InMemorySecureStore();
      final container = containerWith(store);
      await container.read(lockTimeoutProvider.future);

      await container
          .read(lockTimeoutProvider.notifier)
          .setTimeout(LockTimeout.minutes10);

      expect(container.read(lockTimeoutProvider).value, LockTimeout.minutes10);
      expect(await store.read(storageKey), 'minutes10');

      final reopened = containerWith(store);
      expect(
        await reopened.read(lockTimeoutProvider.future),
        LockTimeout.minutes10,
      );
    });

    test('立即档位持久化为零时长', () async {
      final store = InMemorySecureStore();
      final container = containerWith(store);
      await container.read(lockTimeoutProvider.future);

      await container
          .read(lockTimeoutProvider.notifier)
          .setTimeout(LockTimeout.immediate);

      expect(await store.read(storageKey), 'immediate');
      expect(
        container.read(lockTimeoutProvider).value?.duration,
        Duration.zero,
      );
    });
  });

  group('设置页超时时间菜单', () {
    Future<void> pumpSettings(WidgetTester tester, SecureStore store) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [secureStoreProvider.overrideWithValue(store)],
          child: const MaterialApp(home: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('安全分类下展示当前档位，弹窗用实心圆点标记选中项', (tester) async {
      await pumpSettings(tester, InMemorySecureStore());

      expect(find.text('超时时间'), findsOneWidget);
      expect(find.text('切换后台 30秒后锁定数据库'), findsOneWidget);

      await tester.tap(find.text('超时时间'));
      await tester.pumpAndSettle();

      // 弹窗标题 + 设置项标题同时存在。
      expect(find.text('超时时间'), findsNWidgets(2));
      for (final label in ['立即', '30秒', '1分钟', '2分钟', '5分钟', '10分钟']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(5));
    });

    testWidgets('点击其它档位后立即切换并持久化', (tester) async {
      final store = InMemorySecureStore();
      await pumpSettings(tester, store);

      await tester.tap(find.text('超时时间'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5分钟'));
      await tester.pumpAndSettle();

      expect(find.text('切换后台 5分钟后锁定数据库'), findsOneWidget);
      expect(await store.read(storageKey), 'minutes5');
    });

    testWidgets('选择立即时副标题说明无延迟', (tester) async {
      final store = InMemorySecureStore();
      await pumpSettings(tester, store);

      await tester.tap(find.text('超时时间'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('立即'));
      await tester.pumpAndSettle();

      expect(find.text('切换后台后立即锁定数据库'), findsOneWidget);
      expect(await store.read(storageKey), 'immediate');
    });
  });
}
