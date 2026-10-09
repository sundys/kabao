import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/core/config/app_config.dart';
import 'package:kabao/features/settings/presentation/pages/about_page.dart';

/// url_launcher 在测试环境没有插件实现，这里直接接管它的方法通道。
const MethodChannel _launcherChannel = MethodChannel(
  'plugins.flutter.io/url_launcher',
);

void main() {
  final launchedUrls = <String>[];
  var launchSucceeds = true;

  setUp(() {
    launchedUrls.clear();
    launchSucceeds = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, (call) async {
          if (call.method == 'launch' || call.method == 'launchUrl') {
            launchedUrls.add('${call.arguments}');
            return launchSucceeds;
          }
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, null);
  });

  Future<void> pumpAbout(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AboutPage())),
    );
    await tester.pump();
  }

  testWidgets('关于页三个入口都不再显示下方说明文字', (tester) async {
    await pumpAbout(tester);

    expect(find.byType(ListTile), findsNWidgets(3));

    // 原来的副标题（链接地址与说明文案）都不应再出现。
    expect(find.text(AppConfig.githubHomepage), findsNothing);
    expect(find.text('检查 GitHub 上的最新版本并安装'), findsNothing);
    expect(find.text('银行卡和证件 CSV / XLS 模板'), findsNothing);
  });

  testWidgets('开源主页与模板下载以超链接样式展示，检测更新保持普通样式', (tester) async {
    await pumpAbout(tester);

    final home = tester.widget<Text>(find.text('开源主页'));
    expect(home.style?.decoration, TextDecoration.underline);

    final templates = tester.widget<Text>(find.text('CSV 批量导入模板下载'));
    expect(templates.style?.decoration, TextDecoration.underline);

    // 检测更新是应用内动作，不是外链，不按下划线样式展示。
    final update = tester.widget<Text>(find.text('检测更新'));
    expect(update.style?.decoration, isNot(TextDecoration.underline));
  });

  testWidgets('点击开源主页跳转到 GitHub 主页', (tester) async {
    await pumpAbout(tester);

    await tester.tap(find.text('开源主页'));
    await tester.pumpAndSettle();

    expect(launchedUrls, hasLength(1));
    expect(launchedUrls.single, contains(AppConfig.githubHomepage));
    expect(find.text('无法打开链接，请检查是否已安装浏览器'), findsNothing);
  });

  testWidgets('点击模板下载跳转到模板目录', (tester) async {
    await pumpAbout(tester);

    await tester.tap(find.text('CSV 批量导入模板下载'));
    await tester.pumpAndSettle();

    expect(launchedUrls, hasLength(1));
    expect(launchedUrls.single, contains(AppConfig.importTemplatesUrl));
  });

  testWidgets('跳转失败时给出提示', (tester) async {
    launchSucceeds = false;
    await pumpAbout(tester);

    await tester.tap(find.text('开源主页'));
    await tester.pumpAndSettle();

    expect(find.text('无法打开链接，请检查是否已安装浏览器'), findsOneWidget);
  });
}
