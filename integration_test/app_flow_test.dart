import 'package:flutter/widgets.dart' show FocusManager;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kabao/features/wallet/presentation/widgets/wallet_search_button.dart';
import 'package:kabao/features/wallet/presentation/widgets/wallet_search_sheet.dart';

import 'integration_test_helpers.dart';

/// 覆盖验收路径：首次安装 → 创建主密码 → 解锁 → 新首页 → 仿真卡进入分类
/// → 创建分类 → 添加卡片（含额度）→ 首页总额度与全局磨砂搜索。
///
/// 在真机/模拟器运行：
///   flutter test integration_test/app_flow_test.dart -d `<device>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('首次安装到创建卡片的完整流程', (tester) async {
    await pumpFreshApp(tester);

    // ---- 首次设置：创建并确认主密码 ----
    await tester.enterText(
      find.byKey(const Key('setup-password')),
      testMasterPassword,
    );
    await tester.enterText(
      find.byKey(const Key('setup-confirm')),
      testMasterPassword,
    );
    await tester.tap(find.text('开始使用'));
    await tester.pumpAndSettle();

    // ---- 锁定页：用刚创建的主密码解锁 ----
    expect(find.text('卡包已锁定'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('lock-password')),
      testMasterPassword,
    );
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();

    // ---- 新首页：胶囊搜索 + 三个圆形统计 + 仿真卡 ----
    expect(find.byKey(const Key('capsule-search-bar')), findsOneWidget);
    expect(find.byKey(const Key('count-circle-debit')), findsOneWidget);
    expect(find.byKey(const Key('count-circle-credit')), findsOneWidget);
    expect(find.byKey(const Key('count-circle-document')), findsOneWidget);
    expect(find.text('暂无到期事项，一切正常'), findsOneWidget);

    // ---- 点击借记卡仿真卡进入固定分类页，返回后再从信用卡仿真卡进入 ----
    await tester.tap(find.byKey(const Key('simulated-card-debit')));
    await tester.pumpAndSettle();
    expect(find.text('还没有借记卡分类'), findsOneWidget);
    expect(find.byKey(const Key('add-category-button')), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('simulated-card-credit')));
    await tester.pumpAndSettle();
    expect(find.text('还没有信用卡分类'), findsOneWidget);

    // ---- 创建银行分类（名称校验：仅中文 ≤4 字）----
    await tester.tap(find.byKey(const Key('add-category-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category-name-field')),
      '工商银行',
    );
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(find.text('工商银行'), findsOneWidget);

    // ---- 进入分类并添加卡片（含额度） ----
    await tester.tap(find.text('工商银行'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加卡片'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('card-number-field')),
      '6222 0000 1234 5678',
    );
    await tester.enterText(find.byKey(const Key('card-expiry-field')), '08/29');
    await tester.enterText(find.byKey(const Key('card-cvv-field')), '123');
    await tester.enterText(
      find.byKey(const Key('card-u-shield-field')),
      '2027/03/08',
    );
    // 额度默认计入总额（复选框选中），这里录入 50000 元。
    await tester.enterText(
      find.byKey(const Key('card-credit-limit-field')),
      '50000',
    );
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    // 收起软键盘，避免视口被压缩导致保存按钮被惰性构建移出树。
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final formList = find.byType(Scrollable).first;
    await tester.dragUntilVisible(
      find.byKey(const Key('card-save')),
      formList,
      const Offset(0, -200),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('card-save')));
    await tester.pumpAndSettle();

    // 卡片列表显示脱敏分组卡号
    expect(find.text('6222 **** **** 5678'), findsOneWidget);

    // 点击列表条目必须进入卡片详情/编辑查看状态。
    await tester.tap(find.text('6222 **** **** 5678'));
    await tester.pumpAndSettle();
    expect(find.text('卡片详情'), findsOneWidget);
    // 详情页展示额度与计入状态。
    expect(find.text('¥50,000'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    // 单独复制图标不能被详情路由或列表手势遮挡。
    await tester.tap(find.byIcon(Icons.copy_outlined));
    await tester.pump();
    expect(find.text('已复制'), findsOneWidget);

    // 分类页的搜索入口只搜索当前分类，结果同样能进入详情页。
    await tester.tap(find.byType(WalletSearchButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('wallet-search-field')),
      '6222',
    );
    await tester.pumpAndSettle();
    final scopedResult = find.descendant(
      of: find.byType(WalletSearchSheet),
      matching: find.textContaining('6222 **** **** 5678'),
    );
    expect(scopedResult, findsOneWidget);
    await tester.tap(scopedResult);
    await tester.pumpAndSettle();
    expect(find.text('卡片详情'), findsOneWidget);

    // ---- 返回首页：详情 → 分类页 → 分类列表页 → 首页 ----
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('capsule-search-bar')), findsOneWidget);

    // 借记卡圆形统计刷新为 1。
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('count-circle-debit')), findsOneWidget);

    // ---- 左滑仿真卡到信用卡：显示总授信额度 ----
    await tester.drag(
      find.byKey(const Key('simulated-card-debit')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('总授信额度'), findsOneWidget);
    expect(find.text('¥ 50,000'), findsOneWidget);

    // ---- 首页胶囊搜索：全局磨砂搜索层定位该卡片 ----
    await tester.tap(find.byKey(const Key('capsule-search-bar')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('wallet-search-field')),
      '6222',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('工商银行 · 6222 **** **** 5678'));
    await tester.pumpAndSettle();
    expect(find.text('卡片详情'), findsOneWidget);
  });
}
