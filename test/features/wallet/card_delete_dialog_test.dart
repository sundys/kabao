import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/app/theme/app_theme.dart';
import 'package:kabao/features/wallet/domain/models.dart';
import 'package:kabao/features/wallet/presentation/pages/card_detail_page.dart';

CardRecord _card() {
  final now = DateTime(2026, 1, 1);
  return CardRecord(
    id: 'card-1',
    categoryId: 'cat',
    cardType: CardType.debit,
    cardNumber: '6222000012345678',
    holderName: '张三',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  /// 使用应用真实主题：全局 FilledButton 主题带 minimumSize: Size.fromHeight(48)
  /// （宽度无限），曾导致 OverflowBar 把「取消」挤到「删除」上方单独一行。
  Future<void> pumpDetail(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: CardDetailPage(card: _card()),
        ),
      ),
    );
  }

  testWidgets('删除确认框的两个按钮同行、等宽且中间留间隔', (tester) async {
    await pumpDetail(tester);

    await tester.tap(find.text('删除卡片'));
    await tester.pumpAndSettle();

    final cancel = find.widgetWithText(OutlinedButton, '取消');
    final delete = find.widgetWithText(FilledButton, '删除');
    expect(cancel, findsOneWidget);
    expect(delete, findsOneWidget);

    final cancelRect = tester.getRect(cancel);
    final deleteRect = tester.getRect(delete);

    // 同一行：垂直中心一致。
    expect(cancelRect.center.dy, moreOrLessEquals(deleteRect.center.dy));
    // 取消在左、删除在右。
    expect(cancelRect.right, lessThan(deleteRect.left));
    // 各占约一半宽度（允许边框/内边距造成的细微差异）。
    expect(cancelRect.width, moreOrLessEquals(deleteRect.width, epsilon: 1));
    expect(cancelRect.width, greaterThan(100));
    // 中间留出间隔。
    expect(deleteRect.left - cancelRect.right, greaterThanOrEqualTo(12));
  });

  testWidgets('点击取消不会删除卡片', (tester) async {
    await pumpDetail(tester);

    await tester.tap(find.text('删除卡片'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '取消'));
    await tester.pumpAndSettle();

    expect(find.text('删除后无法恢复，确定删除这张卡片吗？'), findsNothing);
    expect(find.text('卡片详情'), findsOneWidget);
  });
}
