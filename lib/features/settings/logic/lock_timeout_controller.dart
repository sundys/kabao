import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/logic/auth_controller.dart';

/// 用户可选的自动锁定超时档位：应用被切到后台后，经过该时长即锁定数据库。
enum LockTimeout {
  immediate(Duration.zero, '立即'),
  seconds15(Duration(seconds: 15), '15秒'),
  seconds30(Duration(seconds: 30), '30秒'),
  minutes1(Duration(minutes: 1), '1分钟'),
  minutes2(Duration(minutes: 2), '2分钟'),
  minutes5(Duration(minutes: 5), '5分钟'),
  minutes10(Duration(minutes: 10), '10分钟');

  const LockTimeout(this.duration, this.label);

  final Duration duration;

  /// 设置页与选择弹窗中展示的中文名称。
  final String label;

  /// 未做过选择时的档位，兼顾安全与重复解锁的成本。
  static const LockTimeout fallback = LockTimeout.seconds30;

  /// 解析持久化的枚举名；无法识别（含首次运行、数据损坏）时回落到
  /// [fallback]，绝不放宽为更长的超时。
  static LockTimeout fromName(String? name) {
    for (final value in LockTimeout.values) {
      if (value.name == name) {
        return value;
      }
    }
    return fallback;
  }
}

/// 自动锁定超时设置，持久化在加密的 secure storage 中，选中状态跨进程有效。
final lockTimeoutProvider =
    AsyncNotifierProvider<LockTimeoutController, LockTimeout>(
      LockTimeoutController.new,
    );

class LockTimeoutController extends AsyncNotifier<LockTimeout> {
  static const String _key = 'kabao.settings.lockTimeout';

  @override
  Future<LockTimeout> build() async {
    final raw = await ref.watch(secureStoreProvider).read(_key);
    return LockTimeout.fromName(raw);
  }

  Future<void> setTimeout(LockTimeout timeout) async {
    // Make the selected row/button responsive; persistence follows.
    state = AsyncData(timeout);
    await ref.read(secureStoreProvider).write(_key, timeout.name);
  }
}
