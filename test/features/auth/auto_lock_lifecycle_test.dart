import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/app/app.dart';
import 'package:kabao/features/auth/logic/auth_controller.dart';
import 'package:kabao/features/auth/logic/auto_lock_controller.dart';
import 'package:kabao/features/auth/models/auth_state.dart';

import '../../helpers/in_memory_secure_store.dart';

/// 直接以已解锁状态启动，避免在 widget 测试里跑 Argon2。
final class _UnlockedAuthController extends AuthController {
  @override
  Future<AuthState> build() async => AuthUnlocked(Uint8List(32));
}

/// 可控时钟：模拟定时器被系统冻结、墙上时间却继续前进的情况。
final class _TestClock {
  DateTime now = DateTime(2026, 1, 1, 9);

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
}

void main() {
  late _TestClock clock;
  late ProviderContainer container;

  Future<void> pumpApp(WidgetTester tester) async {
    clock = _TestClock();
    container = ProviderContainer(
      overrides: [
        secureStoreProvider.overrideWithValue(InMemorySecureStore()),
        authControllerProvider.overrideWith(_UnlockedAuthController.new),
        clockProvider.overrideWithValue(clock.call),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const KabaoApp()),
    );
    await tester.pumpAndSettle();
  }

  /// 走真实的 flutter/lifecycle 通道，与线上行为一致。
  Future<void> sendLifecycle(
    WidgetTester tester,
    AppLifecycleState state,
  ) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage(state.toString()),
      (_) {},
    );
    await tester.pump();
  }

  Future<void> background(WidgetTester tester) async {
    await sendLifecycle(tester, AppLifecycleState.inactive);
    await sendLifecycle(tester, AppLifecycleState.hidden);
    await sendLifecycle(tester, AppLifecycleState.paused);
  }

  testWidgets('离开时长超过档位后回到前台会锁定', (tester) async {
    await pumpApp(tester);
    expect(find.text('卡包已锁定'), findsNothing);

    await background(tester);
    // 系统冻结进程：定时器没有按点触发，但墙上时间已经过去很久。
    clock.advance(const Duration(minutes: 5));
    await sendLifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('卡包已锁定'), findsOneWidget);
  });

  testWidgets('超时前回到应用不锁定', (tester) async {
    await pumpApp(tester);

    await background(tester);
    // 默认档位为 30 秒。
    clock.advance(const Duration(seconds: 5));
    await sendLifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('卡包已锁定'), findsNothing);
  });

  testWidgets('生物识别弹窗期间离开应用，弹窗结束后仍会超时锁定', (tester) async {
    await pumpApp(tester);
    final biometrics = container.read(biometricAuthInProgressProvider.notifier);

    biometrics.start();
    await background(tester);
    clock.advance(const Duration(minutes: 5));

    // 弹窗结束（取消或失败），但用户没有回到应用。
    biometrics.stop();
    clock.advance(const Duration(minutes: 5));

    await sendLifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('卡包已锁定'), findsOneWidget);
  });

  testWidgets('生物识别弹窗引起的短暂后台不会在验证成功后立刻再次锁定', (tester) async {
    await pumpApp(tester);
    final biometrics = container.read(biometricAuthInProgressProvider.notifier);

    biometrics.start();
    await background(tester);
    await sendLifecycle(tester, AppLifecycleState.resumed);
    biometrics.stop();
    await tester.pumpAndSettle();

    expect(find.text('卡包已锁定'), findsNothing);
  });
}
