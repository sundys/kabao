import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kabao/features/wallet/domain/models.dart';
import 'package:kabao/features/wallet/presentation/pages/wallet_home_page.dart';
import 'package:kabao/features/wallet/presentation/pages/wallet_page.dart';

void main() {
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: WalletHomePage())),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpTypePage(WidgetTester tester, CardType type) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: WalletTypePage(cardType: type)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('首页展示胶囊搜索、圆形统计与仿真卡片，无悬浮搜索按钮', (tester) async {
    await pumpHome(tester);

    expect(find.byKey(const Key('capsule-search-bar')), findsOneWidget);
    // 三个圆形统计与三张仿真卡。
    expect(find.byKey(const Key('count-circle-debit')), findsOneWidget);
    expect(find.byKey(const Key('count-circle-credit')), findsOneWidget);
    expect(find.byKey(const Key('count-circle-document')), findsOneWidget);
    expect(find.byKey(const Key('simulated-card-debit')), findsOneWidget);
    expect(find.byKey(const Key('simulated-card-credit')), findsOneWidget);
    // 未解锁金库时数量为 0（PageView 惰性构建，至少渲染前两页）。
    expect(find.text('0 张'), findsAtLeastNWidgets(2));
    // 信用卡卡面展示总授信额度占位。
    expect(find.text('总授信额度'), findsOneWidget);
    expect(find.text('¥ --'), findsOneWidget);
    // 待办空态。
    expect(find.text('暂无到期事项，一切正常'), findsOneWidget);
    // 右下角搜索 FAB 已移除。
    expect(find.byKey(const Key('wallet-search-button')), findsNothing);
  });

  testWidgets('首页胶囊搜索打开磨砂搜索层，默认不展示任何记录', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('capsule-search-bar')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wallet-search-field')), findsOneWidget);
    // 未输入关键词时只给提示，不泄露默认的卡片列表。
    expect(find.text('输入关键词搜索卡片或证件'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('分类页为固定单类型页，无标签栏与滑动切换', (tester) async {
    await pumpTypePage(tester, CardType.credit);

    expect(find.text('还没有信用卡分类'), findsOneWidget);
    expect(find.byKey(const Key('add-category-button')), findsOneWidget);
    // 顶部胶囊搜索限定当前类型。
    expect(find.byKey(const Key('type-page-search-bar')), findsOneWidget);
    expect(find.text('搜索信用卡'), findsOneWidget);
    // 固定页不出现其他类型的标签内容。
    expect(find.text('还没有借记卡分类'), findsNothing);
    expect(find.text('还没有证件分类'), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
  });

  testWidgets('借记卡固定页显示对应空态与搜索提示', (tester) async {
    await pumpTypePage(tester, CardType.debit);

    expect(find.text('还没有借记卡分类'), findsOneWidget);
    expect(find.text('搜索借记卡'), findsOneWidget);
  });

  testWidgets('首页仿真卡点击进入对应类型固定页（go_router）', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const WalletHomePage()),
        GoRoute(
          path: '/wallet/type/:type',
          builder: (_, state) => WalletTypePage(
            cardType: CardType.values.firstWhere(
              (t) => t.name == state.pathParameters['type'],
              orElse: () => CardType.debit,
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('simulated-card-debit')), findsOneWidget);

    await tester.tap(find.byKey(const Key('simulated-card-debit')));
    await tester.pumpAndSettle();

    expect(find.text('还没有借记卡分类'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
  });
}
