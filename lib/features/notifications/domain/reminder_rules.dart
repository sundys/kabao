import '../../wallet/domain/models.dart';

enum ReminderType { cardExpiry, uShieldExpiry, documentExpiry }

int get reminderDaysBeforeExpiry => 90;

const List<int> reminderTiers = [90, 60, 30, 15];

/// Bank card validity: three tiers plus a same-day reminder.
const List<int> cardExpiryReminderTiers = [90, 60, 30, 0];

/// Documents use three tiers (90/60/30) per product decision.
const List<int> documentReminderTiers = [90, 60, 30];

/// Days after the deadline during which a skipped tier is still materialized
/// (covers devices being off / app not opened around the mark).
const int gracePeriodDays = 15;

final class ReminderPlan {
  const ReminderPlan({
    required this.type,
    required this.cardId,
    required this.tier,
    required this.deadline,
    required this.dueAt,
  });

  final ReminderType type;
  final String cardId;
  final int tier;
  final DateTime deadline;
  final DateTime dueAt;

  String get dedupeKey =>
      '${type == ReminderType.cardExpiry
          ? 'expiry'
          : type == ReminderType.uShieldExpiry
          ? 'ushield'
          : 'docexpiry'}:$cardId:$tier';
}

/// Enumerates every possible reminder key for one card or document record.
///
/// The same identifier is used for card records and certificate documents,
/// but their key prefixes keep their notification IDs distinct. This allows a
/// changed or deleted record to cancel both posted banners and pending alarms
/// without retaining sensitive field values outside the encrypted database.
List<String> reminderDedupeKeysFor(String recordId) => [
  for (final tier in cardExpiryReminderTiers) 'expiry:$recordId:$tier',
  for (final tier in reminderTiers) 'ushield:$recordId:$tier',
  for (final tier in documentReminderTiers) 'docexpiry:$recordId:$tier',
];

/// Computes which reminders should exist for a certificate document as of
/// [today]: three tiers (90/60/30 days) before the validity end date.
List<ReminderPlan> plansForDocument(
  String documentId,
  DateTime? validTo,
  DateTime today, {
  bool includeFuture = false,
}) {
  if (validTo == null) {
    return const [];
  }
  final today0 = _dateOnly(today);
  final deadline = _dateOnly(validTo);
  final daysUntil = deadline.difference(today0).inDays;
  return [
    for (final tier in documentReminderTiers)
      if ((includeFuture || daysUntil <= tier) && daysUntil >= -gracePeriodDays)
        ReminderPlan(
          type: ReminderType.documentExpiry,
          cardId: documentId,
          tier: tier,
          deadline: deadline,
          dueAt: deadline.subtract(Duration(days: tier)),
        ),
  ];
}

/// The expiry `MM/YY` deadline is the last day of that month.
DateTime expiryDeadline(int year, int month) {
  if (month < 1 || month > 12) {
    throw ArgumentError.value(month, 'month', 'must be 1-12');
  }
  // Day 0 of the next month = last day of the given month.
  return DateTime(year, month + 1, 0);
}

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Computes which reminders should exist for a card as of [today].
///
/// A tier fires once when `daysUntilDeadline <= tier` (and within the grace
/// window), so reminders are never lost when the app cannot run in the
/// background; dedupe keys guarantee each tier is stored only once.
List<ReminderPlan> plansForCard(
  CardRecord card,
  DateTime today, {
  bool includeFuture = false,
}) {
  final today0 = _dateOnly(today);
  final plans = <ReminderPlan>[];

  void collect(ReminderType type, DateTime? deadline, List<int> tiers) {
    if (deadline == null) {
      return;
    }
    final daysUntil = _dateOnly(deadline).difference(today0).inDays;
    for (final tier in tiers) {
      if ((includeFuture || daysUntil <= tier) &&
          daysUntil >= -gracePeriodDays) {
        plans.add(
          ReminderPlan(
            type: type,
            cardId: card.id,
            tier: tier,
            deadline: deadline,
            dueAt: deadline.subtract(Duration(days: tier)),
          ),
        );
      }
    }
  }

  if (card.expiryMonth != null && card.expiryYear != null) {
    collect(
      ReminderType.cardExpiry,
      expiryDeadline(card.expiryYear!, card.expiryMonth!),
      cardExpiryReminderTiers,
    );
  }
  collect(ReminderType.uShieldExpiry, card.uShieldExpiryDate, reminderTiers);

  return plans;
}

String maskedTail(String normalizedCardNumber) {
  if (normalizedCardNumber.length < 8) {
    return '*' * normalizedCardNumber.length;
  }
  return '**** ${normalizedCardNumber.substring(normalizedCardNumber.length - 4)}';
}
