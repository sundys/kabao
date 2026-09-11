import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/features/wallet/domain/models.dart';
import 'package:kabao/features/wallet/presentation/widgets/card_tile.dart';

CardRecord _card() {
  final now = DateTime.now();
  return CardRecord(
    id: 'card-1',
    categoryId: 'cat',
    cardType: CardType.debit,
    holderName: '张三',
    cardKind: '白金卡',
    cardNumber: '6222365623223699',
    expiryMonth: 2,
    expiryYear: 2027,
    note: '工商银行工资卡备注内容很长需要截断显示',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  testWidgets('三行布局：姓名+卡种、脱敏卡号、有效期+备注', (tester) async {
    final card = _card();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardTile(card: card, categoryColor: const Color(0xFFDCEFE3)),
        ),
      ),
    );

    // 第一行：姓名 + 卡种。
    expect(find.text('张三'), findsOneWidget);
    expect(find.text('白金卡'), findsOneWidget);
    // 第二行：脱敏卡号。
    expect(find.textContaining('6222 **** **** 3699'), findsOneWidget);
    // 第三行：有效期 + 备注。
    expect(find.text('02/27  工商银行工资卡备注内容很长需要截断显示'), findsOneWidget);
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

    await tester.tap(find.text('张三'));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('卡种和备注为空时三行仍然对齐', (tester) async {
    final now = DateTime.now();
    final card = CardRecord(
      id: 'card-1',
      categoryId: 'cat',
      cardType: CardType.debit,
      holderName: '李四',
      cardNumber: '6222365623223699',
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

    expect(find.text('李四'), findsOneWidget);
    expect(find.textContaining('6222 **** **** 3699'), findsOneWidget);
    // 第三行为空，但行高度仍保留以保持对齐。
    expect(
      find.byWidgetPredicate((w) => w is SizedBox && w.height == 20),
      findsNWidgets(3),
    );
  });

  testWidgets('姓名和卡种只有不可见字符时第一行留空，卡号正常显示', (tester) async {
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

  testWidgets('卡片条目三行固定行高', (tester) async {
    final card = _card();
    await tester.binding.setSurfaceSize(const Size(600, 300));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardTile(card: card, categoryColor: const Color(0xFFDCEFE3)),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate((w) => w is SizedBox && w.height == 20),
      findsNWidgets(3),
    );
  });
}
