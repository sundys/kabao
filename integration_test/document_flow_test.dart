import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kabao/features/wallet/domain/document.dart';

import 'integration_test_helpers.dart';

/// 真机验收：证件卡分类 → 录入证件 → 证件号分组显示 → 长期有效勾选。
/// 同时确认中文字段（姓名、签发机关、备注）加密落库后回读无乱码。
///
///   flutter test integration_test/document_flow_test.dart -d `<device>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('证件录入：分组证件号与长期有效', (tester) async {
    await pumpFreshApp(tester);

    // ---- 首次设置 → 解锁 ----
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

    await tester.enterText(
      find.byKey(const Key('lock-password')),
      testMasterPassword,
    );
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();

    // ---- 切到证件卡标签并创建分类 ----
    await tester.tap(find.text('证件卡'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-category-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('category-name-field')), '身份证');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(find.text('身份证'), findsOneWidget);

    // ---- 进入分类并添加证件 ----
    await tester.tap(find.text('身份证'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加证件'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '张三');
    await tester.enterText(
      find.byKey(const Key('doc-id-number')),
      '402356201202263038',
    );
    await tester.pump();
    // 连续输入的数字按 6/8/尾号自动分组显示。
    expect(find.text('402356 20120226 3038'), findsOneWidget);

    // 签发机关与有效期限：先录入日期，确认格式化生效。
    await tester.enterText(
      find.widgetWithText(TextFormField, '如：中南县公安局'),
      '中南县公安局',
    );
    await tester.enterText(
      find.byKey(const Key('doc-validity')),
      '2022022520380225',
    );
    await tester.pump();
    expect(find.text('2022.02.25-2038.02.25'), findsOneWidget);

    // ---- 勾选长期有效：日期被清空并禁止录入 ----
    await tester.tap(find.byKey(const Key('doc-permanent-validity')));
    await tester.pumpAndSettle();
    expect(find.text('2022.02.25-2038.02.25'), findsNothing);
    final validityField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('doc-validity')),
        matching: find.byType(TextField),
      ),
    );
    expect(validityField.enabled, isFalse);

    await tester.enterText(
      find.widgetWithText(TextFormField, '选填'),
      '长期有效的居民身份证',
    );
    await tester.pumpAndSettle();
    // 表单是 ListView，底部的保存按钮在屏幕外时尚未建入 widget 树，
    // 需要先滚动到它出现。
    await tester.scrollUntilVisible(
      find.byKey(const Key('doc-save')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('doc-save')));
    await tester.pumpAndSettle();

    // ---- 列表：脱敏证件号 + 长期有效文案 ----
    expect(find.text('张三'), findsOneWidget);
    expect(
      find.textContaining(DocumentRecord.permanentValidityLabel),
      findsWidgets,
    );

    // ---- 详情页：分组证件号、长期有效、中文字段无乱码 ----
    await tester.tap(find.text('张三'));
    await tester.pumpAndSettle();
    expect(find.text('402356 20120226 3038'), findsOneWidget);
    expect(find.text('长期有效'), findsOneWidget);
    expect(find.text('中南县公安局'), findsOneWidget);
    expect(find.text('长期有效的居民身份证'), findsOneWidget);

    // ---- 回到编辑页：勾选框保持选中，日期仍被锁定 ----
    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();
    final checkbox = tester.widget<CheckboxListTile>(
      find.byKey(const Key('doc-permanent-validity')),
    );
    expect(checkbox.value, isTrue);
    expect(find.text('402356 20120226 3038'), findsOneWidget);
  });
}
