import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

final class KdfParams {
  const KdfParams({
    required this.iterations,
    required this.memoryKiB,
    required this.parallelism,
    required this.hashLength,
  });

  final int iterations;
  final int memoryKiB;
  final int parallelism;
  final int hashLength;

  Map<String, Object?> toJson() => {
    'iterations': iterations,
    'memoryKiB': memoryKiB,
    'parallelism': parallelism,
    'hashLength': hashLength,
  };

  static KdfParams fromJson(Map<String, Object?> json) => KdfParams(
    iterations: json['iterations']! as int,
    memoryKiB: json['memoryKiB']! as int,
    parallelism: json['parallelism']! as int,
    hashLength: json['hashLength']! as int,
  );

  static const KdfParams mobileDefault = KdfParams(
    iterations: 3,
    memoryKiB: 32768,
    parallelism: 2,
    hashLength: 32,
  );
}

class KdfService {
  static const int _argon2idVersion = 0x13;

  Uint8List deriveKey(String password, Uint8List salt, KdfParams params) {
    final generator = pc.Argon2BytesGenerator();
    generator.init(
      pc.Argon2Parameters(
        _argon2idVersion,
        salt,
        desiredKeyLength: params.hashLength,
        iterations: params.iterations,
        memory: params.memoryKiB,
        lanes: params.parallelism,
      ),
    );
    final passwordBytes = Uint8List.fromList(
      utf8.encode(password) as List<int>,
    );
    final out = Uint8List(params.hashLength);
    try {
      generator.deriveKey(passwordBytes, 0, out, 0);
    } finally {
      passwordBytes.fillRange(0, passwordBytes.length, 0);
    }
    return out;
  }
}
