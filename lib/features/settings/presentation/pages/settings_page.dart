import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';

import '../../../../app/app_routes.dart';
import '../../../../app/theme/theme_mode_controller.dart';
import '../../../auth/logic/auth_controller.dart';
import '../../../auth/models/auth_state.dart';
import '../../../backup/presentation/backup_flows.dart';
import '../../../backup/logic/csv_import_service.dart';
import '../../../../shared/services/local_notification_service.dart';
import '../../logic/lock_timeout_controller.dart';
import '../../logic/wipe_service.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool? _biometricsSupported;

  @override
  void initState() {
    super.initState();
    _localAuth.isDeviceSupported().then((supported) {
      if (mounted) {
        setState(() => _biometricsSupported = supported);
      }
    });
  }

  String _themeLabel(WidgetRef ref) {
    final mode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    return switch (mode) {
      ThemeMode.light => '浅色',
      ThemeMode.dark => '暗色',
      ThemeMode.system => '跟随系统',
    };
  }

  Future<void> _pickTheme(BuildContext context, WidgetRef ref) async {
    final current = ref.read(themeModeProvider).value ?? ThemeMode.system;
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('主题颜色'),
        children: [
          for (final (mode, label) in [
            (ThemeMode.light, '浅色'),
            (ThemeMode.dark, '暗色'),
            (ThemeMode.system, '跟随系统颜色设定'),
          ])
            ListTile(
              leading: Icon(switch (mode) {
                ThemeMode.light => Icons.light_mode_outlined,
                ThemeMode.dark => Icons.dark_mode_outlined,
                ThemeMode.system => Icons.brightness_auto_outlined,
              }),
              title: Text(label),
              trailing: mode == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(dialogContext).pop(mode),
            ),
        ],
      ),
    );
    if (selected != null && selected != current) {
      await ref.read(themeModeProvider.notifier).setMode(selected);
    }
  }

  /// 单选弹窗：实心圆点为当前档位，空心圆圈为未选中。选择后立即持久化，
  /// 状态一直保留到用户改选其它档位。
  Future<void> _pickLockTimeout(BuildContext context, WidgetRef ref) async {
    final current = ref.read(lockTimeoutProvider).value ?? LockTimeout.fallback;
    final selected = await showDialog<LockTimeout>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('超时时间'),
        children: [
          for (final timeout in LockTimeout.values)
            ListTile(
              leading: Icon(
                timeout == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: timeout == current
                    ? Theme.of(dialogContext).colorScheme.primary
                    : null,
              ),
              title: Text(timeout.label),
              selected: timeout == current,
              onTap: () => Navigator.of(dialogContext).pop(timeout),
            ),
        ],
      ),
    );
    if (selected != null && selected != current) {
      await ref.read(lockTimeoutProvider.notifier).setTimeout(selected);
    }
  }

  Future<void> _toggleBiometric(bool enabled) async {
    final authState = ref.read(authControllerProvider).value;
    if (enabled) {
      if (authState is! AuthUnlocked || !mounted) {
        return;
      }
      // 开启前必须验证 APP 主密码，防止陌生人随意添加指纹。
      final password = await _askMasterPassword(context);
      if (password == null || !mounted) {
        return;
      }
      final verified = await ref
          .read(authControllerProvider.notifier)
          .verifyPassword(password);
      if (!mounted) {
        return;
      }
      if (!verified) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('主密码错误，未开启')));
        return;
      }
      await ref
          .read(authControllerProvider.notifier)
          .setBiometricEnabled(true, dataKey: authState.dataKey);
    } else {
      await ref
          .read(authControllerProvider.notifier)
          .setBiometricEnabled(false);
    }
    if (mounted) {
      // 刷新开关状态显示。
      ref.invalidate(biometricEnabledProvider);
    }
  }

  Future<String?> _askMasterPassword(BuildContext context) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('验证主密码'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '开启生物识别解锁前，请先输入主密码确认身份。',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ),
              TextFormField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                autofillHints: const [AutofillHints.password],
                enableSuggestions: false,
                autocorrect: false,
                validator: (v) => (v == null || v.isEmpty) ? '请输入主密码' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogContext).pop(controller.text);
              }
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  /// Irreversible wipe: double confirmation, then business data, database
  /// file and all key material. The app returns to first-run setup.
  Future<void> _wipeAllData() async {
    final first = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空全部数据'),
        content: const Text(
          '所有卡片、分类、通知与主密码都将被永久删除，'
          '此操作无法撤销。建议先导出备份。\n\n确定继续吗？',
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          _WipeConfirmationActions(
            dialogContext: dialogContext,
            confirmLabel: '继续',
          ),
        ],
      ),
    );
    if (first != true || !mounted) {
      return;
    }
    final second = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('再次确认'),
        content: const Text('真的要删除全部数据吗？删除后将回到首次设置。'),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          _WipeConfirmationActions(
            dialogContext: dialogContext,
            confirmLabel: '全部删除',
          ),
        ],
      ),
    );
    if (second != true) {
      return;
    }
    await ref.read(wipeServiceProvider).wipeAll();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final biometricEnabled = ref.watch(biometricEnabledProvider).value ?? false;
    final lockTimeout =
        ref.watch(lockTimeoutProvider).value ?? LockTimeout.fallback;
    final lockTimeoutSubtitle = lockTimeout == LockTimeout.immediate
        ? '切换后台后立即锁定数据库'
        : '切换后台 ${lockTimeout.label}后锁定数据库';
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const _SectionHeader(title: '外观'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题颜色'),
            subtitle: Text(_themeLabel(ref)),
            onTap: () => _pickTheme(context, ref),
          ),
          const _SettingsDivider(),
          const _SectionHeader(title: '安全'),
          ListTile(
            leading: const Icon(Icons.password_outlined),
            title: const Text('修改主密码'),
            onTap: () => context.push(AppRoutes.changePassword),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('生物识别登录'),
            subtitle: Text(
              _biometricsSupported == false ? '当前设备不支持' : '使用指纹快速解锁',
            ),
            value: biometricEnabled,
            onChanged: _biometricsSupported == true ? _toggleBiometric : null,
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('超时时间'),
            subtitle: Text(lockTimeoutSubtitle),
            onTap: () => _pickLockTimeout(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('系统通知'),
            subtitle: const Text('管理到期提醒在 Android 通知栏的显示权限'),
            onTap: () async {
              await LocalNotificationService.instance.initialize();
              await LocalNotificationService.instance.openSettings();
            },
          ),
          const _SettingsDivider(),
          const _SectionHeader(title: '数据'),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('导入备份'),
            subtitle: const Text('从加密的 .kabao 备份文件恢复'),
            onTap: () => BackupFlows.import(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('导出备份'),
            subtitle: const Text('导出为独立加密的 .kabao 文件'),
            onTap: () => BackupFlows.export(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.table_rows_outlined),
            title: const Text('导入银行卡 CSV'),
            subtitle: const Text('按标准模板批量导入借记卡或信用卡'),
            onTap: () =>
                BackupFlows.importCsv(context, ref, CsvImportKind.cards),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('导入证件 CSV'),
            subtitle: const Text('按标准模板批量导入证件卡'),
            onTap: () =>
                BackupFlows.importCsv(context, ref, CsvImportKind.documents),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_sync_outlined),
            title: const Text('WebDAV 备份'),
            subtitle: const Text('服务器地址、测试连接与自动备份策略'),
            onTap: () => context.push(AppRoutes.webdav),
          ),
          ListTile(
            leading: const Icon(Icons.dangerous_outlined),
            iconColor: theme.colorScheme.error,
            textColor: theme.colorScheme.error,
            title: const Text('清空全部数据'),
            subtitle: const Text('删除所有卡片、通知与密钥，不可恢复'),
            onTap: _wipeAllData,
          ),
          const _SettingsDivider(),
          const _SectionHeader(title: '关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于卡包'),
            onTap: () => context.push(AppRoutes.about),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// A low-contrast divider that remains visible without looking like a bright
/// white rule in either light or dark mode.
class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alpha = theme.brightness == Brightness.dark ? 0.18 : 0.10;
    return Divider(
      indent: 16,
      endIndent: 16,
      color: theme.colorScheme.onSurface.withValues(alpha: alpha),
      thickness: 1,
    );
  }
}

/// Equal-width, separated actions for the destructive confirmation dialogs.
class _WipeConfirmationActions extends StatelessWidget {
  const _WipeConfirmationActions({
    required this.dialogContext,
    required this.confirmLabel,
  });

  final BuildContext dialogContext;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(dialogContext).colorScheme;
    final cancelBorder = Color.alphaBlend(
      Colors.white.withValues(alpha: .65),
      scheme.primary,
    );
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              side: BorderSide(color: cancelBorder, width: 1.5),
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ),
      ],
    );
  }
}
