import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/features/wallet/domain/models.dart';
import 'package:kabao/features/wallet/presentation/widgets/card_edit_page.dart';

CardRecord _draft() {
  final now = DateTime(2026, 1, 1);
  return CardRecord(
    id: 'card-1',
    categoryId: 'cat',
    cardType: CardType.credit,
    cardNumber: '',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  testWidgets('额度输入框存在，计入总额复选框默认选中且可切换', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: CardEditPage(card: _draft(), isNew: true)),
      ),
    );

    expect(find.byKey(const Key('card-credit-limit-field')), findsOneWidget);
    final checkbox = find.byType(Checkbox);
    expect(checkbox, findsOneWidget);
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);

    await tester.tap(find.byKey(const Key('card-include-in-total-toggle')));
    await tester.pump();
    expect(tester.widget<Checkbox>(checkbox).value, isFalse);
  });

  testWidgets('编辑已有卡片时回填额度与计入状态', (tester) async {
    final now = DateTime(2026, 1, 1);
    final card = CardRecord(
      id: 'card-1',
      categoryId: 'cat',
      cardType: CardType.credit,
      cardNumber: '6222111111111111',
      creditLimit: 50000,
      includeInTotal: false,
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: CardEditPage(card: card, isNew: false)),
      ),
    );

    expect(find.text('50000'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });

  testWidgets('额度输入非法内容时校验失败并保留输入', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: CardEditPage(card: _draft(), isNew: true)),
      ),
    );

    // 9 位数字超过 8 位上限（负号会被输入过滤器直接拦截）。
    await tester.enterText(
      find.byKey(const Key('card-credit-limit-field')),
      '123456789',
    );
    await tester.ensureVisible(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(find.text('额度应为 1-8 位数字（元）'), findsOneWidget);
    expect(find.text('123456789'), findsOneWidget);
  });
}
