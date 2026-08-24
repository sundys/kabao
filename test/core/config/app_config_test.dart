import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/core/config/app_config.dart';

void main() {
  group('版本比较（用于手动检查更新）', () {
    test('识别 v 前缀', () {
      expect(AppConfig.compareVersions('v99.0.0'), isNotNull);
    });

    test('相同版本返回 null', () {
      expect(AppConfig.compareVersions('v${AppConfig.appVersion}'), isNull);
    });

    test('更低版本返回 null', () {
      expect(AppConfig.compareVersions('v0.0.1'), isNull);
      expect(AppConfig.compareVersions('1.0'), isNull);
    });

    test('非法标签返回 null', () {
      expect(AppConfig.compareVersions('latest'), isNull);
      expect(AppConfig.compareVersions('beta-1'), isNull);
      expect(AppConfig.compareVersions(''), isNull);
    });
  });
}
