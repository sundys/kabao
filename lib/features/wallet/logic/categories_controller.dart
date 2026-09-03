import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/providers/repositories_providers.dart';
import '../domain/models.dart';

/// Loads and mutates the bank categories of one card type. Rebuilds whenever
/// the underlying repository appears/disappears (lock/unlock).
final categoriesProvider = AsyncNotifierProvider.autoDispose
    .family<CategoriesController, List<BankCategory>, CardType>(
      (arg) => CategoriesController()..cardType = arg,
    );

/// Reads the number of records in a category without loading encrypted
/// card/document payloads into memory.
final categoryCardCountProvider = FutureProvider.autoDispose
    .family<int, String>((ref, categoryId) async {
      final repo = ref.watch(categoryRepositoryProvider);
      return repo?.countCardsInCategory(categoryId) ?? 0;
    });

class CategoriesController extends AsyncNotifier<List<BankCategory>> {
  late CardType cardType;

  @override
  Future<List<BankCategory>> build() async {
    final repo = ref.watch(categoryRepositoryProvider);
    if (repo == null) {
      return const [];
    }
    return repo.listByType(cardType);
  }

  Future<bool> add(String name) async {
    final repo = ref.read(categoryRepositoryProvider);
    if (repo == null) {
      return false;
    }
    final existing = state.value ?? const <BankCategory>[];
    final now = DateTime.now();
    await repo.save(
      BankCategory(
        id: const Uuid().v4(),
        cardType: cardType,
        name: name.trim(),
        sortOrder: existing.length,
        createdAt: now,
        updatedAt: now,
      ),
    );
    ref.invalidateSelf();
    return true;
  }

  Future<bool> rename(String id, String name) async {
    final repo = ref.read(categoryRepositoryProvider);
    if (repo == null) {
      return false;
    }
    final current = await repo.getById(id);
    if (current == null) {
      return false;
    }
    await repo.save(
      current.copyWith(name: name.trim(), updatedAt: DateTime.now()),
    );
    ref.invalidateSelf();
    return true;
  }

  /// Deletes only when the category has no cards left; callers surface the
  /// remaining count for confirmation beforehand.
  Future<bool> delete(String id) async {
    final repo = ref.read(categoryRepositoryProvider);
    if (repo == null) {
      return false;
    }
    final cardCount = await repo.countCardsInCategory(id);
    if (cardCount > 0) {
      return false;
    }
    await repo.delete(id);
    ref.invalidateSelf();
    return true;
  }

  Future<int> cardCount(String id) async {
    final repo = ref.read(categoryRepositoryProvider);
    if (repo == null) {
      return 0;
    }
    return repo.countCardsInCategory(id);
  }
}
