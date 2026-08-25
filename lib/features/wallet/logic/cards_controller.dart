import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/providers/repositories_providers.dart';
import '../../notifications/logic/reminder_coordinator.dart';
import '../../../shared/services/local_notification_service.dart';
import '../domain/models.dart';

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
    // Remove alarms before a date edit so stale tiers cannot fire.
    await LocalNotificationService.instance.initialize();
    await LocalNotificationService.instance.cancelRemindersFor(card.id);
    // 编辑保存时保留已有的手动排序。
    final previous = state.value?.where((c) => c.id == card.id).firstOrNull;
    final merged = previous != null && card.sortOrder == 0
        ? card.withSortOrder(previous.sortOrder)
        : card;
    await repo.save(merged);
    // A date edit reuses the same dedupe keys, so discard old snapshots before
    // recomputation can create reminders for the new deadlines.
    await ref.read(notificationRepositoryProvider)?.purgeByCard(card.id);
    ref.invalidateSelf();
    // Reminder tiers may change with the new dates; idempotent recompute.
    await ref.read(reminderCoordinatorProvider).recompute();
    return true;
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
    final removed = await repo.delete(id);
    if (removed > 0) {
      ref.invalidateSelf();
      // Drop reminders belonging to the deleted card.
      final notifications = ref.read(notificationRepositoryProvider);
      await notifications?.deleteByCard(id);
      await LocalNotificationService.instance.initialize();
      await LocalNotificationService.instance.cancelRemindersFor(id);
      await ref.read(reminderCoordinatorProvider).recompute();
      return true;
    }
    return false;
  }
}
