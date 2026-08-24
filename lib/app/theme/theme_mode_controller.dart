import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/logic/auth_controller.dart';

/// User-selectable theme mode persisted in secure storage.
/// Values: light / dark / system.
final themeModeProvider = AsyncNotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends AsyncNotifier<ThemeMode> {
  static const String _key = 'kabao.settings.themeMode';

  @override
  Future<ThemeMode> build() async {
    final raw = await ref.watch(secureStoreProvider).read(_key);
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setMode(ThemeMode mode) async {
    await ref.read(secureStoreProvider).write(_key, mode.name);
    state = AsyncData(mode);
  }
}
