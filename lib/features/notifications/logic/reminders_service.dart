import 'package:uuid/uuid.dart';

import '../../wallet/data/card_repository.dart';
import '../../wallet/data/category_repository.dart';
import '../../wallet/data/document_repository.dart';
import '../../wallet/domain/document.dart';
import '../../wallet/domain/models.dart';
import '../data/notification_repository.dart';
import '../domain/models.dart';
import '../domain/reminder_rules.dart';

/// Recomputes reminders for every card and certificate document. Idempotent:
/// existing dedupe keys are never re-inserted, so repeated calls on
/// startup/resume/card changes are safe and never duplicate notifications.
Future<List<AppNotification>> recomputeReminders({
  required CardRepository cards,
  CategoryRepository? categories,
  required NotificationRepository notifications,
  DocumentRepository? documents,
  DateTime? now,
  List<String>? knownDedupeKeys,
}) async {
  final at = now ?? DateTime.now();
  final existing = knownDedupeKeys ?? await notifications.existingDedupeKeys();
  final existingSet = Set<String>.from(existing);
  final created = <AppNotification>[];

  for (final type in CardType.values) {
    if (type == CardType.document) {
      continue; // handled by the document pass below
    }
    for (final card in await cards.listByType(type)) {
      BankCategory? category;
      if (categories != null) {
        category = await categories.getById(card.categoryId);
      }
      for (final plan in plansForCard(card, at)) {
        if (existingSet.contains(plan.dedupeKey)) {
          continue;
        }
        final notification = buildNotification(
          id: const Uuid().v4(),
          plan: plan,
          category: category,
          card: card,
          now: at,
        );
        if (await notifications.insertIfAbsent(notification)) {
          existingSet.add(plan.dedupeKey);
          created.add(notification);
        }
      }
    }
  }

  // Certificate documents: three tiers (90/60/30) before the validity end.
  final docs = documents == null
      ? const <DocumentRecord>[]
      : await documents.listAll();
  for (final doc in docs) {
    BankCategory? category;
    if (categories != null) {
      category = await categories.getById(doc.categoryId);
    }
    for (final plan in plansForDocument(doc.id, doc.validTo, at)) {
      if (existingSet.contains(plan.dedupeKey)) {
        continue;
      }
      final notification = buildDocumentNotification(
        id: const Uuid().v4(),
        plan: plan,
        category: category,
        idNumber: doc.idNumber,
        now: at,
      );
      if (await notifications.insertIfAbsent(notification)) {
        existingSet.add(plan.dedupeKey);
        created.add(notification);
      }
    }
  }

  return created;
}
