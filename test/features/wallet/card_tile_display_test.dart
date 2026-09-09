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
  testWidgets('填了姓名的卡片：第一行姓名加备注，第二行显示脱敏卡号', (tester) async {
    final card = _card();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardTile(card: card, categoryColor: const Color(0xFFDCEFE3)),
        ),
      ),
    );

    expect(find.text('张三 工商银行工资卡备'), findsOneWidget);
    // 第二行：脱敏卡号。
    expect(find.textContaining('6222 **** **** 3699'), findsOneWidget);
  });

  testWidgets('ReorderableListView 中的卡片点击仍触发详情回调', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReorderableListView.builder(
            itemCount: 1,
            onReorderItem: (_, _) {},
            itemBuilder: (context, index) => Padding(
              key: ValueKey(index),
              padding: const EdgeInsets.only(bottom: 8),
              child: CardTile(
                card: _card(),
                categoryColor: const Color(0xFFDCEFE3),
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.textContaining('张三'));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('姓名和备注只有不可见字符时显示脱敏卡号', (tester) async {
    final now = DateTime.now();
    final card = CardRecord(
      id: 'card-1',
      categoryId: 'cat',
      cardType: CardType.debit,
      holderName: '\u200B',
      cardNumber: '6222365623223699',
      note: '\uFEFF',
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardTile(card: card, categoryColor: const Color(0xFFDCEFE3)),
        ),
      ),
    );

    expect(find.text('6222 **** **** 3699'), findsOneWidget);
  });

  testWidgets('卡片条目使用紧凑的两行高度', (tester) async {
    final card = _card();
    await tester.binding.setSurfaceSize(const Size(600, 200));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardTile(card: card, categoryColor: const Color(0xFFDCEFE3)),
        ),
      ),
    );

    expect(tester.getSize(find.byType(ListTile)).height, lessThan(72));
  });

  group('buildSubtitle 显示规则', () {
    final masked = CardNumberValidation.maskForList('6222365623223699');

    test('有姓名：副标题显示脱敏卡号', () {
      expect(
        CardTile.buildSubtitle(showCardNumber: true, masked: masked),
        masked,
      );
    });

    test('有姓名但没有额外详情时仍显示脱敏卡号', () {
      expect(
        CardTile.buildSubtitle(showCardNumber: true, masked: masked),
        masked,
      );
    });

    test('无姓名：副标题为空，标题已显示卡号', () {
      expect(CardTile.buildSubtitle(showCardNumber: false, masked: masked), '');
    });
  });
}
