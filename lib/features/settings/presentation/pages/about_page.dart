import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/app_config.dart';

class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  bool _checking = false;
  UpdateCheckResult? _result;

  Future<void> _checkUpdate() async {
    setState(() => _checking = true);
    final result = await checkForUpdate();
    if (!mounted) {
      return;
    }
    setState(() {
      _checking = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  '${AppConfig.appName} ${AppConfig.appVersion}',
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '卡包是一款本地加密的银行卡信息管理应用。'
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
            leading: const Icon(Icons.new_releases_outlined),
            title: const Text('检查更新'),
            subtitle: _updateSubtitle == null ? null : Text(_updateSubtitle!),
            trailing: _checking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _checking ? null : _checkUpdate,
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('最新版本下载'),
            subtitle: const Text(AppConfig.latestReleaseUrl),
            onTap: () => launchUrl(Uri.parse(AppConfig.latestReleaseUrl)),
          ),
          if (_result != null && _result!.hasUpdate && mounted)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(_result!.releaseUrl ?? AppConfig.githubHomepage),
                ),
                icon: const Icon(Icons.open_in_new),
                label: Text('前往下载新版本 v${_result!.latestVersion}'),
              ),
            ),
        ],
      ),
    );
  }

  String? get _updateSubtitle {
    final result = _result;
    if (result == null || result.failed) {
      return '手动检查 GitHub 上的最新版本';
    }
    if (result.hasUpdate) {
      return '发现新版本 v${result.latestVersion}';
    }
    return '当前已是最新版本';
  }
}
