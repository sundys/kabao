import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/logic/auth_controller.dart';
import '../features/auth/logic/auto_lock_controller.dart';
import '../features/notifications/logic/reminder_coordinator.dart';
import '../features/settings/logic/lock_timeout_controller.dart';
import '../features/settings/logic/update_service.dart';
import '../shared/services/clipboard_service.dart';
import '../shared/services/local_notification_service.dart';
import 'localization.dart';
import 'providers/repositories_providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_mode_controller.dart';

class KabaoApp extends ConsumerStatefulWidget {
  const KabaoApp({super.key});

  @override
  ConsumerState<KabaoApp> createState() => _KabaoAppState();
}

class _KabaoAppState extends ConsumerState<KabaoApp>
    with WidgetsBindingObserver {
  /// 在 [initState] 里建立，避免 [dispose] 时才首次初始化（那时 ref 已不可用）。
  late final AutoLockController _autoLock;

  /// 生物识别弹窗会让宿主 Activity 短暂进入后台（部分机型会发出 hidden/paused）。
  /// 这类后台事件不能直接起锁定计时，否则验证成功后会立刻被再次锁定；但用户
  /// 也可能就在弹窗期间离开应用，所以先记下来，等弹窗结束、应用仍在后台时
  /// 再补上计时。
  bool _leftForegroundDuringBiometric = false;

  @override
  void initState() {
    super.initState();
    _autoLock = AutoLockController(
      clock: ref.read(clockProvider),
      onLock: () => ref.read(authControllerProvider.notifier).lock(),
    );
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual(biometricAuthInProgressProvider, (_, inProgress) {
      if (inProgress || !_leftForegroundDuringBiometric) {
        return;
      }
      _leftForegroundDuringBiometric = false;
      // 只有应用确实仍在后台时才补计时；弹窗结束后已回到前台就不该锁定，
      // 否则一次成功的验证会被立刻推翻。
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != AppLifecycleState.paused &&
          lifecycle != AppLifecycleState.hidden) {
        return;
      }
      _leftForeground();
    });
    // 回收已经安装完成的更新包，避免安装包一直留在缓存目录里。
    unawaited(UpdateService.pruneInstalledPackages());
  }

  @override
  void dispose() {
    _autoLock.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // 生物识别弹窗带来的瞬时后台不参与自动锁定，先记下来。
        if (ref.read(biometricAuthInProgressProvider)) {
          _leftForegroundDuringBiometric = true;
          return;
        }
        _leftForeground();
      case AppLifecycleState.resumed:
        _leftForegroundDuringBiometric = false;
        _autoLock.onForegrounded(_lockDelay);
        if (!ref.read(biometricAuthInProgressProvider)) {
          unawaited(
            LocalNotificationService.instance.refreshPermission().then(
              (_) => ref.read(reminderCoordinatorProvider).recompute(),
            ),
          );
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// 应用离开前台：按设置页的「超时时间」起计时（期间回到应用会取消计时，
  /// 避免频繁重复解锁），并尽力清除自家写入的剪贴板内容。
  ///
  /// 一次离开会收到多个后台事件，只有第一个事件才做这些一次性处理。
  void _leftForeground() {
    if (_autoLock.onBackgrounded(_lockDelay)) {
      unawaited(ClipboardService.clear());
    }
  }

  /// 用户选择的锁定延迟；设置尚未读出时按更严格的默认档位处理。
  Duration get _lockDelay =>
      (ref.read(lockTimeoutProvider).value ?? LockTimeout.fallback).duration;

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    // Keep the persisted lock timeout warm so backgrounding never has to wait
    // on secure storage before starting the timer.
    ref.watch(lockTimeoutProvider);
    // First trigger: right after unlock when the encrypted DB is attached.
    ref.listen(vaultDatabaseProvider, (previous, next) {
      if (previous?.value == null && next.value != null) {
        final coordinator = ref.read(reminderCoordinatorProvider);
        coordinator.recompute().then((_) => coordinator.runAutoBackupIfDue());
      }
    });
    return MaterialApp.router(
      title: '卡包',
      debugShowCheckedModeBanner: false,
      locale: appLocale,
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
