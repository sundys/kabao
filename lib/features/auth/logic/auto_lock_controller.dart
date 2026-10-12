import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 可注入的时钟。自动锁定按「离开前台的时刻」判定，测试需要控制时间流逝。
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 自动锁定决策器：把「离开前台多久」与「现在是否该锁定」分开判定。
///
/// 只靠 [Timer] 判定并不可靠：应用进入后台后系统可能冻结进程（缓存应用冻结 /
/// Doze），定时器不会按点触发；回到前台时，已经过期的定时器回调与 `resumed`
/// 生命周期事件会竞争，一旦 `resumed` 先到，先前的实现就取消了定时器，于是
/// 超时后回到应用仍然是解锁状态（表现为自动锁定「有时」失效）。
///
/// 因此这里以「离开前台的时刻」为准：回到前台时若离开时长已达到档位就直接
/// 锁定；定时器只负责在后台停留期间尽早锁定。
///
/// 同一次离开前台会收到多个事件（框架在 `paused` 与 `resumed` 之间会补发
/// `hidden`/`inactive`），所以一次离开只记录第一个时刻并只起一次计时，
/// 否则补发的事件会把超时判定不断往后推。
final class AutoLockController {
  AutoLockController({required this.onLock, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// 判定需要锁定时调用，由调用方切换会话状态。
  final void Function() onLock;

  final DateTime Function() _clock;

  Timer? _timer;
  DateTime? _leftForegroundAt;
  bool _inBackground = false;

  /// 应用进入后台（paused/hidden）：记录离开时刻并按档位开始计时。
  /// 档位为「立即」时直接锁定。
  ///
  /// 返回本次调用是否真的开始了「离开前台」这一过程，便于调用方只在真正
  /// 离开前台时做一次性处理（例如清除自家写入的剪贴板）。
  bool onBackgrounded(Duration timeout) {
    if (_inBackground) {
      return false;
    }
    _inBackground = true;
    if (timeout <= Duration.zero) {
      _lockNow();
      return true;
    }
    _leftForegroundAt = _clock();
    _timer = Timer(timeout, _lockNow);
    return true;
  }

  /// 应用回到前台：离开时长达到档位则立刻锁定，否则取消计时，无需重复验证。
  void onForegrounded(Duration timeout) {
    final leftAt = _leftForegroundAt;
    final wasInBackground = _inBackground;
    _cancelTimer();
    _inBackground = false;
    _leftForegroundAt = null;
    if (!wasInBackground || leftAt == null) {
      return;
    }
    if (_clock().difference(leftAt) >= timeout) {
      _lockNow();
    }
  }

  /// 会话被重新建立或宿主销毁时丢弃未完成的计时。
  void dispose() {
    _cancelTimer();
    _inBackground = false;
    _leftForegroundAt = null;
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _lockNow() {
    _cancelTimer();
    _leftForegroundAt = null;
    onLock();
  }
}
