import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/vault_providers.dart';
import '../../auth/logic/auth_controller.dart';

final wipeServiceProvider = Provider<WipeService>((ref) => WipeService(ref));

/// Irreversible destruction of all key material and business data. The UI
/// layer must obtain explicit double confirmation before calling [wipeAll].
final class WipeService {
  const WipeService(this._ref);

  final Ref _ref;

  Future<void> wipeAll() async {
    // 1. Business rows (if the vault happens to be attached).
    final db = _ref.read(vaultDatabaseProvider).value;
    if (db != null) {
      try {
        await db.destroyAllData();
      } catch (_) {
        // keep going: file removal is authoritative
      }
    }

    // 2. Database file itself.
    try {
      final path = await VaultDatabaseController.databasePath();
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // ignore: covered by key wipe below
    }

    // 3. All key material in secure storage (master key wrapping, biometric
    // copy, WebDAV credentials/config share this store).
    await _ref.read(masterKeyManagerProvider).wipeAll();

    // 4. Detach the session and return to first-run setup.
    _ref.invalidate(vaultDatabaseProvider);
    _ref.invalidate(authControllerProvider);
  }
}
