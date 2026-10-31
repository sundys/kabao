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

/// 按主键读取单个证件，供证件详情页跟随数据变化刷新。
/// 详情页的路由参数只是快照，编辑保存后需要重新读取。
final documentRecordProvider = FutureProvider.autoDispose
    .family<DocumentRecord?, String>((ref, id) async {
      ref.watch(vaultRevisionProvider);
      final repo = ref.watch(documentRepositoryProvider);
      return repo?.getById(id);
    });

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
    final container = ref.container;
    final notifications = ref.read(notificationRepositoryProvider);
    final coordinator = ref.read(reminderCoordinatorProvider);
    await repo.save(document);
    // 写库期间编辑页可能已返回，本控制器随之被回收；此时不能用 ref 失效，
    // 否则会抛 UnmountedRefException，调用方会误判为保存失败。
    if (!ref.mounted) {
      _invalidateAfterSave(container, document.id);
      return true;
    }
    ref.invalidate(categoryCardCountProvider(categoryId));
    ref.read(vaultRevisionProvider.notifier).bump();
    ref.invalidateSelf();
    // 提醒维护不阻塞保存返回。
    unawaited(_refreshReminders(document.id, notifications, coordinator));
    return true;
  }

  /// 控制器已被回收时的失效兜底：直接通过容器刷新相关 provider。
  void _invalidateAfterSave(ProviderContainer container, String documentId) {
    try {
      container.invalidate(categoryCardCountProvider(categoryId));
      container.read(vaultRevisionProvider.notifier).bump();
      container.invalidate(documentsProvider(categoryId));
      container.invalidate(documentRecordProvider(documentId));
    } catch (_) {
      // 容器已销毁（例如应用退出）：无需再刷新界面。
    }
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
    final container = ref.container;
    final notifications = ref.read(notificationRepositoryProvider);
    final coordinator = ref.read(reminderCoordinatorProvider);
    final removed = await repo.delete(id);
    if (removed > 0) {
      if (!ref.mounted) {
        _invalidateAfterSave(container, id);
        return true;
      }
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
