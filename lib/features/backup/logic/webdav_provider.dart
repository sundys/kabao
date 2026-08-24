import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/logic/auth_controller.dart' show secureStoreProvider;
import '../domain/webdav_config.dart';

final webDavConfigProvider =
    AsyncNotifierProvider<WebDavConfigController, WebDavConfig?>(
      WebDavConfigController.new,
    );

class WebDavConfigController extends AsyncNotifier<WebDavConfig?> {
  WebDavProfileStore get _store =>
      SecureWebDavProfileStore(storage: ref.read(secureStoreProvider));

  @override
  Future<WebDavConfig?> build() async => _store.readConfig();

  Future<void> save(WebDavConfig config, String password) async {
    await _store.writePassword(password);
    await _store.writeConfig(config);
    ref.invalidateSelf();
  }

  Future<void> updateConfig(WebDavConfig config) async {
    await _store.writeConfig(config);
    ref.invalidateSelf();
  }

  Future<String?> readPassword() => _store.readPassword();

  Future<void> clear() async {
    await _store.clear();
    ref.invalidateSelf();
  }
}

const String remoteBackupFileName = 'kabao-auto.kabao';

/// Automatic backups are throttled to at most one per day; the exact policy
/// is shown in the settings UI next to the toggle.
bool shouldAutoBackup(WebDavConfig config, DateTime now) {
  if (!config.autoBackupEnabled) {
    return false;
  }
  final last = config.lastBackupAt;
  if (last == null) {
    return true;
  }
  return now.difference(last) >= const Duration(hours: 24);
}
