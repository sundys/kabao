import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../wallet/domain/models.dart';
import '../data/webdav_client.dart';
import '../domain/webdav_config.dart';
import '../logic/backup_codec.dart';
import 'webdav_provider.dart' show remoteBackupFileName;

/// Builds, uploads and downloads the encrypted cloud backup. All business
/// data is encrypted with the backup password before leaving the device.
final class CloudBackupService {
  CloudBackupService({required this.client});

  final IWebDavClient client;

  /// Verifies credentials and server reachability.
  Future<void> testConnection({
    required WebDavConfig config,
    required String password,
  }) async {
    await client.connect(config, password);
    await client.ping();
  }

  Future<void> upload({
    required WebDavConfig config,
    required String password,
    required List<BankCategory> categories,
    required List<CardRecord> cards,
    DateTime? now,
  }) async {
    await client.connect(config, password);
    final contents = await BackupCodec.encode(
      snapshot: VaultSnapshot(categories: categories, cards: cards),
      password: password,
      now: now ?? DateTime.now(),
    );
    await client.writeFile(remoteBackupFileName, contents);
  }

  /// Returns null when no remote backup exists yet.
  Future<VaultSnapshot?> download({
    required WebDavConfig config,
    required String password,
  }) async {
    await client.connect(config, password);
    final contents = await client.readFile(remoteBackupFileName);
    if (contents == null) {
      return null;
    }
    return BackupCodec.decrypt(contents: contents, password: password);
  }
}

final cloudBackupServiceProvider = Provider<CloudBackupService>(
  (ref) => CloudBackupService(client: WebDavClientAdapter()),
);
