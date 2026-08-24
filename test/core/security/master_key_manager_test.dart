import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/core/crypto/kdf_service.dart';
import 'package:kabao/core/security/master_key_manager.dart';
import 'package:kabao/core/security/secure_store.dart';

import '../../helpers/in_memory_secure_store.dart';

/// Reduced-cost KDF parameters so tests stay fast while exercising the same
/// code paths as production (Argon2id).
const _fastKdf = KdfParams(
  iterations: 1,
  memoryKiB: 1024,
  parallelism: 1,
  hashLength: 32,
);

void main() {
  late SecureStore storage;
  late MasterKeyManager manager;

  setUp(() {
    storage = InMemorySecureStore();
    manager = MasterKeyManager(storage: storage, kdfService: _FastKdf());
  });

  test('初始状态未初始化', () async {
    expect(await manager.isInitialized(), isFalse);
  });

  test('设置主密码后可用正确密码解锁', () async {
    expect(await manager.setupMasterPassword('correct horse'), isTrue);
    final result = await manager.unlockWithPassword('correct horse');
    expect(result, isA<MasterKeySuccess>());
    expect((result as MasterKeySuccess).dek.length, 32);
  });

  test('错误密码解锁失败', () async {
    await manager.setupMasterPassword('correct horse');
    final result = await manager.unlockWithPassword('wrong password');
    expect(
      result,
      isA<MasterKeyFailure>().having(
        (f) => f.error,
        'error',
        MasterKeyError.wrongPassword,
      ),
    );
  });

  test('重复初始化被拒绝，不覆盖已有数据', () async {
    await manager.setupMasterPassword('first');
    final before = await storage.read('kabao.v1.wrappedDek');
    expect(await manager.setupMasterPassword('second'), isFalse);
    expect(await storage.read('kabao.v1.wrappedDek'), before);
  });

  test('修改密码后旧密码失效、新密码可用且 DEK 不变', () async {
    await manager.setupMasterPassword('old-password');
    final original = await manager.unlockWithPassword('old-password');
    final originalDek = (original as MasterKeySuccess).dek;

    expect(
      await manager.changePassword(
        currentPassword: 'old-password',
        newPassword: 'new-password',
      ),
      isTrue,
    );
    expect(
      await manager.unlockWithPassword('old-password'),
      isA<MasterKeyFailure>(),
    );
    final reUnlocked = await manager.unlockWithPassword('new-password');
    expect((reUnlocked as MasterKeySuccess).dek, originalDek);
  });

  test('修改密码使用错误旧密码时失败且原密码仍可用', () async {
    await manager.setupMasterPassword('real-old');
    expect(
      await manager.changePassword(
        currentPassword: 'bad-old',
        newPassword: 'new',
      ),
      isFalse,
    );
    expect(
      await manager.unlockWithPassword('real-old'),
      isA<MasterKeySuccess>(),
    );
  });

  test('启用生物识别后可通过设备密钥副本解锁，禁用后不可', () async {
    await manager.setupMasterPassword('pw');
    final unlocked = await manager.unlockWithPassword('pw');
    final dek = (unlocked as MasterKeySuccess).dek;

    expect(await manager.isBiometricEnabled(), isFalse);
    await manager.enableBiometric(dek);
    expect(await manager.isBiometricEnabled(), isTrue);

    final viaBiometrics = await manager.unlockWithDeviceSecret();
    expect((viaBiometrics as MasterKeySuccess).dek, dek);

    await manager.disableBiometric();
    expect(await manager.isBiometricEnabled(), isFalse);
    expect(await manager.unlockWithDeviceSecret(), isA<MasterKeyFailure>());
  });

  test('清空密钥材料后回到未初始化状态', () async {
    await manager.setupMasterPassword('pw');
    await manager.wipeAll();
    expect(await manager.isInitialized(), isFalse);
    expect(
      await manager.unlockWithPassword('pw'),
      isA<MasterKeyFailure>().having(
        (f) => f.error,
        'error',
        MasterKeyError.notInitialized,
      ),
    );
  });
}

final class _FastKdf implements KdfService {
  @override
  Uint8List deriveKey(String password, Uint8List salt, KdfParams params) =>
      KdfService().deriveKey(password, salt, _fastKdf);
}
