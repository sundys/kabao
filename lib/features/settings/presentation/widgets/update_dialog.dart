import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/app_config.dart';
import '../../../../shared/services/apk_installer.dart';
import '../../logic/update_service.dart';

/// 关于页「检测更新」入口：检查 → 提示 → 下载 → 调起系统安装器。
///
/// 只有用户手动触发才会联网，应用不会在后台自动检测。
Future<void> checkForUpdates(BuildContext context) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final currentVersion = (await PackageInfo.fromPlatform()).version;
  if (!context.mounted) {
    return;
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _CheckingDialog(),
  );
  UpdateCheckResult result;
  try {
    result = await UpdateService().check(currentVersion: currentVersion);
  } finally {
    if (navigator.mounted) {
      navigator.pop();
    }
  }
  if (!context.mounted) {
    return;
  }

  switch (result) {
    case UpdateUpToDate():
      await showDialog<void>(
        context: context,
        builder: (_) => _MessageDialog(
          icon: Icons.verified_outlined,
          title: '已是最新版本',
          message: '当前版本 v$currentVersion 已是最新，无需更新。',
        ),
      );
    case UpdateCheckFailure(:final message):
      await showDialog<void>(
        context: context,
        builder: (_) => _MessageDialog(
          icon: Icons.cloud_off_outlined,
          title: '检测更新失败',
          message: '$message\n\n也可以直接前往发布页手动下载。',
          actionLabel: '前往发布页',
          onAction: () => launchUrl(Uri.parse(AppConfig.latestReleaseUrl)),
        ),
      );
    case UpdateAvailable(:final info):
      await showDialog<void>(
        context: context,
        builder: (_) =>
            UpdateDialog(info: info, currentVersion: currentVersion),
      );
  }
}

class _CheckingDialog extends StatelessWidget {
  const _CheckingDialog();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 18),
            const Text('正在检查更新…'),
          ],
        ),
      ),
    );
  }
}

