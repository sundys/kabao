import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/repositories_providers.dart';
import '../../backup/data/webdav_client.dart';
import '../../backup/domain/webdav_config.dart';
import '../../backup/logic/cloud_backup_service.dart';
import '../../backup/logic/webdav_provider.dart';
import '../../wallet/domain/models.dart';
import '../../../shared/services/local_notification_service.dart';
import 'notifications_provider.dart';
import 'reminders_service.dart';

final reminderCoordinatorProvider = Provider<ReminderCoordinator>(
  (ref) => ReminderCoordinator(ref),
);

/// Runs reminder recomputation whenever the vault becomes available (unlock)
/// and exposes a hook for lifecycle resume. Failures never surface to the
/// user; the next trigger will retry.
final class ReminderCoordinator {
  const ReminderCoordinator(this._ref);

  final Ref _ref;

  Future<void> recompute() async {
    final cards = _ref.read(cardRepositoryProvider);
    final categories = _ref.read(categoryRepositoryProvider);
    final notifications = _ref.read(notificationRepositoryProvider);
    final documents = _ref.read(documentRepositoryProvider);
    if (cards == null || notifications == null) {
      return;
    }
    try {
      final localNotifications = LocalNotificationService.instance;
      await localNotifications.initialize();
      await recomputeReminders(
        cards: cards,
        categories: categories,
        notifications: notifications,
        documents: documents,
        localNotifications: localNotifications,
      );
      _ref.invalidate(notificationsProvider);
    } catch (_) {
      // Recompute is retried on the next trigger.
    }
  }

  /// Automatic WebDAV backup (daily throttle), only when explicitly enabled
  /// by the user in settings. Failures are silent by design.
  Future<void> runAutoBackupIfDue() async {
    try {
      final config = await _ref.read(webDavConfigProvider.future);
      if (config == null || !shouldAutoBackup(config, DateTime.now())) {
        return;
      }
      final controller = _ref.read(webDavConfigProvider.notifier);
      final db = _ref.read(vaultDatabaseProvider).value;
      final categoryRepo = _ref.read(categoryRepositoryProvider);
      final cardRepo = _ref.read(cardRepositoryProvider);
      if (db == null || categoryRepo == null || cardRepo == null) {
        return;
      }
      final password = await controller.readPassword();
      if (password == null) {
        return;
      }
      final service = CloudBackupService(client: WebDavClientAdapter());
      await service.upload(
        config: config,
        password: password,
        categories: [
          ...await categoryRepo.listByType(CardType.debit),
          ...await categoryRepo.listByType(CardType.credit),
        ],
        cards: [
          ...await cardRepo.listByType(CardType.debit),
          ...await cardRepo.listByType(CardType.credit),
        ],
      );
      await controller.updateConfig(
        WebDavConfig(
          url: config.url,
          username: config.username,
          directory: config.directory,
          autoBackupEnabled: true,
          allowHttp: config.allowHttp,
          lastBackupAt: DateTime.now(),
        ),
      );
    } catch (_) {
      // Silent: retried on next unlock per policy shown in settings.
    }
  }
}
