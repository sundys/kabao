import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/database/encrypted_database.dart';
import '../../features/auth/logic/auth_controller.dart';
import '../../features/auth/models/auth_state.dart';

/// Opens the encrypted database while a session is authenticated and attaches
/// the in-memory DEK. Returns null whenever the vault is locked or unset up,
/// so no repository can read payloads without authentication.
final vaultDatabaseProvider =
    AsyncNotifierProvider<VaultDatabaseController, EncryptedDatabase?>(
      VaultDatabaseController.new,
    );

final class VaultDatabaseController extends AsyncNotifier<EncryptedDatabase?> {
  @override
  Future<EncryptedDatabase?> build() async {
    final auth = await ref.watch(authControllerProvider.future);
    switch (auth) {
      case AuthUnlocked(:final dataKey):
        final path = await databasePath();
        final db = await EncryptedDatabase.open(path);
        db.attachKey(dataKey);
        ref.onDispose(() {
          db.detachKey();
          db.close();
        });
        return db;
      case AuthNeedsSetup():
      case AuthLocked():
      case AuthInitializing():
        return null;
    }
  }

  static Future<String> databasePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'kabao_vault.db');
  }
}
