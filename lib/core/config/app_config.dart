/// App-wide non-secret configuration.
abstract final class AppConfig {
  static const String appName = '卡包';

  /// 兜底版本号；正常情况下关于页从包信息动态读取。
  static const String appVersion = '1.0.9';

  /// Open-source homepage and release source.
  static const String githubRepo = 'sundys/kabao';
  static const String githubHomepage = 'https://github.com/sundys/kabao';

  /// Standard CSV/XLS import templates in the source repository.
  static const String importTemplatesUrl =
      'https://github.com/sundys/kabao/tree/master/templates';

  /// 发布页面（最新版本下载地址）。
  static const String latestReleaseUrl =
      'https://github.com/$githubRepo/releases/latest';
}
