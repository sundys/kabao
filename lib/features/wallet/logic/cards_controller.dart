import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/providers/repositories_providers.dart';
import '../../notifications/data/notification_repository.dart';
import '../../notifications/logic/reminder_coordinator.dart';
import '../../../shared/services/local_notification_service.dart';
import '../domain/models.dart';
import 'categories_controller.dart';
import 'wallet_summary_providers.dart';

/// Loads and mutates the card records of one category.
final cardsProvider = AsyncNotifierProvider.autoDispose
    .family<CardsController, List<CardRecord>, String>(
      (arg) => CardsController()..categoryId = arg,
    );

class CardsController extends AsyncNotifier<List<CardRecord>> {
  late String categoryId;

  @override
  Future<List<CardRecord>> build() async {
    final repo = ref.watch(cardRepositoryProvider);
    if (repo == null) {
      return const [];
    }
    final cards = await repo.listByCategory(categoryId);
    // 默认按姓名排序；已手动排序的卡片按手动序号优先。
    cards.sort((a, b) {
      final aManual = a.sortOrder > 0;
      final bManual = b.sortOrder > 0;
      if (aManual != bManual) {
        return aManual ? -1 : 1;
      }
      if (aManual && bManual && a.sortOrder != b.sortOrder) {
        return a.sortOrder.compareTo(b.sortOrder);
      }
      return (a.holderName ?? '').compareTo(b.holderName ?? '');
    });
    return cards;
  }

  /// 长按拖动排序：按新顺序写入手动序号并持久化。
  Future<void> reorder(int oldIndex, int newIndex) async {
    final repo = ref.read(cardRepositoryProvider);
    final current = [...?state.value];
    if (repo == null ||
        oldIndex < 0 ||
        newIndex < 0 ||
        oldIndex >= current.length) {
      return;
    }
    if (newIndex == oldIndex || newIndex >= current.length) {
      return;
    }
    final item = current.removeAt(oldIndex);
    current.insert(newIndex, item);

    final orders = <String, int>{};
    for (var i = 0; i < current.length; i++) {
      orders[current[i].id] = i + 1;
    }
    await repo.updateSortOrders(orders);
    ref.invalidateSelf();
  }

  Future<bool> save(CardRecord card) async {
    final repo = ref.read(cardRepositoryProvider);
    if (repo == null) {
      return false;
    }
    // 先取出后续异步步骤所需的依赖：卡片页可能在后台步骤完成前就被关闭，
    // 那时 autoDispose 的 ref 已不可用。
    final notifications = ref.read(notificationRepositoryProvider);
    final coordinator = ref.read(reminderCoordinatorProvider);
    // 编辑保存时保留已有的手动排序。
    final previous = state.value?.where((c) => c.id == card.id).firstOrNull;
    final merged = previous != null && card.sortOrder == 0
        ? card.withSortOrder(previous.sortOrder)
        : card;
    await repo.save(merged);
    ref.invalidate(categoryCardCountProvider(categoryId));
    // 首页统计（数量/总授信额度/待办）随之刷新。
    ref.read(vaultRevisionProvider.notifier).bump();
    ref.invalidateSelf();
    // 提醒维护放在返回之后执行：解密通知、重挂系统闹钟都与“保存成功”无关，
    // 不应让用户在保存按钮上等待。
    unawaited(_refreshReminders(card.id, notifications, coordinator));
    return true;
  }

  /// Drops stale alarms and snapshots of one card, then recomputes only that
  /// card's reminder tiers. Failures stay silent; the next unlock/resume
  /// recomputes everything anyway.
  Future<void> _refreshReminders(
    String cardId,
    NotificationRepository? notifications,
    ReminderCoordinator coordinator,
  ) async {
    try {
      final localNotifications = LocalNotificationService.instance;
      await localNotifications.initialize();
      // Remove alarms before a date edit so stale tiers cannot fire.
      await localNotifications.cancelRemindersFor(cardId);
      // A date edit reuses the same dedupe keys, so discard old snapshots
      // before recomputation can create reminders for the new deadlines.
      await notifications?.purgeByCard(cardId);
      await coordinator.recomputeFor(cardId);
    } catch (_) {
      // Retried on the next recompute trigger.
    }
  }

  Future<CardRecord> createDraft(CardType type) {
    final now = DateTime.now();
    return Future.value(
      CardRecord(
        id: const Uuid().v4(),
        categoryId: categoryId,
        cardType: type,
        cardNumber: '',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<bool> delete(String id) async {
    final repo = ref.read(cardRepositoryProvider);
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

  /// Dismisses the deleted card's in-app reminders and its system alarms.
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
