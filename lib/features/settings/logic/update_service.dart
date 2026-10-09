import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/config/app_config.dart';

/// 一次发布中的可下载文件。
final class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.downloadUrl});

  final String name;
  final String downloadUrl;
}

/// 从公开的 GitHub Release 读到的更新信息，不含任何用户数据。
final class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.assets,
    required this.releaseUrl,
  });

  /// 去掉前缀 `v` 的版本号，例如 `1.0.19`。
  final String version;

  /// Release 说明正文，可能为空。
  final String notes;

  final List<ReleaseAsset> assets;

  final String releaseUrl;

  /// 按设备 ABI 选出对应的 APK 资源；没有匹配项时返回 null。
  ///
  /// [abis] 来自 `Build.SUPPORTED_ABIS`，顺序即优先级。
  ReleaseAsset? apkForAbis(List<String> abis) {
    for (final abi in abis) {
      final suffix = _abiSuffix(abi);
      if (suffix == null) {
        continue;
      }
      for (final asset in assets) {
        final name = asset.name.toLowerCase();
        if (name.endsWith('.apk') && name.contains(suffix)) {
          return asset;
        }
      }
    }
    return null;
  }

  static String? _abiSuffix(String abi) {
    final normalized = abi.toLowerCase();
    if (normalized.startsWith('arm64') || normalized == 'aarch64') {
      return 'arm64-v8a';
    }
    if (normalized.startsWith('armeabi')) {
      return 'armeabi-v7a';
    }
    if (normalized.startsWith('x86_64') || normalized == 'x64') {
      return 'x86_64';
    }
    return null;
  }
}

/// 检测更新的结果。
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

/// 已经是最新版本。
final class UpdateUpToDate extends UpdateCheckResult {
  const UpdateUpToDate();
}

/// 有可用更新。
final class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable(this.info);

  final UpdateInfo info;
}

/// 检测失败（离线、所有代理都不可用、返回内容无法解析等）。
final class UpdateCheckFailure extends UpdateCheckResult {
  const UpdateCheckFailure(this.message);

  final String message;
}

/// 下载更新包时的失败。
final class UpdateDownloadException implements Exception {
  const UpdateDownloadException(this.message);

  final String message;

  @override
  String toString() => 'UpdateDownloadException($message)';
}

/// 版本号比较：只比较 `major.minor.patch`，忽略构建号与预发布后缀。
int compareVersions(String a, String b) {
  final left = _numericParts(a);
  final right = _numericParts(b);
  for (var i = 0; i < left.length; i++) {
    final diff = left[i].compareTo(right[i]);
    if (diff != 0) {
      return diff;
    }
  }
  return 0;
}

List<int> _numericParts(String version) {
  final core = version.split('+').first.split('-').first;
  final parts = core.split('.');
  final result = <int>[];
  for (var i = 0; i < 3; i++) {
    result.add(i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0);
  }
  return result;
}

