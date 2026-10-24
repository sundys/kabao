import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/repositories_providers.dart';
import '../../wallet/domain/document.dart';
import '../../wallet/domain/models.dart';
import '../../wallet/logic/wallet_summary_providers.dart';
import '../domain/reminder_rules.dart';

/// 待办窗口：与第一档提醒一致，到期前 90 天开始进入待办。
const int todoWindowDays = 90;

/// 一条待办：某张卡片/证件的一个截止日期临近或已过期。
final class TodoItem {
  const TodoItem({
    required this.kindLabel,
    required this.subject,
    required this.maskedTail,
    required this.deadline,
    required this.daysLeft,
    required this.routeLocation,
    this.card,
    this.document,
  });

  /// 到期内容，如“借记卡有效期”“U 盾证书”“证件有效期”。
  final String kindLabel;

  /// 所属分类名（如工商银行、身份证）。
  final String subject;

  /// 脱敏尾号，如“**** 1234”。
  final String maskedTail;

  final DateTime deadline;

  /// 距到期天数：负数表示已过期。
  final int daysLeft;

  /// 点击待办跳转的目标路由。
  final String routeLocation;

  /// 跳转携带的记录（卡片或证件，用于详情页直接渲染）。
  final CardRecord? card;
  final DocumentRecord? document;

  bool get expired => daysLeft < 0;
}

/// 汇总三种卡片的到期事项：卡片有效期、U 盾证书、证件有效期。
/// 已到期的全部保留；未到期的在 [todoWindowDays] 窗口内进入待办。
/// 纯函数便于单元测试。
List<TodoItem> buildTodoItems({
  required Iterable<CardRecord> cards,
  required Iterable<DocumentRecord> documents,
  required Map<String, BankCategory> categoryById,
  required DateTime today,
}) {
  final today0 = DateTime(today.year, today.month, today.day);
  final items = <TodoItem>[];

  void add({
    required String kindLabel,
    required String subject,
    required String masked,
    required DateTime? deadline,
    required String routeLocation,
    CardRecord? card,
    DocumentRecord? document,
  }) {
    if (deadline == null) {
      return;
    }
    final daysLeft = DateTime(
      deadline.year,
      deadline.month,
      deadline.day,
    ).difference(today0).inDays;
    if (daysLeft > todoWindowDays) {
      return;
    }
    items.add(
      TodoItem(
        kindLabel: kindLabel,
        subject: subject,
        maskedTail: masked,
        deadline: deadline,
        daysLeft: daysLeft,
        routeLocation: routeLocation,
        card: card,
        document: document,
      ),
    );
  }

  for (final card in cards) {
    final subject = categoryById[card.categoryId]?.name ?? '银行卡片';
    final masked = maskedTail(card.cardNumber);
    final typePrefix = card.cardType == CardType.debit ? '借记卡' : '信用卡';
    if (card.expiryMonth != null && card.expiryYear != null) {
      add(
        kindLabel: '$typePrefix有效期',
        subject: subject,
        masked: masked,
        deadline: expiryDeadline(card.expiryYear!, card.expiryMonth!),
        routeLocation: '/wallet/card/${card.id}',
        card: card,
      );
    }
    add(
      kindLabel: 'U盾证书',
      subject: subject,
      masked: masked,
      deadline: card.uShieldExpiryDate,
      routeLocation: '/wallet/card/${card.id}',
      card: card,
    );
  }

  for (final document in documents) {
    if (document.validityIsPermanent) {
      continue;
    }
    add(
      kindLabel: '证件有效期',
      subject: categoryById[document.categoryId]?.name ?? '证件',
      masked: maskedTail(document.idNumber),
      deadline: document.validTo,
      routeLocation: '/wallet/document/${document.id}',
      document: document,
    );
  }

  items.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
  return items;
}

/// 首页待办列表数据源。
final todoItemsProvider = FutureProvider.autoDispose<List<TodoItem>>((
  ref,
) async {
  ref.watch(vaultRevisionProvider);
  final cardRepo = ref.watch(cardRepositoryProvider);
  final categoryRepo = ref.watch(categoryRepositoryProvider);
  final documentRepo = ref.watch(documentRepositoryProvider);
  if (cardRepo == null || categoryRepo == null || documentRepo == null) {
    return const [];
  }
  final categoryById = {
    for (final category in await categoryRepo.listAll()) category.id: category,
  };
  return buildTodoItems(
    cards: [
      ...await cardRepo.listByType(CardType.debit),
      ...await cardRepo.listByType(CardType.credit),
    ],
    documents: await documentRepo.listAll(),
    categoryById: categoryById,
    today: DateTime.now(),
  );
});
