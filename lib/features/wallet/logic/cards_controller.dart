import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/providers/repositories_providers.dart';
import '../../notifications/logic/reminder_coordinator.dart';
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
    return repo.listByCategory(categoryId);
  }

  Future<bool> save(CardRecord card) async {
    final repo = ref.read(cardRepositoryProvider);
    if (repo == null) {
      return false;
    }
    await repo.save(card);
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
      ref.read(reminderCoordinatorProvider).recompute();
      return true;
    }
    return false;
  }
}