/// 只负责公开 Release 的读取与下载，不接触任何本地业务数据。
final class UpdateService {
  UpdateService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: _requestTimeout,
              sendTimeout: _requestTimeout,
              receiveTimeout: _requestTimeout,
              // 交给下面的逐项 try/catch 处理，避免 Dio 直接抛出。
              validateStatus: (status) => status != null && status < 500,
            ),
          );

  static const Duration _requestTimeout = Duration(seconds: 12);

  final Dio _dio;

  /// 依次尝试直连与各加速前缀，返回最新发布；没有发布时返回 null。
  Future<UpdateCheckResult> check({
    required String currentVersion,
    CancelToken? cancelToken,
  }) async {
    final api = await _checkViaApi(cancelToken);
    if (api.sawNotFound) {
      return const UpdateCheckFailure('暂未找到可用的发布版本');
    }
    // 部分代理只转发 github.com、不转发 api.github.com，此时退回发布页取标签。
    final info = api.info ?? await _checkViaReleasePage(cancelToken);
    if (info == null) {
      return const UpdateCheckFailure('无法连接更新服务器，请检查网络后重试');
    }
    return compareVersions(info.version, currentVersion) > 0
        ? UpdateAvailable(info)
        : const UpdateUpToDate();
  }

  Future<({UpdateInfo? info, bool sawNotFound})> _checkViaApi(
    CancelToken? cancelToken,
  ) async {
    var sawNotFound = false;
    for (final prefix in AppConfig.githubProxies) {
      try {
        final response = await _dio.get<Map<String, Object?>>(
          '$prefix${AppConfig.latestReleaseApiUrl}',
          cancelToken: cancelToken,
          options: Options(
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'kabao-update-check',
            },
          ),
        );
        final status = response.statusCode ?? 0;
        if (status == 404) {
          // 仓库尚无 Release，换代理也是同样结果。
          sawNotFound = true;
          break;
        }
        final data = response.data;
        if (status != 200 || data == null) {
          continue;
        }
        final info = _parseRelease(data);
        if (info != null) {
          return (info: info, sawNotFound: false);
        }
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) {
          rethrow;
        }
      } catch (_) {
        // 换下一个代理继续尝试。
      }
    }
    return (info: null, sawNotFound: sawNotFound);
  }

  /// 发布页兜底：读取 `releases/latest` 的跳转标签，再按发布约定推导 APK 地址
  /// （CI 固定产出 `kabao-<版本>-<abi>.apk`）。拿不到更新说明，但能完成升级。
  Future<UpdateInfo?> _checkViaReleasePage(CancelToken? cancelToken) async {
    for (final prefix in AppConfig.githubProxies) {
      try {
        final response = await _dio.get<String>(
          '$prefix${AppConfig.latestReleaseUrl}',
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: false,
            headers: const {'User-Agent': 'kabao-update-check'},
          ),
        );
        final location = response.headers.value('location');
        final tag =
            _tagFromText(location ?? '') ?? _tagFromText(response.data ?? '');
        if (tag == null) {
          continue;
        }
        final version = normalizeVersion(tag);
        return UpdateInfo(
          version: version,
          notes: '',
          releaseUrl: '${AppConfig.githubHomepage}/releases/tag/$tag',
          assets: [
            for (final abi in const ['arm64-v8a', 'armeabi-v7a'])
              ReleaseAsset(
                name: 'kabao-$version-$abi.apk',
                downloadUrl:
                    '${AppConfig.githubHomepage}/releases/download/$tag/'
                    'kabao-$version-$abi.apk',
              ),
          ],
        );
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) {
          rethrow;
        }
      } catch (_) {
        // 换下一个代理继续尝试。
      }
    }
    return null;
  }

  static final RegExp _tagPattern = RegExp(r'releases/tag/(v?\d+\.\d+\.\d+)');

  /// 从跳转地址或页面内容里提取版本标签。
  static String? _tagFromText(String text) {
    if (text.isEmpty) {
      return null;
    }
    final match = _tagPattern.firstMatch(text);
    return match?.group(1);
  }

  UpdateInfo? _parseRelease(Map<String, Object?> json) {
    final tag = json['tag_name'];
    if (tag is! String || tag.isEmpty) {
      return null;
    }
    final assets = <ReleaseAsset>[];
    final rawAssets = json['assets'];
    if (rawAssets is List) {
      for (final item in rawAssets) {
        if (item is! Map) {
          continue;
        }
        final name = item['name'];
        final url = item['browser_download_url'];
        if (name is String && url is String && url.isNotEmpty) {
          assets.add(ReleaseAsset(name: name, downloadUrl: url));
        }
      }
    }
    return UpdateInfo(
      version: normalizeVersion(tag),
      notes: (json['body'] as String?)?.trim() ?? '',
      assets: assets,
      releaseUrl: (json['html_url'] as String?) ?? AppConfig.latestReleaseUrl,
    );
  }

  /// 依次尝试直连与各加速前缀，把 [asset] 下载到 [targetPath]。
  Future<File> download(
    ReleaseAsset asset, {
    required String targetPath,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    Object? lastError;
    for (final prefix in AppConfig.githubProxies) {
      final file = File(targetPath);
      try {
        if (await file.exists()) {
          await file.delete();
        }
        await _dio.download(
          '$prefix${asset.downloadUrl}',
          targetPath,
          cancelToken: cancelToken,
          onReceiveProgress: onProgress,
          options: Options(
            headers: const {'User-Agent': 'kabao-update-check'},
            receiveTimeout: const Duration(minutes: 30),
          ),
        );
        if (await file.exists() && await file.length() > 0) {
          return file;
        }
        lastError = const UpdateDownloadException('下载内容为空');
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) {
          rethrow;
        }
        lastError = error;
      } catch (error) {
        lastError = error;
      }
    }
    throw UpdateDownloadException(
      lastError == null ? '下载失败，请稍后重试' : '下载失败，请检查网络后重试',
    );
  }

  /// 更新包缓存路径；目录不存在时创建。
  static Future<String> cachePathFor(String version) async {
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, AppConfig.updateCacheDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return p.join(dir.path, 'kabao-$version.apk');
  }
}

/// 去掉 Release 标签的 `v` 前缀。
String normalizeVersion(String tag) {
  final trimmed = tag.trim();
  return trimmed.startsWith('v') || trimmed.startsWith('V')
      ? trimmed.substring(1)
      : trimmed;
}
