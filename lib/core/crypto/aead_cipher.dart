import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

final class AeadDecryptionException implements Exception {
  const AeadDecryptionException(this.message);

  final String message;

  @override
  String toString() => 'AeadDecryptionException: $message';
}

final class AeadCipher {
  AeadCipher({int Function(int)? randomByteFactory})
    : _random = Random.secure();

  static const int nonceLength = 12;

  final Random _random;
  final AesGcm _algorithm = AesGcm.with256bits();

  Uint8List generateNonce() => Uint8List.fromList(
    List.generate(nonceLength, (_) => _random.nextInt(256)),
  );

  /// Returns combined bytes: [nonce(12)] + [ciphertext] + [mac(16)].
  Future<Uint8List> encrypt(Uint8List key, Uint8List plaintext) async {
    final nonce = generateNonce();
    final secretBox = await _algorithm.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
    );
    final combined = Uint8List(
      nonce.length + secretBox.cipherText.length + secretBox.mac.bytes.length,
    );
    combined.setRange(0, nonce.length, nonce);
    combined.setRange(
      nonce.length,
      nonce.length + secretBox.cipherText.length,
      secretBox.cipherText,
    );
    combined.setRange(
      combined.length - secretBox.mac.bytes.length,
      combined.length,
      secretBox.mac.bytes,
    );
    return combined;
  }

  Future<Uint8List> decrypt(Uint8List key, Uint8List combined) async {
    if (combined.length < nonceLength + 16) {
      throw const AeadDecryptionException('ciphertext too short');
    }
    final nonce = Uint8List.sublistView(combined, 0, nonceLength);
    final mac = Uint8List.sublistView(combined, combined.length - 16);
    final cipherText = Uint8List.sublistView(
      combined,
      nonceLength,
      combined.length - 16,
    );
    try {
      final clear = await _algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: SecretKey(key),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const AeadDecryptionException('authentication failed');
    }
  }

  Uint8List generateKey(int length) =>
      Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));
}
