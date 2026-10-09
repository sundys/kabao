import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/features/settings/logic/update_service.dart';

/// 按 URL 返回预置响应，用于验证代理依次重试的行为。
final class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responses, {this.locationHeaders = const {}});

  /// 匹配规则：URL 前缀命中即返回对应响应。
  final Map<String, (int status, String body)> responses;

  /// 命中时的 `location` 响应头，用于模拟发布页的 302 跳转。
  final Map<String, String> locationHeaders;
  final List<String> requested = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    requested.add(url);
    for (final entry in responses.entries) {
      if (url.startsWith(entry.key)) {
        final (status, body) = entry.value;
        final headers = <String, List<String>>{
          Headers.contentTypeHeader: [Headers.jsonContentType],
        };
        final location = locationHeaders[entry.key];
        if (location != null) {
          headers['location'] = [location];
        }
        return ResponseBody.fromString(body, status, headers: headers);
      }
    }
    // 未命中的地址按“代理不可用”处理（5xx），而不是 404“仓库没有发布”。
    return ResponseBody.fromString('', 503);
  }

  @override
  void close({bool force = false}) {}
}

String releaseJson({
  required String tag,
  String body = '',
  List<(String, String)> assets = const [],
}) => jsonEncode({
  'tag_name': tag,
  'body': body,
  'html_url': 'https://github.com/sundys/kabao/releases/tag/$tag',
  'assets': [
    for (final (name, url) in assets)
      {'name': name, 'browser_download_url': url},
  ],
});

void main() {
  group('版本比较', () {
    test('按 major.minor.patch 逐段比较', () {
      expect(compareVersions('1.0.19', '1.0.18'), greaterThan(0));
      expect(compareVersions('1.0.18', '1.0.19'), lessThan(0));
      expect(compareVersions('1.0.19', '1.0.19'), 0);
      expect(compareVersions('1.1.0', '1.0.99'), greaterThan(0));
      expect(compareVersions('2.0.0', '1.9.9'), greaterThan(0));
    });

    test('忽略构建号与预发布后缀', () {
      expect(compareVersions('1.0.19+21', '1.0.19'), 0);
      expect(compareVersions('1.0.19-beta', '1.0.19'), 0);
      expect(compareVersions('1.0', '1.0.0'), 0);
    });

    test('去掉 Release 标签的 v 前缀', () {
      expect(normalizeVersion('v1.0.19'), '1.0.19');
      expect(normalizeVersion('V1.0.19'), '1.0.19');
      expect(normalizeVersion('1.0.19'), '1.0.19');
    });
  });

  group('按 ABI 选择安装包', () {
    const info = UpdateInfo(
      version: '1.0.19',
      notes: '',
      releaseUrl: '',
      assets: [
        ReleaseAsset(
          name: 'kabao-1.0.19-arm64-v8a.apk',
          downloadUrl: 'https://example.com/arm64',
        ),
        ReleaseAsset(
          name: 'kabao-1.0.19-armeabi-v7a.apk',
          downloadUrl: 'https://example.com/armv7',
        ),
        ReleaseAsset(
          name: 'kabao-1.0.19.aab',
          downloadUrl: 'https://example.com/aab',
        ),
      ],
    );

    test('优先取 64 位包', () {
      expect(
        info.apkForAbis(['arm64-v8a', 'armeabi-v7a'])?.downloadUrl,
        'https://example.com/arm64',
      );
    });

    test('64 位无包时回落到 32 位', () {
      expect(
        info.apkForAbis(['armeabi-v7a', 'armeabi'])?.downloadUrl,
        'https://example.com/armv7',
      );
    });

    test('没有匹配架构时返回 null', () {
      expect(info.apkForAbis(['x86', 'mips']), isNull);
      expect(info.apkForAbis([]), isNull);
    });
  });

  group('检测更新', () {
    UpdateService serviceWith(_FakeAdapter adapter) {
      final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500));
      dio.httpClientAdapter = adapter;
      return UpdateService(dio: dio);
    }

    test('直连可用时不走代理', () async {
      final adapter = _FakeAdapter({
        'https://api.github.com/': (200, releaseJson(tag: 'v1.0.20')),
        'https://ghfast.top/': (200, releaseJson(tag: 'v9.9.9')),
      });
      final result = await serviceWith(adapter).check(currentVersion: '1.0.19');

      expect(result, isA<UpdateAvailable>());
      expect((result as UpdateAvailable).info.version, '1.0.20');
      expect(adapter.requested, hasLength(1));
    });

    test('直连失败后依次尝试代理直到成功', () async {
      final adapter = _FakeAdapter({
        'https://ghfast.top/': (200, releaseJson(tag: 'v1.0.20')),
      });
      final result = await serviceWith(adapter).check(currentVersion: '1.0.19');

      expect(result, isA<UpdateAvailable>());
      expect(adapter.requested.first, startsWith('https://api.github.com/'));
      expect(adapter.requested[1], startsWith('https://ghfast.top/'));
    });

    test('版本不比当前新时判定为已是最新', () async {
      final adapter = _FakeAdapter({
        'https://api.github.com/': (200, releaseJson(tag: 'v1.0.19')),
      });
      final result = await serviceWith(adapter).check(currentVersion: '1.0.19');

      expect(result, isA<UpdateUpToDate>());
    });

    test('全部通道不可用时给出可重试的失败结果', () async {
      final adapter = _FakeAdapter(const {});
      final result = await serviceWith(adapter).check(currentVersion: '1.0.19');

      expect(result, isA<UpdateCheckFailure>());
      expect((result as UpdateCheckFailure).message, contains('网络'));
    });

    test('仓库没有 Release 时不再尝试其它代理', () async {
      final adapter = _FakeAdapter({
        'https://api.github.com/': (404, ''),
        'https://ghfast.top/': (200, releaseJson(tag: 'v1.0.20')),
      });
      final result = await serviceWith(adapter).check(currentVersion: '1.0.19');

      expect(result, isA<UpdateCheckFailure>());
      expect(adapter.requested, hasLength(1));
    });

    test('API 被墙时退回发布页，并按发布约定推导 APK 地址', () async {
      const pageUrl =
          'https://ghfast.top/https://github.com/sundys/kabao/releases/latest';
      final adapter = _FakeAdapter(
        {pageUrl: (302, '')},
        locationHeaders: {
          pageUrl: 'https://github.com/sundys/kabao/releases/tag/v1.0.20',
        },
      );
      final result = await serviceWith(adapter).check(currentVersion: '1.0.19');

      expect(result, isA<UpdateAvailable>());
      final info = (result as UpdateAvailable).info;
      expect(info.version, '1.0.20');
      expect(
        info.apkForAbis(['arm64-v8a'])?.downloadUrl,
        'https://github.com/sundys/kabao/releases/download/v1.0.20/'
        'kabao-1.0.20-arm64-v8a.apk',
      );
      expect(
        info.apkForAbis(['armeabi-v7a'])?.downloadUrl,
        'https://github.com/sundys/kabao/releases/download/v1.0.20/'
        'kabao-1.0.20-armeabi-v7a.apk',
      );
    });
  });
}
