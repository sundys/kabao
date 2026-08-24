import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/repositories_providers.dart';
import '../../wallet/domain/models.dart';
import '../domain/webdav_config.dart';
import '../logic/backup_service.dart';
import '../logic/cloud_backup_service.dart';
import '../logic/webdav_provider.dart';

/// WebDAV configuration with explicit backup policy. Test connection never
/// implies automatic backups; the toggle below controls them and states the
/// exact policy.
class WebDavSettingsPage extends ConsumerStatefulWidget {
  const WebDavSettingsPage({super.key});

  @override
  ConsumerState<WebDavSettingsPage> createState() => _WebDavSettingsPageState();
}

class _WebDavSettingsPageState extends ConsumerState<WebDavSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _directoryController = TextEditingController();

  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final config = await ref.read(webDavConfigProvider.future);
    if (!mounted) {
      return;
    }
    setState(() {
      if (config != null) {
        _urlController.text = config.url;
        _usernameController.text = config.username;
        _directoryController.text = config.directory;
      }
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _directoryController.dispose();
    super.dispose();
  }

  Future<(WebDavConfig, String)?> _collect() async {
    if (!_formKey.currentState!.validate()) {
      return null;
    }
    var password = _passwordController.text;
    if (password.isEmpty) {
      password =
          await ref.read(webDavConfigProvider.notifier).readPassword() ?? '';
    }
    if (password.isEmpty) {
      if (!mounted) {
        return null;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入密码/令牌')));
      return null;
    }
    if (!mounted) {
      return null;
    }
    final current = ref.read(webDavConfigProvider).value;
    final allowHttp = _urlController.text.startsWith('http://')
        ? current?.allowHttp == true || await _confirmHttp(context)
        : false;
    return (
      WebDavConfig(
        url: _urlController.text.trim(),
        username: _usernameController.text.trim(),
        directory: _directoryController.text.trim(),
        autoBackupEnabled: current?.autoBackupEnabled ?? false,
        allowHttp: allowHttp,
        lastBackupAt: current?.lastBackupAt,
      ),
      password,
    );
  }

  static Future<bool> _confirmHttp(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('使用不加密的 HTTP？'),
        content: const Text(
          'HTTP 不加密传输，卡片密文虽仍受备份密码保护，'
          '但服务器地址与账号可能被窃听。仅建议开发环境使用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('我已了解风险'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _testConnection() async {
    final collected = await _collect();
    if (collected == null) {
      return;
    }
    final (config, password) = collected;
    setState(() => _busy = true);
    try {
      await ref
          .read(cloudBackupServiceProvider)
          .testConnection(config: config, password: password);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('连接成功')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('连接失败：请检查地址、账号或密码')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _save() async {
    final collected = await _collect();
    if (collected == null) {
      return;
    }
    final (config, password) = collected;
    await ref.read(webDavConfigProvider.notifier).save(config, password);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('配置已保存')));
  }

  Future<void> _backupNow() async {
    final collected = await _collect();
    if (collected == null) {
      return;
    }
    final (config, password) = collected;
    setState(() => _busy = true);
    try {
      final categoryRepo = ref.read(categoryRepositoryProvider)!;
      final cardRepo = ref.read(cardRepositoryProvider)!;
      await ref
          .read(cloudBackupServiceProvider)
          .upload(
            config: config,
            password: password,
            categories: [
              ...await categoryRepo.listByType(CardType.debit),
              ...await categoryRepo.listByType(CardType.credit),
            ],
            cards: [
              ...await cardRepo.listByType(CardType.debit),
              ...await cardRepo.listByType(CardType.credit),
            ],
          );
      await ref
          .read(webDavConfigProvider.notifier)
          .updateConfig(
            WebDavConfig(
              url: config.url,
              username: config.username,
              directory: config.directory,
              autoBackupEnabled: config.autoBackupEnabled,
              allowHttp: config.allowHttp,
              lastBackupAt: DateTime.now(),
            ),
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('云端备份完成')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('云端备份失败，请检查网络与配置')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _restoreFromCloud() async {
    final collected = await _collect();
    if (collected == null) {
      return;
    }
    final (config, password) = collected;
    setState(() => _busy = true);
    try {
      final snapshot = await ref
          .read(cloudBackupServiceProvider)
          .download(config: config, password: password);
      if (!mounted) {
        return;
      }
      if (snapshot == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('云端还没有备份')));
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('从云端恢复'),
          content: Text(
            '将合并 ${snapshot.categories.length} 个分类、'
            '${snapshot.cards.length} 张卡片。\n\n'
            '相同 ID 的记录以更新时间较新者为准，不会删除现有数据。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('开始恢复'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
      final db = ref.read(vaultDatabaseProvider).value!;
      final result = await BackupService(database: db).importMerge(snapshot);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('恢复完成：$result')));
    } on Exception catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('恢复失败：密码错误或网络异常')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(webDavConfigProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV 备份')),
      body: !_loaded && config == null
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: '服务器地址',
                      hintText: 'https://dav.example.com/dav',
                    ),
                    validator: (v) {
                      final value = v?.trim() ?? '';
                      if (value.startsWith('https://')) {
                        return null;
                      }
                      if (value.startsWith('http://')) {
                        return null; // requires explicit confirmation later
                      }
                      return '以 https:// 或 http:// 开头';
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(labelText: '账号'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入账号' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '密码 / 应用令牌',
                      hintText: '留空表示沿用已保存的密码',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _directoryController,
                    decoration: const InputDecoration(
                      labelText: '远程目录（可选）',
                      hintText: '例如 kabao',
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _testConnection,
                    icon: const Icon(Icons.network_check),
                    label: const Text('测试连接'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('保存配置'),
                  ),
                  const Divider(height: 32),
                  SwitchListTile(
                    title: const Text('自动云备份'),
                    subtitle: const Text(
                      '开启后：每次解锁时若距上次备份超过 24 小时则自动备份一次。'
                      '测试连接成功不会自动开启此功能。',
                    ),
                    value: config?.autoBackupEnabled ?? false,
                    onChanged: config == null
                        ? null
                        : (enabled) {
                            ref
                                .read(webDavConfigProvider.notifier)
                                .updateConfig(
                                  WebDavConfig(
                                    url: config.url,
                                    username: config.username,
                                    directory: config.directory,
                                    autoBackupEnabled: enabled,
                                    allowHttp: config.allowHttp,
                                    lastBackupAt: config.lastBackupAt,
                                  ),
                                );
                          },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _backupNow,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('立即备份到云端'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _restoreFromCloud,
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('从云端恢复'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('清除 WebDAV 配置'),
                          content: const Text('将删除服务器地址、账号与本机保存的密码。'),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              child: const Text('清除'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && mounted) {
                        await ref.read(webDavConfigProvider.notifier).clear();
                      }
                    },
                    icon: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    label: Text(
                      '清除配置',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
