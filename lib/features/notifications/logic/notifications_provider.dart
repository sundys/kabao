import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/repositories_providers.dart';
import '../domain/models.dart';

/// Active (non-deleted) notifications, newest first. Rebuilds whenever the
/// repository appears (unlock) or is invalidated by mutations/recompute.
final notificationsProvider =
    AsyncNotifierProvider<NotificationsController, List<AppNotification>>(
      NotificationsController.new,
    );

class NotificationsController extends AsyncNotifier<List<AppNotification>> {
  @override
  Future<List<AppNotification>> build() async {
    final repo = ref.watch(notificationRepositoryProvider);
    if (repo == null) {
      return const [];
    }
    return repo.listActive();
  }

  Future<void> markRead(AppNotification notification) async {
    final repo = ref.read(notificationRepositoryProvider);
    if (repo == null) {
      return;
    }
    await repo.markRead(notification.id);
    ref.invalidateSelf();
  }

  Future<void> delete(AppNotification notification) async {
    final repo = ref.read(notificationRepositoryProvider);
    if (repo == null) {
      return;
    }
    await repo.delete(notification.id);
    ref.invalidateSelf();
  }
}
