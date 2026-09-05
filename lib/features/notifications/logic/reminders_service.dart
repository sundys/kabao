import 'package:uuid/uuid.dart';

import '../../wallet/data/card_repository.dart';
import '../../wallet/data/category_repository.dart';
import '../../wallet/data/document_repository.dart';
import '../../wallet/domain/document.dart';
import '../../wallet/domain/models.dart';
import '../data/notification_repository.dart';
import '../domain/models.dart';
import '../domain/reminder_rules.dart';
import '../../../shared/services/local_notification_service.dart';

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
  LocalNotificationService? localNotifications,
}) async {
  final at = now ?? DateTime.now();
  final systemNotifications = localNotifications;
  final notificationCache = <String, AppNotification>{
    for (final notification in await notifications.listAll())
      notification.dedupeKey: notification,
  };
  final existing = knownDedupeKeys ?? notificationCache.keys.toList();
  final deleted = systemNotifications == null
      ? const <String>[]
      : await notifications.deletedDedupeKeys();
  final existingSet = Set<String>.from(existing);
  final deletedSet = Set<String>.from(deleted);
  final created = <AppNotification>[];
  final categoryCache = <String, BankCategory?>{};

  Future<BankCategory?> categoryFor(String categoryId) async {
    if (categories == null) {
      return null;
    }
    if (!categoryCache.containsKey(categoryId)) {
      categoryCache[categoryId] = await categories.getById(categoryId);
    }
    return categoryCache[categoryId];
  }

  for (final type in CardType.values) {
    if (type == CardType.document) {
      continue; // handled by the document pass below
    }
    for (final card in await cards.listByType(type)) {
      final category = await categoryFor(card.categoryId);
      for (final plan in plansForCard(
        card,
        at,
        includeFuture: systemNotifications != null,
      )) {
        if (existingSet.contains(plan.dedupeKey)) {
          if (!deletedSet.contains(plan.dedupeKey)) {
            final existingNotification = notificationCache[plan.dedupeKey];
            final notification = buildNotification(
              id: existingNotification?.id ?? 'system-${plan.dedupeKey}',
              plan: plan,
              category: category,
              card: card,
              now: at,
            );
            if (_systemDeliveryAt(plan).isAfter(at)) {
              final armed = await systemNotifications?.schedule(
                notification,
                now: at,
              );
              if (armed == true && existingNotification != null) {
                await notifications.markSystemScheduled(
                  existingNotification.id,
                );
              }
            } else if (existingNotification != null &&
                existingNotification.systemScheduledAt == null &&
                existingNotification.systemDeliveredAt == null) {
              final delivered = await systemNotifications?.present(
                notification,
              );
              if (delivered == true) {
                await notifications.markSystemDelivered(
                  existingNotification.id,
                );
              }
            }
          }
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
          // [schedule] posts already-missed reminders immediately, while a
          // reminder reached before 09:00 today remains armed for 09:00.
          final deliveredOrArmed = await systemNotifications?.schedule(
            notification,
            now: at,
          );
          if (deliveredOrArmed == true) {
            if (_systemDeliveryAt(plan).isAfter(at)) {
              await notifications.markSystemScheduled(notification.id);
            } else {
              await notifications.markSystemDelivered(notification.id);
            }
          }
        }
      }
    }
  }

  // Certificate documents: three tiers (90/60/30) before the validity end.
  final docs = documents == null
      ? const <DocumentRecord>[]
      : await documents.listAll();
  for (final doc in docs) {
    final category = await categoryFor(doc.categoryId);
    for (final plan in plansForDocument(
      doc.id,
      doc.validTo,
      at,
      includeFuture: systemNotifications != null,
    )) {
      if (existingSet.contains(plan.dedupeKey)) {
        if (!deletedSet.contains(plan.dedupeKey)) {
          final existingNotification = notificationCache[plan.dedupeKey];
          final notification = buildDocumentNotification(
            id: existingNotification?.id ?? 'system-${plan.dedupeKey}',
            plan: plan,
            category: category,
            idNumber: doc.idNumber,
            now: at,
          );
          if (_systemDeliveryAt(plan).isAfter(at)) {
            final armed = await systemNotifications?.schedule(
              notification,
              now: at,
            );
            if (armed == true && existingNotification != null) {
              await notifications.markSystemScheduled(existingNotification.id);
            }
          } else if (existingNotification != null &&
              existingNotification.systemScheduledAt == null &&
              existingNotification.systemDeliveredAt == null) {
            final delivered = await systemNotifications?.present(notification);
            if (delivered == true) {
              await notifications.markSystemDelivered(existingNotification.id);
            }
          }
        }
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
        // Keep the Android delivery time consistent with card reminders.
        final deliveredOrArmed = await systemNotifications?.schedule(
          notification,
          now: at,
        );
        if (deliveredOrArmed == true) {
          if (_systemDeliveryAt(plan).isAfter(at)) {
            await notifications.markSystemScheduled(notification.id);
          } else {
            await notifications.markSystemDelivered(notification.id);
          }
        }
      }
    }
  }

  return created;
}

DateTime _systemDeliveryAt(ReminderPlan plan) =>
    DateTime(plan.dueAt.year, plan.dueAt.month, plan.dueAt.day, 9);
