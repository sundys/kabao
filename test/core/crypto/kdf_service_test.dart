import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/core/crypto/kdf_service.dart';

void main() {
  late KdfService kdf;

  setUp(() => kdf = KdfService());

  test('相同密码与盐派生相同密钥', () {
    final salt = List.generate(16, (i) => i);
    final params = const KdfParams(
      iterations: 1,
      memoryKiB: 1024,
      parallelism: 1,
      hashLength: 32,
    );
    final a = kdf.deriveKey('主密码123', Uint8List.fromList(salt), params);
    final b = kdf.deriveKey('主密码123', Uint8List.fromList(salt), params);
    expect(a, b);
  });

  test('不同盐派生不同密钥', () {
    final params = const KdfParams(
      iterations: 1,
      memoryKiB: 1024,
      parallelism: 1,
      hashLength: 32,
    );
    final a = kdf.deriveKey(
      'pw',
      Uint8List.fromList(List.filled(16, 1)),
      params,
    );
    final b = kdf.deriveKey(
      'pw',
      Uint8List.fromList(List.filled(16, 2)),
      params,
    );
    expect(a, isNot(b));
  });

  test('输出长度符合参数', () {
    final params = const KdfParams(
      iterations: 1,
      memoryKiB: 1024,
      parallelism: 1,
      hashLength: 64,
    );
    expect(
      kdf
          .deriveKey('pw', Uint8List.fromList(List.filled(16, 0)), params)
          .length,
      64,
    );
  });

  test('JSON 参数序列化往返一致', () {
    const params = KdfParams(
      iterations: 3,
      memoryKiB: 32768,
      parallelism: 2,
      hashLength: 32,
    );
    final restored = KdfParams.fromJson(params.toJson());
    expect(restored.iterations, params.iterations);
    expect(restored.memoryKiB, params.memoryKiB);
    expect(restored.parallelism, params.parallelism);
    expect(restored.hashLength, params.hashLength);
  });
}
