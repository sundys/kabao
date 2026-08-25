import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/features/wallet/domain/models.dart';
import 'package:kabao/features/wallet/presentation/widgets/card_tile.dart';
import 'package:kabao/shared/utils/card_number_utils.dart';

CardRecord _card() {
  final now = DateTime.now();
  return CardRecord(
    id: 'card-1',
    categoryId: 'cat',
    cardType: CardType.debit,
    holderName: '张三',
    cardNumber: '6222365623223699',
    expiryMonth: 2,
    expiryYear: 2027,
    note: '工商银行工资卡备注内容很长需要截断显示',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  testWidgets('填了姓名的卡片：标题显示姓名，副标题第一行卡号、第二行有效期与备注', (tester) async {
    final card = _card();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardTile(card: card, categoryColor: const Color(0xFFDCEFE3)),
        ),
      ),
    );

    expect(find.text('张三'), findsOneWidget);
    // 第一行：脱敏卡号。
    expect(find.textContaining('6222 **** **** 3699'), findsOneWidget);
    // 第二行：有效期 + 截断备注（超 6 字）。
    expect(find.textContaining('有效期 02/27 工商银行工资…'), findsOneWidget);
  });

  group('buildSubtitle 拼接规则', () {
    final masked = CardNumberValidation.maskForList('6222365623223699');

    test('有姓名：第一行卡号，第二行有效期 + 备注', () {
      expect(
        CardTile.buildSubtitle(
          showCardNumber: true,
          masked: masked,
          expiryText: '02/27',
          remarkShort: '工商银行工资…',
        ),
        '$masked\n有效期 02/27 工商银行工资…',
      );
    });

    test('备注为空时第二行只有有效期', () {
      expect(
        CardTile.buildSubtitle(
          showCardNumber: true,
          masked: masked,
          expiryText: '02/27',
          remarkShort: '',
        ),
        '$masked\n有效期 02/27',
      );
    });

    test('无姓名（标题即卡号）时副标题不重复显示卡号', () {
      expect(
        CardTile.buildSubtitle(
          showCardNumber: false,
          masked: masked,
          expiryText: '02/27',
          remarkShort: '备注',
        ),
        '有效期 02/27 备注',
      );
    });
  });
}
