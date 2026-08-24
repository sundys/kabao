import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/logic/auth_controller.dart';
import '../features/notifications/logic/reminder_coordinator.dart';
import '../shared/services/clipboard_service.dart';
import '../shared/services/local_notification_service.dart';
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
  /// 界面被覆盖（切后台/下拉通知栏）后延迟锁定的时间；期间回到应用会取消
  /// 锁定，避免频繁重复解锁。
  static const Duration lockDelay = Duration(seconds: 10);

  Timer? _lockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LocalNotificationService.instance.initialize();
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // While the system biometric prompt is showing, some devices emit
    // hidden/paused/resumed for the host activity; ignoring these prevents
    // an unlock loop after a successful scan.
    final biometricBusy = ref.read(biometricAuthInProgressProvider);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (!biometricBusy) {
          _startLockTimer();
        }
      case AppLifecycleState.resumed:
        _cancelLockTimer();
        if (!biometricBusy) {
          ref.read(reminderCoordinatorProvider).recompute();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _startLockTimer() {
    _lockTimer?.cancel();
    // Best-effort: remove a copied card number from the clipboard.
    ClipboardService.clear();
    _lockTimer = Timer(lockDelay, () {
      ref.read(authControllerProvider.notifier).lock();
    });
  }

  void _cancelLockTimer() {
    _lockTimer?.cancel();
    _lockTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
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
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
