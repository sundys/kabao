import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/features/settings/logic/update_service.dart';
import 'package:kabao/features/settings/presentation/widgets/update_dialog.dart';
import 'package:kabao/shared/services/apk_installer.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 当前安装版本，与 [_info] 的版本一起决定「安装是否成功」。
const String _installedVersion = '1.0.22';

const UpdateInfo _info = UpdateInfo(
  version: '1.0.23',
  notes: '修复若干问题',
  releaseUrl: 'https://github.com/sundys/kabao/releases/tag/v1.0.23',
  assets: [
    ReleaseAsset(
      name: 'kabao-1.0.23-arm64-v8a.apk',
      downloadUrl:
          'https://github.com/sundys/kabao/releases/download/v1.0.23/'
          'kabao-1.0.23-arm64-v8a.apk',
    ),
  ],
);

/// 记录每次安装请求的替身，用来确认「重新安装」没有重新下载。
final class _FakeInstaller extends ApkInstaller {
  _FakeInstaller();

  final List<String> installed = [];
  bool launchSucceeds = true;

  @override
  bool get isSupported => true;

  @override
  Future<List<String>> supportedAbis() async => const ['arm64-v8a'];

  @override
  Future<bool> canInstallPackages() async => true;

  @override
  Future<void> openInstallPermissionSettings() async {}

  @override
  Future<bool> install(String apkPath) async {
    installed.add(apkPath);
    return launchSucceeds;
  }
}

/// 所有请求都返回同一段安装包内容，并记录请求过的地址。
final class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body, {this.status = 200});

  final String body;
  final int status;
  final List<String> requested = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.uri.toString());
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

UpdateService _serviceWith(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500));
  dio.httpClientAdapter = adapter;
  return UpdateService(dio: dio);
}

void main() {
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kabao-update-dialog');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProviderChannel,
          (call) async =>
              call.method == 'getTemporaryDirectory' ? tempDir.path : null,
        );
    PackageInfo.setMockInitialValues(
      appName: '卡包',
      packageName: 'com.sundys.kabao',
      version: _installedVersion,
      buildNumber: '24',
      buildSignature: '',
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> openDialog(
    WidgetTester tester, {
    required UpdateService service,
    required ApkInstaller installer,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => UpdateDialog(
                    info: _info,
                    currentVersion: _installedVersion,
                    service: service,
                    installer: installer,
                  ),
                ),
                child: const Text('检测更新'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('检测更新'));
    await tester.pumpAndSettle();
  }

  /// 点击窗口主按钮，并等待「下载 → 调起安装器」结束。
  ///
  /// 下载会写真实文件，必须放在 runAsync 中让真实 IO 有机会完成。
  Future<void> tapPrimary(WidgetTester tester, String label) async {
    await tester.runAsync(() async {
      await tester.tap(find.text(label));
      await tester.pump();
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (find.text('下载中…').evaluate().isEmpty) {
          break;
        }
      }
    });
    await tester.pump();
    await tester.pump();
  }

  /// 模拟应用生命周期变化（安装器打开会让应用退到后台，返回时恢复）。
  Future<void> sendLifecycle(
    WidgetTester tester,
    AppLifecycleState state,
  ) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage(state.toString()),
      (_) {},
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('下载完成后调起安装器，安装未完成时原地重新安装且不重新下载', (tester) async {
    final installer = _FakeInstaller();
    final adapter = _FakeAdapter('APK-BYTES');

    await openDialog(
      tester,
      service: _serviceWith(adapter),
      installer: installer,
    );
    expect(find.text('立即更新'), findsOneWidget);

    await tapPrimary(tester, '立即更新');

    // 下载完成即调起安装器，窗口不关闭，等用户从安装界面返回。
    expect(installer.installed, hasLength(1));
    expect(adapter.requested, hasLength(1));
    expect(find.text('安装包已下载完成，请在系统安装界面完成安装。'), findsOneWidget);
    expect(find.text('重新安装'), findsOneWidget);

    // 安装被取消或失败后回到应用：版本没变，提示可以原地重装。
    await sendLifecycle(tester, AppLifecycleState.inactive);
    await sendLifecycle(tester, AppLifecycleState.resumed);

    expect(find.text('安装未完成，可直接重新安装，无需重新下载。'), findsOneWidget);
    expect(find.text('重新安装'), findsOneWidget);

    await tapPrimary(tester, '重新安装');

    // 第二次安装直接复用缓存中的安装包，没有再次下载。
    expect(installer.installed, hasLength(2));
    expect(installer.installed.last, installer.installed.first);
    expect(adapter.requested, hasLength(1));
    expect(find.text('重新安装'), findsOneWidget);
  });

  testWidgets('安装成功后从安装器返回，窗口自动关闭', (tester) async {
    final installer = _FakeInstaller();
    final adapter = _FakeAdapter('APK-BYTES');

    await openDialog(
      tester,
      service: _serviceWith(adapter),
      installer: installer,
    );
    await tapPrimary(tester, '立即更新');
    expect(installer.installed, hasLength(1));

    // 系统里已经是新版本，说明安装完成。
    PackageInfo.setMockInitialValues(
      appName: '卡包',
      packageName: 'com.sundys.kabao',
      version: _info.version,
      buildNumber: '25',
      buildSignature: '',
    );
    await sendLifecycle(tester, AppLifecycleState.inactive);
    await sendLifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('重新安装'), findsNothing);
    expect(find.text('检测更新'), findsOneWidget);
  });

  testWidgets('下载失败时给出重试入口，不保留安装包', (tester) async {
    final installer = _FakeInstaller();
    final adapter = _FakeAdapter('', status: 503);

    await openDialog(
      tester,
      service: _serviceWith(adapter),
      installer: installer,
    );
    await tapPrimary(tester, '立即更新');

    expect(installer.installed, isEmpty);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('前往发布页'), findsOneWidget);
    expect(find.text('重新安装'), findsNothing);
  });
}
