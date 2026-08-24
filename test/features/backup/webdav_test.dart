import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/features/backup/logic/webdav_provider.dart'
    show shouldAutoBackup;
import 'package:kabao/features/backup/domain/webdav_config.dart';
import 'package:kabao/features/backup/data/webdav_client.dart';

void main() {
  group('WebDavConfig 序列化', () {
    test('往返一致且不含密码字段', () {
      final config = WebDavConfig(
        url: 'https://dav.example.com/dav',
        username: 'alice',
        directory: 'kabao',
        autoBackupEnabled: true,
        lastBackupAt: DateTime.fromMillisecondsSinceEpoch(1000000),
      );
      final encoded = config.encoded();
      expect(encoded.contains('password'), isFalse);
      final restored = WebDavConfig.fromJsonString(encoded);
      expect(restored!.url, config.url);
      expect(restored.username, config.username);
      expect(restored.directory, config.directory);
      expect(restored.autoBackupEnabled, isTrue);
      expect(restored.lastBackupAt, config.lastBackupAt);
    });

    test('非法或损坏的存储内容返回 null 而非抛出', () {
      expect(WebDavConfig.fromJsonString(null), isNull);
      expect(WebDavConfig.fromJsonString(''), isNull);
      expect(WebDavConfig.fromJsonString('not json'), isNull);
      // 缺少必填字段 / URL 无协议
      expect(WebDavConfig.fromJsonString('{"username":"a"}'), isNull);
      expect(
        WebDavConfig.fromJsonString('{"url":"dav.example.com","username":"a"}'),
        isNull,
      );
    });
  });

  group('自动备份策略（显式节流）', () {
    test('未开启自动备份时永不触发', () {
      final config = WebDavConfig(
        url: 'https://x',
        username: 'u',
        directory: '',
      );
      expect(shouldAutoBackup(config, DateTime.now()), isFalse);
    });

    test('开启后从未备份过则触发', () {
      final config = const WebDavConfig(
        url: 'https://x',
        username: 'u',
        autoBackupEnabled: true,
      );
      expect(
        shouldAutoBackup(config, DateTime.fromMillisecondsSinceEpoch(0)),
        isTrue,
      );
    });

    test('24 小时节流：不足一天不触发，超过一天触发', () {
      final now = DateTime(2026, 8, 24, 12);
      final justNow = WebDavConfig(
        url: 'https://x',
        username: 'u',
        autoBackupEnabled: true,
        lastBackupAt: now.subtract(const Duration(hours: 23)),
      );
      expect(shouldAutoBackup(justNow, now), isFalse);

      const stale = WebDavConfig(
        url: 'https://x',
        username: 'u',
        autoBackupEnabled: true,
        lastBackupAt: null,
      );
      expect(stale.autoBackupEnabled, isTrue);

      final old = WebDavConfig(
        url: 'https://x',
        username: 'u',
        autoBackupEnabled: true,
        lastBackupAt: now.subtract(const Duration(hours: 25)),
      );
      expect(shouldAutoBackup(old, now), isTrue);
    });
  });

  group('HTTP 策略', () {
    test('客户端拒绝未经确认的 HTTP 地址', () async {
      final adapter = WebDavClientAdapter();
      const httpConfig = WebDavConfig(
        url: 'http://dav.example.com',
        username: 'u',
      );
      await expectLater(
        adapter.connect(httpConfig, 'pw'),
        throwsA(const WebDavException(WebDavError.httpOnlyRefused)),
      );
    });

    test('用户显式确认后允许 HTTP（开发场景）', () async {
      final adapter = WebDavClientAdapter();
      const config = WebDavConfig(
        url: 'http://localhost',
        username: 'u',
        allowHttp: true,
      );
      // 不应抛出 HTTP 拒绝错误；连接本身在无服务时以 network 失败。
      try {
        await adapter.connect(config, 'pw');
        await adapter.ping();
      } on WebDavException catch (e) {
        expect(e.error, WebDavError.network);
      }
    });
  });
}
