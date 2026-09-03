import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/providers/repositories_providers.dart';
import '../../notifications/logic/reminder_coordinator.dart';
import '../../../shared/services/local_notification_service.dart';
import '../domain/document.dart';
import 'categories_controller.dart';

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
    await LocalNotificationService.instance.initialize();
    await LocalNotificationService.instance.cancelRemindersFor(document.id);
    await repo.save(document);
    ref.invalidate(categoryCardCountProvider(categoryId));
    // Validity-date edits reuse dedupe keys; rebuild the encrypted snapshots.
    await ref.read(notificationRepositoryProvider)?.purgeByCard(document.id);
    ref.invalidateSelf();
    // Reminder tiers may change with the new dates; idempotent recompute.
    await ref.read(reminderCoordinatorProvider).recompute();
    return true;
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
    final removed = await repo.delete(id);
    if (removed > 0) {
      ref.invalidateSelf();
      ref.invalidate(categoryCardCountProvider(categoryId));
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
