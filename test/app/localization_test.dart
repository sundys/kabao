import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/app/app.dart';
import 'package:kabao/app/localization.dart';
import 'package:kabao/features/auth/logic/auth_controller.dart';

import '../helpers/in_memory_secure_store.dart';

void main() {
  testWidgets('KabaoApp 为内置组件提供中文文案', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStoreProvider.overrideWithValue(InMemorySecureStore()),
        ],
        child: const KabaoApp(),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.text('创建主密码'));
    final material = MaterialLocalizations.of(context);
    expect(material.copyButtonLabel, '复制');
    expect(material.cutButtonLabel, '剪切');
    expect(material.pasteButtonLabel, '粘贴');
    expect(material.selectAllButtonLabel, '全选');

    final cupertino = CupertinoLocalizations.of(context);
    expect(cupertino.copyButtonLabel, '复制');
    expect(cupertino.cutButtonLabel, '剪切');
    expect(cupertino.pasteButtonLabel, '粘贴');
  });

  testWidgets('文本框长按菜单显示中文', (tester) async {
    final controller = TextEditingController(text: '6222 0212 3456 7890');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: appLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
          body: Center(child: TextField(controller: controller)),
        ),
      ),
    );

    await tester.longPress(find.byType(TextField));
    await tester.pumpAndSettle();

    for (final english in const ['Cut', 'Copy', 'Paste', 'Select all']) {
      expect(find.text(english), findsNothing, reason: '不应出现英文菜单项');
    }
    // 未选中文本且剪贴板为空时，长按只会显示「全选」；缺少本地化代理时这里
    // 会显示英文的 Select all。
    expect(find.text('全选'), findsOneWidget, reason: '长按文本框后应出现中文选择菜单');
  });
}
