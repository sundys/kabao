import 'dart:async';

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

enum _UpdateStage { ready, downloading, permission, installing, failed }

/// 更新窗口：展示新版本与更新说明，下载时显示进度，完成后调用系统安装器。
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.info,
    required this.currentVersion,
  });

  final UpdateInfo info;
  final String currentVersion;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog>
    with WidgetsBindingObserver {
  _UpdateStage _stage = _UpdateStage.ready;
  String? _error;
  String? _apkPath;

  int _received = 0;
  int _total = 0;
  double _bytesPerSecond = 0;
  int _lastReceived = 0;
  DateTime _lastTick = DateTime.now();

  /// 已跳转系统设置申请安装权限，等待用户返回。
  bool _awaitingPermission = false;

  CancelToken? _cancelToken;
  final UpdateService _service = UpdateService();

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
    if (state == AppLifecycleState.resumed && _awaitingPermission) {
      _awaitingPermission = false;
      unawaited(_continueAfterPermission());
    }
  }

  double get _progress => _total > 0 ? (_received / _total).clamp(0, 1) : 0;

  Future<void> _start() async {
    setState(() {
      _stage = _UpdateStage.downloading;
      _error = null;
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
    final abis = await ApkInstaller.supportedAbis();
    return widget.info.apkForAbis(abis);
  }

  /// 安装前确认「安装未知应用」权限；缺失时跳转设置，待用户返回后继续。
  Future<void> _continueAfterPermission() async {
    final path = _apkPath;
    if (path == null) {
      return;
    }
    if (!ApkInstaller.isSupported) {
      _fail('当前平台不支持直接安装，请前往发布页下载。');
      return;
    }
    final allowed = await ApkInstaller.canInstallPackages();
    if (!mounted) {
      return;
    }
    if (!allowed) {
      setState(() => _stage = _UpdateStage.permission);
      _awaitingPermission = true;
      await ApkInstaller.openInstallPermissionSettings();
      return;
    }
    setState(() => _stage = _UpdateStage.installing);
    final launched = await ApkInstaller.install(path);
    if (!mounted) {
      return;
    }
    if (!launched) {
      _fail('无法调起系统安装器，请前往发布页手动下载。');
      return;
    }
    // 系统安装界面已经弹出，关闭本窗口避免遮挡。
    Navigator.of(context).pop();
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
        return Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '请在弹出的系统设置中允许「安装未知应用」，返回后将继续安装。',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
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

  List<Widget> _buildActions() {
    final busy =
        _stage == _UpdateStage.downloading || _stage == _UpdateStage.installing;
    return [
      TextButton(
        onPressed: busy ? null : () => Navigator.of(context).pop(),
        child: Text(_stage == _UpdateStage.permission ? '稍后再说' : '稍后'),
      ),
      if (_stage == _UpdateStage.failed)
        FilledButton(
          onPressed: () async {
            await launchUrl(Uri.parse(AppConfig.latestReleaseUrl));
          },
          child: const Text('前往发布页'),
        ),
      FilledButton(
        onPressed: busy
            ? null
            : switch (_stage) {
                _UpdateStage.failed => _start,
                _UpdateStage.permission => _continueAfterPermission,
                _ => _start,
              },
        child: Text(switch (_stage) {
          _UpdateStage.failed => '重试',
          _UpdateStage.permission => '我已允许',
          _UpdateStage.downloading => '下载中…',
          _ => '立即更新',
        }),
      ),
    ];
  }

  static String _formatMB(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  static String _formatSpeed(double bytesPerSecond) =>
      '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(2)} MB';
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
