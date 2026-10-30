import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/providers/repositories_providers.dart';
import '../../notifications/data/notification_repository.dart';
import '../../notifications/logic/reminder_coordinator.dart';
import '../../../shared/services/local_notification_service.dart';
import '../domain/document.dart';
import 'categories_controller.dart';
import 'wallet_summary_providers.dart';

/// Loads and mutates certificate documents of one sub-category.
final documentsProvider = AsyncNotifierProvider.family
    .autoDispose<DocumentsController, List<DocumentRecord>, String>(
      (arg) => DocumentsController()..categoryId = arg,
    );

class DocumentsController extends AsyncNotifier<List<DocumentRecord>> {
  late String categoryId;

  @override
  Future<List<DocumentRecord>> build() async {
    final repo = ref.watch(documentRepositoryProvider);
    if (repo == null) {
      return const [];
    }
    return repo.listByCategory(categoryId);
  }

  Future<bool> save(DocumentRecord document) async {
    final repo = ref.read(documentRepositoryProvider);
    if (repo == null) {
      return false;
    }
    // 先取出后续异步步骤所需的依赖，避免页面关闭后 autoDispose 的 ref 失效。
    final notifications = ref.read(notificationRepositoryProvider);
    final coordinator = ref.read(reminderCoordinatorProvider);
    await repo.save(document);
    ref.invalidate(categoryCardCountProvider(categoryId));
    ref.read(vaultRevisionProvider.notifier).bump();
    ref.invalidateSelf();
    // 提醒维护不阻塞保存返回。
    unawaited(_refreshReminders(document.id, notifications, coordinator));
    return true;
  }

  Future<void> _refreshReminders(
    String documentId,
    NotificationRepository? notifications,
    ReminderCoordinator coordinator,
  ) async {
    try {
      final localNotifications = LocalNotificationService.instance;
      await localNotifications.initialize();
      await localNotifications.cancelRemindersFor(documentId);
      // Validity-date edits reuse dedupe keys; rebuild the encrypted snapshots.
      await notifications?.purgeByCard(documentId);
      await coordinator.recomputeFor(documentId);
    } catch (_) {
      // Retried on the next recompute trigger.
    }
  }

  Future<DocumentRecord> createDraft() {
    final now = DateTime.now();
    return Future.value(
      DocumentRecord(
        id: const Uuid().v4(),
        categoryId: categoryId,
        holderName: '',
        idNumber: '',
        issuer: '',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<bool> delete(String id) async {
    final repo = ref.read(documentRepositoryProvider);
    if (repo == null) {
      return false;
    }
    final notifications = ref.read(notificationRepositoryProvider);
    final coordinator = ref.read(reminderCoordinatorProvider);
    final removed = await repo.delete(id);
    if (removed > 0) {
      ref.invalidateSelf();
      ref.invalidate(categoryCardCountProvider(categoryId));
      ref.read(vaultRevisionProvider.notifier).bump();
      unawaited(_dropReminders(id, notifications, coordinator));
      return true;
    }
    return false;
  }

  Future<void> _dropReminders(
    String id,
    NotificationRepository? notifications,
    ReminderCoordinator coordinator,
  ) async {
    try {
      await notifications?.deleteByCard(id);
      final localNotifications = LocalNotificationService.instance;
      await localNotifications.initialize();
      await localNotifications.cancelRemindersFor(id);
      await coordinator.recomputeFor(id);
    } catch (_) {
      // Retried on the next recompute trigger.
    }
  }
}
