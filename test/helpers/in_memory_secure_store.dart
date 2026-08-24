import 'package:kabao/core/security/secure_store.dart';

/// In-memory SecureStore for tests. Values never leave process memory and
/// mirror the real store's contract closely enough for unit tests.
final class InMemorySecureStore implements SecureStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<Map<String, String>> readAll() async => Map.of(_values);

  @override
  Future<void> deleteAll() async => _values.clear();
}
