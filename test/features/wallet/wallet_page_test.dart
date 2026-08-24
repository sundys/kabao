import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/features/wallet/presentation/pages/wallet_page.dart';

void main() {
  Future<void> pumpWallet(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: WalletPage())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('默认显示借记卡标签，可滑动/点击切换到信用卡', (tester) async {
    await pumpWallet(tester);

    expect(find.text('借记卡'), findsOneWidget);
    expect(find.text('还没有借记卡分类'), findsOneWidget);

    await tester.tap(find.text('信用卡'));
    await tester.pumpAndSettle();

    expect(find.text('还没有信用卡分类'), findsOneWidget);
    expect(find.text('还没有借记卡分类'), findsNothing);
  });

  testWidgets('空状态提示创建分类入口', (tester) async {
    await pumpWallet(tester);
    expect(find.text('新建分类'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
