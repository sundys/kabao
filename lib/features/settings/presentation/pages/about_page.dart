import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/app_config.dart';

/// 版本号从应用包信息动态读取，随构建自动更新。
final _versionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final version = ref.watch(_versionProvider).value ?? AppConfig.appVersion;
    return Scaffold(
      appBar: AppBar(title: const Text('关于卡包')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  '${AppConfig.appName} $version',
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '卡包是一款本地加密的银行卡与证件信息管理应用。'
            '所有数据仅以加密形式保存在您的设备上，'
            '不连接任何业务服务器，不上传任何分析数据。',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('开源主页'),
            subtitle: const Text(AppConfig.githubHomepage),
            onTap: () => launchUrl(Uri.parse(AppConfig.githubHomepage)),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('最新版本下载'),
            subtitle: const Text(AppConfig.latestReleaseUrl),
            onTap: () => launchUrl(Uri.parse(AppConfig.latestReleaseUrl)),
          ),
          ListTile(
            leading: const Icon(Icons.table_view_outlined),
            title: const Text('CSV 批量导入模板下载'),
            subtitle: const Text('银行卡和证件 CSV / XLS 模板'),
            onTap: () => launchUrl(Uri.parse(AppConfig.importTemplatesUrl)),
          ),
        ],
      ),
    );
  }
}
