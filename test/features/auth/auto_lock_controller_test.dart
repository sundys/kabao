import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/features/auth/logic/auto_lock_controller.dart';

/// 可控时钟：用来模拟「定时器没有按点触发，但真实时间已经过去」的冻结场景。
final class _TestClock {
  DateTime now = DateTime(2026, 1, 1, 9);

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
}

void main() {
  late _TestClock clock;
  late int lockCount;
  late AutoLockController controller;

  setUp(() {
    clock = _TestClock();
    lockCount = 0;
    controller = AutoLockController(
      clock: clock.call,
      onLock: () => lockCount += 1,
    );
  });

  tearDown(() => controller.dispose());

  test('离开时长未达到档位时回到前台不锁定', () {
    controller.onBackgrounded(const Duration(minutes: 1));
    clock.advance(const Duration(seconds: 20));

    controller.onForegrounded(const Duration(minutes: 1));

    expect(lockCount, 0);
  });

  test('定时器被系统冻结未触发时，回到前台按离开时长补锁定', () {
    controller.onBackgrounded(const Duration(minutes: 1));
    // 进程被冻结：定时器没有执行，但墙上时间已经远远超过档位。
    clock.advance(const Duration(hours: 2));

    controller.onForegrounded(const Duration(minutes: 1));

    expect(lockCount, 1);
  });

  test('恰好达到档位即锁定', () {
    controller.onBackgrounded(const Duration(seconds: 15));
    clock.advance(const Duration(seconds: 15));

    controller.onForegrounded(const Duration(seconds: 15));

    expect(lockCount, 1);
  });

  test('后台停留超过档位时由定时器锁定，回到前台不再重复锁定', () async {
    controller.onBackgrounded(const Duration(milliseconds: 40));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(lockCount, 1);

    clock.advance(const Duration(hours: 1));
    controller.onForegrounded(const Duration(milliseconds: 40));

    expect(lockCount, 1);
  });

  test('立即档位在进入后台时直接锁定', () {
    controller.onBackgrounded(Duration.zero);
    expect(lockCount, 1);

    clock.advance(const Duration(hours: 1));
    controller.onForegrounded(Duration.zero);
    expect(lockCount, 1);
  });

  test('未离开前台就收到 resumed 不会锁定', () {
    controller.onForegrounded(const Duration(seconds: 15));
    expect(lockCount, 0);
  });

  test('同一次离开前台的多个后台事件只记录一次离开时刻', () {
    controller.onBackgrounded(const Duration(seconds: 15));
    clock.advance(const Duration(seconds: 10));
    // 框架在 paused 与 resumed 之间会补发 hidden/inactive。
    controller.onBackgrounded(const Duration(seconds: 15));
    clock.advance(const Duration(seconds: 10));

    controller.onForegrounded(const Duration(seconds: 15));

    expect(lockCount, 1);
  });

  test('立即档位下补发的后台事件不会重复锁定', () {
    controller.onBackgrounded(Duration.zero);
    controller.onBackgrounded(Duration.zero);
    controller.onBackgrounded(Duration.zero);
    expect(lockCount, 1);
  });

  test('dispose 丢弃未完成的计时', () async {
    controller.onBackgrounded(const Duration(milliseconds: 40));
    controller.dispose();
    clock.advance(const Duration(hours: 1));

    await Future<void>.delayed(const Duration(milliseconds: 120));
    controller.onForegrounded(const Duration(milliseconds: 40));

    expect(lockCount, 0);
  });
}
