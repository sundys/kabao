import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/features/auth/logic/auth_controller.dart';
import 'package:kabao/features/settings/presentation/pages/settings_page.dart';

import '../../helpers/in_memory_secure_store.dart';

/// 设置页改为分组卡片布局后，所有设置项与交互都必须原样保留。
void main() {
  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStoreProvider.overrideWithValue(InMemorySecureStore()),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('分组标题齐全且设置项文案未变', (tester) async {
    await pumpSettings(tester);

    for (final section in ['外观', '安全', '数据']) {
      expect(find.text(section), findsOneWidget, reason: '缺少分组：$section');
    }

    for (final title in [
      '主题颜色',
      '修改主密码',
      '生物识别登录',
      '超时时间',
      '系统通知',
      '导入备份',
      '导出备份',
      '导入银行卡 CSV',
      '导入证件 CSV',
      'WebDAV 备份',
    ]) {
      expect(find.text(title), findsOneWidget, reason: '缺少设置项：$title');
    }

    // ListView 懒构建，下方的分组需要先滚动到位再断言。
    await tester.scrollUntilVisible(find.text('关于卡包'), 200);
    await tester.pumpAndSettle();
    for (final section in ['危险操作', '关于']) {
      expect(find.text(section), findsOneWidget, reason: '缺少分组：$section');
    }
    for (final title in ['清空全部数据', '关于卡包']) {
      expect(find.text(title), findsOneWidget, reason: '缺少设置项：$title');
    }
  });

  testWidgets('开关项与可点击项仍能正常交互', (tester) async {
    await pumpSettings(tester);

    expect(find.byType(SwitchListTile), findsOneWidget);

    // 点击「超时时间」仍弹出档位选择。
    await tester.tap(find.text('超时时间'));
    await tester.pumpAndSettle();
    expect(find.text('立即'), findsOneWidget);
    expect(find.text('5分钟'), findsOneWidget);

    // 选一个档位后副标题同步刷新。
    await tester.tap(find.text('5分钟'));
    await tester.pumpAndSettle();
    expect(find.text('切换后台 5分钟后锁定数据库'), findsOneWidget);
  });

  testWidgets('危险操作分组使用错误色，且不出现点击涟漪被遮挡的断言', (tester) async {
    await pumpSettings(tester);
    await tester.scrollUntilVisible(find.text('清空全部数据'), 200);
    await tester.pumpAndSettle();

    final dangerText = find.text('清空全部数据');
    final danger = tester.widget<Text>(dangerText);
    expect(
      danger.style?.color,
      Theme.of(tester.element(dangerText)).colorScheme.error,
    );
    // 若 ListTile 的墨水层被有色容器遮住，Flutter 会在构建期抛断言。
    expect(tester.takeException(), isNull);
  });
}