/// 轻量提示弹窗（已是最新 / 检测失败）。
class _MessageDialog extends StatelessWidget {
  const _MessageDialog({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      icon: Icon(icon, size: 34, color: theme.colorScheme.primary),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        if (actionLabel != null)
          FilledButton(
            onPressed: () async {
              await onAction?.call();
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

enum _UpdateStage {
  /// 尚未下载，等待用户点击「立即更新」。
  ready,

  /// 正在下载安装包。
  downloading,

  /// 已下载完成，等待用户在系统设置里授予「安装未知应用」。
  permission,

  /// 正在调起系统安装器。
  installing,

  /// 安装器已调起，等待用户在系统界面完成安装。
  installPending,

  /// 从安装器返回但版本没有变化（取消或安装失败），可直接重装。
  reinstall,

  /// 流程失败，可重试或前往发布页。
  failed,
}

/// 更新窗口：展示新版本与更新说明，下载时显示进度，完成后调用系统安装器。
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.info,
    required this.currentVersion,
    this.service,
    this.installer = const ApkInstaller(),
  });

  final UpdateInfo info;
  final String currentVersion;

  /// 供测试注入替身；为空时使用真实实现。
  final UpdateService? service;
  final ApkInstaller installer;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog>
    with WidgetsBindingObserver {
  _UpdateStage _stage = _UpdateStage.ready;
  String? _error;

  /// 已下载完成的安装包路径。不为空时「重新安装」直接复用，不会再下载一次。
  String? _apkPath;

  int _received = 0;
  int _total = 0;
  double _bytesPerSecond = 0;
  int _lastReceived = 0;
  DateTime _lastTick = DateTime.now();

  /// 已跳转系统设置申请安装权限，等待用户返回。
  bool _awaitingPermission = false;

  /// 已调起系统安装器，等待用户返回。
  bool _awaitingInstall = false;

  CancelToken? _cancelToken;
  late final UpdateService _service = widget.service ?? UpdateService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelToken?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    if (_awaitingPermission) {
      _awaitingPermission = false;
      unawaited(_continueAfterPermission());
      return;
    }
    if (_awaitingInstall) {
      _awaitingInstall = false;
      unawaited(_afterInstaller());
    }
  }

  double get _progress => _total > 0 ? (_received / _total).clamp(0, 1) : 0;

  Future<void> _start() async {
    setState(() {
      _stage = _UpdateStage.downloading;
      _error = null;
      _apkPath = null;
      _received = 0;
      _total = 0;
      _bytesPerSecond = 0;
      _lastReceived = 0;
      _lastTick = DateTime.now();
    });
    try {
      final asset = await _resolveAsset();
      if (asset == null) {
        throw const UpdateDownloadException('该版本没有适配本机 CPU 架构的安装包，请前往发布页手动下载。');
      }
      final path = await UpdateService.cachePathFor(widget.info.version);
      final token = CancelToken();
      _cancelToken = token;
      await _service.download(
        asset,
        targetPath: path,
        cancelToken: token,
        onProgress: (received, total) {
          if (!mounted) {
            return;
          }
          final now = DateTime.now();
          final elapsed = now.difference(_lastTick).inMilliseconds;
          if (elapsed >= 400) {
            setState(() {
              _bytesPerSecond = (received - _lastReceived) * 1000 / elapsed;
              _lastReceived = received;
              _lastTick = now;
            });
          }
          setState(() {
            _received = received;
            _total = total > 0 ? total : _total;
          });
        },
      );
      _apkPath = path;
      if (!mounted) {
        return;
      }
      await _continueAfterPermission();
    } on UpdateDownloadException catch (error) {
      _fail(error.message);
    } on DioException catch (error) {
      _fail(CancelToken.isCancel(error) ? '已取消更新' : '下载失败，请检查网络后重试。');
    } catch (_) {
      _fail('更新失败，请稍后重试。');
    }
  }

  Future<ReleaseAsset?> _resolveAsset() async {
    final abis = await widget.installer.supportedAbis();
    return widget.info.apkForAbis(abis);
  }

  /// 本地是否已有可以直接安装的安装包：平台支持安装，且安装包还在缓存里。
  bool get _hasInstallablePackage =>
      _apkPath != null && widget.installer.isSupported;

  /// 主按钮动作：已经有安装包就直接安装，否则先下载。
  Future<void> _primaryAction() =>
      _hasInstallablePackage ? _continueAfterPermission() : _start();

  /// 安装前确认「安装未知应用」权限；缺失时跳转设置，待用户返回后继续。
  Future<void> _continueAfterPermission() async {
    if (_apkPath == null) {
      return;
    }
    if (!widget.installer.isSupported) {
      _fail('当前平台不支持直接安装，请前往发布页下载。');
      return;
    }
    final allowed = await widget.installer.canInstallPackages();
    if (!mounted) {
      return;
    }
    if (!allowed) {
      setState(() => _stage = _UpdateStage.permission);
      _awaitingPermission = true;
      await widget.installer.openInstallPermissionSettings();
      return;
    }
    await _launchInstaller();
  }

  /// 调起系统安装器安装已经下载好的安装包，这里不会再发起下载。
  Future<void> _launchInstaller() async {
    final path = _apkPath;
    if (path == null) {
      return;
    }
    if (!await File(path).exists()) {
      // 安装包已被系统清理，只能重新下载。
      await _start();
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _stage = _UpdateStage.installing);
    bool launched;
    try {
      launched = await widget.installer.install(path);
    } catch (_) {
      launched = false;
    }
    if (!mounted) {
      return;
    }
    if (!launched) {
      _fail('无法调起系统安装器，请点击「重新安装」重试。');
      return;
    }
    // 不关闭窗口：安装成功时本进程会被系统结束，安装失败或被取消时用户会回到
    // 这里，直接「重新安装」即可，不必重新下载。
    setState(() => _stage = _UpdateStage.installPending);
    _awaitingInstall = true;
  }

  /// 用户从系统安装器返回。
  ///
  /// 版本已经提升说明安装成功；否则停在窗口里，让用户直接重新安装缓存中的安装包。
  Future<void> _afterInstaller() async {
    if (!mounted || _stage != _UpdateStage.installPending) {
      return;
    }
    var installed = false;
    try {
      final version = (await PackageInfo.fromPlatform()).version;
      installed = compareVersions(version, widget.info.version) >= 0;
    } catch (_) {
      // 读不到版本时按「尚未安装」处理，让用户可以直接重试。
    }
    if (!mounted || _stage != _UpdateStage.installPending) {
      return;
    }
    if (installed) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _stage = _UpdateStage.reinstall);
  }

  void _fail(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _stage = _UpdateStage.failed;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopScope(
      // 下载中不允许点击遮罩关闭，避免留下残缺的缓存文件。
      canPop: _stage != _UpdateStage.downloading,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(22, 24, 22, 8),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [scheme.primary, scheme.tertiary],
                    ),
                  ),
                  child: const Icon(
                    Icons.system_update_alt_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '发现新版本',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: _VersionPill(
                  from: widget.currentVersion,
                  to: widget.info.version,
                ),
              ),
              if (widget.info.notes.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  '更新内容',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 148),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: .5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      widget.info.notes,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _buildStatus(theme),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildStatus(ThemeData theme) {
    switch (_stage) {
      case _UpdateStage.ready:
        return const SizedBox.shrink();
      case _UpdateStage.downloading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _total > 0 ? _progress : null,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _total > 0
                      ? '${(_progress * 100).toStringAsFixed(0)}%'
                      : '正在连接…',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  _total > 0
                      ? '${_formatMB(_received)} / ${_formatMB(_total)}'
                      : '',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            if (_bytesPerSecond > 0)
              Text(
                '${_formatSpeed(_bytesPerSecond)}/s',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        );
      case _UpdateStage.permission:
        return const _HintRow(
          icon: Icons.info_outline,
          text: '请在弹出的系统设置中允许「安装未知应用」，返回后将继续安装。',
        );
      case _UpdateStage.installing:
        return const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            SizedBox(width: 12),
            Text('正在调起系统安装器…'),
          ],
        );
      case _UpdateStage.installPending:
        return const _HintRow(
          icon: Icons.download_done_rounded,
          text: '安装包已下载完成，请在系统安装界面完成安装。',
        );
      case _UpdateStage.reinstall:
        return const _HintRow(
          icon: Icons.refresh_rounded,
          text: '安装未完成，可直接重新安装，无需重新下载。',
        );
      case _UpdateStage.failed:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer.withValues(alpha: .45),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(
                Icons.error_outline,
                size: 18,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_error ?? '更新失败', style: theme.textTheme.bodySmall),
              ),
            ],
          ),
        );
    }
  }

  /// 主按钮文案：只要本地还留着可安装的安装包，就不需要再下载一遍。
  String get _primaryLabel {
    switch (_stage) {
      case _UpdateStage.downloading:
        return '下载中…';
      case _UpdateStage.installing:
        return '安装中…';
      case _UpdateStage.permission:
        return '我已允许';
      case _UpdateStage.ready:
        return _hasInstallablePackage ? '重新安装' : '立即更新';
      case _UpdateStage.installPending:
      case _UpdateStage.reinstall:
        return '重新安装';
      case _UpdateStage.failed:
        return _hasInstallablePackage ? '重新安装' : '重试';
    }
  }

  List<Widget> _buildActions() {
    final busy =
        _stage == _UpdateStage.downloading || _stage == _UpdateStage.installing;
    return [
      TextButton(
        onPressed: busy ? null : () => Navigator.of(context).pop(),
        child: Text(_stage == _UpdateStage.permission ? '稍后再说' : '稍后'),
      ),
      // 只有本地没有可用安装包时，才需要用户自己去发布页下载。
      if (_stage == _UpdateStage.failed && !_hasInstallablePackage)
        FilledButton(
          onPressed: () => launchUrl(Uri.parse(AppConfig.latestReleaseUrl)),
          child: const Text('前往发布页'),
        ),
      FilledButton(
        onPressed: busy
            ? null
            : switch (_stage) {
                _UpdateStage.permission => _continueAfterPermission,
                _ => _primaryAction,
              },
        child: Text(_primaryLabel),
      ),
    ];
  }

  static String _formatMB(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  static String _formatSpeed(double bytesPerSecond) =>
      '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(2)} MB';
}

/// 状态区的一行提示：图标 + 说明。
class _HintRow extends StatelessWidget {
  const _HintRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
      ],
    );
  }
}

/// 「1.0.18 → 1.0.19」样式的版本标签。
class _VersionPill extends StatelessWidget {
  const _VersionPill({required this.from, required this.to});

  final String from;
  final String to;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'v$from',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 16,
              color: scheme.primary,
            ),
          ),
          Text(
            'v$to',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
