import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/features/notifications/logic/todo_items.dart';
import 'package:kabao/features/wallet/domain/document.dart';
import 'package:kabao/features/wallet/domain/models.dart';

CardRecord _card({
  required String id,
  String categoryId = 'cat-1',
  CardType type = CardType.credit,
  int? expiryMonth,
  int? expiryYear,
  DateTime? uShield,
}) {
  final now = DateTime(2026, 1, 1);
  return CardRecord(
    id: id,
    categoryId: categoryId,
    cardType: type,
    cardNumber: '622236562322$id',
    expiryMonth: expiryMonth,
    expiryYear: expiryYear,
    uShieldExpiryDate: uShield,
    createdAt: now,
    updatedAt: now,
  );
}

BankCategory _category(String id, String name) {
  final now = DateTime(2026, 1, 1);
  return BankCategory(
    id: id,
    cardType: CardType.credit,
    name: name,
    createdAt: now,
    updatedAt: now,
  );
}

DocumentRecord _document({
  required String id,
  DateTime? validTo,
  bool permanent = false,
}) {
  final now = DateTime(2026, 1, 1);
  return DocumentRecord(
    id: id,
    categoryId: 'cat-9',
    holderName: '张三',
    idNumber: '110000199001010000',
    issuer: '公安局',
    validTo: validTo,
    validityIsPermanent: permanent,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  final today = DateTime(2026, 10, 24);

  test('到期/临近到期事项进入待办并按紧急度排序', () {
    final items = buildTodoItems(
      cards: [
        // 有效期 2026/10 → 月末 10/31 截止，剩余 7 天。
        _card(
          id: '01',
          type: CardType.debit,
          expiryMonth: 10,
          expiryYear: 2026,
        ),
        // 剩余 70 天的 U 盾。
        _card(id: '02', uShield: DateTime(2027, 1, 2)),
        // 有效期 2026/11 → 11/30 截止，剩余 37 天。
        _card(id: '03', expiryMonth: 11, expiryYear: 2026),
      ],
      documents: [
        _document(id: 'd1', validTo: DateTime(2026, 12, 30)), // 剩余 67 天。
        _document(id: 'd2', permanent: true), // 长期有效：不进入待办。
      ],
      categoryById: {
        'cat-1': _category('cat-1', '工商银行'),
        'cat-9': _category('cat-9', '身份证'),
      },
      today: today,
    );

    expect(items.map((i) => i.daysLeft).toList(), [7, 37, 67, 70]);
    expect(items[0].kindLabel, '借记卡有效期');
    expect(items[0].expired, isFalse);
    expect(items[1].kindLabel, '信用卡有效期');
    expect(items[1].subject, '工商银行');
    expect(items[2].kindLabel, '证件有效期');
    expect(items[3].kindLabel, 'U盾证书');
  });

  test('窗口外的事项不进入待办；无截止日的记录被跳过', () {
    final items = buildTodoItems(
      cards: [
        _card(id: '01', uShield: DateTime(2027, 6, 1)), // 剩余 >90 天。
        _card(id: '02'), // 无任何日期。
      ],
      documents: [_document(id: 'd1')], // 非长期但 validTo 为空。
      categoryById: const {},
      today: today,
    );
    expect(items, isEmpty);
  });

  test('很久之前过期的旧卡仍保留在待办中', () {
    final items = buildTodoItems(
      cards: [_card(id: '01', uShield: DateTime(2024, 1, 1))],
      documents: const [],
      categoryById: const {},
      today: today,
    );
    expect(items.single.expired, isTrue);
    expect(items.single.daysLeft, lessThan(0));
  });
}
