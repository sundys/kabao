import 'dart:typed_data';

sealed class AuthState {
  const AuthState();
}

final class AuthInitializing extends AuthState {
  const AuthInitializing();
}

/// First launch: no master password exists yet.
final class AuthNeedsSetup extends AuthState {
  const AuthNeedsSetup();
}

final class AuthLocked extends AuthState {
  const AuthLocked({this.biometricEnabled = false});

  final bool biometricEnabled;
}

final class AuthUnlocked extends AuthState {
  const AuthUnlocked(this.dataKey);

  /// In-memory DEK for the current session. Must never be logged or
  /// persisted.
  final Uint8List dataKey;
}
