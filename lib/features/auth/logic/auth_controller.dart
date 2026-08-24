import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/master_key_manager.dart';
import '../../../core/security/secure_store.dart';
import '../models/auth_state.dart';

final secureStoreProvider = Provider<SecureStore>((ref) {
  return FlutterSecureStore();
});

final masterKeyManagerProvider = Provider<MasterKeyManager>((ref) {
  return MasterKeyManager(storage: ref.watch(secureStoreProvider));
});

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// Whether the Keystore-backed biometric key copy exists. Only meaningful
/// while unlocked.
final biometricEnabledProvider = FutureProvider<bool>((ref) async {
  final auth = ref.watch(authControllerProvider).value;
  if (auth is! AuthUnlocked) {
    return false;
  }
  return ref.watch(masterKeyManagerProvider).isBiometricEnabled();
});

/// True while the system biometric prompt is showing. Lifecycle handling
/// must not treat the prompt's transient backgrounding as "user left the
/// app", otherwise a successful scan would be followed by an immediate
/// re-lock (unlock loop).
final biometricAuthInProgressProvider =
    NotifierProvider<BiometricAuthInProgress, bool>(
      BiometricAuthInProgress.new,
    );

class BiometricAuthInProgress extends Notifier<bool> {
  @override
  bool build() => false;

  void start() => state = true;

  void stop() => state = false;
}

/// Progressive backoff after consecutive failed unlocks. Delays are indexed by
/// (failure count - allowedImmediateAttempts) and capped at one minute.
const List<int> unlockBackoffSeconds = [0, 2, 5, 10, 20, 40, 60];
const int _immediateAttempts = 2;

class AuthController extends AsyncNotifier<AuthState> {
  int _failedAttempts = 0;
  DateTime _lockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _biometricEnabled = false;

  Timer? _backoffTimer;

  Duration get remainingBackoff {
    final remaining = _lockedUntil.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  Future<AuthState> build() async {
    ref.onDispose(() => _backoffTimer?.cancel());
    final manager = ref.watch(masterKeyManagerProvider);
    if (!await manager.isInitialized()) {
      return const AuthNeedsSetup();
    }
    _biometricEnabled = await manager.isBiometricEnabled();
    return AuthLocked(biometricEnabled: _biometricEnabled);
  }

  /// Creates the master password on first launch. Returns false when the
  /// vault already exists.
  Future<bool> setupMasterPassword(String password) async {
    final ok = await ref
        .read(masterKeyManagerProvider)
        .setupMasterPassword(password);
    if (ok) {
      state = const AsyncData(AuthLocked());
    }
    return ok;
  }

  Future<bool> unlockWithPassword(String password) async {
    if (remainingBackoff > Duration.zero) {
      return false;
    }
    final result = await ref
        .read(masterKeyManagerProvider)
        .unlockWithPassword(password);
    switch (result) {
      case MasterKeySuccess(:final dek):
        _resetFailures();
        state = AsyncData(AuthUnlocked(dek));
        return true;
      case MasterKeyFailure():
        _registerFailure();
        return false;
    }
  }

  /// Verifies the device biometrics and unseals the Keystore-backed key copy.
  /// Returns false on any failure; the password path always remains usable.
  Future<bool> unlockWithBiometrics({
    required Future<bool> Function() authenticate,
  }) async {
    if (remainingBackoff > Duration.zero) {
      return false;
    }
    final verified = await authenticate();
    if (!verified) {
      _registerFailure();
      return false;
    }
    final result = await ref
        .read(masterKeyManagerProvider)
        .unlockWithDeviceSecret();
    switch (result) {
      case MasterKeySuccess(:final dek):
        _resetFailures();
        state = AsyncData(AuthUnlocked(dek));
        return true;
      case MasterKeyFailure():
        return false;
    }
  }

  void lock() {
    state = AsyncData(AuthLocked(biometricEnabled: _biometricEnabled));
  }

  /// Must be called during an authenticated session: enabling stores a
  /// Keystore-protected DEK copy, disabling removes it.
  Future<void> setBiometricEnabled(bool enabled, {Uint8List? dataKey}) async {
    final manager = ref.read(masterKeyManagerProvider);
    if (enabled && dataKey != null) {
      await manager.enableBiometric(dataKey);
      _biometricEnabled = true;
    } else {
      await manager.disableBiometric();
      _biometricEnabled = false;
    }
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => ref
      .read(masterKeyManagerProvider)
      .changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );

  /// Verifies a password without altering the current session state. Used
  /// for sensitive-action confirmation (e.g. enabling biometrics).
  Future<bool> verifyPassword(String password) async {
    final result = await ref
        .read(masterKeyManagerProvider)
        .unlockWithPassword(password);
    return result is MasterKeySuccess;
  }

  void _resetFailures() {
    _failedAttempts = 0;
    _lockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _registerFailure() {
    _failedAttempts += 1;
    final index = _failedAttempts - _immediateAttempts - 1;
    final seconds = index < 0
        ? 0
        : unlockBackoffSeconds[index.clamp(0, unlockBackoffSeconds.length - 1)];
    if (seconds <= 0) {
      return;
    }
    _lockedUntil = DateTime.now().add(Duration(seconds: seconds));
    _backoffTimer?.cancel();
    _backoffTimer = Timer(Duration(seconds: seconds), () {
      final s = state.value;
      if (s is AuthLocked) {
        state = AsyncData(s);
      }
    });
  }
}
