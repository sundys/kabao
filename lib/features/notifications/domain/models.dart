import 'dart:convert';

import '../../wallet/domain/models.dart';
import 'reminder_rules.dart';

final class AppNotification {
  AppNotification({
    required this.id,
    required this.type,
    required this.cardId,
    required this.dedupeKey,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.deletedAt,
    this.scheduledFor,
    this.modelVersion = 1,
  });

  final String id;
  final ReminderType type;
  final String cardId;

  /// Unique per (card, reminder type, tier); prevents duplicate inserts.
  final String dedupeKey;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? deletedAt;
  final DateTime? scheduledFor;
  final int modelVersion;

  bool get isRead => readAt != null;
  bool get isDeleted => deletedAt != null;

  Map<String, Object?> toRow() => {
    'id': id,
    'card_id': cardId,
    'dedupe_key': dedupeKey,
    'read_at': readAt?.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'created_at': createdAt.millisecondsSinceEpoch,
    'scheduled_for': scheduledFor?.millisecondsSinceEpoch,
    'model_version': modelVersion,
    'payload': utf8.encode(
      jsonEncode({'title': title, 'body': body, 'type': type.name}),
    ),
  };

  static AppNotification fromRow(Map<String, Object?> row) {
    final payload =
        jsonDecode(utf8.decode(row['payload']! as List<int>))
            as Map<String, Object?>;
    int? epoch(Object? v) => v == null ? null : (v as num).toInt();
    return AppNotification(
      id: row['id']! as String,
      type: ReminderType.values.firstWhere(
        (t) => t.name == payload['type'],
        orElse: () => ReminderType.cardExpiry,
      ),
      cardId: row['card_id'] as String? ?? '',
      dedupeKey: row['dedupe_key']! as String,
      title: payload['title']! as String,
      body: payload['body']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(epoch(row['created_at'])!),
      readAt: epoch(row['read_at']) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(epoch(row['read_at'])!),
      deletedAt: epoch(row['deleted_at']) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(epoch(row['deleted_at'])!),
      scheduledFor: epoch(row['scheduled_for']) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(epoch(row['scheduled_for'])!),
      modelVersion: epoch(row['model_version']) ?? 1,
    );
  }
}

/// Builds the user-facing snapshot for a reminder plan.
AppNotification buildNotification({
  required String id,
  required ReminderPlan plan,
  required BankCategory? category,
  required CardRecord card,
  required DateTime now,
}) {
  final what = plan.type == ReminderType.cardExpiry ? '卡片有效期' : 'U 盾证书';
  final deadlineText = _formatDeadline(plan.deadline);
  final bankName = category?.name ?? '银行卡片';
  // 标题使用卡片类型：借记卡到期提醒 / 信用卡到期提醒 / U 盾证书提醒。
  final title = switch (plan.type) {
    ReminderType.cardExpiry =>
      card.cardType == CardType.debit ? '借记卡到期提醒' : '信用卡到期提醒',
    _ => '$what提醒',
  };
  return _build(
    id: id,
    plan: plan,
    now: now,
    what: what,
    subject: bankName,
    masked: maskedTail(card.cardNumber),
    deadlineText: deadlineText,
    title: title,
  );
}

/// Builds the user-facing snapshot for a certificate reminder plan.
AppNotification buildDocumentNotification({
  required String id,
  required ReminderPlan plan,
  required BankCategory? category,
  required String idNumber,
  required DateTime now,
}) => _build(
  id: id,
  plan: plan,
  now: now,
  what: '证件有效期限',
  subject: category?.name ?? '证件',
  masked: maskedTail(idNumber),
  deadlineText: _formatDeadline(plan.deadline),
);

String _formatDeadline(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/'
    '${d.day.toString().padLeft(2, '0')}';

AppNotification _build({
  required String id,
  required ReminderPlan plan,
  required DateTime now,
  required String what,
  required String subject,
  required String masked,
  required String deadlineText,
  String? title,
}) {
  final daysLeft = plan.deadline
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  final body = daysLeft > 0
      ? '「$subject」（$masked）的$what将于 '
            '$deadlineText 到期，剩余 $daysLeft 天。'
      : daysLeft == 0
      ? '「$subject」（$masked）的$what将于 $deadlineText 到期，今天到期。'
      : '「$subject」（$masked）的$what已于 '
            '$deadlineText 到期，请尽快处理。';
  return AppNotification(
    id: id,
    type: plan.type,
    cardId: plan.cardId,
    dedupeKey: plan.dedupeKey,
    title: title ?? '$what提醒',
    body: body,
    createdAt: now,
    scheduledFor: plan.dueAt,
  );
}
