import 'dart:convert';
import 'dart:io';

/// App-wide non-secret configuration.
abstract final class AppConfig {
  static const String appName = '卡包';
  static const String appVersion = '1.0.0';

  /// Open-source homepage and release source.
  static const String githubRepo = 'sundys/kabao';
  static const String githubHomepage = 'https://github.com/sundys/kabao';

  /// 发布页面（最新版本下载地址）。
  static const String latestReleaseUrl =
      'https://github.com/$githubRepo/releases/latest';
  static const String releasesApiUrl =
      'https://api.github.com/repos/$githubRepo/releases/latest';

  /// Returns the newer version tag when [latestTag] > current, else null.
  /// Accepts tags like `v1.2.3` or plain `1.2.3`.
  static String? compareVersions(String latestTag) {
    final latest = _normalize(latestTag);
    final current = _normalize(appVersion);
    if (latest == null || current == null) {
      return null;
    }
    int compare(List<int> a, List<int> b) {
      for (var i = 0; i < a.length.clamp(0, b.length); i++) {
        if (a[i] != b[i]) {
          return a[i] - b[i];
        }
      }
      return a.length - b.length;
    }

    final la = latest.split('.').map(int.parse).toList();
    final ca = current.split('.').map(int.parse).toList();
    return compare(la, ca) > 0 ? latest : null;
  }

  static String? _normalize(String tag) {
    var value = tag.trim();
    if (value.startsWith('v')) {
      value = value.substring(1);
    }
    return RegExp(r'^\d+(\.\d+)*$').hasMatch(value) ? value : null;
  }
}

final class UpdateCheckResult {
  const UpdateCheckResult({
    this.hasUpdate = false,
    this.latestVersion,
    this.releaseUrl,
    this.failed = false,
  });

  final bool hasUpdate;
  final String? latestVersion;
  final String? releaseUrl;
  final bool failed;

  bool get isUpToDate => !hasUpdate && !failed;
}

/// Manual update check against GitHub Releases. Never runs automatically
/// (product requirement: user-triggered only).
Future<UpdateCheckResult> checkForUpdate({HttpClient? client}) async {
  final factory = client ?? HttpClient();
  try {
    final request = await factory.getUrl(Uri.parse(AppConfig.releasesApiUrl));
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github+json',
    );
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      await response.drain<void>();
      return const UpdateCheckResult(failed: true);
    }
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, Object?>;
    final tagName = json['tag_name'] as String?;
    final htmlUrl = json['html_url'] as String?;
    if (tagName == null) {
      return const UpdateCheckResult(failed: true);
    }
    final newer = AppConfig.compareVersions(tagName);
    return UpdateCheckResult(
      hasUpdate: newer != null,
      latestVersion: newer ?? tagName,
      releaseUrl: htmlUrl ?? AppConfig.githubHomepage,
    );
  } catch (_) {
    return const UpdateCheckResult(failed: true);
  } finally {
    factory.close(force: false);
  }
}
