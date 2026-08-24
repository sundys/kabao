import 'dart:convert';

import '../../../core/security/secure_store.dart';

/// Non-secret WebDAV configuration. Credentials are never part of this
/// object's persisted form; the password lives under a separate secure
/// storage key (Android Keystore backed).
final class WebDavConfig {
  const WebDavConfig({
    required this.url,
    required this.username,
    this.directory = '',
    this.autoBackupEnabled = false,
    this.allowHttp = false,
    this.lastBackupAt,
  });

  /// Base URL, e.g. `https://dav.example.com/dav`. Never contains embedded
  /// credentials.
  final String url;
  final String username;
  final String directory;
  final bool autoBackupEnabled;

  /// True only after the user explicitly acknowledged plain-HTTP risk
  /// (development scenarios). Production default is HTTPS-only.
  final bool allowHttp;

  final DateTime? lastBackupAt;

  Map<String, Object?> toJson() => {
    'url': url,
    'username': username,
    'directory': directory,
    'autoBackupEnabled': autoBackupEnabled,
    'allowHttp': allowHttp,
    'lastBackupAt': lastBackupAt?.millisecondsSinceEpoch,
  };

  static WebDavConfig? fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      final lastBackupAt = json['lastBackupAt'];
      final url = json['url']! as String;
      if (!url.startsWith('https://') && !url.startsWith('http://')) {
        return null;
      }
      return WebDavConfig(
        url: url,
        username: json['username']! as String,
        directory: json['directory'] as String? ?? '',
        autoBackupEnabled: json['autoBackupEnabled'] == true,
        allowHttp: json['allowHttp'] == true,
        lastBackupAt: lastBackupAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (lastBackupAt as num).toInt(),
              ),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  String encoded() => jsonEncode(toJson());
}

final class WebDavCredentials {
  const WebDavCredentials({required this.username, required this.password});

  final String username;
  final String password;
}

/// Storage-backed profile: non-secret config plus separately stored secret.
abstract interface class WebDavProfileStore {
  Future<WebDavConfig?> readConfig();
  Future<void> writeConfig(WebDavConfig config);
  Future<String?> readPassword();
  Future<void> writePassword(String password);
  Future<void> clear();
}

final class SecureWebDavProfileStore implements WebDavProfileStore {
  SecureWebDavProfileStore({required this.storage});

  static const String _kConfig = 'kabao.webdav.config';
  static const String _kPassword = 'kabao.webdav.password';

  final SecureStore storage;

  @override
  Future<WebDavConfig?> readConfig() async =>
      WebDavConfig.fromJsonString(await storage.read(_kConfig));

  @override
  Future<void> writeConfig(WebDavConfig config) async =>
      storage.write(_kConfig, config.encoded());

  @override
  Future<String?> readPassword() => storage.read(_kPassword);

  @override
  Future<void> writePassword(String password) =>
      storage.write(_kPassword, password);

  @override
  Future<void> clear() async {
    await storage.delete(_kConfig);
    await storage.delete(_kPassword);
  }
}
