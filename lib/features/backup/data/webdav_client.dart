import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart' show DioException;
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../domain/webdav_config.dart';

enum WebDavError { network, authFailed, notFound, httpOnlyRefused, serverError }

final class WebDavException implements Exception {
  const WebDavException(this.error, {this.statusCode});

  final WebDavError error;
  final int? statusCode;

  @override
  String toString() {
    // Intentionally excludes URLs, usernames and tokens.
    final code = statusCode == null ? '' : ' ($statusCode)';
    return 'WebDavException(${error.name}$code)';
  }
}

/// Thin wrapper over the WebDAV client. All failures are normalized to
/// [WebDavException] without echoing the URL, username or credentials.
abstract interface class IWebDavClient {
  Future<void> connect(WebDavConfig config, String password);
  Future<void> ping();
  Future<void> writeFile(String remotePath, String contents);
  Future<String?> readFile(String remotePath);
}

final class WebDavClientAdapter implements IWebDavClient {
  webdav.Client? _client;
  String? _directory;

  @override
  Future<void> connect(WebDavConfig config, String password) async {
    if (!config.url.startsWith('https://')) {
      if (!config.url.startsWith('http://') || !config.allowHttp) {
        throw const WebDavException(WebDavError.httpOnlyRefused);
      }
    }
    _directory = config.directory.trim();
    final client = webdav.newClient(
      config.url,
      user: config.username,
      password: password,
      debug: false,
    );
    client.setHeaders({'accept-charset': 'utf-8'});
    _client = client;
  }

  String _resolve(String path) {
    final dir = _directory?.trim() ?? '';
    if (dir.isEmpty) {
      return path;
    }
    return dir.endsWith('/') ? '$dir$path' : '$dir/$path';
  }

  @override
  Future<void> ping() async {
    try {
      await _client?.ping();
    } on WebDavException {
      rethrow;
    } on DioException catch (e) {
      throw WebDavException(_mapStatus(e), statusCode: e.response?.statusCode);
    } catch (_) {
      throw const WebDavException(WebDavError.network);
    }
  }

  @override
  Future<void> writeFile(String remotePath, String contents) async {
    try {
      final data = Uint8List.fromList(utf8.encode(contents));
      await _client?.write(_resolve(remotePath), data);
    } on WebDavException {
      rethrow;
    } on DioException catch (e) {
      throw WebDavException(_mapStatus(e), statusCode: e.response?.statusCode);
    } catch (_) {
      throw const WebDavException(WebDavError.network);
    }
  }

  @override
  Future<String?> readFile(String remotePath) async {
    try {
      final bytes = await _client?.read(_resolve(remotePath));
      return bytes == null ? null : utf8.decode(bytes);
    } on WebDavException {
      rethrow;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      throw WebDavException(_mapStatus(e), statusCode: e.response?.statusCode);
    } catch (_) {
      throw const WebDavException(WebDavError.network);
    }
  }

  static WebDavError _mapStatus(DioException e) {
    final status = e.response?.statusCode ?? 0;
    if (status == 401 || status == 403) {
      return WebDavError.authFailed;
    }
    if (status >= 500) {
      return WebDavError.serverError;
    }
    return WebDavError.network;
  }
}
