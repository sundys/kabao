import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/core/crypto/aead_cipher.dart';

void main() {
  late AeadCipher aead;
  late Uint8List key;

  setUp(() {
    aead = AeadCipher();
    key = aead.generateKey(32);
  });

  test('加密后可解密还原', () async {
    final plaintext = Uint8List.fromList('卡片机密数据'.codeUnits);
    final encrypted = await aead.encrypt(key, plaintext);
    expect(encrypted, isNot(plaintext));

    final decrypted = await aead.decrypt(key, encrypted);
    expect(decrypted, plaintext);
  });

  test('相同明文两次加密产生不同密文（唯一随机 nonce）', () async {
    final plaintext = Uint8List.fromList(List.filled(64, 7));
    final first = await aead.encrypt(key, plaintext);
    final second = await aead.encrypt(key, plaintext);
    expect(first, isNot(second));
  });

  test('密文被篡改时认证失败', () async {
    final encrypted = await aead.encrypt(
      key,
      Uint8List.fromList(List.filled(48, 1)),
    );
    final tampered = Uint8List.fromList(encrypted);
    tampered[tampered.length ~/ 2] ^= 0xFF;
    expect(
      () => aead.decrypt(key, tampered),
      throwsA(isA<AeadDecryptionException>()),
    );
  });

  test('错误密钥解密失败', () async {
    final encrypted = await aead.encrypt(key, Uint8List.fromList([9, 9, 9]));
    final wrongKey = aead.generateKey(32);
    expect(
      () => aead.decrypt(wrongKey, encrypted),
      throwsA(isA<AeadDecryptionException>()),
    );
  });

  test('密文过短直接拒绝', () async {
    expect(
      () => aead.decrypt(key, Uint8List.fromList([1, 2, 3])),
      throwsA(isA<AeadDecryptionException>()),
    );
  });
}
