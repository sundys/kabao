import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/app_config.dart';
import '../widgets/update_dialog.dart';

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
          _AboutTile(
            icon: Icons.code,
            title: '开源主页',
            link: true,
            onTap: () => _openUrl(context, AppConfig.githubHomepage),
          ),
          _AboutTile(
            icon: Icons.system_update_alt_rounded,
            title: '检测更新',
            onTap: () => checkForUpdates(context),
          ),
          _AboutTile(
            icon: Icons.table_view_outlined,
            title: 'CSV 批量导入模板下载',
            link: true,
            onTap: () => _openUrl(context, AppConfig.importTemplatesUrl),
          ),
        ],
      ),
    );
  }

  /// 打开外部链接；失败时给出提示，避免点击后毫无反应。
  Future<void> _openUrl(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse(url));
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('无法打开链接，请检查是否已安装浏览器')),
      );
    }
  }
}

/// 关于页的一行入口。[link] 为真时标题按超链接样式显示（外部跳转）。
class _AboutTile extends StatelessWidget {
  const _AboutTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.link = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool link;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      leading: Icon(icon, color: link ? scheme.primary : null),
      title: Text(
        title,
        style: link
            ? theme.textTheme.bodyLarge?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.underline,
                decorationColor: scheme.primary.withValues(alpha: .5),
              )
            : null,
      ),
      onTap: onTap,
    );
  }
}
