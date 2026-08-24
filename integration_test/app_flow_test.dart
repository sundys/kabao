import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'integration_test_helpers.dart';

/// 覆盖验收路径：首次安装 → 创建主密码 → 解锁 → 创建分类 → 添加卡片。
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

    // ---- 主页可见：借记卡/信用卡标签 ----
    expect(find.text('借记卡'), findsOneWidget);

    // ---- 创建银行分类（名称校验：仅中文 ≤4 字）----
    await tester.tap(find.text('新建分类'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category-name-field')),
      '工商银行',
    );
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(find.text('工商银行'), findsOneWidget);

    // ---- 进入分类并添加卡片 ----
    await tester.tap(find.text('工商银行'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加卡片'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '6222 0000 1234 5678');
    await tester.enterText(fields.at(1), '08/29');
    await tester.enterText(fields.at(2), '123');
    await tester.enterText(fields.at(3), '2027/3/8');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 卡片列表显示脱敏分组卡号
    expect(find.text('6222 **** **** 5678'), findsOneWidget);
  });
}
