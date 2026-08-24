import 'dart:convert';
import 'dart:typed_data';

import '../crypto/aead_cipher.dart';
import '../crypto/kdf_service.dart';
import 'secure_store.dart';

enum MasterKeyError { notInitialized, wrongPassword, storageFailure }

sealed class MasterKeyResult {
  const MasterKeyResult();
}

final class MasterKeySuccess extends MasterKeyResult {
  const MasterKeySuccess(this.dek);

  final Uint8List dek;
}

final class MasterKeyFailure extends MasterKeyResult {
  const MasterKeyFailure(this.error);

  final MasterKeyError error;
}

/// Manages the data encryption key (DEK).
///
/// The DEK is wrapped with a key-encryption-key (KEK) derived from the master
/// password via Argon2id. When biometric unlock is enabled, a second copy of
/// the DEK is kept in the platform secure storage (Android Keystore backed) so
/// biometrics can unseal an existing key without weakening the password path.
final class MasterKeyManager {
  static const String _kSalt = 'kabao.v1.salt';
  static const String _kKdfParams = 'kabao.v1.kdfParams';
  static const String _kWrappedDek = 'kabao.v1.wrappedDek';
  static const String _kDirectDek = 'kabao.v1.directDek';
  static const String _kBiometricEnabled = 'kabao.v1.biometricEnabled';

  final SecureStore storage;
  final KdfService _kdf;
  final AeadCipher _aead;

  MasterKeyManager({
    required this.storage,
    KdfService? kdfService,
    AeadCipher? aeadCipher,
  }) : _kdf = kdfService ?? KdfService(),
       _aead = aeadCipher ?? AeadCipher();

  Future<bool> isInitialized() async {
    final wrapped = await storage.read(_kWrappedDek);
    return wrapped != null;
  }

  Future<bool> isBiometricEnabled() async =>
      await storage.read(_kBiometricEnabled) == 'true';

  /// Creates a fresh DEK wrapped by the given master password.
  ///
  /// Fails (returns false) if the vault was already initialized, so existing
  /// data can never be silently overwritten.
  Future<bool> setupMasterPassword(String password) async {
    if (await isInitialized()) {
      return false;
    }
    try {
      final salt = _aead.generateKey(16);
      final dek = _aead.generateKey(32);
      final params = KdfParams.mobileDefault;
      final kek = _kdf.deriveKey(password, salt, params);
      final wrapped = await _aead.encrypt(kek, dek);
      await storage.write(_kSalt, base64Encode(salt));
      await storage.write(_kKdfParams, jsonEncode(params.toJson()));
      await storage.write(_kWrappedDek, base64Encode(wrapped));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<MasterKeyResult> unlockWithPassword(String password) async {
    final stored = await _readWrapped();
    if (stored == null) {
      return const MasterKeyFailure(MasterKeyError.notInitialized);
    }
    final (salt, params, wrapped) = stored;
    final kek = _kdf.deriveKey(password, salt, params);
    try {
      final dek = await _aead.decrypt(kek, wrapped);
      return MasterKeySuccess(dek);
    } on AeadDecryptionException {
      return const MasterKeyFailure(MasterKeyError.wrongPassword);
    }
  }

  /// Unseals the Keystore-protected DEK copy. Only available when the user
  /// enabled biometric unlock; never replaces the password path.
  Future<MasterKeyResult> unlockWithDeviceSecret() async {
    if (!await isBiometricEnabled()) {
      return const MasterKeyFailure(MasterKeyError.notInitialized);
    }
    final direct = await storage.read(_kDirectDek);
    if (direct == null) {
      return const MasterKeyFailure(MasterKeyError.notInitialized);
    }
    return MasterKeySuccess(Uint8List.fromList(base64Decode(direct)));
  }

  /// Re-wraps the same DEK under a new password. The old wrapping is only
  /// replaced after every new value has been computed and written
  /// successfully, so a failure leaves the vault openable with the old
  /// password.
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final unlocked = await unlockWithPassword(currentPassword);
    if (unlocked is! MasterKeySuccess) {
      return false;
    }
    final dek = unlocked.dek;
    try {
      final newSalt = _aead.generateKey(16);
      final params = KdfParams.mobileDefault;
      final newKek = _kdf.deriveKey(newPassword, newSalt, params);
      final newWrapped = await _aead.encrypt(newKek, dek);
      await storage.write(_kSalt, base64Encode(newSalt));
      await storage.write(_kKdfParams, jsonEncode(params.toJson()));
      await storage.write(_kWrappedDek, base64Encode(newWrapped));
      if (await isBiometricEnabled()) {
        await storage.write(_kDirectDek, base64Encode(dek));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Enables biometric unlock during an authenticated session where the DEK
  /// is already available in memory.
  Future<void> enableBiometric(Uint8List dek) async {
    assert(dek.length == 32, 'unexpected DEK length');
    await storage.write(_kDirectDek, base64Encode(dek));
    await storage.write(_kBiometricEnabled, 'true');
  }

  Future<void> disableBiometric() async {
    await storage.delete(_kDirectDek);
    await storage.delete(_kBiometricEnabled);
  }

  /// Irreversible wipe of all key material. Callers must wipe business data
  /// separately before or after this as part of a confirmed flow.
  Future<void> wipeAll() => storage.deleteAll();

  Future<(Uint8List, KdfParams, Uint8List)?> _readWrapped() async {
    final saltStr = await storage.read(_kSalt);
    final paramsStr = await storage.read(_kKdfParams);
    final wrappedStr = await storage.read(_kWrappedDek);
    if (saltStr == null || paramsStr == null || wrappedStr == null) {
      return null;
    }
    final params = KdfParams.fromJson(
      Map<String, Object?>.from(jsonDecode(paramsStr) as Map),
    );
    return (
      Uint8List.fromList(base64Decode(saltStr)),
      params,
      Uint8List.fromList(base64Decode(wrappedStr)),
    );
  }
}
